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

  test('согласует прежних, новых и сохраняющегося участников полного жизненного цикла', () async {
    final thirdId = _intentionId(_uuid(3));
    final fourthId = _intentionId(_uuid(4));
    final fifthId = _intentionId(_uuid(5));
    final sixthId = _intentionId(_uuid(6));
    final seventhId = _intentionId(_uuid(7));
    final eighthId = _intentionId(_uuid(8));
    final ninthId = _intentionId(_uuid(9));
    for (final entry in <(IntentionId, String)>[
      (thirdId, 'Новый исходный участник'),
      (fourthId, 'Первый новый связанный участник'),
      (fifthId, 'Сосед прежнего исходного участника'),
      (sixthId, 'Сосед прежнего связанного участника'),
      (seventhId, 'Второй новый связанный участник'),
      (eighthId, 'Посторонний исходный участник'),
      (ninthId, 'Посторонний связанный участник'),
    ]) {
      await _insertIntention(database, entry.$1, title: entry.$2);
    }

    final sourceWitnessId = _relationId(_uuid(102));
    final relatedWitnessId = _relationId(_uuid(103));
    final newSourceWitnessId = _relationId(_uuid(104));
    final newRelatedWitnessId = _relationId(_uuid(105));
    final unrelatedRelationId = _relationId(_uuid(106));
    await _insertRelation(
      database,
      id: sourceWitnessId,
      sourceId: sourceId,
      relatedId: fifthId,
    );
    await _insertRelation(
      database,
      id: relatedWitnessId,
      sourceId: relatedId,
      relatedId: sixthId,
    );
    await _insertRelation(
      database,
      id: newSourceWitnessId,
      sourceId: thirdId,
      relatedId: fifthId,
    );
    await _insertRelation(
      database,
      id: newRelatedWitnessId,
      sourceId: seventhId,
      relatedId: sixthId,
    );
    await _insertRelation(
      database,
      id: unrelatedRelationId,
      sourceId: eighthId,
      relatedId: ninthId,
    );

    final relationEvents = StreamIterator(repository.watchRelation(relationId));
    final sourceEvents = StreamIterator(
      repository.watchRelation(sourceWitnessId),
    );
    final relatedEvents = StreamIterator(
      repository.watchRelation(relatedWitnessId),
    );
    final unrelatedEvents = <LongTermRelationReadResult>[];
    final unrelatedCancelled = Completer<void>();
    late final StreamSubscription<LongTermRelationReadResult>
    unrelatedSubscription;
    unrelatedSubscription = repository
        .watchRelation(unrelatedRelationId)
        .listen((event) {
          unrelatedEvents.add(event);
          if (unrelatedEvents.length == 2) {
            unawaited(
              unrelatedSubscription.cancel().then(unrelatedCancelled.complete),
            );
          }
        });
    addTearDown(relationEvents.cancel);
    addTearDown(sourceEvents.cancel);
    addTearDown(relatedEvents.cancel);
    await Future.wait([
      _nextDetails(relationEvents),
      _nextDetails(sourceEvents),
      _nextDetails(relatedEvents),
    ]);
    await _waitFor(() => unrelatedEvents.length == 1);

    await repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(thirdId),
          relatedIntentionId: LongTermRelationFieldSet(fourthId),
        ),
      ),
    );

    final moved = (await _nextDetails(relationEvents))!;
    final formerSource = (await _nextDetails(sourceEvents))!;
    final formerRelated = (await _nextDetails(relatedEvents))!;
    expect(moved.source.id, thirdId);
    expect(moved.source.title, 'Новый исходный участник');
    expect(moved.source.activeRelationCount, 2);
    expect(moved.related.id, fourthId);
    expect(moved.related.title, 'Первый новый связанный участник');
    expect(moved.related.activeRelationCount, 1);
    expect(formerSource.source.activeRelationCount, 1);
    expect(formerRelated.source.activeRelationCount, 1);

    await repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(seventhId),
        ),
      ),
    );

    final movedAgain = (await _nextDetails(relationEvents))!;
    expect(movedAgain.source.id, thirdId);
    expect(movedAgain.source.title, 'Новый исходный участник');
    expect(movedAgain.source.activeRelationCount, 2);
    expect(movedAgain.related.id, seventhId);
    expect(movedAgain.related.title, 'Второй новый связанный участник');
    expect(movedAgain.related.activeRelationCount, 2);

    final newSourceEvents = StreamIterator(
      repository.watchRelation(newSourceWitnessId),
    );
    final newRelatedEvents = StreamIterator(
      repository.watchRelation(newRelatedWitnessId),
    );
    addTearDown(newSourceEvents.cancel);
    addTearDown(newRelatedEvents.cancel);
    final [newSource, newRelated] = await Future.wait([
      _nextDetails(newSourceEvents),
      _nextDetails(newRelatedEvents),
    ]);
    expect(newSource!.source.activeRelationCount, 2);
    expect(newRelated!.source.activeRelationCount, 2);

    await repository.execute(ArchiveLongTermRelation(relationId));
    final archived = (await _nextDetails(relationEvents))!;
    final sourceAfterArchive = (await _nextDetails(newSourceEvents))!;
    final relatedAfterArchive = (await _nextDetails(newRelatedEvents))!;
    expect(archived.relation.scope, RelationScope.archived);
    expect(archived.source.activeRelationCount, 1);
    expect(archived.related.activeRelationCount, 1);
    expect(sourceAfterArchive.source.activeRelationCount, 1);
    expect(relatedAfterArchive.source.activeRelationCount, 1);

    await repository.execute(RestoreLongTermRelation(relationId));
    final restored = (await _nextDetails(relationEvents))!;
    await _nextDetails(newSourceEvents);
    await _nextDetails(newRelatedEvents);
    expect(restored.relation.scope, RelationScope.active);
    expect(restored.source.activeRelationCount, 2);
    expect(restored.related.activeRelationCount, 2);

    await repository.execute(DeleteLongTermRelation(relationId));
    expect(await _nextDetails(relationEvents), isNull);
    final sourceAfterDelete = (await _nextDetails(newSourceEvents))!;
    final relatedAfterDelete = (await _nextDetails(newRelatedEvents))!;
    expect(sourceAfterDelete.source.activeRelationCount, 1);
    expect(relatedAfterDelete.source.activeRelationCount, 1);
    await Future<void>.delayed(Duration.zero);
    expect(unrelatedEvents, hasLength(1));

    await repository.execute(
      UpdateIntention(
        id: eighthId,
        title: 'Переименованный посторонний участник',
        description: null,
      ),
    );
    await _waitFor(() => unrelatedEvents.length == 2);
    await unrelatedCancelled.future;
    expect(
      _snapshot(unrelatedEvents.last).value!.source.title,
      'Переименованный посторонний участник',
    );
  });

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

Future<LongTermRelationDetails?> _nextDetails(
  StreamIterator<LongTermRelationReadResult> events,
) async {
  expect(await events.moveNext(), isTrue);
  return _snapshot(events.current).value;
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
