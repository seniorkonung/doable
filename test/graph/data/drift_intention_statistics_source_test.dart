import 'dart:async';
import 'dart:math';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/contribution_reachability_reference.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _SourceProbe probe;

  Future<void> open({int intentions = 9}) async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _SourceProbe();
    database = await harness.openReadyDatabase(
      setup: (db) => raw = db,
      observer: probe,
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      InMemoryDiagnosticsSink(),
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= intentions; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
    });
  }

  tearDown(() => harness.dispose());

  void addAction(
    int number,
    List<int> path, {
    String date = '2026-10-12',
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

  void addRelation(
    int number,
    int source,
    int target, {
    bool archived = false,
  }) => seedRawGraph(raw, () {
    seedRelation(raw, seedUuid(number), seedUuid(source), seedUuid(target));
    if (archived) {
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [seedUuid(number)],
      );
    }
  });

  // Строки пути не ссылаются на намерения, поэтому удалённое намерение
  // в чтении статистики — просто отсутствующая строка.
  void removeIntention(int number) => seedRawGraph(
    raw,
    () =>
        raw.execute('DELETE FROM intentions WHERE id = ?', [seedUuid(number)]),
  );

  Future<IntentionStatisticsSourceSnapshot?> read({
    StatisticsView? view = StatisticsView.throughRelations,
    StatisticsPeriod? period,
    int intention = 2,
  }) => repository.readIntentionStatisticsSource(
    IntentionStatisticsQuery(
      intentionId: seedIntentionId(intention),
      period: period ?? StatisticsMonth(2026, 10),
      view: view,
      pageSize: 100,
    ),
  );

  Future<IntentionContributionResult<CalendarDate>> compute(
    IntentionStatisticsSourceSnapshot source, {
    int intention = 2,
  }) async => computeIntentionContribution(
    graph: await repository.loadStatisticsRelationSnapshot(),
    intentionId: seedIntentionId(intention),
    groups: source.groups,
    activeOutgoingRelations: source.activeOutgoingRelations,
  );

  group('с девятью намерениями', () {
    setUp(open);

    test('роли засчитываются по позициям пути, путь из одного намерения — '
        'корневым и конечным, а разбивки не содержат само намерение '
        'и удалённые', () async {
      addAction(201, [1, 2, 3], date: '2026-10-01', completed: true);
      addAction(202, [2, 4], date: '2026-10-05');
      addAction(203, [2], date: '2026-10-05', completed: true);
      addAction(204, [5, 2], date: '2026-10-07', completed: true);
      addAction(205, [6, 2, 7], date: '2026-10-07');
      addAction(206, [8, 9], date: '2026-10-07', completed: true);
      addAction(207, [2, 3], date: '2026-11-01', completed: true);
      addAction(208, [9, 2], date: '2026-10-31');
      addAction(209, [7, 2], date: '2026-10-31', completed: true);
      removeIntention(7);

      for (final view in StatisticsView.values) {
        final source = (await read(view: view))!;
        expect(source.view, view);
        expect(_counts(source.periodCounts), (8, 5));
        expect(_counts(source.rootIntentions), (2, 1));
        expect(_counts(source.intermediateIntentions), (2, 1));
        expect(_counts(source.terminalIntentions), (4, 3));
        if (view == StatisticsView.throughRelations) {
          expect(source.savedPathDetails, isNull);
          continue;
        }
        final details = source.savedPathDetails!;
        expect(details.breakdowns.keys, view.breakdowns, reason: view.name);
        final (counts, days, roots, terminals) = switch (view) {
          StatisticsView.rootIntentions => (
            (2, 1),
            {5: (2, 1)},
            null,
            [(4, (1, 0))],
          ),
          StatisticsView.intermediateIntentions => (
            (2, 1),
            {1: (1, 1), 7: (1, 0)},
            [(1, (1, 1)), (6, (1, 0))],
            [(3, (1, 1))],
          ),
          StatisticsView.terminalIntentions => (
            (4, 3),
            {5: (1, 1), 7: (1, 1), 31: (2, 1)},
            [(5, (1, 1)), (9, (1, 0))],
            null,
          ),
          StatisticsView.throughRelations => throw StateError('Недостижимо'),
        };
        expect(_counts(details.counts), counts, reason: view.name);
        expect({
          for (final entry in details.calendarCounts.entries)
            entry.key.day: _counts(entry.value),
        }, days);
        expect(
          _entries(details.breakdowns[StatisticsBreakdown.rootIntentions]),
          roots,
        );
        expect(
          _entries(details.breakdowns[StatisticsBreakdown.terminalIntentions]),
          terminals,
        );
      }
    });

    test('действие относится к нескольким связям намерения, а опорное '
        'намерение перед следующим по активной связи опускается', () async {
      // Высыпаться — 1, Вечерний ритуал — 2, Убрать телефон — 3,
      // Лечь до полуночи — 4.
      addRelation(101, 1, 3);
      addRelation(102, 1, 2);
      addRelation(103, 2, 3);
      addRelation(104, 1, 4);
      addAction(201, [2, 3], completed: true);
      addAction(202, [4], completed: true);

      final source = (await read(intention: 1))!;
      expect(
        [for (final group in source.groups) group.seeds.map(_number).toSet()],
        unorderedEquals([
          {3},
          {4},
        ]),
      );
      final result = await compute(source, intention: 1);
      expect(_counts(result.counts), (2, 2));
      expect(result.explicitPathActions, 0);
      expect(_relations(result), {101: (1, 1), 102: (1, 1), 104: (1, 1)});
      expect(_entries(result.terminalIntentions), [(4, (1, 1)), (3, (1, 1))]);
    });

    test('звено перед намерением остаётся опорным, поэтому связь, ведущая '
        'к нему в обход намерения, засчитывает действие', () async {
      addRelation(101, 5, 1);
      addRelation(102, 1, 6);
      addRelation(103, 1, 7);
      addRelation(104, 7, 5);
      addRelation(105, 1, 8, archived: true);
      addAction(201, [5, 1, 6], completed: true);

      final source = (await read(intention: 1))!;
      expect(source.groups.single.seeds.map(_number).toSet(), {5, 6});
      expect(
        source.groups.single.pathPosition,
        isA<ContributionBeforeTerminal>()
            .having((p) => p.isRoot, 'isRoot', isFalse)
            .having(
              (p) => p.followingRelationId,
              'followingRelationId',
              _relationId(102),
            ),
      );
      final result = await compute(source, intention: 1);
      expect(_relations(result), {102: (1, 1), 103: (1, 1)});
      expect(result.explicitPathActions, 1);
    });

    test('архивированная следующая связь сохраняет основание, а действие, '
        'где намерение конечное, в разбивку по связям не входит', () async {
      addRelation(101, 2, 3, archived: true);
      addRelation(102, 2, 4);
      addRelation(103, 4, 1);
      addAction(201, [2, 3], completed: true);
      addAction(202, [1, 2]);

      final result = await compute((await read())!);
      expect(_counts(result.counts), (2, 1));
      expect(result.explicitPathActions, 2);
      expect(_relations(result), {101: (1, 1)});
      expect(_entries(result.terminalIntentions), [(3, (1, 1))]);
    });

    test('вид по умолчанию — роль с наибольшим числом действий за всё '
        'время, при равенстве — первая', () async {
      addAction(201, [2, 1], date: '2020-01-01');
      addAction(202, [1, 2, 3], date: '2024-05-05');
      addAction(203, [3, 2], date: '2026-10-12');
      expect((await read(view: null))!.view, StatisticsView.rootIntentions);
      addAction(204, [3, 2, 1], date: '2030-12-31');
      expect(
        (await read(view: null))!.view,
        StatisticsView.intermediateIntentions,
      );
      addAction(205, [4, 2], date: '2026-10-12');
      addAction(206, [5, 2], date: '2019-03-03');
      final terminal = (await read(view: null))!;
      expect(terminal.view, StatisticsView.terminalIntentions);
      expect(_counts(terminal.terminalIntentions), (2, 0));
    });

    test('намерение вне путей открывается на «Через связи», только если '
        'активные связи доводят до него действия', () async {
      addAction(201, [1, 3], date: '2020-01-01');
      Future<StatisticsView> openedView() async =>
          (await read(view: null, intention: 5))!.view;
      expect(await openedView(), StatisticsView.rootIntentions);
      addRelation(101, 5, 6);
      addRelation(102, 6, 3, archived: true);
      expect(await openedView(), StatisticsView.rootIntentions);
      addRelation(103, 6, 7);
      addRelation(104, 7, 6);
      addRelation(105, 7, 1);
      expect(await openedView(), StatisticsView.throughRelations);
    });

    test('месяц и год включают границы и високосный день, а календарь года '
        'сворачивает дни до месяцев', () async {
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
        addAction(201 + i, [2, 3], date: dates[i], completed: i == 2);
      }
      final month = (await read(
        view: StatisticsView.rootIntentions,
        period: StatisticsMonth(2024, 2),
      ))!;
      expect(_counts(month.periodCounts), (3, 1));
      expect(
        month.savedPathDetails!.calendarCounts.keys.map((d) => d.day).toSet(),
        {1, 28, 29},
      );
      final year = (await read(
        view: StatisticsView.rootIntentions,
        period: StatisticsYear(2024),
      ))!;
      expect(_counts(year.rootIntentions), (6, 1));
      expect(
        {
          for (final entry in year.savedPathDetails!.calendarCounts.entries)
            entry.key.month: _counts(entry.value),
        },
        {1: (1, 0), 2: (3, 1), 3: (1, 0), 12: (1, 0)},
      );
      final february = year.groups.singleWhere(
        (g) => g.calendarPart.month == 2,
      );
      expect(february.calendarPart.day, 1);
      expect(_counts(february.counts), (3, 1));
    });

    test(
      'отсутствующее намерение отличается от пустого вида и периода',
      () async {
        expect(await read(intention: 999), isNull);
        final empty = (await read(view: StatisticsView.terminalIntentions))!;
        expect(empty.groups, isEmpty);
        expect(_counts(empty.periodCounts), (0, 0));
        expect(empty.savedPathDetails!.calendarCounts, isEmpty);
        expect(
          empty.savedPathDetails!.breakdowns[StatisticsBreakdown
              .rootIntentions],
          isEmpty,
        );
        addAction(201, [2, 3], completed: true);
        final emptyView = (await read(
          view: StatisticsView.terminalIntentions,
        ))!;
        expect(_counts(emptyView.periodCounts), (1, 1));
        expect(_counts(emptyView.terminalIntentions), (0, 0));
        expect(emptyView.savedPathDetails!.calendarCounts, isEmpty);
      },
    );

    test(
      'команда между запросами не смешивает сводку, карточки и группы',
      () async {
        addAction(201, [1, 2, 3]);
        probe.entered = Completer<void>();
        probe.release = Completer<void>();
        final reading = read(view: StatisticsView.intermediateIntentions);
        await probe.entered!.future;
        final command = repository.execute(
          UpdateActionFields(
            actionId: seedActionId(201),
            patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
          ),
        );
        probe.release!.complete();
        final before = (await reading)!;
        final confirmed = await command;
        expect(confirmed, isA<GraphCommandSucceeded>());
        final after = (await read(
          view: StatisticsView.intermediateIntentions,
        ))!;
        for (final (snapshot, contribution) in [(before, 0), (after, 1)]) {
          expect(snapshot.periodCounts.contribution, contribution);
          expect(snapshot.intermediateIntentions.contribution, contribution);
          expect(snapshot.groups.single.counts.contribution, contribution);
          expect(
            snapshot
                .savedPathDetails!
                .calendarCounts
                .values
                .single
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

    test('группы читают действия по индексу даты, строки пути и связи — по '
        'ключам, а вид по умолчанию — по индексу ролей', () async {
      addRelation(101, 4, 3);
      addAction(201, [1, 2, 3]);
      final statements = <LocalDatabaseSqlStatement>[];
      probe.record = statements;
      await read(view: null, intention: 4);
      probe.record = null;
      String plan(String marker) {
        final statement = statements.singleWhere(
          (s) => s.statements.single.contains(marker),
        );
        return raw
            .select(
              'EXPLAIN QUERY PLAN ${statement.statements.single}',
              statement.arguments,
            )
            .map((row) => row['detail'] as String)
            .join('\n');
      }

      final groups = plan('path_rows');
      expect(
        groups,
        contains(
          'INDEX actions_date_completion_schedule_order (date>? AND date<?)',
        ),
      );
      expect(groups, isNot(matches(RegExp(r'SCAN (a|p|n|i|r)\b'))));
      final roles = plan('root_actions');
      expect(
        roles,
        contains('INDEX action_path_items_intention_action (intention_id=?)'),
      );
      expect(roles, isNot(matches(RegExp(r'SCAN (p|n)\b'))));
      expect(plan('RECURSIVE'), isNot(matches(RegExp(r'SCAN (r|p)\b'))));
    });

    test('отказ SQLite при чтении групп отклоняет весь снимок', () async {
      addAction(201, [2]);
      probe.failure = sqlite.SqliteException(
        message: 'Недоступно',
        extendedResultCode: 5,
      );
      await expectLater(
        read(),
        throwsA(isA<StatisticsReadUnavailableFailure>()),
      );
    });

    test('повреждённая следующая связь не превращается в отсутствие '
        'основания', () async {
      addRelation(101, 2, 3);
      addAction(201, [2, 3]);
      probe.invalidFollowingRelation = true;
      await expectLater(
        read(),
        throwsA(isA<StatisticsReadCorruptionFailure>()),
      );
    });

    test(
      'некорректная дата отклоняется до сворачивания до месяца года',
      () async {
        addAction(201, [2], date: '2026-02-30');
        await expectLater(
          read(period: StatisticsYear(2026)),
          throwsA(isA<StatisticsReadCorruptionFailure>()),
        );
      },
    );
  });

  test('«Через связи» и его разбивки совпадают с эталоном по полным путям '
      'на воспроизводимых случайных графах', () async {
    const nodeCount = 9;
    final random = Random(2311);
    for (var sample = 0; sample < 12; sample++) {
      if (sample > 0) await harness.dispose();
      await open(intentions: nodeCount);
      final deleted = {
        for (var node = 1; node <= nodeCount; node++)
          if (random.nextInt(6) == 0) node,
      };
      final relations = <ContributionReferenceRelation>[];
      for (var source = 1; source <= nodeCount; source++) {
        for (var target = 1; target <= nodeCount; target++) {
          if (source == target ||
              deleted.contains(source) ||
              deleted.contains(target) ||
              random.nextInt(4) != 0) {
            continue;
          }
          final archived = random.nextInt(4) == 0;
          addRelation(
            source * 100 + target,
            source,
            target,
            archived: archived,
          );
          relations.add((
            source: seedIntentionId(source),
            target: seedIntentionId(target),
            archived: archived,
          ));
        }
      }
      final actions = <ContributionReferenceAction>[];
      for (var index = 0; index < 30; index++) {
        final path = ([
          for (var node = 1; node <= nodeCount; node++) node,
        ]..shuffle(random)).take(1 + random.nextInt(5)).toList();
        final completed = random.nextBool();
        for (var copy = random.nextInt(4) == 0 ? 2 : 1; copy > 0; copy--) {
          addAction(
            2000 + actions.length,
            path,
            date:
                '2026-10-${(1 + random.nextInt(31)).toString().padLeft(2, '0')}',
            completed: completed,
          );
          actions.add((
            path: [for (final node in path) seedIntentionId(node)],
            completed: completed,
          ));
        }
      }
      deleted.forEach(removeIntention);
      for (var intention = 1; intention <= nodeCount; intention++) {
        if (deleted.contains(intention)) continue;
        final reason = 'Граф $sample, намерение $intention, seed 2311';
        final result = await compute(
          (await read(intention: intention))!,
          intention: intention,
        );
        final reference = referenceIntentionActionStatistics(
          intentionId: seedIntentionId(intention),
          relations: relations,
          actions: actions,
          deleted: {for (final node in deleted) seedIntentionId(node)},
        );
        expect(_counts(result.counts), (
          reference.throughRelations.planned,
          reference.throughRelations.contribution,
        ), reason: reason);
        expect(
          result.explicitPathActions,
          reference.explicitPathActions,
          reason: reason,
        );
        expect(
          {
            for (final entry in result.terminalIntentions)
              _number(entry.intentionId): _counts(entry.counts),
          },
          {
            for (final entry in reference.terminalIntentions.entries)
              _number(entry.key): (
                entry.value.planned,
                entry.value.contribution,
              ),
          },
          reason: reason,
        );
        expect(_relations(result), {
          for (final entry in reference.relations.entries)
            _number(entry.key.source) * 100 + _number(entry.key.target): (
              entry.value.planned,
              entry.value.contribution,
            ),
        }, reason: reason);
      }
    }
  });
}

(int, int) _counts(ContributionCounts value) =>
    (value.planned, value.contribution);

int _number(IntentionId id) =>
    int.parse(id.toCanonicalString().substring(24), radix: 16);

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  seedUuid(number),
) as LongTermRelationIdDecodingSuccess).id;

List<(int, (int, int))>? _entries(
  List<ContributionReachabilityEntry>? entries,
) => entries == null
    ? null
    : [
        for (final entry in entries)
          (_number(entry.intentionId), _counts(entry.counts)),
      ];

Map<int, (int, int)> _relations(IntentionContributionResult<Object> result) => {
  for (final entry in result.relations)
    int.parse(entry.relationId.toCanonicalString().substring(24), radix: 16):
        _counts(entry.counts),
};

final class _SourceProbe extends LocalDatabaseConnectionObserver {
  Completer<void>? entered;
  Completer<void>? release;
  Object? failure;
  bool invalidFollowingRelation = false;
  List<LocalDatabaseSqlStatement>? record;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    record?.add(statement);
    if (!statement.statements.single.contains('path_rows')) return;
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
        rows.first['following_relation_id'] == null) {
      return rows;
    }
    return [
      {...rows.first, 'following_relation_id': 'не идентификатор'},
      ...rows.skip(1),
    ];
  }
}
