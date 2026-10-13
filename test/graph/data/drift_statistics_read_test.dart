import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late PersonalGraphRepository repository;
  late ProviderContainer container;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadGate gate;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    gate = _ReadGate();
    database = await harness.openReadyDatabase(observer: gate);
    diagnostics = InMemoryDiagnosticsSink();
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 10, 12),
            diagnostics,
          ),
        ),
      ],
    );
    repository = container.read(personalGraphRepositoryProvider);
    await seedDurabilityGraph(database);
    await database.customStatement(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority)
         VALUES (?, ?, ?, 'need', 2)''',
      [durabilityUuid(105), durabilityUuid(3), durabilityUuid(4)],
    );
  });
  tearDown(() async {
    container.dispose();
    await harness.dispose();
  });

  Future<void> addChoice(
    int number,
    String date, {
    bool completed = false,
    int source = 1,
    int selected = 4,
    List<int> path = const [101, 102, 105],
  }) async {
    await database.customStatement(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          is_completed) VALUES (?, ?, ?, ?, ?)''',
      [
        durabilityUuid(number),
        durabilityUuid(source),
        durabilityUuid(selected),
        date,
        completed ? 1 : 0,
      ],
    );
    for (var index = 0; index < path.length; index++) {
      await database.customStatement(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          durabilityUuid(number * 10 + index),
          durabilityUuid(number),
          durabilityUuid(path[index]),
          index == 0 ? null : durabilityUuid(number * 10 + index - 1),
        ],
      );
    }
  }

  Future<StatisticsFirstPage> first(
    StatisticsView view, {
    StatisticsPeriod? period,
    CalendarDate? localDate,
    int pageSize = 100,
  }) async {
    final result = await repository.getStatisticsPage(
      StatisticsQuery(
        period: period ?? StatisticsMonth(2026, 10),
        view: view,
        localDate: localDate ?? CalendarDate.fromParts(2026, 10, 12),
        pageSize: pageSize,
      ),
    );
    expect(result, isA<StatisticsPageSuccess>());
    return (result as StatisticsPageSuccess).value as StatisticsFirstPage;
  }

  test(
    'три вида учитывают дубликаты и каждое промежуточное намерение',
    () async {
      await addChoice(201, '2026-10-01', completed: true);
      await addChoice(202, '2026-10-01', completed: true);
      await addChoice(203, '2026-10-11');
      await addChoice(204, '2026-10-12', path: [103]);
      await addChoice(205, '2026-10-31', path: [103]);
      await addChoice(206, '2026-09-30', completed: true);
      await addChoice(207, '2026-11-01', completed: true);

      for (final (view, expected) in [
        (StatisticsView.sourceIntentions, [(1, 5, 2)]),
        (StatisticsView.intermediateIntentions, [(3, 3, 2), (2, 3, 2)]),
        (StatisticsView.selectedActions, [(4, 5, 2)]),
      ]) {
        final page = await first(view);
        expect(page.totalItems, expected.length);
        expect(
          page.items.map(
            (item) => (item.id, item.counts.planned, item.counts.contribution),
          ),
          expected.map(
            (value) => (durabilityIntention(value.$1), value.$2, value.$3),
          ),
        );
        expect(page.summary.counts.planned, 5);
        expect(page.summary.counts.contribution, 2);
        expect(page.summary.uncompleted.missed, 1);
        expect(page.summary.uncompleted.upcoming, 2);
        expect(page.nextCursor, isNull);
      }
    },
  );

  test('пустой промежуточный вид сохраняет ненулевую сводку периода', () async {
    await addChoice(201, '2026-10-12', path: [103]);
    final page = await first(StatisticsView.intermediateIntentions);
    expect(page.items, isEmpty);
    expect(page.totalItems, 0);
    expect(page.summary.counts.planned, 1);
    expect(page.summary.counts.contribution, 0);
    expect(page.summary.uncompleted.upcoming, 1);
    final empty = await first(
      StatisticsView.sourceIntentions,
      period: StatisticsMonth(2025, 3),
    );
    expect(empty.items, isEmpty);
    expect(empty.summary.counts.planned, 0);
    expect(empty.summary.uncompleted.missed, 0);
    expect(empty.summary.uncompleted.upcoming, 0);
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
      await addChoice(number, date);
    }
    final month = await first(
      StatisticsView.sourceIntentions,
      period: StatisticsMonth(2024, 2),
      localDate: CalendarDate.fromParts(2024, 2, 29),
    );
    expect(month.summary.counts.planned, 2);
    expect(month.summary.uncompleted.missed, 1);
    expect(month.summary.uncompleted.upcoming, 1);
    final year = await first(
      StatisticsView.sourceIntentions,
      period: StatisticsYear(2024),
    );
    expect(year.summary.counts.planned, 5);
    expect(year.summary.uncompleted.missed, 5);
    final nextDay = await first(
      StatisticsView.sourceIntentions,
      period: StatisticsMonth(2024, 2),
      localDate: CalendarDate.fromParts(2024, 3, 1),
    );
    expect(nextDay.summary.uncompleted.missed, 2);
    expect(nextDay.summary.uncompleted.upcoming, 0);
  });

  test(
    'текущие названия и архивные отметки не меняют сохранённый вклад',
    () async {
      await addChoice(201, '2026-10-12', completed: true);
      expect(
        await repository.execute(
          DisableIntentionReadiness(durabilityIntention(4)),
        ),
        isA<GraphCommandSucceeded>(),
      );
      for (final number in [1, 2, 3, 4]) {
        expect(
          await repository.execute(
            UpdateIntention(
              id: durabilityIntention(number),
              title: 'Новое название $number',
              description: null,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        expect(
          await repository.execute(
            ArchiveIntention(durabilityIntention(number)),
          ),
          isA<GraphCommandSucceeded>(),
        );
      }
      for (final view in const [
        StatisticsView.sourceIntentions,
        StatisticsView.intermediateIntentions,
        StatisticsView.selectedActions,
      ]) {
        final page = await first(view);
        expect(page.items, isNotEmpty);
        for (final item in page.items) {
          expect(item.archiveState, IntentionArchiveState.archived);
          expect(item.title, startsWith('Новое название'));
          expect(item.counts.planned, 1);
          expect(item.counts.contribution, 1);
        }
      }
    },
  );

  test('порции всех видов сохраняют полный порядок, включая равные и нулевые вклады', () async {
    final weights = [(3, 2), (2, 2), (2, 1), (2, 1), (2, 0), (2, 0)];
    for (var index = 0; index < weights.length; index++) {
      final source = 10 + index * 10;
      for (var offset = 0; offset < 3; offset++) {
        await database.customStatement(
          '''INSERT INTO intentions
             (id, title, is_action_ready, created_at, updated_at)
             VALUES (?, ?, ?, 1, 1)''',
          [
            durabilityUuid(source + offset),
            'Участник ${source + offset}',
            offset == 2 ? 1 : 0,
          ],
        );
      }
      final relation = 1000 + index * 2;
      for (var offset = 0; offset < 2; offset++) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id, type, priority)
             VALUES (?, ?, ?, 'need', 1)''',
          [
            durabilityUuid(relation + offset),
            durabilityUuid(source + offset),
            durabilityUuid(source + offset + 1),
          ],
        );
      }
      for (var copy = 0; copy < weights[index].$1; copy++) {
        await addChoice(
          300 + index * 3 + copy,
          '2026-10-12',
          completed: copy < weights[index].$2,
          source: source,
          selected: source + 2,
          path: [relation, relation + 1],
        );
      }
    }
    for (final (view, offset) in const [
      (StatisticsView.sourceIntentions, 0),
      (StatisticsView.intermediateIntentions, 1),
      (StatisticsView.selectedActions, 2),
    ]) {
      final page = await first(view, pageSize: 2);
      expect(page.totalItems, 6);
      expect(page.items, hasLength(2));
      expect(page.summary.counts.planned, 13);
      expect(page.summary.counts.contribution, 6);
      final items = [...page.items];
      var cursor = page.nextCursor;
      while (cursor != null) {
        final result = await repository.getStatisticsPage(
          StatisticsQuery(
            period: StatisticsMonth(2026, 10),
            view: view,
            localDate: CalendarDate.fromParts(2026, 10, 12),
            pageSize: 2,
            cursor: cursor,
          ),
        );
        expect(result, isA<StatisticsPageSuccess>());
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
        for (final number in [10, 20, 40, 30, 60, 50])
          durabilityIntention(number + offset),
      ]);
      expect(
        items.map((item) => (item.counts.planned, item.counts.contribution)),
        [(3, 2), (2, 2), (2, 1), (2, 1), (2, 0), (2, 0)],
      );
    }
  });

  test('курсор отклоняется после смены условий, команды или эпохи', () async {
    await addChoice(201, '2026-10-12');
    final page = await first(
      StatisticsView.intermediateIntentions,
      pageSize: 1,
    );
    final cursor = page.nextCursor!;
    StatisticsQuery query({
      StatisticsPeriod? period,
      StatisticsView? view,
      CalendarDate? localDate,
      int pageSize = 1,
    }) => StatisticsQuery(
      period: period ?? StatisticsMonth(2026, 10),
      view: view ?? StatisticsView.intermediateIntentions,
      localDate: localDate ?? CalendarDate.fromParts(2026, 10, 12),
      pageSize: pageSize,
      cursor: cursor,
    );
    for (final changed in [
      query(period: StatisticsYear(2026)),
      query(view: StatisticsView.sourceIntentions),
      query(view: StatisticsView.throughRelations),
      query(localDate: CalendarDate.fromParts(2026, 10, 13)),
      query(pageSize: 2),
    ]) {
      expect(
        (await repository.getStatisticsPage(
          changed,
        ) as StatisticsPageError).failure,
        isA<StatisticsSnapshotExpired>(),
      );
    }
    final anotherEpoch = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      diagnostics,
    );
    expect(
      (await anotherEpoch.getStatisticsPage(
        query(),
      ) as StatisticsPageError).failure,
      isA<StatisticsSnapshotExpired>(),
    );
    expect(
      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      (await repository.getStatisticsPage(
        query(),
      ) as StatisticsPageError).failure,
      isA<StatisticsSnapshotExpired>(),
    );
    final current = await first(StatisticsView.intermediateIntentions);
    expect(current.summary.counts.contribution, 1);
    expect(current.revision.compareTo(page.revision), GraphRevisionOrder.newer);
  });

  test(
    'команда во время чтения не смешивает сводку и элементы снимка',
    () async {
      await addChoice(201, '2026-10-12');
      gate.entered = Completer<void>();
      gate.release = Completer<void>();
      final reading = first(StatisticsView.sourceIntentions);
      await gate.entered!.future;
      final command = repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      gate.release!.complete();
      final before = await reading;
      expect(await command, isA<GraphCommandSucceeded>());
      final after = await first(StatisticsView.sourceIntentions);
      expect(before.summary.counts.contribution, 0);
      expect(before.items.single.counts.contribution, 0);
      expect(after.summary.counts.contribution, 1);
      expect(after.items.single.counts.contribution, 1);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
    },
  );
}

final class _ReadGate extends LocalDatabaseConnectionObserver {
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        entered == null ||
        entered!.isCompleted) {
      return;
    }
    entered!.complete();
    await release!.future;
  }
}
