import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/contribution_reachability_reference.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Связи (номер, источник, связанное, архивирована).
const _relations = [
  (101, 1, 2, false),
  (102, 2, 3, false),
  (103, 3, 4, true),
  (104, 5, 3, false),
];

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _SeedProbe probe;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _SeedProbe();
    database = await harness.openReadyDatabase(
      setup: (db) => raw = db,
      observer: probe,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 8; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      for (final (number, source, related, archived) in _relations) {
        seedRelation(
          raw,
          seedUuid(number),
          seedUuid(source),
          seedUuid(related),
        );
        if (archived) {
          raw.execute(
            'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
            [seedUuid(number)],
          );
        }
      }
    });
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => harness.dispose());

  void addAction(
    int number,
    String date,
    List<int> path, {
    bool completed = false,
  }) => seedRawGraph(
    raw,
    () => seedAction(
      raw,
      id: seedUuid(number),
      path: [for (final intention in path) seedUuid(intention)],
      date: date,
      isCompleted: completed,
    ),
  );

  Future<StatisticsSeedGroupsSnapshot> read({StatisticsPeriod? period}) =>
      repository.readStatisticsSeedGroups(
        period: period ?? StatisticsMonth(2026, 10),
      );

  Map<String, (int, int)> grouped(StatisticsSeedGroupsSnapshot snapshot) => {
    for (final group in snapshot.groups)
      group.seeds.map((id) => id.toCanonicalString()).join(','): (
        group.counts.planned,
        group.counts.contribution,
      ),
  };

  String key(List<int> seeds) => seeds.map(seedUuid).join(',');

  test('опорные — существующие намерения пути, за которыми следующее не идёт '
      'по активной связи; равные наборы объединяются', () async {
    final paths = [
      [1, 2, 3],
      [1, 2, 3],
      [5, 3],
      [3, 4],
      [2, 6],
      [8],
      [1, 8, 3],
    ];
    for (var i = 0; i < paths.length; i++) {
      addAction(201 + i, '2026-10-12', paths[i], completed: i.isEven);
    }
    expect(
      await repository.execute(ArchiveIntention(seedIntentionId(6))),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await repository.execute(DeleteIntention(seedIntentionId(8))),
      isA<GraphCommandSucceeded>(),
    );

    final snapshot = await read();
    expect(grouped(snapshot), {
      key([3]): (3, 2),
      key([3, 4]): (1, 0),
      key([2, 6]): (1, 1),
      key([1, 3]): (1, 1),
    });
    // Действие только с удалённым намерением опорной группы не даёт,
    // но остаётся в сводке.
    expect(snapshot.summary.planned, 7);
    expect(snapshot.summary.contribution, 4);

    final relations = [
      for (final (_, source, related, archived) in _relations)
        (
          source: seedIntentionId(source),
          target: seedIntentionId(related),
          archived: archived,
        ),
    ];
    final expected = referenceActionContributionCounts(
      relations: relations,
      actions: [
        for (var i = 0; i < paths.length; i++)
          (path: paths[i].map(seedIntentionId).toList(), completed: i.isEven),
      ],
      deleted: {seedIntentionId(8)},
    );
    final actual = computeContributionReachability(
      await repository.loadStatisticsRelationSnapshot(),
      snapshot.groups,
    );
    expect({
      for (final row in actual)
        row.intentionId: (
          planned: row.counts.planned,
          contribution: row.counts.contribution,
        ),
    }, expected);
  });

  test(
    'группы и сводка ограничены месяцем и годом, включая високосный день',
    () async {
      final dates = [
        '2023-12-31',
        '2024-01-01',
        '2024-01-31',
        '2024-02-01',
        '2024-02-29',
        '2024-03-01',
        '2024-12-31',
        '2025-01-01',
      ];
      for (var i = 0; i < dates.length; i++) {
        addAction(201 + i, dates[i], [1, 2, 3], completed: i == 3);
      }
      final month = await read(period: StatisticsMonth(2024, 2));
      expect(grouped(month), {
        key([3]): (2, 1),
      });
      expect((month.summary.planned, month.summary.contribution), (2, 1));
      final year = await read(period: StatisticsYear(2024));
      expect(grouped(year), {
        key([3]): (6, 1),
      });
      expect((year.summary.planned, year.summary.contribution), (6, 1));
      final empty = await read();
      expect(empty.groups, isEmpty);
      expect(empty.summary.planned, 0);
    },
  );

  test('удаление действия убирает его группу на ревизии команды', () async {
    addAction(201, '2026-10-12', [2, 6]);
    addAction(202, '2026-10-12', [1, 2, 3], completed: true);
    final before = await read();
    expect(grouped(before), {
      key([2, 6]): (1, 0),
      key([3]): (1, 1),
    });
    final result = await repository.execute(DeleteAction(seedActionId(201)));
    expect(result, isA<GraphCommandSucceeded>());
    final after = await read();
    expect(grouped(after), {
      key([3]): (1, 1),
    });
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
    expect(
      after.revision.compareTo(
        (result as GraphCommandSucceeded).value.revision,
      ),
      GraphRevisionOrder.same,
    );
  });

  test('команда между запросами не смешивает сводку и веса групп', () async {
    addAction(201, '2026-10-12', [1]);
    probe.entered = Completer<void>();
    probe.release = Completer<void>();
    final reading = read();
    await probe.entered!.future;
    final command = repository.execute(
      UpdateActionFields(
        actionId: seedActionId(201),
        patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
      ),
    );
    probe.release!.complete();
    final before = await reading;
    expect(await command, isA<GraphCommandSucceeded>());
    final after = await read();
    expect(before.summary.contribution, 0);
    expect(before.groups.single.counts.contribution, 0);
    expect(after.summary.contribution, 1);
    expect(after.groups.single.counts.contribution, 1);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
  });

  for (final (name, error, failure) in <(String, Object, Matcher)>[
    (
      'недоступность',
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      isA<StatisticsReadUnavailableFailure>(),
    ),
    (
      'повреждение',
      sqlite.SqliteException(message: 'Повреждение', extendedResultCode: 11),
      isA<StatisticsReadCorruptionFailure>(),
    ),
    (
      'неизвестный отказ',
      StateError('Неизвестный отказ'),
      isA<StatisticsReadUnexpectedFailure>(),
    ),
  ]) {
    test('отказ подготовки групп отклоняет всю выдачу: $name', () async {
      addAction(201, '2026-10-12', [1]);
      probe.failure = error;
      await expectLater(read(), throwsA(failure));
    });
  }

  test('некорректная календарная дата даёт отказ всего чтения', () async {
    addAction(201, '2026-02-30', [1]);
    await expectLater(
      read(period: StatisticsYear(2026)),
      throwsA(isA<StatisticsReadCorruptionFailure>()),
    );
  });

  for (final (field, value) in <(String, Object)>[
    ('seed_key', 'не идентификатор'),
    ('planned', -1),
    ('contribution', 2),
  ]) {
    test(
      'декодирование опорных групп отклоняет повреждённое поле $field',
      () async {
        addAction(201, '2026-10-12', [1], completed: true);
        probe.replaceField = field;
        probe.replacement = value;
        await expectLater(
          read(),
          throwsA(isA<StatisticsReadCorruptionFailure>()),
        );
      },
    );
  }
}

final class _SeedProbe extends LocalDatabaseConnectionObserver {
  Object? failure;
  String? replaceField;
  Object? replacement;
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.single.contains('seed_key')) {
      return;
    }
    if (failure case final error?) throw error;
    if (entered case final gate? when !gate.isCompleted) {
      gate.complete();
      await release!.future;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final field = replaceField;
    if (field == null || rows.isEmpty || !rows.first.containsKey('seed_key')) {
      return rows;
    }
    return [
      {...rows.first, field: replacement},
      ...rows.skip(1),
    ];
  }
}
