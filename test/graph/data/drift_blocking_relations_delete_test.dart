import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
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
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/large_blocking_relations_fixture.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late List<IntentionId> intentions;
  late _RelationIds relationIds;
  late _BulkDeleteObserver deleteObserver;

  setUp(() async {
    deleteObserver = _BulkDeleteObserver();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        deleteObserver,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    intentions = [for (var i = 1; i <= 12; i++) _intentionId(i)];
    for (final id in intentions) {
      await database
          .into(database.intentions)
          .insert(
            IntentionsCompanion.insert(
              id: id.toCanonicalString(),
              title: 'Намерение ${intentions.indexOf(id)}',
              createdAt: 1000000,
              updatedAt: 2000000,
            ),
          );
    }
    relationIds = _RelationIds();
    repository = _repository(database, diagnostics, relationIds);
  });

  tearDown(() => database.close());

  test('удаляет ровно выбранные связи восьми групп одним пакетом', () async {
    final owner = intentions[0];
    final selected = <LongTermRelationId>[];
    for (final scope in RelationScope.values) {
      for (final type in LongTermRelationType.values) {
        for (final outgoing in [true, false]) {
          final neighbor = intentions[selected.length + 1];
          final id = await _create(
            repository,
            outgoing ? owner : neighbor,
            outgoing ? neighbor : owner,
            type: type,
          );
          selected.add(id);
          if (scope == RelationScope.archived) {
            expect(
              await repository.execute(ArchiveLongTermRelation(id)),
              isA<GraphCommandSucceeded>(),
            );
          }
        }
      }
    }
    final unselected = await _create(repository, owner, intentions[9]);
    final neighborRelation = await _create(
      repository,
      intentions[1],
      intentions[2],
    );
    final intentionsBefore = await _rows(database, 'intentions');
    final unselectedBefore = await _relation(database, unselected);
    final neighborBefore = await _relation(database, neighborRelation);
    final revisionBefore = await _revision(repository, owner);

    final confirmed = _success(
      await repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: selected),
      ),
    );

    expect(
      confirmed.revision.compareTo(revisionBefore),
      GraphRevisionOrder.newer,
    );
    expect(
      confirmed.value.deletedRelations.map((relation) => relation.id).toSet(),
      selected.toSet(),
    );
    expect(confirmed.value.changes.map((change) => change.revision).toSet(), {
      confirmed.revision,
    });
    expect(
      confirmed.value.changes
          .whereType<LongTermRelationDeletedChange>()
          .map((change) => change.id)
          .toSet(),
      selected.toSet(),
    );
    final countChanges = confirmed.value.changes
        .whereType<IntentionRelationCountsChanged>()
        .toList();
    expect(countChanges.map((change) => change.intentionId).toSet(), {
      owner,
      ...intentions.sublist(1, 9),
    });
    for (final change in countChanges) {
      final actual = (await repository.getRelationCounts(
        change.intentionId,
      ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
      expect(change.counts, actual.value);
      expect(
        actual.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
    }
    for (final id in selected) {
      expect(await _relation(database, id), isNull);
    }
    expect(await _relation(database, unselected), unselectedBefore);
    expect(await _relation(database, neighborRelation), neighborBefore);
    expect(await _rows(database, 'intentions'), intentionsBefore);
  });

  test(
    'отсутствующее намерение и устаревший набор не меняют ревизию',
    () async {
      final owner = intentions[0];
      final first = await _create(repository, owner, intentions[1]);
      final foreign = await _create(repository, intentions[2], intentions[3]);
      final revision = await _revision(repository, owner);
      final missing = _intentionId(99);

      expect(
        _failure(
          await repository.execute(
            DeleteBlockingRelations(intentionId: missing, relationIds: [first]),
          ),
        ),
        isA<DeleteBlockingRelationsIntentionNotFoundFailure>(),
      );
      expect(
        _failure(
          await repository.execute(
            DeleteBlockingRelations(
              intentionId: owner,
              relationIds: [first, _relationId(999)],
            ),
          ),
        ),
        isA<DeleteBlockingRelationsSelectionConflictFailure>().having(
          (failure) => failure.reason,
          'причина',
          BlockingRelationConflictReason.relationMissing,
        ),
      );
      expect(
        _failure(
          await repository.execute(
            DeleteBlockingRelations(
              intentionId: owner,
              relationIds: [first, foreign],
            ),
          ),
        ),
        isA<DeleteBlockingRelationsSelectionConflictFailure>().having(
          (failure) => failure.reason,
          'причина',
          BlockingRelationConflictReason.noLongerBlocking,
        ),
      );
      expect(await _relation(database, first), isNotNull);
      expect(await _relation(database, foreign), isNotNull);
      expect(
        (await _revision(repository, owner)).compareTo(revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'новые связи и остальные связи соседей сохраняются при встречном цикле',
    () async {
      final owner = intentions[0];
      final selected = await _create(repository, owner, intentions[1]);
      final command = DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [selected],
      );
      final newIncoming = await _create(repository, intentions[1], owner);
      final cycle = await _create(repository, intentions[1], intentions[2]);
      final cycleBack = await _create(repository, intentions[2], intentions[1]);
      final untouched = {
        for (final id in [newIncoming, cycle, cycleBack])
          id: await _relation(database, id),
      };

      _success(await repository.execute(command));

      expect(await _relation(database, selected), isNull);
      for (final entry in untouched.entries) {
        expect(await _relation(database, entry.key), entry.value);
      }
      final recreated = await _create(repository, owner, intentions[1]);
      expect(recreated, isNot(selected));
      expect(await _relation(database, recreated), isNotNull);
      expect(
        (await repository.execute(DeleteIntention(owner))),
        isA<GraphCommandFailed>(),
      );
    },
  );

  test(
    'изменение собственных полей и архива не отменяет подтверждение',
    () async {
      final owner = intentions[0];
      final id = await _create(repository, owner, intentions[1]);
      final command = DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [id],
      );
      expect(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: id,
            patch: LongTermRelationPatch(
              type: const LongTermRelationFieldSet(LongTermRelationType.can),
              priority: const LongTermRelationFieldSet(RelationPriority.p4),
              description: LongTermRelationDescriptionPatch.fromInput(
                'Новое описание',
              ),
            ),
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(ArchiveLongTermRelation(id)),
        isA<GraphCommandSucceeded>(),
      );

      final confirmed = _success(await repository.execute(command));

      expect(
        confirmed.value.deletedRelations.single.type,
        LongTermRelationType.can,
      );
      expect(
        confirmed.value.deletedRelations.single.priority,
        RelationPriority.p4,
      );
      expect(
        confirmed.value.deletedRelations.single.scope,
        RelationScope.archived,
      );
      expect(await _relation(database, id), isNull);
    },
  );

  test(
    'смена участников лишает принадлежности и отменяет весь набор',
    () async {
      final owner = intentions[0];
      final first = await _create(repository, owner, intentions[1]);
      final moved = await _create(repository, intentions[2], owner);
      final command = DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [first, moved],
      );
      expect(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: moved,
            patch: LongTermRelationPatch(
              relatedIntentionId: LongTermRelationFieldSet(intentions[3]),
            ),
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      final revision = await _revision(repository, owner);

      expect(
        _failure(await repository.execute(command)),
        isA<DeleteBlockingRelationsSelectionConflictFailure>()
            .having((failure) => failure.relationId, 'связь', moved)
            .having(
              (failure) => failure.reason,
              'причина',
              BlockingRelationConflictReason.noLongerBlocking,
            ),
      );
      expect(await _relation(database, first), isNotNull);
      expect(await _relation(database, moved), isNotNull);
      expect(
        (await _revision(repository, owner)).compareTo(revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test('отказ записи откатывает весь набор и сохраняет ревизию', () async {
    final owner = intentions[0];
    final first = await _create(repository, owner, intentions[1]);
    final second = await _create(repository, owner, intentions[2]);
    final before = await _rows(database, 'long_term_relations');
    final revision = await _revision(repository, owner);
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_bulk_delete_failure
      BEFORE DELETE ON long_term_relations
      WHEN OLD.id = '${second.toCanonicalString()}'
      BEGIN
        SELECT RAISE(ABORT, 'canary bulk delete failure');
      END
    ''');

    final failure = _failure(
      await repository.execute(
        DeleteBlockingRelations(
          intentionId: owner,
          relationIds: [first, second],
        ),
      ),
    );

    expect(failure, isA<DeleteBlockingRelationsUnexpectedFailure>());
    expect(await _rows(database, 'long_term_relations'), before);
    expect(
      (await _revision(repository, owner)).compareTo(revision),
      GraphRevisionOrder.same,
    );
    final event = diagnostics.events
        .whereType<BlockingRelationsDeleteDiagnosticsEvent>()
        .last;
    expect(
      event.status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'код',
        DiagnosticsFailureCode.unexpected,
      ),
    );
  });

  test(
    'повреждённая выбранная связь даёт corruption без частичного удаления',
    () async {
      final owner = intentions[0];
      final first = await _create(repository, owner, intentions[1]);
      final corrupted = await _create(repository, owner, intentions[2]);
      final revision = await _revision(repository, intentions[3]);
      await database.customUpdate(
        'UPDATE long_term_relations SET description = ? WHERE id = ?',
        variables: [
          const Variable<String>('   '),
          Variable<String>(corrupted.toCanonicalString()),
        ],
        updates: {database.longTermRelations},
      );

      final failure = _failure(
        await repository.execute(
          DeleteBlockingRelations(
            intentionId: owner,
            relationIds: [first, corrupted],
          ),
        ),
      );

      expect(failure, isA<DeleteBlockingRelationsCorruptionFailure>());
      expect(await _relation(database, first), isNotNull);
      expect(await _relation(database, corrupted), isNotNull);
      final event = diagnostics.events
          .whereType<BlockingRelationsDeleteDiagnosticsEvent>()
          .last;
      expect(
        event.status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'код',
          DiagnosticsFailureCode.corruption,
        ),
      );
      expect(
        (await _revision(repository, intentions[3])).compareTo(revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'непроверяемый итоговый счётчик откатывает уже удалённый набор',
    () async {
      final owner = intentions[0];
      final selected = await _create(repository, owner, intentions[1]);
      final unselected = await _create(repository, owner, intentions[2]);
      final revision = await _revision(repository, intentions[3]);
      await database.customUpdate(
        'UPDATE long_term_relations SET description = ? WHERE id = ?',
        variables: [
          const Variable<String>('   '),
          Variable<String>(unselected.toCanonicalString()),
        ],
        updates: {database.longTermRelations},
      );

      expect(
        _failure(
          await repository.execute(
            DeleteBlockingRelations(
              intentionId: owner,
              relationIds: [selected],
            ),
          ),
        ),
        isA<DeleteBlockingRelationsCorruptionFailure>(),
      );
      expect(await _relation(database, selected), isNotNull);
      expect(await _relation(database, unselected), isNotNull);
      expect(
        (await _revision(repository, intentions[3])).compareTo(revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'отказ получателя диагностики до и после commit не меняет исход',
    () async {
      final owner = intentions[0];
      final first = await _create(repository, owner, intentions[1]);
      final second = await _create(repository, owner, intentions[2]);
      final sink = _ThrowingDiagnosticsSink();
      repository = _repository(database, sink, relationIds);

      final confirmed = _success(
        await repository.execute(
          DeleteBlockingRelations(
            intentionId: owner,
            relationIds: [first, second],
          ),
        ),
      );

      expect(confirmed.value.deletedRelations, hasLength(2));
      expect(await _relation(database, first), isNull);
      expect(await _relation(database, second), isNull);
      expect(sink.events.map((event) => event.status.runtimeType), [
        DiagnosticsStarted,
        DiagnosticsSucceeded,
      ]);

      final missing = _failure(
        await repository.execute(
          DeleteBlockingRelations(intentionId: owner, relationIds: [first]),
        ),
      );
      expect(missing, isA<DeleteBlockingRelationsSelectionConflictFailure>());
      expect(
        sink.events.last.status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'код',
          DiagnosticsFailureCode.conflict,
        ),
      );
    },
  );

  test(
    'одиночное удаление до набора даёт конфликт, после набора — отсутствие',
    () async {
      final owner = intentions[0];
      final selected = await _create(repository, owner, intentions[1]);
      final command = DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [selected],
      );
      final singleFirst = repository.execute(DeleteLongTermRelation(selected));
      final bulkSecond = repository.execute(command);
      expect(await singleFirst, isA<GraphCommandSucceeded>());
      expect(
        _failure(await bulkSecond),
        isA<DeleteBlockingRelationsSelectionConflictFailure>(),
      );

      final next = await _create(repository, owner, intentions[2]);
      final bulkFirst = repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: [next]),
      );
      final singleSecond = repository.execute(DeleteLongTermRelation(next));
      _success(await bulkFirst);
      expect(
        await singleSecond,
        isA<GraphCommandFailed>().having(
          (result) => result.failure,
          'причина',
          isA<LongTermRelationNotFoundFailure>(),
        ),
      );
    },
  );

  test(
    'смена участников до набора конфликтует, после набора видит отсутствие',
    () async {
      final owner = intentions[0];
      final selected = await _create(repository, owner, intentions[1]);
      final update = UpdateLongTermRelation(
        relationId: selected,
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(intentions[2]),
        ),
      );
      final command = DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [selected],
      );
      final updateFirst = repository.execute(update);
      final bulkSecond = repository.execute(command);
      expect(await updateFirst, isA<GraphCommandSucceeded>());
      expect(
        _failure(await bulkSecond),
        isA<DeleteBlockingRelationsSelectionConflictFailure>(),
      );
      expect(await _relation(database, selected), isNotNull);

      final next = await _create(repository, owner, intentions[3]);
      final bulkFirst = repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: [next]),
      );
      final updateSecond = repository.execute(
        UpdateLongTermRelation(
          relationId: next,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(intentions[4]),
          ),
        ),
      );
      _success(await bulkFirst);
      expect(
        await updateSecond,
        isA<GraphCommandFailed>().having(
          (result) => result.failure,
          'причина',
          isA<LongTermRelationNotFoundFailure>(),
        ),
      );
    },
  );

  test(
    'каскад до набора архивирует выбранную связь, после — только оставшуюся',
    () async {
      final owner = intentions[0];
      final selected = await _create(repository, owner, intentions[1]);
      final archiveFirst = repository.execute(ArchiveIntention(owner));
      final bulkSecond = repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: [selected]),
      );
      expect(await archiveFirst, isA<GraphCommandSucceeded>());
      expect(
        _success(await bulkSecond).value.deletedRelations.single.scope,
        RelationScope.archived,
      );
      expect(await _relation(database, selected), isNull);

      final otherOwner = intentions[2];
      final next = await _create(repository, otherOwner, intentions[3]);
      final remaining = await _create(repository, otherOwner, intentions[4]);
      final bulkFirst = repository.execute(
        DeleteBlockingRelations(intentionId: otherOwner, relationIds: [next]),
      );
      final archiveSecond = repository.execute(ArchiveIntention(otherOwner));
      _success(await bulkFirst);
      expect(await archiveSecond, isA<GraphCommandSucceeded>());
      expect(await _relation(database, next), isNull);
      expect((await _relation(database, remaining))?['is_archived'], 1);
    },
  );

  test('набор за границей SQL-порции удаляется одним результатом', () async {
    final owner = intentions.first;
    await LargeBlockingRelationsFixture.seed(database, owner);
    final selected = LargeBlockingRelationsFixture.selectedIds;
    final beforeIntentions = await _rows(database, 'intentions');
    final unselected = await _relation(
      database,
      LargeBlockingRelationsFixture.unselected,
    );
    final unrelated = await _relation(
      database,
      LargeBlockingRelationsFixture.unrelated,
    );
    final previousRevision = await _revision(repository, owner);
    deleteObserver.clear();

    final confirmed = _success(
      await repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: selected),
      ),
    );

    expect(deleteObserver.batchSizes, [400, 1]);
    expect(
      confirmed.revision.compareTo(previousRevision),
      GraphRevisionOrder.newer,
    );
    expect(
      confirmed.value.deletedRelations.map((relation) => relation.id),
      selected,
    );
    expect(confirmed.value.changes.map((change) => change.revision).toSet(), {
      confirmed.revision,
    });
    expect(
      confirmed.value.changes
          .whereType<IntentionRelationCountsChanged>()
          .singleWhere((change) => change.intentionId == owner)
          .counts
          .activeNeedOutgoing,
      1,
    );
    expect((await _rows(database, 'long_term_relations')).length, 2);
    expect(
      await _relation(database, LargeBlockingRelationsFixture.unselected),
      unselected,
    );
    expect(
      await _relation(database, LargeBlockingRelationsFixture.unrelated),
      unrelated,
    );
    expect(await _rows(database, 'intentions'), beforeIntentions);
  });

  test('конфликт в поздней SQL-порции сохраняет весь набор', () async {
    final owner = intentions.first;
    await LargeBlockingRelationsFixture.seed(database, owner);
    final selected = LargeBlockingRelationsFixture.selectedIds;
    await database.customStatement(
      'DELETE FROM long_term_relations WHERE id = ?',
      [selected.last.toCanonicalString()],
    );
    final before = await _rows(database, 'long_term_relations');
    final revision = await _revision(repository, owner);
    deleteObserver.clear();

    final failure = _failure(
      await repository.execute(
        DeleteBlockingRelations(intentionId: owner, relationIds: selected),
      ),
    );

    expect(
      failure,
      isA<DeleteBlockingRelationsSelectionConflictFailure>().having(
        (failure) => failure.relationId,
        'связь поздней порции',
        selected.last,
      ),
    );
    expect(deleteObserver.batchSizes, isEmpty);
    expect(await _rows(database, 'long_term_relations'), before);
    expect(
      (await _revision(repository, owner)).compareTo(revision),
      GraphRevisionOrder.same,
    );
  });

  test('отказ после первой SQL-порции откатывает все удаления', () async {
    final owner = intentions.first;
    await LargeBlockingRelationsFixture.seed(database, owner);
    final beforeRelations = await _rows(database, 'long_term_relations');
    final beforeIntentions = await _rows(database, 'intentions');
    final revision = await _revision(repository, owner);
    deleteObserver.clear();
    deleteObserver.failAfterFirstBatch = true;

    final failure = _failure(
      await repository.execute(
        DeleteBlockingRelations(
          intentionId: owner,
          relationIds: LargeBlockingRelationsFixture.selectedIds,
        ),
      ),
    );

    expect(failure, isA<DeleteBlockingRelationsUnexpectedFailure>());
    expect(deleteObserver.batchSizes, [400]);
    expect(await _rows(database, 'long_term_relations'), beforeRelations);
    expect(await _rows(database, 'intentions'), beforeIntentions);
    expect(
      (await _revision(repository, owner)).compareTo(revision),
      GraphRevisionOrder.same,
    );
  });
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
  _RelationIds ids,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 22),
  diagnostics,
  relationIdGenerator: ids,
);

Future<LongTermRelationId> _create(
  DriftPersonalGraphRepository repository,
  IntentionId source,
  IntentionId related, {
  LongTermRelationType type = LongTermRelationType.need,
}) async {
  final result = await repository.execute(
    CreateLongTermRelation(
      sourceIntentionId: source,
      relatedIntentionId: related,
      type: type,
      priority: RelationPriority.p2,
      description: LongTermRelationDescription.fromInput('Описание'),
    ),
  );
  expect(result, isA<GraphCommandSucceeded>());
  return ((result as GraphCommandSucceeded).value.value
          as LongTermRelationCreated)
      .relation
      .id;
}

ConfirmedGraphResult<BlockingRelationsDeleted> _success(
  DeleteBlockingRelationsResult result,
) {
  expect(result, isA<GraphCommandSucceeded>());
  return (result
          as GraphCommandSucceeded<
            BlockingRelationsDeleted,
            DeleteBlockingRelationsFailure
          >)
      .value;
}

DeleteBlockingRelationsFailure _failure(DeleteBlockingRelationsResult result) {
  expect(result, isA<GraphCommandFailed>());
  return (result
          as GraphCommandFailed<
            BlockingRelationsDeleted,
            DeleteBlockingRelationsFailure
          >)
      .failure;
}

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
  IntentionId id,
) async => (await repository.getRelationCounts(
  id,
) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

Future<Map<String, Object?>?> _relation(
  AppDatabase database,
  LongTermRelationId id,
) async =>
    (await database
            .customSelect(
              'SELECT * FROM long_term_relations WHERE id = ?',
              variables: [Variable<String>(id.toCanonicalString())],
            )
            .getSingleOrNull())
        ?.data;

Future<List<Map<String, Object?>>> _rows(
  AppDatabase database,
  String table,
) async => [
  for (final row
      in await database.customSelect('SELECT * FROM $table ORDER BY id').get())
    row.data,
];

IntentionId _intentionId(int value) =>
    switch (IntentionId.decode(_uuid(value))) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError('Недопустимый ID'),
    };

LongTermRelationId _relationId(int value) => switch (LongTermRelationId.decode(
  _uuid(value),
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError('Недопустимый ID'),
};

String _uuid(int value) =>
    '018f0000-0000-7000-8000-${value.toString().padLeft(12, '0')}';

final class _RelationIds implements LongTermRelationIdGenerator {
  var next = 100;

  @override
  LongTermRelationId generate() => _relationId(next++);
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final events = <BlockingRelationsDeleteDiagnosticsEvent>[];

  @override
  void record(DiagnosticsEvent event) {
    events.add(event as BlockingRelationsDeleteDiagnosticsEvent);
    throw StateError('Отказ диагностики');
  }
}

final class _BulkDeleteObserver extends LocalDatabaseConnectionObserver {
  final batchSizes = <int>[];
  var failAfterFirstBatch = false;

  void clear() => batchSizes.clear();

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.update ||
        !statement.statements.any(
          (sql) =>
              sql.startsWith('DELETE FROM long_term_relations WHERE id IN'),
        )) {
      return;
    }
    batchSizes.add(statement.arguments.length);
    if (failAfterFirstBatch && batchSizes.length == 1) {
      throw StateError('Контрольный отказ после первой порции удаления.');
    }
  }
}
