import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

const _relations = [
  (101, 1, 2),
  (102, 2, 3),
  (103, 1, 4),
  (104, 1, 5),
  (105, 4, 2),
  (106, 2, 1),
  (107, 5, 3),
  (108, 2, 4),
  (109, 4, 3),
];

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _SourceProbe probe;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _SourceProbe();
    database = await harness.openReadyDatabase(observer: probe);
    await seedDurabilityGraph(database);
    await database.customStatement('UPDATE intentions SET is_action_ready = 1');
    for (final (number, source, target) in _relations.skip(4)) {
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority)
           VALUES (?, ?, ?, 'need', 2)''',
        [
          durabilityUuid(number),
          durabilityUuid(source),
          durabilityUuid(target),
        ],
      );
    }
    repository = durabilityRepository(database);
  });
  tearDown(() => harness.dispose());

  Future<void> addChoice(
    int number,
    List<int> path, {
    String date = '2026-10-12',
    bool completed = true,
  }) async {
    await database.customStatement(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date, is_completed)
         VALUES (?, ?, ?, ?, ?)''',
      [
        durabilityUuid(number),
        durabilityUuid(_relations.singleWhere((r) => r.$1 == path.first).$2),
        durabilityUuid(_relations.singleWhere((r) => r.$1 == path.last).$3),
        date,
        completed ? 1 : 0,
      ],
    );
    for (var i = 0; i < path.length; i++) {
      await database.customStatement(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          durabilityUuid(number * 10 + i),
          durabilityUuid(number),
          durabilityUuid(path[i]),
          i == 0 ? null : durabilityUuid(number * 10 + i - 1),
        ],
      );
    }
  }

  Future<IntentionStatisticsSourceSnapshot?> read({
    StatisticsView view = StatisticsView.throughRelations,
    StatisticsPeriod? period,
    CalendarDate? localDate,
    int intention = 2,
  }) => repository.readIntentionStatisticsSource(
    IntentionStatisticsQuery(
      intentionId: durabilityIntention(intention),
      period: period ?? StatisticsMonth(2026, 10),
      view: view,
      localDate: localDate ?? CalendarDate.fromParts(2026, 10, 12),
      pageSize: 100,
    ),
  );

  test(
    'четыре положения в пути сохраняют веса и разбивки выбранного вида',
    () async {
      await addChoice(201, [102], date: '2026-10-01');
      await addChoice(202, [101, 102], date: '2026-10-11');
      await addChoice(203, [101, 102], date: '2026-10-11', completed: false);
      await addChoice(204, [101], completed: false);
      await addChoice(205, [107], date: '2026-10-13');

      for (final view in StatisticsView.values) {
        final source = (await read(view: view))!;
        expect(source.groups, hasLength(4));
        expect(_counts(source.periodSummary.counts), (5, 3));
        expect(_counts(source.sourceIntentions), (1, 1));
        expect(_counts(source.intermediateIntentions), (2, 1));
        expect(_counts(source.selectedActions), (1, 0));
        if (view == StatisticsView.throughRelations) {
          expect(source.savedPathDetails, isNull);
          continue;
        }
        final details = source.savedPathDetails!;
        expect(details.breakdowns.keys, view.breakdowns);
        final expected = switch (view) {
          StatisticsView.sourceIntentions => (1, 1, 0, 0, 1),
          StatisticsView.intermediateIntentions => (2, 1, 1, 0, 11),
          StatisticsView.selectedActions => (1, 0, 0, 1, 12),
          StatisticsView.throughRelations => throw StateError('Недостижимо'),
        };
        expect(_counts(details.summary.counts), (expected.$1, expected.$2));
        expect(details.summary.uncompleted.missed, expected.$3);
        expect(details.summary.uncompleted.upcoming, expected.$4);
        expect(details.calendarCounts.keys.single.day, expected.$5);
        for (final breakdown in details.breakdowns.entries) {
          final row = breakdown.value.single;
          expect(
            row.intentionId,
            durabilityIntention(
              breakdown.key == StatisticsBreakdown.sourceIntentions ? 1 : 3,
            ),
          );
          expect(_counts(row.counts), (expected.$1, expected.$2));
        }
      }
    },
  );

  test(
    'группы SQLite различают предшественников в контрольном цикле',
    () async {
      for (final number in [103, 104, 107, 108, 109]) {
        await database.customStatement(
          'DELETE FROM long_term_relations WHERE id = ?',
          [durabilityUuid(number)],
        );
      }
      await addChoice(201, [101, 102]);
      final first = (await read())!;
      final graph = await repository.loadStatisticsRelationSnapshot();
      IntentionContributionResult<CalendarDate> compute(
        IntentionStatisticsSourceSnapshot source,
      ) => computeIntentionContribution(
        graph: graph,
        intentionId: durabilityIntention(2),
        groups: source.groups,
        activeOutgoingRelations: source.activeOutgoingRelations,
      );
      expect(
        {
          for (final row in compute(first).relations)
            row.relationId: _counts(row.counts),
        },
        {durabilityRelation(102): (1, 1), durabilityRelation(106): (1, 1)},
      );
      await addChoice(202, [105, 102]);
      final second = (await read())!;
      expect(second.groups, hasLength(2));
      expect(
        {
          for (final row in compute(second).relations)
            row.relationId: _counts(row.counts),
        },
        {durabilityRelation(102): (2, 2), durabilityRelation(106): (1, 1)},
      );
    },
  );

  test(
    'разные следующие связи сохраняют явный вклад после архивирования X',
    () async {
      await addChoice(201, [101, 102]);
      await addChoice(202, [101, 108, 109]);
      await addChoice(203, [101]);
      final active = (await read())!;
      expect(active.groups, hasLength(3));
      expect(
        await repository.execute(
          DisableIntentionReadiness(durabilityIntention(3)),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(2))),
        isA<GraphCommandSucceeded>(),
      );
      final archived = (await read(
        view: StatisticsView.intermediateIntentions,
      ))!;
      expect(_counts(archived.intermediateIntentions), (2, 2));
      expect(_counts(archived.selectedActions), (1, 1));
      expect(
        archived
            .savedPathDetails!
            .breakdowns[StatisticsBreakdown.sourceIntentions]!
            .single
            .intentionId,
        durabilityIntention(1),
      );
      expect(archived.activeOutgoingRelations, isEmpty);
      final result = computeIntentionContribution(
        graph: await repository.loadStatisticsRelationSnapshot(),
        intentionId: durabilityIntention(2),
        groups: archived.groups,
        activeOutgoingRelations: archived.activeOutgoingRelations,
      );
      expect(_counts(result.summary.counts), (3, 3));
      expect(result.explicitPathChoices, 3);
      expect(
        {
          for (final row in result.relations)
            row.relationId: _counts(row.counts),
        },
        {durabilityRelation(102): (1, 1), durabilityRelation(108): (1, 1)},
      );
      for (final group in archived.groups.where(
        (g) => g.selectedActionId == durabilityIntention(3),
      )) {
        expect(group.seeds.toSet(), {
          for (final id in [1, 2, 3]) durabilityIntention(id),
        });
      }
    },
  );

  test('месяц и год ограничивают даты и сохраняют деление внутри календарной части', () async {
    final dates = [
      '2023-12-31',
      '2024-01-01',
      '2024-02-01',
      '2024-02-28',
      '2024-02-29',
      '2024-03-01',
      '2024-12-31',
      '2025-01-01',
    ];
    for (var i = 0; i < dates.length; i++) {
      await addChoice(201 + i, [102], date: dates[i], completed: i == 2);
    }
    final today = CalendarDate.fromParts(2024, 2, 29);
    final month = (await read(
      view: StatisticsView.sourceIntentions,
      period: StatisticsMonth(2024, 2),
      localDate: today,
    ))!;
    expect(_counts(month.periodSummary.counts), (3, 1));
    expect(
      month.savedPathDetails!.calendarCounts.keys.map((d) => d.day).toSet(),
      {1, 28, 29},
    );
    final year = (await read(
      view: StatisticsView.sourceIntentions,
      period: StatisticsYear(2024),
      localDate: today,
    ))!;
    expect(_counts(year.sourceIntentions), (6, 1));
    expect(year.savedPathDetails!.summary.uncompleted.missed, 2);
    expect(year.savedPathDetails!.summary.uncompleted.upcoming, 3);
    expect(
      {
        for (final entry in year.savedPathDetails!.calendarCounts.entries)
          entry.key.month: _counts(entry.value),
      },
      {1: (1, 0), 2: (3, 1), 3: (1, 0), 12: (1, 0)},
    );
    final february = year.groups.singleWhere((g) => g.calendarPart.month == 2);
    expect(_counts(february.summary.counts), (3, 1));
    expect(february.summary.uncompleted.missed, 1);
    expect(february.summary.uncompleted.upcoming, 1);
    final nextDay = (await read(
      period: StatisticsYear(2024),
      localDate: CalendarDate.fromParts(2024, 3, 1),
    ))!;
    expect(nextDay.periodSummary.uncompleted.missed, 3);
    expect(nextDay.periodSummary.uncompleted.upcoming, 2);
  });

  test(
    'отсутствующее намерение отличается от пустого вида и периода',
    () async {
      expect(await read(intention: 999), isNull);
      final empty = (await read(view: StatisticsView.selectedActions))!;
      expect(empty.groups, isEmpty);
      expect(_counts(empty.periodSummary.counts), (0, 0));
      expect(empty.savedPathDetails!.calendarCounts, isEmpty);
      expect(
        empty.savedPathDetails!.breakdowns[StatisticsBreakdown
            .sourceIntentions],
        isEmpty,
      );
      await addChoice(201, [102]);
      final emptyView = (await read(view: StatisticsView.selectedActions))!;
      expect(_counts(emptyView.periodSummary.counts), (1, 1));
      expect(_counts(emptyView.selectedActions), (0, 0));
      expect(emptyView.savedPathDetails!.calendarCounts, isEmpty);
      expect(
        emptyView.savedPathDetails!.breakdowns[StatisticsBreakdown
            .sourceIntentions],
        isEmpty,
      );
    },
  );

  test(
    'команда между запросами не смешивает сводку, карточки и группы',
    () async {
      await addChoice(201, [101, 102], completed: false);
      probe.entered = Completer<void>();
      probe.release = Completer<void>();
      final reading = read(view: StatisticsView.intermediateIntentions);
      await probe.entered!.future;
      final command = repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      probe.release!.complete();
      final before = (await reading)!;
      final confirmed = await command;
      expect(confirmed, isA<GraphCommandSucceeded>());
      final after = (await read(view: StatisticsView.intermediateIntentions))!;
      for (final (snapshot, contribution) in [(before, 0), (after, 1)]) {
        expect(snapshot.periodSummary.counts.contribution, contribution);
        expect(snapshot.intermediateIntentions.contribution, contribution);
        expect(
          snapshot.groups.single.summary.counts.contribution,
          contribution,
        );
        expect(
          snapshot.savedPathDetails!.calendarCounts.values.single.contribution,
          contribution,
        );
        expect(
          snapshot
              .savedPathDetails!
              .breakdowns[StatisticsBreakdown.sourceIntentions]!
              .single
              .counts
              .contribution,
          contribution,
        );
      }
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        after.revision.compareTo(
          (confirmed as GraphCommandSucceeded).value.revision,
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'разбивки суммируют календарные части и сортируют по полному ключу',
    () async {
      final paths = [
        [101, 102],
        [101, 102],
        [105, 102],
        [101, 108],
        [105, 106],
        [105, 106],
        [105, 106, 104],
      ];
      for (var i = 0; i < paths.length; i++) {
        await addChoice(
          201 + i,
          paths[i],
          date: '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          completed: i != 2 && i != 5,
        );
      }
      final details = (await read(view: StatisticsView.intermediateIntentions))!
          .savedPathDetails!;
      expect(_counts(details.summary.counts), (7, 5));
      expect(
        [
          for (final row
              in details.breakdowns[StatisticsBreakdown.sourceIntentions]!)
            (row.intentionId, _counts(row.counts)),
        ],
        [(durabilityIntention(1), (3, 3)), (durabilityIntention(4), (4, 2))],
      );
      expect(
        [
          for (final row
              in details.breakdowns[StatisticsBreakdown.selectedActions]!)
            (row.intentionId, _counts(row.counts)),
        ],
        [
          (durabilityIntention(3), (3, 2)),
          (durabilityIntention(1), (2, 1)),
          (durabilityIntention(5), (1, 1)),
          (durabilityIntention(4), (1, 1)),
        ],
      );
    },
  );

  test('отказ SQLite после сводки отклоняет весь снимок', () async {
    await addChoice(201, [102]);
    probe.failure = sqlite.SqliteException(
      message: 'Недоступно',
      extendedResultCode: 5,
    );
    await expectLater(read(), throwsA(isA<StatisticsReadUnavailableFailure>()));
  });

  test(
    'повреждённая следующая связь не превращается в отсутствие основания',
    () async {
      await addChoice(201, [101, 102]);
      probe.invalidFollowingRelation = true;
      await expectLater(
        read(),
        throwsA(isA<StatisticsReadCorruptionFailure>()),
      );
    },
  );

  test(
    'некорректная дата отклоняется до сворачивания до месяца года',
    () async {
      await addChoice(201, [102], date: '2026-02-30');
      await expectLater(
        read(period: StatisticsYear(2026)),
        throwsA(isA<StatisticsReadCorruptionFailure>()),
      );
    },
  );
}

(int, int) _counts(ContributionCounts value) =>
    (value.planned, value.contribution);

final class _SourceProbe extends LocalDatabaseConnectionObserver {
  Completer<void>? entered;
  Completer<void>? release;
  Object? failure;
  bool invalidFollowingRelation = false;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.single.contains('archived_seed_key')) {
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
    if (!invalidFollowingRelation ||
        rows.isEmpty ||
        !rows.first.containsKey('following_relation_id')) {
      return rows;
    }
    return [
      {...rows.first, 'following_relation_id': 'не идентификатор'},
      ...rows.skip(1),
    ];
  }
}
