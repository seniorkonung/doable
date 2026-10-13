import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _SnapshotProbe probe;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _SnapshotProbe();
    database = await harness.openReadyDatabase(observer: probe);
    await seedDurabilityGraph(database);
    repository = durabilityRepository(database);
  });
  tearDown(() => harness.dispose());

  for (final (name, command) in <(String, LongTermRelationCommand)>[
    (
      'создание',
      CreateLongTermRelation(
        sourceIntentionId: durabilityIntention(5),
        relatedIntentionId: durabilityIntention(1),
        type: LongTermRelationType.can,
        priority: RelationPriority.p2,
        description: null,
      ),
    ),
    (
      'смена исходного намерения',
      UpdateLongTermRelation(
        relationId: durabilityRelation(101),
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(durabilityIntention(5)),
        ),
      ),
    ),
    (
      'смена связанного намерения',
      UpdateLongTermRelation(
        relationId: durabilityRelation(101),
        patch: LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(durabilityIntention(3)),
        ),
      ),
    ),
    (
      'смена типа',
      UpdateLongTermRelation(
        relationId: durabilityRelation(101),
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
        ),
      ),
    ),
    (
      'смена приоритета',
      UpdateLongTermRelation(
        relationId: durabilityRelation(101),
        patch: const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p4),
        ),
      ),
    ),
    (
      'смена описания',
      UpdateLongTermRelation(
        relationId: durabilityRelation(101),
        patch: LongTermRelationPatch(
          description: LongTermRelationDescriptionPatch.fromInput('Описание'),
        ),
      ),
    ),
    ('архивирование', ArchiveLongTermRelation(durabilityRelation(101))),
    ('удаление', DeleteLongTermRelation(durabilityRelation(101))),
  ]) {
    test('$name связи требует новой ленивой загрузки', () async {
      await repository.loadStatisticsRelationSnapshot();
      final reads = probe.reads;
      expect(await repository.execute(command), isA<GraphCommandSucceeded>());
      expect(probe.reads, reads);
      final graph = await repository.loadStatisticsRelationSnapshot();
      expect(probe.reads, greaterThan(reads));
      expect(_edges(graph), await _storedEdges(database));
      expect(_edges(graph, parents: true), _edges(graph));
    });
  }

  test('восстановление связи требует новой загрузки', () async {
    await repository.execute(ArchiveLongTermRelation(durabilityRelation(101)));
    await repository.loadStatisticsRelationSnapshot();
    final reads = probe.reads;
    expect(
      await repository.execute(
        RestoreLongTermRelation(durabilityRelation(101)),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      _edges(await repository.loadStatisticsRelationSnapshot()),
      contains((1, 2)),
    );
    expect(probe.reads, greaterThan(reads));
  });

  test('массовое удаление связей требует новой загрузки', () async {
    await repository.loadStatisticsRelationSnapshot();
    final reads = probe.reads;
    expect(
      await repository.execute(
        DeleteBlockingRelations.longTerm(
          intentionId: durabilityIntention(1),
          relationIds: [durabilityRelation(101), durabilityRelation(103)],
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(_edges(await repository.loadStatisticsRelationSnapshot()), {
      (2, 3),
      (1, 5),
    });
    expect(probe.reads, greaterThan(reads));
  });

  test('изменения выборов и данных намерений не перечитывают связи', () async {
    await repository.loadStatisticsRelationSnapshot();
    final reads = probe.reads;
    for (final command in <DailyChoiceCommand>[
      durabilityCreate(),
      UpdateDailyChoiceFields(
        choiceId: durabilityChoice(201),
        patch: const DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(false),
        ),
      ),
      ReplaceDailyChoicePath(
        choiceId: durabilityChoice(201),
        sourceIntentionId: durabilityIntention(1),
        selectedIntentionId: durabilityIntention(4),
        path: durabilityPath([103]),
      ),
      DeleteDailyChoice(durabilityChoice(201)),
    ]) {
      expect(await repository.execute(command), isA<GraphCommandSucceeded>());
      await repository.loadStatisticsRelationSnapshot();
      expect(probe.reads, reads);
    }
    for (final command in <IntentionCommand>[
      UpdateIntention(
        id: durabilityIntention(1),
        title: 'Название',
        description: 'Описание',
      ),
      EnableIntentionReadiness(durabilityIntention(1)),
      DisableIntentionReadiness(durabilityIntention(1)),
    ]) {
      expect(await repository.execute(command), isA<GraphCommandSucceeded>());
      await repository.loadStatisticsRelationSnapshot();
      expect(probe.reads, reads);
    }
    await repository.execute(DeleteLongTermRelation(durabilityRelation(104)));
    await repository.loadStatisticsRelationSnapshot();
    final afterDeletion = probe.reads;
    for (final command in <IntentionCommand>[
      ArchiveIntention(durabilityIntention(5)),
      RestoreIntention(durabilityIntention(5)),
      DeleteIntention(durabilityIntention(5)),
      const CreateIntention(title: 'Новое намерение', description: null),
    ]) {
      expect(await repository.execute(command), isA<GraphCommandSucceeded>());
      await repository.loadStatisticsRelationSnapshot();
      expect(probe.reads, afterDeletion);
    }
  });

  test(
    'операция без изменений и отказ после записи сохраняют снимок',
    () async {
      await repository.loadStatisticsRelationSnapshot();
      final reads = probe.reads;
      expect(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: durabilityRelation(101),
            patch: const LongTermRelationPatch(),
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      await repository.loadStatisticsRelationSnapshot();
      expect(probe.reads, reads);
      probe.failNextRelationUpdate = true;
      expect(
        await repository.execute(
          ArchiveLongTermRelation(durabilityRelation(101)),
        ),
        isA<GraphCommandFailed>(),
      );
      expect(
        _edges(await repository.loadStatisticsRelationSnapshot()),
        contains((1, 2)),
      );
      expect(probe.reads, reads);
    },
  );

  test('новая эпоха начинает отдельную загрузку снимка', () async {
    await repository.loadStatisticsRelationSnapshot();
    final reads = probe.reads;
    final nextEpoch = durabilityRepository(database);
    expect(
      _edges(await nextEpoch.loadStatisticsRelationSnapshot()),
      await _storedEdges(database),
    );
    expect(probe.reads, greaterThan(reads));
  });

  test('снимок содержит только активные связи в обоих направлениях', () async {
    await repository.execute(ArchiveLongTermRelation(durabilityRelation(104)));
    final graph = await repository.loadStatisticsRelationSnapshot();
    expect(_edges(graph), {(1, 2), (2, 3), (1, 4)});
    expect(graph.children, hasLength(3));
    expect(graph.intentionIds, hasLength(4));
    expect(_edges(graph, parents: true), _edges(graph));
    expect(graph.intentionIds.toSet(), {
      for (final number in [1, 2, 3, 4]) durabilityIntention(number),
    });
    expect(probe.reads, 1);
    await repository.loadStatisticsRelationSnapshot();
    expect(probe.reads, 1);
  });

  test('пустой снимок тоже переиспользуется', () async {
    await repository.execute(ArchiveIntention(durabilityIntention(1)));
    await repository.execute(ArchiveIntention(durabilityIntention(2)));
    expect(
      (await repository.loadStatisticsRelationSnapshot()).children,
      isEmpty,
    );
    final reads = probe.reads;
    expect(
      (await repository.loadStatisticsRelationSnapshot()).parents,
      isEmpty,
    );
    expect(probe.reads, reads);
  });

  test('изменение связей между порциями завершает одну попытку', () async {
    await _addRelations(database, 520);
    probe.pauseNextRead();
    final loading = repository.loadStatisticsRelationSnapshot();
    final expired = expectLater(
      loading,
      throwsA(isA<StatisticsSnapshotExpired>()),
    );
    await probe.entered!.future;
    final command = repository.execute(
      ArchiveLongTermRelation(durabilityRelation(101)),
    );
    probe.release!.complete();
    expect(await command, isA<GraphCommandSucceeded>());
    await expired;
    expect(
      probe.reads,
      1,
      reason: 'Устаревшая попытка не начинает новых чтений',
    );

    final graph = await repository.loadStatisticsRelationSnapshot();
    expect(_edges(graph), isNot(contains((1, 2))));
    expect(graph.children, hasLength(523));
    expect(_edges(graph, parents: true), _edges(graph));
    expect(probe.reads, greaterThan(2));
    expect(probe.largestPage, lessThanOrEqualTo(512));
    expect(probe.readsPerTransaction, everyElement(1));
  });

  test('правка намерения между порциями не мешает снимку', () async {
    await _addRelations(database, 520);
    probe.pauseNextRead();
    final loading = repository.loadStatisticsRelationSnapshot();
    await probe.entered!.future;
    final command = repository.execute(
      UpdateIntention(
        id: durabilityIntention(1),
        title: 'Новое название',
        description: null,
      ),
    );
    probe.release!.complete();
    expect(await command, isA<GraphCommandSucceeded>());
    final graph = await loading;
    expect(graph.children, hasLength(524));
    expect(_edges(graph, parents: true), _edges(graph));
    expect(probe.reads, greaterThan(1));
    final reads = probe.reads;
    await repository.loadStatisticsRelationSnapshot();
    expect(probe.reads, reads);
  });

  test('каскад архивирования делает загруженный снимок непригодным', () async {
    await repository.execute(durabilityCreate());
    await repository.loadStatisticsRelationSnapshot();
    final reads = probe.reads;
    final result = await repository.execute(
      ArchiveIntention(durabilityIntention(2)),
    );
    expect(result, isA<GraphCommandSucceeded>());
    final changes = (result as GraphCommandSucceeded).value.changes
        .whereType<LongTermRelationUpdatedChange>();
    expect(changes.map((change) => change.id).toSet(), {
      durabilityRelation(101),
      durabilityRelation(102),
    });
    for (final change in changes) {
      expect(change.before.scope, RelationScope.active);
      expect(change.after.scope, RelationScope.archived);
      expect(change.permissions.isConfirmed, isTrue);
      expect(change.permissions.canDelete, isFalse);
    }
    expect(probe.reads, reads, reason: 'Пересборка ленивая');
    final graph = await repository.loadStatisticsRelationSnapshot();
    expect(_edges(graph), {(1, 4), (1, 5)});
    expect(probe.reads, greaterThan(reads));
  });
}

Future<Set<(int, int)>> _storedEdges(AppDatabase database) async => {
  for (final row
      in await database
          .customSelect(
            'SELECT source_intention_id, related_intention_id FROM long_term_relations WHERE is_archived = 0',
          )
          .get())
    (
      int.parse(
        row.read<String>('source_intention_id').split('-').last,
        radix: 16,
      ),
      int.parse(
        row.read<String>('related_intention_id').split('-').last,
        radix: 16,
      ),
    ),
};

Set<(int, int)> _edges(
  ContributionRelationGraph graph, {
  bool parents = false,
}) {
  final offsets = parents ? graph.parentOffsets : graph.childOffsets;
  final neighbors = parents ? graph.parents : graph.children;
  int number(int index) => int.parse(
    graph.intentionIds[index].toCanonicalString().split('-').last,
    radix: 16,
  );
  return {
    for (var node = 0; node < graph.intentionIds.length; node++)
      for (var edge = offsets[node]; edge < offsets[node + 1]; edge++)
        parents
            ? (number(neighbors[edge]), number(node))
            : (number(node), number(neighbors[edge])),
  };
}

Future<void> _addRelations(AppDatabase database, int count) async {
  await database.transaction(() async {
    for (var i = 0; i < count; i++) {
      await database.customStatement(
        '''INSERT INTO intentions
           (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)''',
        [durabilityUuid(1000 + i), 'Намерение $i'],
      );
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority)
           VALUES (?, ?, ?, 'need', 2)''',
        [durabilityUuid(2000 + i), durabilityUuid(1), durabilityUuid(1000 + i)],
      );
    }
  });
}

final class _SnapshotProbe extends LocalDatabaseConnectionObserver {
  var failNextRelationUpdate = false;
  var reads = 0;
  var largestPage = 0;
  var _transactionReads = 0;
  var _inTransaction = false;
  final readsPerTransaction = <int>[];
  Completer<void>? entered;
  Completer<void>? release;

  void pauseNextRead() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (failNextRelationUpdate &&
        statement.operation == LocalDatabaseSqlOperation.update &&
        statement.statements.single.contains('long_term_relations')) {
      failNextRelationUpdate = false;
      throw StateError('Отказ после записи до подтверждения');
    }
  }

  @override
  void onTransactionStarted() {
    _inTransaction = true;
    _transactionReads = 0;
  }

  @override
  void onTransactionFinished() {
    if (_transactionReads > 0) readsPerTransaction.add(_transactionReads);
    _inTransaction = false;
  }

  @override
  Future<List<Map<String, Object?>>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) async {
    if (!statement.statements.single.startsWith(
      'SELECT creation_sequence, source_intention_id, related_intention_id',
    )) {
      return rows;
    }
    expect(_inTransaction, isTrue);
    reads++;
    _transactionReads++;
    if (rows.length > largestPage) largestPage = rows.length;
    if (entered case final gate? when !gate.isCompleted) {
      gate.complete();
      await release!.future;
    }
    return rows;
  }
}
