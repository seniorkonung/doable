import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadTrace trace;

  DriftPersonalGraphRepository newRepository() => DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 10, 12),
    diagnostics,
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    trace = _ReadTrace();
    database = await harness.openReadyDatabase(
      setup: (db) => raw = db,
      observer: trace,
    );
    diagnostics = InMemoryDiagnosticsSink();
    repository = newRepository();
    seedRawGraph(raw, () {
      for (var number = 1; number <= 9; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
    });
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

  StatisticsQuery query(
    StatisticsView view, {
    StatisticsPeriod? period,
    int pageSize = 100,
    StatisticsCursor? cursor,
  }) => StatisticsQuery(
    period: period ?? StatisticsMonth(2026, 10),
    view: view,
    pageSize: pageSize,
    cursor: cursor,
  );

  Future<StatisticsFirstPage> first(
    StatisticsView view, {
    StatisticsPeriod? period,
    int pageSize = 100,
  }) async {
    final result = await repository.getStatisticsPage(
      query(view, period: period, pageSize: pageSize),
    );
    expect(result, isA<StatisticsPageSuccess>());
    return (result as StatisticsPageSuccess).value as StatisticsFirstPage;
  }

  List<(int, int, int)> counted(StatisticsPage page) => [
    for (final item in page.items)
      (
        int.parse(item.title.split(' ').last),
        item.counts.planned,
        item.counts.contribution,
      ),
  ];

  test('виды засчитывают действие по позициям пути, а путь из одного '
      'намерения — корневым и конечным', () async {
    addAction(201, '2026-10-01', [1, 2, 3], completed: true);
    // Полный дубликат учитывается самостоятельно.
    addAction(202, '2026-10-01', [1, 2, 3], completed: true);
    addAction(203, '2026-10-11', [1, 4, 5, 3]);
    addAction(204, '2026-10-31', [6]);
    addAction(205, '2026-09-30', [1, 2, 3], completed: true);
    addAction(206, '2026-11-01', [1, 2, 3], completed: true);

    for (final (view, expected) in [
      (StatisticsView.rootIntentions, [(1, 3, 2), (6, 1, 0)]),
      (
        StatisticsView.intermediateIntentions,
        [(2, 2, 2), (5, 1, 0), (4, 1, 0)],
      ),
      (StatisticsView.terminalIntentions, [(3, 3, 2), (6, 1, 0)]),
    ]) {
      final page = await first(view);
      expect(counted(page), expected, reason: view.name);
      expect(page.totalItems, expected.length);
      expect(page.nextCursor, isNull);
      expect(page.summary.planned, 4);
      expect(page.summary.contribution, 2);
    }
  });

  test('удалённое намерение исчезает из вида без передачи роли соседям, '
      'а сводка по-прежнему считает его действия', () async {
    addAction(201, '2026-10-12', [7, 2, 3], completed: true);
    addAction(202, '2026-10-12', [8], completed: true);
    for (final number in [7, 8]) {
      expect(
        await repository.execute(DeleteIntention(seedIntentionId(number))),
        isA<GraphCommandSucceeded>(),
      );
    }

    final root = await first(StatisticsView.rootIntentions);
    expect(root.items, isEmpty);
    expect(root.totalItems, 0);
    expect(root.summary.planned, 2);
    expect(root.summary.contribution, 2);
    expect(counted(await first(StatisticsView.intermediateIntentions)), [
      (2, 1, 1),
    ]);
    expect(counted(await first(StatisticsView.terminalIntentions)), [
      (3, 1, 1),
    ]);
  });

  test('пустой вид сохраняет сводку периода, а период без действий '
      'даёт нулевую сводку', () async {
    addAction(201, '2026-10-12', [1, 2]);
    final page = await first(StatisticsView.intermediateIntentions);
    expect(page.items, isEmpty);
    expect(page.totalItems, 0);
    expect(page.summary.planned, 1);
    expect(page.summary.contribution, 0);

    final empty = await first(
      StatisticsView.rootIntentions,
      period: StatisticsMonth(2025, 3),
    );
    expect(empty.items, isEmpty);
    expect(empty.summary.planned, 0);
    expect(empty.summary.contribution, 0);
  });

  test('месяц и год включают границы и високосный день', () async {
    for (final (number, date) in [
      (201, '2023-12-31'),
      (202, '2024-01-01'),
      (203, '2024-02-01'),
      (204, '2024-02-29'),
      (205, '2024-03-01'),
      (206, '2024-12-31'),
      (207, '2025-01-01'),
    ]) {
      addAction(number, date, [1]);
    }
    final month = await first(
      StatisticsView.rootIntentions,
      period: StatisticsMonth(2024, 2),
    );
    expect(month.summary.planned, 2);
    expect(counted(month), [(1, 2, 0)]);
    final year = await first(
      StatisticsView.rootIntentions,
      period: StatisticsYear(2024),
    );
    expect(year.summary.planned, 5);
  });

  test(
    'архивирование и новые названия не меняют роли сохранённого пути',
    () async {
      addAction(201, '2026-10-12', [1, 2, 3], completed: true);
      for (final number in [1, 2, 3]) {
        expect(
          await repository.execute(
            UpdateIntention(
              id: seedIntentionId(number),
              title: 'Новое название $number',
              description: null,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        expect(
          await repository.execute(ArchiveIntention(seedIntentionId(number))),
          isA<GraphCommandSucceeded>(),
        );
      }
      for (final (view, number) in [
        (StatisticsView.rootIntentions, 1),
        (StatisticsView.intermediateIntentions, 2),
        (StatisticsView.terminalIntentions, 3),
      ]) {
        final item = (await first(view)).items.single;
        expect(item.id, seedIntentionId(number));
        expect(item.title, 'Новое название $number');
        expect(item.archiveState, IntentionArchiveState.archived);
        expect((item.counts.planned, item.counts.contribution), (1, 1));
      }
    },
  );

  test('порции всех видов идут по запланированному вкладу, вкладу и '
      'идентификатору без повторов и пропусков', () async {
    // Пары (запланировано, выполнено) для путей из трёх намерений.
    const weights = [(2, 0), (3, 1), (2, 2), (2, 1), (2, 1), (2, 0)];
    var number = 300;
    seedRawGraph(raw, () {
      for (var index = 0; index < weights.length; index++) {
        final first = 10 + index * 10;
        for (var offset = 0; offset < 3; offset++) {
          seedIntention(
            raw,
            seedUuid(first + offset),
            'Намерение ${first + offset}',
          );
        }
        for (var copy = 0; copy < weights[index].$1; copy++) {
          seedAction(
            raw,
            id: seedUuid(number++),
            path: [
              for (var offset = 0; offset < 3; offset++)
                seedUuid(first + offset),
            ],
            date: '2026-10-12',
            isCompleted: copy < weights[index].$2,
          );
        }
      }
    });
    for (final (view, offset) in const [
      (StatisticsView.rootIntentions, 0),
      (StatisticsView.intermediateIntentions, 1),
      (StatisticsView.terminalIntentions, 2),
    ]) {
      final page = await first(view, pageSize: 2);
      expect(page.totalItems, 6);
      expect(page.items, hasLength(2));
      expect(page.summary.planned, 13);
      expect(page.summary.contribution, 5);
      final items = [...page.items];
      var cursor = page.nextCursor;
      while (cursor != null) {
        final result = await repository.getStatisticsPage(
          query(view, pageSize: 2, cursor: cursor),
        );
        final continuation = (result as StatisticsPageSuccess).value;
        expect(continuation, isA<StatisticsContinuationPage>());
        expect(continuation.items.length, lessThanOrEqualTo(2));
        expect(
          continuation.revision.compareTo(page.revision),
          GraphRevisionOrder.same,
        );
        items.addAll(continuation.items);
        cursor = continuation.nextCursor;
      }
      expect(items.map((item) => item.id), [
        for (final first in [20, 30, 50, 40, 60, 10])
          seedIntentionId(first + offset),
      ]);
      expect(
        items.map((item) => (item.counts.planned, item.counts.contribution)),
        [(3, 1), (2, 2), (2, 1), (2, 1), (2, 0), (2, 0)],
      );
    }
  });

  test('курсор отклоняется после смены условий, изменения действия или '
      'эпохи', () async {
    addAction(201, '2026-10-12', [1, 2, 3]);
    addAction(202, '2026-10-12', [4, 5, 6]);
    final page = await first(
      StatisticsView.intermediateIntentions,
      pageSize: 1,
    );
    final cursor = page.nextCursor!;
    Future<StatisticsReadFailure> failure(
      DriftPersonalGraphRepository reader,
      StatisticsQuery changed,
    ) async => ((await reader.getStatisticsPage(
      changed,
    )) as StatisticsPageError).failure;

    for (final changed in [
      query(
        StatisticsView.intermediateIntentions,
        period: StatisticsYear(2026),
        pageSize: 1,
        cursor: cursor,
      ),
      query(StatisticsView.rootIntentions, pageSize: 1, cursor: cursor),
      query(StatisticsView.throughRelations, pageSize: 1, cursor: cursor),
      query(StatisticsView.intermediateIntentions, pageSize: 2, cursor: cursor),
    ]) {
      expect(
        await failure(repository, changed),
        isA<StatisticsSnapshotExpired>(),
      );
    }
    final same = query(
      StatisticsView.intermediateIntentions,
      pageSize: 1,
      cursor: cursor,
    );
    expect(
      await failure(newRepository(), same),
      isA<StatisticsSnapshotExpired>(),
    );
    expect(
      await repository.execute(
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(await failure(repository, same), isA<StatisticsSnapshotExpired>());
    final current = await first(StatisticsView.intermediateIntentions);
    expect(current.summary.contribution, 1);
    expect(current.revision.compareTo(page.revision), GraphRevisionOrder.newer);
  });

  test('удаление действия убирает его из сводки и видов', () async {
    addAction(201, '2026-10-12', [1, 2]);
    addAction(202, '2026-10-12', [1], completed: true);
    expect(
      await repository.execute(DeleteAction(seedActionId(201))),
      isA<GraphCommandSucceeded>(),
    );
    final page = await first(StatisticsView.rootIntentions);
    expect(counted(page), [(1, 1, 1)]);
    expect((page.summary.planned, page.summary.contribution), (1, 1));
  });

  test(
    'команда во время чтения не смешивает сводку и элементы снимка',
    () async {
      addAction(201, '2026-10-12', [1]);
      trace.entered = Completer<void>();
      trace.release = Completer<void>();
      final reading = first(StatisticsView.rootIntentions);
      await trace.entered!.future;
      final command = repository.execute(
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      );
      trace.release!.complete();
      final before = await reading;
      expect(await command, isA<GraphCommandSucceeded>());
      final after = await first(StatisticsView.rootIntentions);
      expect(before.summary.contribution, 0);
      expect(before.items.single.counts.contribution, 0);
      expect(after.summary.contribution, 1);
      expect(after.items.single.counts.contribution, 1);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
    },
  );

  test('сводка и виды по ролям читают действия периода по индексу даты, '
      'а строки пути — по первичному ключу', () async {
    addAction(201, '2026-10-12', [1, 2, 3]);
    final statements = <LocalDatabaseSqlStatement>[];
    trace.record = statements;
    for (final view in [
      StatisticsView.rootIntentions,
      StatisticsView.intermediateIntentions,
      StatisticsView.terminalIntentions,
    ]) {
      await first(view);
    }
    trace.record = null;
    final plans = [
      for (final statement in statements)
        if (statement.statements.single.contains('FROM actions'))
          raw
              .select(
                'EXPLAIN QUERY PLAN ${statement.statements.single}',
                statement.arguments,
              )
              .map((row) => row['detail'] as String)
              .join('\n'),
    ];
    // Сводка и агрегат каждого из трёх видов.
    expect(plans, hasLength(6));
    expect(
      plans.where(
        (plan) => plan.contains(
          'SEARCH p USING INDEX sqlite_autoindex_action_path_items_1 '
          '(action_id=?',
        ),
      ),
      hasLength(3),
    );
    for (final plan in plans) {
      expect(
        plan,
        contains(
          'INDEX actions_date_completion_schedule_order (date>? AND date<?)',
        ),
      );
      // Просматриваются только промежуточные результаты агрегата.
      expect(plan, isNot(matches(RegExp(r'SCAN (a|p|n|i|actions)\b'))));
    }
  });
}

final class _ReadTrace extends LocalDatabaseConnectionObserver {
  Completer<void>? entered;
  Completer<void>? release;
  List<LocalDatabaseSqlStatement>? record;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    record?.add(statement);
    if (entered == null || entered!.isCompleted) return;
    entered!.complete();
    await release!.future;
  }
}
