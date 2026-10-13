import 'dart:isolate';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  StatisticsQuery query({
    StatisticsCursor? cursor,
    StatisticsPeriod? period,
    CalendarDate? localDate,
    int pageSize = 2,
    StatisticsView view = StatisticsView.sourceIntentions,
  }) => StatisticsQuery(
    period: period ?? StatisticsMonth(2026, 9),
    view: view,
    localDate: localDate ?? CalendarDate.fromParts(2026, 9, 23),
    pageSize: pageSize,
    cursor: cursor,
  );

  DriftPersonalGraphRepository createRepository({
    ContributionReachabilityRunner runner =
        runContributionReachabilityInIsolate,
  }) => DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 9, 23),
    diagnostics,
    dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(201)),
    choicePathStepIdGenerator: SequentialStepIds(301),
    statisticsReachabilityRunner: runner,
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _ReadProbe();
    database = await harness.openReadyDatabase(observer: probe);
    await seedDurabilityGraph(database);
    diagnostics = InMemoryDiagnosticsSink();
    repository = createRepository();
    expect(
      await repository.execute(durabilityCreate()),
      isA<GraphCommandSucceeded>(),
    );
  });
  tearDown(() => harness.dispose());

  test(
    'первая и поздняя порции дают точные числа и архивные отметки',
    () async {
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(2))),
        isA<GraphCommandSucceeded>(),
      );
      final first = _page(
        await repository.readThroughRelationsStatisticsPage(query()),
      ) as StatisticsFirstPage;
      expect(first.summary.counts.planned, 1);
      expect(first.summary.counts.contribution, 1);
      expect(first.summary.uncompleted.missed, 0);
      expect(first.summary.uncompleted.upcoming, 0);
      expect(first.totalItems, 3);
      expect(first.items.map((item) => item.id), [
        durabilityIntention(3),
        durabilityIntention(2),
      ]);
      expect(first.items.last.archiveState, IntentionArchiveState.archived);
      expect(first.items.last.title, 'Намерение 2');
      final last = _page(
        await repository.readThroughRelationsStatisticsPage(
          query(cursor: first.nextCursor),
        ),
      );
      expect(last, isA<StatisticsContinuationPage>());
      expect(last.items.single.id, durabilityIntention(1));
      expect(last.nextCursor, isNull);
      for (final item in [...first.items, ...last.items]) {
        expect(item.counts.planned, 1);
        expect(item.counts.contribution, 1);
      }
      expect(probe.titleRows, [2, 1]);
      expect(last.revision.compareTo(first.revision), GraphRevisionOrder.same);
      expect(probe.sourceReads, 1);
      expect(_computations(diagnostics), 1);
    },
  );

  test('пустой период даёт подтверждённую нулевую первую порцию', () async {
    final page = _page(
      await repository.readThroughRelationsStatisticsPage(
        query(period: StatisticsMonth(2026, 10)),
      ),
    ) as StatisticsFirstPage;
    expect(page.summary.counts.planned, 0);
    expect(page.summary.counts.contribution, 0);
    expect(page.totalItems, 0);
    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
  });

  test(
    'команда и цикл событий работают до завершения подсчёта в изоляте',
    () async {
      final started = ReceivePort();
      addTearDown(started.close);
      final release = started.first;
      var delayNext = true;
      repository = createRepository(
        runner: (graph, groups) {
          if (!delayNext) {
            return runContributionReachabilityInIsolate(graph, groups);
          }
          delayNext = false;
          return _computeWithGate(graph, groups, started.sendPort);
        },
      );
      var completed = false;
      final reading = repository.readThroughRelationsStatisticsPage(query())
        ..then((_) => completed = true);
      final gate = await release as SendPort;
      addTearDown(() => gate.send(null));
      var eventRan = false;
      await Future<void>(() => eventRan = true);
      expect(eventRan, isTrue);
      expect(completed, isFalse);
      final command = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(false),
          ),
        ),
      );
      expect(command, isA<GraphCommandSucceeded>());
      expect(completed, isFalse);
      gate.send(null);
      _expectExpired(await reading);
      expect(probe.titleRows, isEmpty);
      expect(probe.sourceReads, 1);
      expect(probe.snapshotReads, 1);
      expect(_computations(diagnostics), 1);
      expect(
        diagnostics.events
            .whereType<StatisticsReadDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsFailed>().having(
          (s) => s.code,
          'категория',
          DiagnosticsFailureCode.conflict,
        ),
      );

      final fresh = _page(
        await repository.readThroughRelationsStatisticsPage(query()),
      ) as StatisticsFirstPage;
      expect(fresh.summary.counts.contribution, 0);
      expect(
        fresh.items.every((item) => item.counts.contribution == 0),
        isTrue,
      );
      expect(probe.sourceReads, 2);
      expect(probe.snapshotReads, 1);
      expect(_computations(diagnostics), 2);
    },
  );

  test(
    'первая порция и продолжение переиспользуют количества на одной ревизии',
    () async {
      final first = _page(
        await repository.readThroughRelationsStatisticsPage(query()),
      );
      final cached = _page(
        await repository.readThroughRelationsStatisticsPage(query(pageSize: 1)),
      );
      expect(cached.items.single.id, first.items.first.id);
      final last = _page(
        await repository.readThroughRelationsStatisticsPage(
          query(cursor: first.nextCursor),
        ),
      );
      expect(last.items.single.id, durabilityIntention(1));
      expect(probe.sourceReads, 1);
      expect(probe.snapshotReads, 1);
      expect(_computations(diagnostics), 1);
      expect(probe.titleRows, [2, 1, 1]);
    },
  );

  test('кэш ограничен двумя результатами, продолжение вытесненного не пересчитывается', () async {
    final first = _page(
      await repository.readThroughRelationsStatisticsPage(query()),
    );
    final year = _page(
      await repository.readThroughRelationsStatisticsPage(
        query(period: StatisticsYear(2026)),
      ),
    );
    await repository.readThroughRelationsStatisticsPage(
      query(period: StatisticsMonth(2026, 10)),
    );
    _expectExpired(
      await repository.readThroughRelationsStatisticsPage(
        query(cursor: first.nextCursor),
      ),
    );
    expect(probe.sourceReads, 3);
    expect(_computations(diagnostics), 3);
    final continued = _page(
      await repository.readThroughRelationsStatisticsPage(
        query(period: StatisticsYear(2026), cursor: year.nextCursor),
      ),
    );
    expect(continued.items.single.id, durabilityIntention(1));
    expect(probe.sourceReads, 3);
    expect(_computations(diagnostics), 3);
    await repository.readThroughRelationsStatisticsPage(query());
    expect(probe.sourceReads, 4);
    expect(_computations(diagnostics), 4);
  });

  test('смена местной даты пересчитывает сводку без изменения графа', () async {
    expect(
      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(false),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    final today = _page(
      await repository.readThroughRelationsStatisticsPage(query()),
    ) as StatisticsFirstPage;
    final tomorrow = _page(
      await repository.readThroughRelationsStatisticsPage(
        query(localDate: CalendarDate.fromParts(2026, 9, 24)),
      ),
    ) as StatisticsFirstPage;
    expect(today.summary.uncompleted.upcoming, 1);
    expect(today.summary.uncompleted.missed, 0);
    expect(tomorrow.summary.uncompleted.upcoming, 0);
    expect(tomorrow.summary.uncompleted.missed, 1);
    expect(probe.sourceReads, 2);
    expect(_computations(diagnostics), 2);
  });

  test('курсор отклоняется при смене условий, вида чтения и эпохи', () async {
    final first = _page(
      await repository.readThroughRelationsStatisticsPage(query()),
    );
    final cursor = first.nextCursor;
    for (final changed in [
      query(cursor: cursor, period: StatisticsYear(2026)),
      query(cursor: cursor, localDate: CalendarDate.fromParts(2026, 9, 24)),
      query(cursor: cursor, pageSize: 1),
      query(cursor: cursor, view: StatisticsView.selectedActions),
    ]) {
      _expectExpired(
        await repository.readThroughRelationsStatisticsPage(changed),
      );
    }
    _expectExpired(await repository.getStatisticsPage(query(cursor: cursor)));
    final newEpoch = createRepository();
    _expectExpired(
      await newEpoch.readThroughRelationsStatisticsPage(query(cursor: cursor)),
    );
    expect(probe.sourceReads, 1);
    expect(_computations(diagnostics), 1);
    expect(probe.titleRows, [2]);
  });

  test(
    'подтверждённая команда отклоняет продолжение до чтения названий',
    () async {
      final first = _page(
        await repository.readThroughRelationsStatisticsPage(query()),
      );
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(2))),
        isA<GraphCommandSucceeded>(),
      );
      _expectExpired(
        await repository.readThroughRelationsStatisticsPage(
          query(cursor: first.nextCursor),
        ),
      );
      expect(probe.titleRows, [2]);
      expect(probe.sourceReads, 1);
      expect(_computations(diagnostics), 1);
      final fresh = _page(
        await repository.readThroughRelationsStatisticsPage(query()),
      ) as StatisticsFirstPage;
      expect(fresh.totalItems, 3);
      expect(fresh.items.last.archiveState, IntentionArchiveState.archived);
      expect(probe.sourceReads, 2);
      expect(probe.snapshotReads, 2);
      expect(_computations(diagnostics), 2);
    },
  );
}

StatisticsPage _page(StatisticsPageResult result) {
  expect(result, isA<StatisticsPageSuccess>());
  return (result as StatisticsPageSuccess).value;
}

void _expectExpired(StatisticsPageResult result) {
  expect(
    result,
    isA<StatisticsPageError>().having(
      (error) => error.failure,
      'сигнал новой первой порции',
      isA<StatisticsSnapshotExpired>(),
    ),
  );
}

int _computations(InMemoryDiagnosticsSink diagnostics) => diagnostics.events
    .whereType<StatisticsReadDiagnosticsEvent>()
    .where(
      (event) =>
          event.stage == StatisticsReadDiagnosticsStage.computation &&
          event.status is DiagnosticsStarted,
    )
    .length;

Future<List<ContributionReachabilityEntry>> _computeWithGate(
  ContributionRelationGraph graph,
  List<ContributionSeedGroup> groups,
  SendPort started,
) => Isolate.run(() async {
  final gate = ReceivePort();
  started.send(gate.sendPort);
  await gate.first;
  return computeContributionReachability(graph, groups);
});

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  var sourceReads = 0;
  var snapshotReads = 0;
  final titleRows = <int>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final sql = statement.statements.single;
    if (sql.contains('seed_key')) sourceReads++;
    if (sql.contains('creation_sequence >')) snapshotReads++;
    if (sql.contains('SELECT id, title, is_archived FROM intentions')) {
      titleRows.add(rows.length);
    }
    return rows;
  }
}
