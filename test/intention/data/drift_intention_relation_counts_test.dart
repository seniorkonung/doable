import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 19),
      diagnostics,
    );
  });

  tearDown(() => database.close());

  test(
    'возвращает самостоятельную точную сводку существующего намерения',
    () async {
      final owner = _id(_uuid(1));
      final neighbors = [
        for (var index = 2; index <= 9; index++) _id(_uuid(index)),
      ];
      for (final id in [owner, ...neighbors]) {
        await _insertIntention(database, id);
      }
      await _insertAllGroups(database, owner, neighbors);

      final result = await repository.getRelationCounts(owner);

      expect(result, isA<ResultSuccess<GraphSnapshot<RelationCounts>>>());
      final snapshot =
          (result as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
      expect(snapshot.value.total, 8);
      expect([
        snapshot.value.activeNeedIncoming,
        snapshot.value.activeNeedOutgoing,
        snapshot.value.activeCanIncoming,
        snapshot.value.activeCanOutgoing,
        snapshot.value.archivedNeedIncoming,
        snapshot.value.archivedNeedOutgoing,
        snapshot.value.archivedCanIncoming,
        snapshot.value.archivedCanOutgoing,
      ], everyElement(1));
      expect(diagnostics.events, [
        isA<RelationCountsReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsStarted>(),
        ),
        isA<RelationCountsReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsSucceeded>(),
        ),
      ]);
    },
  );

  test('отличает отсутствующее намерение от подтверждённого нуля', () async {
    final existing = _id(_uuid(20));
    await _insertIntention(database, existing);

    final existingSnapshot = _successfulSnapshot(
      await repository.watchIntention(existing).first,
    );
    final missingSnapshot = _successfulSnapshot(
      await repository.watchIntention(_id(_uuid(21))).first,
    );

    expect(existingSnapshot.value!.relationCounts.total, 0);
    expect(missingSnapshot.value, isNull);
  });

  test('блокирует удаление связью любой группы и сохраняет ревизию', () async {
    // Блокирует любая связь по любому из двух концов, активная или в архиве;
    // тип связи на проверку не влияет. Два случая проходят оба направления,
    // оба типа и оба состояния архива.
    final groups = [
      (incoming: true, type: 'need', archived: false),
      (incoming: false, type: 'can', archived: true),
    ];

    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final owner = _id(_uuid(300 + index * 2));
      final neighbor = _id(_uuid(301 + index * 2));
      await _insertIntention(database, owner);
      await _insertIntention(database, neighbor);
      await _insertRelation(
        database,
        id: _uuid(400 + index),
        sourceId: group.incoming ? neighbor : owner,
        relatedId: group.incoming ? owner : neighbor,
        type: group.type,
        isArchived: group.archived,
      );
      final revisionBefore = _successfulSnapshot(
        await repository.watchIntention(owner).first,
      ).revision;

      final result = await repository.execute(DeleteIntention(owner));

      expect(
        result,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (failure) => failure.failure,
              'failure',
              isA<IntentionHasBlockingRelationsFailure>().having(
                (failure) => failure.intentionId,
                'intentionId',
                owner,
              ),
            ),
      );
      final revisionAfter = _successfulSnapshot(
        await repository.watchIntention(owner).first,
      ).revision;
      expect(revisionBefore.compareTo(revisionAfter), GraphRevisionOrder.same);
      expect(
        await (database.select(database.intentions)
              ..where((row) => row.id.equals(owner.toCanonicalString())))
            .getSingleOrNull(),
        isNotNull,
      );
    }

    expect(
      diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
      hasLength(groups.length),
    );
    expect(
      diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().map(
        (event) => event.status,
      ),
      everyElement(
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'code',
          DiagnosticsFailureCode.conflict,
        ),
      ),
    );
  });

  test(
    'не доверяет прежнему нулю и блокирует удаление связями за первой порцией',
    () async {
      final owner = _id(_uuid(500));
      final neighbors = [
        for (var index = 0; index < 51; index++) _id(_uuid(501 + index)),
      ];
      await _insertIntention(database, owner);
      for (final neighbor in neighbors) {
        await _insertIntention(database, neighbor);
      }
      final emptySnapshot = _successfulSnapshot(
        await repository.watchIntention(owner).first,
      );
      expect(emptySnapshot.value!.relationCounts.total, 0);
      for (var index = 0; index < neighbors.length; index++) {
        await _insertRelation(
          database,
          id: _uuid(600 + index),
          sourceId: neighbors[index],
          relatedId: owner,
          type: 'can',
          isArchived: true,
        );
      }

      final result = await repository.execute(DeleteIntention(owner));

      expect(
        result,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (failure) => failure.failure,
              'failure',
              isA<IntentionHasBlockingRelationsFailure>().having(
                (failure) => failure.intentionId,
                'intentionId',
                owner,
              ),
            ),
      );
      final currentSnapshot = _successfulSnapshot(
        await repository.watchIntention(owner).first,
      );
      expect(currentSnapshot.value!.relationCounts.activeNeedOutgoing, 0);
      expect(currentSnapshot.value!.relationCounts.archivedCanIncoming, 51);
      expect(
        emptySnapshot.revision.compareTo(currentSnapshot.revision),
        GraphRevisionOrder.same,
      );
      expect(
        await database
            .customSelect(
              'SELECT COUNT(*) AS relation_count FROM long_term_relations',
            )
            .getSingle()
            .then((row) => row.read<int>('relation_count')),
        51,
      );
    },
  );

  test('наблюдает подробные поля и сводку на одной ревизии', () async {
    final owner = _id(_uuid(30));
    final neighbor = _id(_uuid(31));
    await _insertIntention(database, owner, title: 'Владелец');
    await _insertIntention(database, neighbor, title: 'Сосед');
    await _insertRelation(
      database,
      id: _uuid(130),
      sourceId: owner,
      relatedId: neighbor,
      type: 'need',
      isArchived: false,
    );

    final result = await repository.watchIntention(owner).first;

    expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
    final snapshot =
        (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;
    expect(snapshot.value?.intention.title, 'Владелец');
    expect(snapshot.value?.relationCounts.activeNeedOutgoing, 1);
  });

  test('не публикует частичный успех при повреждении соседства', () async {
    final owner = _id(_uuid(50));
    final neighbor = _id(_uuid(51));
    await _insertIntention(database, owner, title: 'Владелец');
    await _insertIntention(database, neighbor, title: 'Сосед');
    // Схема не проверяет формат идентификатора связи.
    await _insertRelation(
      database,
      id: 'не-uuid',
      sourceId: owner,
      relatedId: neighbor,
      type: 'need',
      isArchived: false,
    );

    final counts = await repository.getRelationCounts(owner);
    final details = await repository.watchIntention(owner).first;

    expect(
      counts,
      isA<ResultFailure<GraphSnapshot<RelationCounts>>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionCorruptionFailure>(),
      ),
    );
    expect(
      details,
      isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionCorruptionFailure>(),
      ),
    );
  });

  test('не публикует наблюдение при изменении другого намерения', () async {
    final watchedId = _id(_uuid(70));
    final changedId = _id(_uuid(71));
    await _insertIntention(database, watchedId, title: 'Наблюдаемое');
    await _insertIntention(database, changedId, title: 'Изменяемое');
    final snapshots = <Object>[];
    final subscription = repository
        .watchIntention(watchedId)
        .listen(snapshots.add);
    // Генератор `watchIntention` ждёт инвалидации, а не `yield`: отмена
    // завершилась бы только после неё, поэтому её не ожидают.
    addTearDown(() => subscription.cancel().ignore());
    while (snapshots.isEmpty) {
      await pumpEventQueue();
    }

    final result = await repository.execute(
      UpdateIntention(id: changedId, title: 'Изменённое', description: null),
    );
    expect(
      result,
      isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    );
    await pumpEventQueue();

    expect(snapshots, hasLength(1));
  });

  test('архивирует только непосредственные активные связи и возвращает абсолютные счётчики', () async {
    final owner = _id(_uuid(80));
    final firstNeighbor = _id(_uuid(81));
    final secondNeighbor = _id(_uuid(82));
    final archivedNeighbor = _id(_uuid(83));
    final unrelated = _id(_uuid(84));
    for (final id in [
      owner,
      firstNeighbor,
      secondNeighbor,
      archivedNeighbor,
      unrelated,
    ]) {
      await _insertIntention(
        database,
        id,
        title: 'Намерение ${id.toCanonicalString()}',
      );
    }
    await _insertRelation(
      database,
      id: _uuid(180),
      sourceId: owner,
      relatedId: firstNeighbor,
      type: 'need',
      isArchived: false,
    );
    await _insertRelation(
      database,
      id: _uuid(181),
      sourceId: secondNeighbor,
      relatedId: owner,
      type: 'can',
      isArchived: false,
    );
    await _insertRelation(
      database,
      id: _uuid(182),
      sourceId: firstNeighbor,
      relatedId: secondNeighbor,
      type: 'can',
      isArchived: false,
    );
    await _insertRelation(
      database,
      id: _uuid(183),
      sourceId: archivedNeighbor,
      relatedId: owner,
      type: 'need',
      isArchived: true,
    );
    await _insertRelation(
      database,
      id: _uuid(184),
      sourceId: archivedNeighbor,
      relatedId: unrelated,
      type: 'need',
      isArchived: false,
    );

    final result = await repository.execute(ArchiveIntention(owner));

    final confirmed = _confirmedCommand(result);
    final countChanges = {
      for (final change
          in confirmed.changes.whereType<IntentionRelationCountsChanged>())
        change.intentionId: change.counts,
    };
    expect(
      countChanges.keys,
      unorderedEquals([owner, firstNeighbor, secondNeighbor]),
    );
    expect(countChanges[owner]?.active, 0);
    expect(countChanges[owner]?.archived, 3);
    expect(countChanges[firstNeighbor]?.active, 1);
    expect(countChanges[firstNeighbor]?.archived, 1);
    expect(countChanges[secondNeighbor]?.active, 1);
    expect(countChanges[secondNeighbor]?.archived, 1);
    expect(await _relationArchiveStates(database), {
      _uuid(180): true,
      _uuid(181): true,
      _uuid(182): false,
      _uuid(183): true,
      _uuid(184): false,
    });
    final intentions = {
      for (final row in await database.select(database.intentions).get())
        row.id: row,
    };
    expect(intentions[owner.toCanonicalString()]?.isArchived, isTrue);
    expect(intentions[firstNeighbor.toCanonicalString()]?.isArchived, isFalse);
    expect(intentions[secondNeighbor.toCanonicalString()]?.isArchived, isFalse);
    expect(
      intentions[archivedNeighbor.toCanonicalString()]?.isArchived,
      isFalse,
    );
    expect(intentions[unrelated.toCanonicalString()]?.isArchived, isFalse);
    expect(
      intentions[owner.toCanonicalString()]?.updatedAt,
      DateTime.utc(2026, 9, 19).microsecondsSinceEpoch,
    );
    expect(
      intentions.entries
          .where((entry) => entry.key != owner.toCanonicalString())
          .map((entry) => entry.value.updatedAt),
      everyElement(1),
    );

    final restore = _confirmedCommand(
      await repository.execute(RestoreIntention(owner)),
    );

    expect(
      restore.changes.whereType<IntentionRelationCountsChanged>(),
      isEmpty,
    );
    expect(await _relationArchiveStates(database), {
      _uuid(180): true,
      _uuid(181): true,
      _uuid(182): false,
      _uuid(183): true,
      _uuid(184): false,
    });
    final restoredOwner = await (database.select(
      database.intentions,
    )..where((row) => row.id.equals(owner.toCanonicalString()))).getSingle();
    expect(restoredOwner.isArchived, isFalse);
  });

  test(
    'публикует после каскада только владельцу и соседям изменённых связей',
    () async {
      final owner = _id(_uuid(90));
      final activeNeighbor = _id(_uuid(91));
      final archivedNeighbor = _id(_uuid(92));
      final unrelated = _id(_uuid(93));
      for (final id in [owner, activeNeighbor, archivedNeighbor, unrelated]) {
        await _insertIntention(database, id);
      }
      await _insertRelation(
        database,
        id: _uuid(190),
        sourceId: owner,
        relatedId: activeNeighbor,
        type: 'need',
        isArchived: false,
      );
      await _insertRelation(
        database,
        id: _uuid(191),
        sourceId: archivedNeighbor,
        relatedId: owner,
        type: 'can',
        isArchived: true,
      );
      final snapshots = {
        for (final id in [owner, activeNeighbor, archivedNeighbor, unrelated])
          id: <Result<GraphSnapshot<IntentionDetails?>>>[],
      };
      final subscriptions = [
        for (final entry in snapshots.entries)
          repository.watchIntention(entry.key).listen(entry.value.add),
      ];
      // Генератор `watchIntention` ждёт инвалидации, а не `yield`: отмена
      // завершилась бы только после неё, поэтому её не ожидают.
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.cancel().ignore();
        }
      });
      Future<void> untilPublished(IntentionId id, int count) async {
        while (snapshots[id]!.length < count) {
          await pumpEventQueue();
        }
      }

      /// Число публикаций каждого наблюдения: владелец, сосед с активной
      /// связью, сосед с архивной связью и посторонний.
      List<int> published() => [
        for (final id in [owner, activeNeighbor, archivedNeighbor, unrelated])
          snapshots[id]!.length,
      ];
      for (final id in snapshots.keys) {
        await untilPublished(id, 1);
      }

      final archived = _confirmedCommand(
        await repository.execute(ArchiveIntention(owner)),
      );
      await untilPublished(owner, 2);
      await untilPublished(activeNeighbor, 2);
      await pumpEventQueue();

      final ownerSnapshot = _successfulSnapshot(snapshots[owner]!.last);
      final neighborSnapshot = _successfulSnapshot(
        snapshots[activeNeighbor]!.last,
      );
      expect(
        ownerSnapshot.revision.compareTo(archived.revision),
        GraphRevisionOrder.same,
      );
      expect(
        neighborSnapshot.revision.compareTo(archived.revision),
        GraphRevisionOrder.same,
      );
      expect(
        ownerSnapshot.value?.intention.archiveState,
        IntentionArchiveState.archived,
      );
      expect(ownerSnapshot.value?.relationCounts.active, 0);
      expect(ownerSnapshot.value?.relationCounts.archived, 2);
      expect(neighborSnapshot.value?.relationCounts.active, 0);
      expect(neighborSnapshot.value?.relationCounts.archived, 1);
      expect(published(), [2, 2, 1, 1]);

      // Восстановление не возвращает связи: меняется только владелец.
      final restored = _confirmedCommand(
        await repository.execute(RestoreIntention(owner)),
      );
      await untilPublished(owner, 3);
      await pumpEventQueue();
      expect(
        _successfulSnapshot(snapshots[owner]!.last).revision
            .compareTo(restored.revision),
        GraphRevisionOrder.same,
      );
      expect(published(), [3, 2, 1, 1]);

      // Повторное архивирование без активных связей меняет только владельца.
      final archivedWithoutActiveRelations = _confirmedCommand(
        await repository.execute(ArchiveIntention(owner)),
      );
      await untilPublished(owner, 4);
      await pumpEventQueue();
      expect(published(), [4, 2, 1, 1]);

      // Повтор без изменений ничего не публикует.
      final noOp = _confirmedCommand(
        await repository.execute(ArchiveIntention(owner)),
      );
      await pumpEventQueue();
      expect(
        archivedWithoutActiveRelations.revision.compareTo(noOp.revision),
        GraphRevisionOrder.same,
      );
      expect(published(), [4, 2, 1, 1]);
    },
  );
}

Future<void> _insertAllGroups(
  AppDatabase database,
  IntentionId owner,
  List<IntentionId> neighbors,
) async {
  final groups = [
    (incoming: true, type: 'need', archived: false),
    (incoming: false, type: 'need', archived: false),
    (incoming: true, type: 'can', archived: false),
    (incoming: false, type: 'can', archived: false),
    (incoming: true, type: 'need', archived: true),
    (incoming: false, type: 'need', archived: true),
    (incoming: true, type: 'can', archived: true),
    (incoming: false, type: 'can', archived: true),
  ];
  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    await _insertRelation(
      database,
      id: _uuid(100 + index),
      sourceId: group.incoming ? neighbors[index] : owner,
      relatedId: group.incoming ? owner : neighbors[index],
      type: group.type,
      isArchived: group.archived,
    );
  }
}

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  String title = 'Намерение',
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
    INSERT INTO intentions (id, title, created_at, updated_at)
    VALUES (?, ?, 1, 1)
  ''',
    [id.toCanonicalString(), title],
  ),
);

Future<void> _insertRelation(
  AppDatabase database, {
  required String id,
  required IntentionId sourceId,
  required IntentionId relatedId,
  required String type,
  required bool isArchived,
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      is_archived
    ) VALUES (?, ?, ?, ?, 1, ?)
  ''',
    [
      id,
      sourceId.toCanonicalString(),
      relatedId.toCanonicalString(),
      type,
      isArchived ? 1 : 0,
    ],
  ),
);

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';

ConfirmedGraphResult<IntentionCommandSuccess> _confirmedCommand(
  Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

GraphSnapshot<IntentionDetails?> _successfulSnapshot(
  Result<GraphSnapshot<IntentionDetails?>> result,
) {
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;
}

Future<Map<String, bool>> _relationArchiveStates(AppDatabase database) async =>
    {
      for (final row in await database.customSelect('''
    SELECT id, is_archived
    FROM long_term_relations
    ORDER BY id
  ''').get())
        row.read<String>('id'): row.read<int>('is_archived') == 1,
    };
