import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late IntentionId sourceId;
  late IntentionId relatedId;
  late LongTermRelationId relationId;
  late bool databaseIsOpen;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    databaseIsOpen = true;
    diagnostics = InMemoryDiagnosticsSink();
    repository = _repository(database, diagnostics);
    sourceId = _intentionId(_uuid(1));
    relatedId = _intentionId(_uuid(2));
    relationId = _relationId(_uuid(101));
    await _insertIntention(database, sourceId, title: 'Исходное намерение');
    await _insertIntention(database, relatedId, title: 'Связанное намерение');
    await _insertRelation(
      database,
      id: relationId,
      sourceId: sourceId,
      relatedId: relatedId,
      description: '  Полное описание\nс переносом  ',
    );
  });

  tearDown(() async {
    if (databaseIsOpen) await database.close();
  });

  test(
    'возвращает связь, полное описание и актуальных участников одним снимком',
    () async {
      final thirdId = _intentionId(_uuid(3));
      await _insertIntention(database, thirdId, title: 'Третье намерение');
      await _insertRelation(
        database,
        id: _relationId(_uuid(102)),
        sourceId: sourceId,
        relatedId: thirdId,
      );

      final result = await repository.watchRelation(relationId).first;
      final snapshot = _snapshot(result);
      final details = snapshot.value!;

      expect(details.relation.id, relationId);
      expect(details.description!.value, '  Полное описание\nс переносом  ');
      expect(details.source.id, sourceId);
      expect(details.source.title, 'Исходное намерение');
      expect(details.source.activeRelationCount, 2);
      expect(details.related.id, relatedId);
      expect(details.related.title, 'Связанное намерение');
      expect(details.related.activeRelationCount, 1);
      expect(
        diagnostics.events
            .whereType<LongTermRelationDetailReadDiagnosticsEvent>(),
        [
          isA<LongTermRelationDetailReadDiagnosticsEvent>().having(
            (event) => event.status,
            'статус',
            isA<DiagnosticsStarted>(),
          ),
          isA<LongTermRelationDetailReadDiagnosticsEvent>().having(
            (event) => event.status,
            'статус',
            isA<DiagnosticsSucceeded>(),
          ),
        ],
      );
    },
  );

  test('подтверждённое отсутствие отличается от ошибки чтения', () async {
    final missing = await repository
        .watchRelation(_relationId(_uuid(999)))
        .first;

    expect(_snapshot(missing).value, isNull);

    await database.customStatement(
      'UPDATE long_term_relations SET description = ? WHERE id = ?',
      [' ', relationId.toCanonicalString()],
    );
    final corrupted = await repository.watchRelation(relationId).first;

    expect(_failure(corrupted), isA<LongTermRelationReadCorruptionFailure>());
  });

  test('перечитывает участника после его переименования', () async {
    final events = StreamIterator(repository.watchRelation(relationId));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final initial = _snapshot(events.current);

    await repository.execute(
      UpdateIntention(
        id: relatedId,
        title: 'Переименованное намерение',
        description: null,
      ),
    );

    expect(await events.moveNext(), isTrue);
    final updated = _snapshot(events.current);
    expect(
      updated.revision.compareTo(initial.revision),
      GraphRevisionOrder.newer,
    );
    expect(updated.value!.related.title, 'Переименованное намерение');
    expect(updated.value!.relation.id, relationId);
  });

  test('согласованно отражает каскадное архивирование участника', () async {
    final events = StreamIterator(repository.watchRelation(relationId));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);

    await repository.execute(ArchiveIntention(sourceId));

    expect(await events.moveNext(), isTrue);
    final details = _snapshot(events.current).value!;
    expect(details.relation.scope, RelationScope.archived);
    expect(details.source.archiveState, IntentionArchiveState.archived);
    expect(details.related.archiveState, IntentionArchiveState.active);
    expect(details.source.activeRelationCount, 0);
    expect(details.related.activeRelationCount, 0);
  });

  test(
    'обновляет количество участника при изменении другого соседства',
    () async {
      final thirdId = _intentionId(_uuid(3));
      await _insertIntention(database, thirdId, title: 'Третье намерение');
      final events = StreamIterator(repository.watchRelation(relationId));
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);

      await repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: relatedId,
          relatedIntentionId: thirdId,
          type: LongTermRelationType.can,
          priority: RelationPriority.p3,
          description: null,
        ),
      );

      expect(await events.moveNext(), isTrue);
      final details = _snapshot(events.current).value!;
      expect(details.relation.id, relationId);
      expect(details.source.activeRelationCount, 1);
      expect(details.related.activeRelationCount, 2);
    },
  );

  test('не перечитывает связь при изменении постороннего намерения', () async {
    final unrelatedId = _intentionId(_uuid(3));
    await _insertIntention(database, unrelatedId, title: 'Постороннее');
    final received = <LongTermRelationReadResult>[];
    final cancelled = Completer<void>();
    late final StreamSubscription<LongTermRelationReadResult> subscription;
    subscription = repository.watchRelation(relationId).listen((event) {
      received.add(event);
      if (received.length == 2) {
        unawaited(subscription.cancel().then(cancelled.complete));
      }
    });
    await _waitFor(() => received.length == 1);

    await repository.execute(
      UpdateIntention(
        id: unrelatedId,
        title: 'Изменённое постороннее',
        description: null,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));

    await repository.execute(
      UpdateIntention(
        id: sourceId,
        title: 'Изменённое исходное',
        description: null,
      ),
    );
    await _waitFor(() => received.length == 2);
    await cancelled.future;
  });

  test('отсутствующий участник не даёт частично успешную модель', () async {
    await database.customStatement('PRAGMA foreign_keys = OFF');
    await (database.delete(
      database.intentions,
    )..where((row) => row.id.equals(relatedId.toCanonicalString()))).go();
    await database.customStatement('PRAGMA foreign_keys = ON');

    final result = await repository.watchRelation(relationId).first;

    expect(_failure(result), isA<LongTermRelationReadCorruptionFailure>());
  });

  test('сбой чтения не даёт частично успешную модель', () async {
    await database.close();
    databaseIsOpen = false;

    final result = await repository.watchRelation(relationId).first;

    expect(_failure(result), isA<LongTermRelationReadUnexpectedFailure>());
    expect(
      diagnostics.events
          .whereType<LongTermRelationDetailReadDiagnosticsEvent>()
          .last
          .status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.unexpected,
      ),
    );
  });

  test('отказ диагностики не меняет успешный результат', () async {
    final throwingDiagnostics = _ThrowingDiagnosticsSink();
    final result = await _repository(
      database,
      throwingDiagnostics,
    ).watchRelation(relationId).first;

    expect(_snapshot(result).value!.relation.id, relationId);
    expect(
      throwingDiagnostics.attemptedEvents,
      everyElement(isA<LongTermRelationDetailReadDiagnosticsEvent>()),
    );
  });
}

GraphSnapshot<LongTermRelationDetails?> _snapshot(
  LongTermRelationReadResult result,
) {
  expect(result, isA<LongTermRelationReadSuccess>());
  return (result as LongTermRelationReadSuccess).value;
}

LongTermRelationReadFailure _failure(LongTermRelationReadResult result) {
  expect(result, isA<LongTermRelationReadError>());
  return (result as LongTermRelationReadError).failure;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id.toCanonicalString(),
        title: title,
        createdAt: DateTime.utc(2026, 9, 20).microsecondsSinceEpoch,
        updatedAt: DateTime.utc(2026, 9, 20).microsecondsSinceEpoch,
      ),
    );

Future<void> _insertRelation(
  AppDatabase database, {
  required LongTermRelationId id,
  required IntentionId sourceId,
  required IntentionId relatedId,
  String? description,
}) => database
    .into(database.longTermRelations)
    .insert(
      LongTermRelationsCompanion.insert(
        id: id.toCanonicalString(),
        sourceIntentionId: sourceId.toCanonicalString(),
        relatedIntentionId: relatedId.toCanonicalString(),
        type: 'need',
        priority: 2,
        description: Value(description),
        isArchived: const Value(false),
      ),
    );

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 20),
  diagnostics,
);

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(
        value,
        'value',
      ),
    };

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('Управляемый отказ диагностики.');
  }
}
