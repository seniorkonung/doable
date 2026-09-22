import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late IntentionId sourceId;
  late IntentionId relatedId;
  late IntentionId thirdId;
  late IntentionId fourthId;
  late LongTermRelationId relationId;
  late LongTermRelationId secondRelationId;
  late LongTermRelationId replacementRelationId;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    sourceId = _intentionId(_uuid(1));
    relatedId = _intentionId(_uuid(2));
    thirdId = _intentionId(_uuid(3));
    fourthId = _intentionId(_uuid(4));
    relationId = _relationId(_uuid(101));
    secondRelationId = _relationId(_uuid(102));
    replacementRelationId = _relationId(_uuid(103));
    for (final entry in <(IntentionId, String)>[
      (sourceId, 'Исходное намерение'),
      (relatedId, 'Связанное намерение'),
      (thirdId, 'Третье намерение'),
      (fourthId, 'Четвёртое намерение'),
    ]) {
      await _insertIntention(database, entry.$1, title: entry.$2);
    }
    repository = _repository(database, diagnostics, [
      relationId,
      secondRelationId,
      replacementRelationId,
    ]);
  });

  tearDown(() => database.close());

  test(
    'удаление активной связи удаляет описание и сохраняет остальной граф',
    () async {
      await _create(repository, sourceId, relatedId);
      await _create(repository, thirdId, fourthId);
      final intentionsBefore = await _storedIntentions(database);
      final otherRelationBefore = await _storedRelation(
        database,
        secondRelationId,
      );
      final events = StreamIterator(repository.watchRelation(relationId));
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);

      final confirmed = _confirmedDeleted(
        await repository.execute(DeleteLongTermRelation(relationId)),
      );

      expect(confirmed.value.relation.id, relationId);
      expect(confirmed.value.relation.sourceIntentionId, sourceId);
      expect(confirmed.value.relation.relatedIntentionId, relatedId);
      expect(await _storedRelationOrNull(database, relationId), isNull);
      expect(
        await _storedRelation(database, secondRelationId),
        otherRelationBefore,
      );
      expect(await _storedIntentions(database), intentionsBefore);

      final changes = confirmed.value.changes;
      expect(changes.map((change) => change.revision).toSet(), {
        confirmed.revision,
      });
      final deletion = changes
          .whereType<LongTermRelationDeletedChange>()
          .single;
      expect(deletion.id, relationId);
      expect(deletion.before, confirmed.value.relation);
      expect(deletion.after, isNull);
      final countChanges = changes
          .whereType<IntentionRelationCountsChanged>()
          .toList(growable: false);
      expect(countChanges.map((change) => change.intentionId), {
        sourceId,
        relatedId,
      });
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == sourceId)
            .counts
            .activeNeedOutgoing,
        0,
      );
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == relatedId)
            .counts
            .activeNeedIncoming,
        0,
      );

      expect(await events.moveNext(), isTrue);
      expect(_relationSnapshot(events.current).value, isNull);
    },
  );

  test(
    'архивная связь удаляется при архивном участнике без восстановления',
    () async {
      await _create(
        repository,
        sourceId,
        relatedId,
        type: LongTermRelationType.can,
        priority: RelationPriority.p4,
      );
      await repository.execute(ArchiveIntention(sourceId));
      expect((await _storedRelation(database, relationId))['is_archived'], 1);
      expect((await _storedIntention(database, sourceId))['is_archived'], 1);

      final deleted = _confirmedDeleted(
        await repository.execute(DeleteLongTermRelation(relationId)),
      );

      expect(deleted.value.relation.scope, RelationScope.archived);
      expect(await _storedRelationOrNull(database, relationId), isNull);
      expect((await _storedIntention(database, sourceId))['is_archived'], 1);
      expect((await _storedIntention(database, relatedId))['is_archived'], 0);
    },
  );

  test(
    'повтор и устаревшее изменение не восстанавливают удалённую связь',
    () async {
      await _create(repository, sourceId, relatedId);
      await repository.execute(DeleteLongTermRelation(relationId));
      final revisionAfterDelete = await _revision(repository, sourceId);

      final repeatedDelete = _failure(
        await repository.execute(DeleteLongTermRelation(relationId)),
      );
      final staleUpdate = _failure(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p1),
            ),
          ),
        ),
      );

      expect(
        repeatedDelete,
        isA<LongTermRelationNotFoundFailure>().having(
          (failure) => failure.relationId,
          'relationId',
          relationId,
        ),
      );
      expect(staleUpdate, isA<LongTermRelationNotFoundFailure>());
      expect(await _storedRelationOrNull(database, relationId), isNull);
      expect(
        (await _revision(repository, sourceId)).compareTo(revisionAfterDelete),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'удаление освобождает пару для новой идентичности и последовательности',
    () async {
      final original = await _create(repository, sourceId, relatedId);

      await repository.execute(DeleteLongTermRelation(relationId));
      final replacement = await _create(repository, sourceId, relatedId);

      expect(replacement.relation.id, secondRelationId);
      expect(replacement.relation.id, isNot(original.relation.id));
      expect(
        replacement.relation.creationSequence.value,
        greaterThan(original.relation.creationSequence.value),
      );
      expect(replacement.relation.sourceIntentionId, sourceId);
      expect(replacement.relation.relatedIntentionId, relatedId);
    },
  );

  test(
    'пересечение с удалением намерения даёт последовательный результат',
    () async {
      await _create(repository, sourceId, relatedId);
      await _create(repository, thirdId, fourthId);

      final blocked = await repository.execute(DeleteIntention(sourceId));
      expect(
        blocked,
        isA<GraphCommandFailed>().having(
          (failure) => failure.failure,
          'конфликт зависимостей',
          isA<IntentionHasBlockingRelationsFailure>(),
        ),
      );
      expect(await _storedRelationOrNull(database, relationId), isNotNull);
      expect(await _storedIntentionOrNull(database, sourceId), isNotNull);

      await repository.execute(DeleteLongTermRelation(relationId));
      expect(await _storedIntentionOrNull(database, sourceId), isNotNull);

      await repository.execute(DeleteLongTermRelation(secondRelationId));
      final intentionDeleted = await repository.execute(
        DeleteIntention(thirdId),
      );
      expect(intentionDeleted, isA<GraphCommandSucceeded>());
      expect(await _storedIntentionOrNull(database, thirdId), isNull);
      expect(await _storedIntentionOrNull(database, fourthId), isNotNull);
    },
  );

  test('ошибка записи откатывает удаление и не публикует изменение', () async {
    await _create(repository, sourceId, relatedId);
    final storedBefore = await _storedRelation(database, relationId);
    final revisionBefore = await _revision(repository, sourceId);
    final events = <LongTermRelationReadResult>[];
    final subscription = repository
        .watchRelation(relationId)
        .listen(events.add);
    addTearDown(() {
      unawaited(subscription.cancel());
    });
    await _waitFor(() => events.length == 1);
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_relation_delete_failure
      BEFORE DELETE ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'canary relation delete failure');
      END
    ''');

    final failure = _failure(
      await repository.execute(DeleteLongTermRelation(relationId)),
    );
    await pumpEventQueue(times: 10);

    expect(failure, isA<LongTermRelationUnexpectedFailure>());
    expect(await _storedRelation(database, relationId), storedBefore);
    expect(
      (await _revision(repository, sourceId)).compareTo(revisionBefore),
      GraphRevisionOrder.same,
    );
    expect(events, hasLength(1));
  });

  test(
    'диагностика удаления безопасна и её отказ не повторяет запись',
    () async {
      await _create(repository, sourceId, relatedId);

      await repository.execute(DeleteLongTermRelation(relationId));

      final deletionEvent = diagnostics.events
          .whereType<LongTermRelationCommandDiagnosticsEvent>()
          .singleWhere(
            (event) =>
                event.commandType ==
                LongTermRelationCommandDiagnosticsType.delete,
          );
      expect(deletionEvent.status, isA<DiagnosticsSucceeded>());

      await _create(repository, sourceId, relatedId);
      final throwingDiagnostics = _ThrowingDiagnosticsSink();
      repository = _repository(database, throwingDiagnostics, const []);

      final result = await repository.execute(
        DeleteLongTermRelation(secondRelationId),
      );

      expect(result, isA<GraphCommandSucceeded>());
      expect(await _storedRelationOrNull(database, secondRelationId), isNull);
      expect(
        throwingDiagnostics.attemptedEvents,
        everyElement(
          isA<LongTermRelationCommandDiagnosticsEvent>().having(
            (event) => event.commandType,
            'тип команды',
            LongTermRelationCommandDiagnosticsType.delete,
          ),
        ),
      );
    },
  );
}

Future<LongTermRelationCreated> _create(
  DriftPersonalGraphRepository repository,
  IntentionId sourceId,
  IntentionId relatedId, {
  LongTermRelationType type = LongTermRelationType.need,
  RelationPriority priority = RelationPriority.p2,
}) async => _created(
  await repository.execute(
    CreateLongTermRelation(
      sourceIntentionId: sourceId,
      relatedIntentionId: relatedId,
      type: type,
      priority: priority,
      description: LongTermRelationDescription.fromInput('  Описание\n'),
    ),
  ),
);

LongTermRelationCreated _created(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandSucceeded>());
  return (result
              as GraphCommandSucceeded<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >)
          .value
          .value
      as LongTermRelationCreated;
}

ConfirmedGraphResult<LongTermRelationDeleted> _confirmedDeleted(
  LongTermRelationCommandResult result,
) {
  expect(result, isA<GraphCommandSucceeded>());
  final confirmed =
      (result
              as GraphCommandSucceeded<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >)
          .value;
  return ConfirmedGraphResult(
    revision: confirmed.revision,
    value: confirmed.value as LongTermRelationDeleted,
  );
}

LongTermRelationCommandFailure _failure(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandFailed>());
  return (result
          as GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >)
      .failure;
}

GraphSnapshot<LongTermRelationDetails?> _relationSnapshot(
  LongTermRelationReadResult result,
) {
  expect(result, isA<LongTermRelationReadSuccess>());
  return (result as LongTermRelationReadSuccess).value;
}

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
  IntentionId intentionId,
) async => (await repository.getRelationCounts(
  intentionId,
) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
  List<LongTermRelationId> ids,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 22),
  diagnostics,
  relationIdGenerator: _DeterministicRelationIdGenerator(ids),
);

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
        createdAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
        updatedAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
      ),
    );

Future<Map<String, Object?>?> _storedRelationOrNull(
  AppDatabase database,
  LongTermRelationId id,
) async {
  final row = await database
      .customSelect(
        'SELECT * FROM long_term_relations WHERE id = ?',
        variables: [Variable<String>(id.toCanonicalString())],
        readsFrom: {database.longTermRelations},
      )
      .getSingleOrNull();
  return row == null ? null : Map.unmodifiable(row.data);
}

Future<Map<String, Object?>> _storedRelation(
  AppDatabase database,
  LongTermRelationId id,
) async => (await _storedRelationOrNull(database, id))!;

Future<Map<String, Object?>?> _storedIntentionOrNull(
  AppDatabase database,
  IntentionId id,
) async {
  final row = await database
      .customSelect(
        'SELECT * FROM intentions WHERE id = ?',
        variables: [Variable<String>(id.toCanonicalString())],
        readsFrom: {database.intentions},
      )
      .getSingleOrNull();
  return row == null ? null : Map.unmodifiable(row.data);
}

Future<Map<String, Object?>> _storedIntention(
  AppDatabase database,
  IntentionId id,
) async => (await _storedIntentionOrNull(database, id))!;

Future<List<Map<String, Object?>>> _storedIntentions(
  AppDatabase database,
) async => [
  for (final row
      in await database.customSelect('SELECT * FROM intentions').get())
    Map<String, Object?>.unmodifiable(row.data),
];

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(value),
    };

String _uuid(int suffix) =>
    '018f0000-0000-7000-8000-${suffix.toString().padLeft(12, '0')}';

final class _DeterministicRelationIdGenerator
    implements LongTermRelationIdGenerator {
  _DeterministicRelationIdGenerator(this._ids);

  final List<LongTermRelationId> _ids;
  var _index = 0;

  @override
  LongTermRelationId generate() => _ids[_index++];
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('Управляемый отказ диагностики.');
  }
}
