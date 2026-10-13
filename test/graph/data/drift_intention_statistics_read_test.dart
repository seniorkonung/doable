import 'dart:isolate';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _relations = [
  (101, 1, 2),
  (102, 2, 3),
  (103, 1, 4),
  (104, 1, 5),
  (105, 4, 2),
  (106, 2, 1),
  (107, 5, 3),
  (108, 2, 4),
];

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  DriftPersonalGraphRepository createRepository({
    IntentionContributionRunner runner = runIntentionContributionInIsolate,
  }) => DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 10, 12),
    diagnostics,
    intentionStatisticsRunner: runner,
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _ReadProbe();
    database = await harness.openReadyDatabase(observer: probe);
    diagnostics = InMemoryDiagnosticsSink();
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
    repository = createRepository();
  });
  tearDown(() => harness.dispose());

  IntentionStatisticsQuery query({
    StatisticsView view = StatisticsView.throughRelations,
    StatisticsPeriod? period,
    int intention = 2,
    int pageSize = 1,
    CalendarDate? localDate,
  }) => IntentionStatisticsQuery(
    intentionId: durabilityIntention(intention),
    period: period ?? StatisticsMonth(2026, 10),
    view: view,
    localDate: localDate ?? CalendarDate.fromParts(2026, 10, 12),
    pageSize: pageSize,
  );

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

  test('раздел собирает четыре карточки и календарь выбранного вида', () async {
    await addChoice(201, [102], date: '2026-10-01');
    await addChoice(202, [101, 102], date: '2026-10-11');
    await addChoice(203, [101, 102], date: '2026-10-11', completed: false);
    await addChoice(204, [101], completed: false);
    await addChoice(205, [107], date: '2026-10-13');

    for (final view in StatisticsView.values) {
      final section = (await repository.readIntentionStatisticsSection(
        query(view: view),
      ))!;
      expect(_counts(section.periodCounts), (5, 3));
      expect(
        [
          for (final card in StatisticsView.values)
            _counts(section.cards[card]),
        ],
        [(1, 1), (2, 1), (1, 0), (5, 3)],
      );
      expect(section.details.view, view);
      final calendar = section.calendar as IntentionStatisticsMonthCalendar;
      expect(
        {
          for (final entry in calendar.statuses.entries)
            entry.key.day: entry.value,
        },
        switch (view) {
          StatisticsView.sourceIntentions => {
            1: DailyChoiceDayStatus.allCompleted,
          },
          StatisticsView.intermediateIntentions => {
            11: DailyChoiceDayStatus.hasIncomplete,
          },
          StatisticsView.selectedActions => {
            12: DailyChoiceDayStatus.hasIncomplete,
          },
          StatisticsView.throughRelations => {
            1: DailyChoiceDayStatus.allCompleted,
            11: DailyChoiceDayStatus.hasIncomplete,
            12: DailyChoiceDayStatus.hasIncomplete,
            13: DailyChoiceDayStatus.allCompleted,
          },
        },
      );
      expect(
        section.details.uncompleted.missed,
        view == StatisticsView.intermediateIntentions ||
                view == StatisticsView.throughRelations
            ? 1
            : 0,
      );
      expect(
        section.details.uncompleted.upcoming,
        view == StatisticsView.selectedActions ||
                view == StatisticsView.throughRelations
            ? 1
            : 0,
      );

      final year = (await repository.readIntentionStatisticsSection(
        query(view: view, period: StatisticsYear(2026)),
      ))!;
      final months = (year.calendar as IntentionStatisticsYearCalendar).months;
      expect(months, hasLength(12));
      expect(_counts(months[9]), _counts(section.selectedCounts));
      expect(months.where((m) => m.planned > 0), hasLength(1));
    }
  });

  Future<List<T>> collect<T>(
    StatisticsBreakdownFirstPage<T> first,
    GraphRevision revision,
  ) async {
    final items = [...first.items];
    var cursor = first.nextCursor;
    while (cursor != null) {
      final page = await repository.readIntentionStatisticsBreakdown(cursor);
      expect(page.items.length, lessThanOrEqualTo(1));
      expect(page.revision.compareTo(revision), GraphRevisionOrder.same);
      items.addAll(page.items);
      cursor = page.nextCursor;
    }
    expect(items.length, first.totalItems);
    return items;
  }

  test(
    'все разбивки сохраняют точное число и порядок при равных ключах',
    () async {
      final paths = [
        [102],
        [108],
        [106],
        [101, 102],
        [105, 102],
        [101, 108],
        [105, 106],
        [101],
        [105],
      ];
      for (var i = 0; i < paths.length; i++) {
        await addChoice(201 + i, paths[i]);
      }
      for (final view in StatisticsView.values) {
        final section = (await repository.readIntentionStatisticsSection(
          query(view: view),
        ))!;
        Future<void> intentions(
          StatisticsBreakdownFirstPage<StatisticsItem> first,
          List<(int, int)> expected,
        ) async {
          final items = await collect(first, section.revision);
          expect(
            [for (final item in items) (item.id, _counts(item.counts))],
            [
              for (final (id, count) in expected)
                (durabilityIntention(id), (count, count)),
            ],
          );
        }

        switch (section.details) {
          case IntentionStatisticsSourceDetails(:final selectedActions):
            await intentions(selectedActions, [(4, 1), (3, 1), (1, 1)]);
          case IntentionStatisticsIntermediateDetails(
            :final sourceIntentions,
            :final selectedActions,
          ):
            await intentions(sourceIntentions, [(4, 2), (1, 2)]);
            await intentions(selectedActions, [(3, 2), (4, 1), (1, 1)]);
          case IntentionStatisticsSelectedDetails(:final sourceIntentions):
            await intentions(sourceIntentions, [(4, 1), (1, 1)]);
          case IntentionStatisticsThroughRelationsDetails(
            :final selectedActions,
            :final relations,
            :final explicitPathChoices,
          ):
            expect(explicitPathChoices, 9);
            await intentions(selectedActions, [(3, 3), (4, 2), (2, 2), (1, 2)]);
            final rows = await collect(relations, section.revision);
            expect(
              [
                for (final row in rows)
                  (row.id, _counts(row.relatedIntention.counts)),
              ],
              [
                (durabilityRelation(106), (7, 7)),
                (durabilityRelation(108), (4, 4)),
                (durabilityRelation(102), (3, 3)),
              ],
            );
        }
      }
      expect(probe.titleRows, isNotEmpty);
      expect(probe.titleRows.every((count) => count <= 1), isTrue);
      expect(probe.sourceReads, 4);
      expect(_computations(diagnostics), 4);
      expect(
        diagnostics.events.whereType<StatisticsReadDiagnosticsEvent>().where(
          (e) =>
              e.readType == StatisticsReadDiagnosticsType.breakdown &&
              e.stage == StatisticsReadDiagnosticsStage.titles &&
              e.status is DiagnosticsSucceeded,
        ),
        isNotEmpty,
      );
    },
  );

  test('архивные отметки связи и связанного намерения независимы', () async {
    await addChoice(201, [101, 102]);
    await addChoice(202, [101, 108]);
    expect(
      await repository.execute(
        ArchiveLongTermRelation(durabilityRelation(102)),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await repository.execute(ArchiveIntention(durabilityIntention(4))),
      isA<GraphCommandSucceeded>(),
    );
    final section = (await repository.readIntentionStatisticsSection(query()))!;
    final details =
        section.details as IntentionStatisticsThroughRelationsDetails;
    final rows = await collect(details.relations, section.revision);
    final byId = {for (final row in rows) row.id: row};
    expect(byId[durabilityRelation(102)]!.scope, RelationScope.archived);
    expect(
      byId[durabilityRelation(102)]!.relatedIntention.archiveState,
      IntentionArchiveState.active,
    );
    expect(byId[durabilityRelation(108)]!.scope, RelationScope.archived);
    expect(
      byId[durabilityRelation(108)]!.relatedIntention.archiveState,
      IntentionArchiveState.archived,
    );
    expect(
      byId[durabilityRelation(108)]!.relatedIntention.title,
      'Намерение 4',
    );
    expect(byId[durabilityRelation(106)]!.scope, RelationScope.active);
    final actions = await collect(details.selectedActions, section.revision);
    expect(actions.first.id, durabilityIntention(4));
    expect(actions.first.archiveState, IntentionArchiveState.archived);
  });

  test(
    'отсутствующее намерение отличается от пустого периода и вида',
    () async {
      expect(
        await repository.readIntentionStatisticsSection(query(intention: 999)),
        isNull,
      );
      expect(_computations(diagnostics), 0);
      final empty = (await repository.readIntentionStatisticsSection(query()))!;
      expect(_counts(empty.selectedCounts), (0, 0));
      expect(
        (empty.calendar as IntentionStatisticsMonthCalendar).statuses,
        isEmpty,
      );
      final details =
          empty.details as IntentionStatisticsThroughRelationsDetails;
      expect(details.relations.totalItems, 0);
      expect(details.relations.nextCursor, isNull);
      expect(details.selectedActions.items, isEmpty);
      await addChoice(201, [102]);
      repository = createRepository();
      final emptyView = (await repository.readIntentionStatisticsSection(
        query(view: StatisticsView.selectedActions),
      ))!;
      expect(_counts(emptyView.periodCounts), (1, 1));
      expect(_counts(emptyView.selectedCounts), (0, 0));
      expect(
        (emptyView.details as IntentionStatisticsSelectedDetails)
            .sourceIntentions
            .totalItems,
        0,
      );
    },
  );

  test(
    'команда завершается во время изолята, устаревшая попытка не повторяется',
    () async {
      await addChoice(201, [101, 102]);
      final started = ReceivePort();
      addTearDown(started.close);
      var delay = true;
      repository = createRepository(
        runner: (graph, id, groups, outgoing) {
          if (!delay) {
            return runIntentionContributionInIsolate(
              graph,
              id,
              groups,
              outgoing,
            );
          }
          delay = false;
          return _computeWithGate(
            graph,
            id,
            groups,
            outgoing,
            started.sendPort,
          );
        },
      );
      var completed = false;
      final reading = repository.readIntentionStatisticsSection(query());
      final rejected = expectLater(
        reading,
        throwsA(isA<StatisticsSnapshotExpired>()),
      );
      reading.then<void>(
        (_) => completed = true,
        onError: (Object _) {
          completed = true;
        },
      );
      final gate = await started.first as SendPort;
      addTearDown(() => gate.send(null));
      await Future<void>(() {});
      expect(completed, isFalse);
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
      expect(completed, isFalse);
      gate.send(null);
      await rejected;
      expect(probe.titleRows, isEmpty);
      expect(probe.sourceReads, 1);
      expect(_computations(diagnostics), 1);
      final failure = diagnostics.events
          .whereType<StatisticsReadDiagnosticsEvent>()
          .last;
      expect(failure.readType, StatisticsReadDiagnosticsType.intentionSection);
      expect(
        failure.status,
        isA<DiagnosticsFailed>().having(
          (s) => s.code,
          'категория',
          DiagnosticsFailureCode.conflict,
        ),
      );
      final fresh = (await repository.readIntentionStatisticsSection(query()))!;
      expect(_counts(fresh.selectedCounts), (1, 0));
      expect(_counts(fresh.cards.intermediateIntentions), (1, 0));
      expect(
        (fresh.calendar as IntentionStatisticsMonthCalendar)
            .statuses
            .values
            .single,
        DailyChoiceDayStatus.hasIncomplete,
      );
      expect(probe.sourceReads, 2);
      expect(probe.snapshotReads, 1);
      expect(_computations(diagnostics), 2);
    },
  );

  test(
    'смена ревизии и эпохи отклоняет продолжение до чтения названий',
    () async {
      await addChoice(201, [102]);
      await addChoice(202, [108]);
      final section = (await repository.readIntentionStatisticsSection(
        query(),
      ))!;
      final cursor =
          (section.details as IntentionStatisticsThroughRelationsDetails)
              .selectedActions
              .nextCursor!;
      final titleReads = probe.titleRows.length;
      await expectLater(
        createRepository().readIntentionStatisticsBreakdown(cursor),
        throwsA(isA<StatisticsSnapshotExpired>()),
      );
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(4))),
        isA<GraphCommandSucceeded>(),
      );
      await expectLater(
        repository.readIntentionStatisticsBreakdown(cursor),
        throwsA(isA<StatisticsSnapshotExpired>()),
      );
      expect(probe.titleRows, hasLength(titleReads));
      expect(probe.sourceReads, 1);
      expect(_computations(diagnostics), 1);
    },
  );

  test('кэш сохраняет два результата, а вытесненный курсор не пересчитывает раздел', () async {
    await addChoice(201, [102]);
    await addChoice(202, [108]);
    final first = (await repository.readIntentionStatisticsSection(query()))!;
    final firstCursor =
        (first.details as IntentionStatisticsThroughRelationsDetails)
            .selectedActions
            .nextCursor!;
    final wider = (await repository.readIntentionStatisticsSection(
      query(pageSize: 2),
    ))!;
    expect(
      (wider.details as IntentionStatisticsThroughRelationsDetails)
          .selectedActions
          .items,
      hasLength(2),
    );
    final year = (await repository.readIntentionStatisticsSection(
      query(period: StatisticsYear(2026)),
    ))!;
    final yearCursor =
        (year.details as IntentionStatisticsThroughRelationsDetails)
            .selectedActions
            .nextCursor!;
    await repository.readIntentionStatisticsSection(
      query(period: StatisticsMonth(2026, 11)),
    );
    await expectLater(
      repository.readIntentionStatisticsBreakdown(firstCursor),
      throwsA(isA<StatisticsSnapshotExpired>()),
    );
    expect(
      (await repository.readIntentionStatisticsBreakdown(yearCursor))
          .items
          .single
          .id,
      durabilityIntention(3),
    );
    expect(probe.sourceReads, 3);
    expect(_computations(diagnostics), 3);
    await repository.readIntentionStatisticsSection(query());
    expect(probe.sourceReads, 4);
  });

  test(
    'ключ кэша различает намерение и местную дату без смены ревизии',
    () async {
      await addChoice(201, [102], completed: false);
      final source = (await repository.readIntentionStatisticsSection(
        query(view: StatisticsView.sourceIntentions),
      ))!;
      final other = (await repository.readIntentionStatisticsSection(
        query(view: StatisticsView.sourceIntentions, intention: 3),
      ))!;
      final tomorrow = (await repository.readIntentionStatisticsSection(
        query(
          view: StatisticsView.sourceIntentions,
          localDate: CalendarDate.fromParts(2026, 10, 13),
        ),
      ))!;
      expect(_counts(source.selectedCounts), (1, 0));
      expect(_counts(other.selectedCounts), (0, 0));
      expect(source.details.uncompleted.upcoming, 1);
      expect(tomorrow.details.uncompleted.missed, 1);
      expect(
        tomorrow.revision.compareTo(source.revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'отказ второй разбивки отклоняет целый раздел с диагностикой этапа',
    () async {
      await addChoice(201, [101, 102]);
      probe.failTitleRead = 2;
      await expectLater(
        repository.readIntentionStatisticsSection(
          query(view: StatisticsView.intermediateIntentions),
        ),
        throwsA(isA<StatisticsReadUnavailableFailure>()),
      );
      final event = diagnostics.events
          .whereType<StatisticsReadDiagnosticsEvent>()
          .last;
      expect(event.readType, StatisticsReadDiagnosticsType.intentionSection);
      expect(event.stage, StatisticsReadDiagnosticsStage.titles);
      expect(
        event.status,
        isA<DiagnosticsFailed>().having(
          (s) => s.code,
          'категория',
          DiagnosticsFailureCode.unavailable,
        ),
      );
    },
  );

  test('отказ изолята отклоняет раздел до чтения названий', () async {
    await addChoice(201, [101, 102]);
    repository = createRepository(runner: _failedComputation);
    await expectLater(
      repository.readIntentionStatisticsSection(query()),
      throwsA(isA<StatisticsReadUnexpectedFailure>()),
    );
    expect(probe.titleRows, isEmpty);
    final events = diagnostics.events
        .whereType<StatisticsReadDiagnosticsEvent>();
    expect(
      events.last.readType,
      StatisticsReadDiagnosticsType.intentionSection,
    );
    expect(events.last.stage, StatisticsReadDiagnosticsStage.computation);
    expect(
      events.last.status,
      isA<DiagnosticsFailed>().having(
        (s) => s.code,
        'категория',
        DiagnosticsFailureCode.unexpected,
      ),
    );
  });

  test('отказ продолжения сохраняет кэш для явного повтора', () async {
    await addChoice(201, [102]);
    await addChoice(202, [108]);
    final first = (await repository.readIntentionStatisticsSection(query()))!;
    final cursor = (first.details as IntentionStatisticsThroughRelationsDetails)
        .relations
        .nextCursor!;
    probe.failTitleRead = probe.titleReads + 1;
    await expectLater(
      repository.readIntentionStatisticsBreakdown(cursor),
      throwsA(isA<StatisticsReadUnavailableFailure>()),
    );
    final event = diagnostics.events
        .whereType<StatisticsReadDiagnosticsEvent>()
        .last;
    expect(event.readType, StatisticsReadDiagnosticsType.breakdown);
    expect(
      event.status,
      isA<DiagnosticsFailed>().having(
        (s) => s.code,
        'категория',
        DiagnosticsFailureCode.unavailable,
      ),
    );
    final next = await repository.readIntentionStatisticsBreakdown(cursor);
    expect(next.items.single.id, durabilityRelation(108));
    expect(probe.sourceReads, 1);
    expect(_computations(diagnostics), 1);
  });

  test('повреждение архивной отметки связи отклоняет целый раздел', () async {
    await addChoice(201, [101, 102]);
    probe.corruptRelationArchive = true;
    await expectLater(
      repository.readIntentionStatisticsSection(query()),
      throwsA(isA<StatisticsReadCorruptionFailure>()),
    );
  });
}

(int, int) _counts(ContributionCounts counts) =>
    (counts.planned, counts.contribution);

int _computations(InMemoryDiagnosticsSink sink) => sink.events
    .whereType<StatisticsReadDiagnosticsEvent>()
    .where(
      (e) =>
          e.stage == StatisticsReadDiagnosticsStage.computation &&
          e.status is DiagnosticsStarted,
    )
    .length;

Future<IntentionContributionResult<CalendarDate>> _computeWithGate(
  ContributionRelationGraph graph,
  IntentionId id,
  List<IntentionContributionGroup<CalendarDate>> groups,
  List<ContributionOutgoingRelation> outgoing,
  SendPort started,
) => Isolate.run(() async {
  final gate = ReceivePort();
  started.send(gate.sendPort);
  await gate.first;
  return computeIntentionContribution(
    graph: graph,
    intentionId: id,
    groups: groups,
    activeOutgoingRelations: outgoing,
  );
});

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  var sourceReads = 0;
  var snapshotReads = 0;
  final titleRows = <int>[];
  int? failTitleRead;
  var titleReads = 0;
  var corruptRelationArchive = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    if (_isStatisticsTitles(statement) && ++titleReads == failTitleRead) {
      throw sqlite.SqliteException(
        message: 'Недоступно',
        extendedResultCode: 5,
      );
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (statement.statements.single.contains('archived_seed_key')) {
      sourceReads++;
    }
    if (statement.statements.single.contains('creation_sequence >')) {
      snapshotReads++;
    }
    if (_isStatisticsTitles(statement)) titleRows.add(rows.length);
    if (corruptRelationArchive &&
        rows.isNotEmpty &&
        rows.first.containsKey('intention_archived')) {
      return [
        {...rows.first, 'is_archived': 2},
        ...rows.skip(1),
      ];
    }
    return rows;
  }
}

bool _isStatisticsTitles(LocalDatabaseSqlStatement statement) {
  final sql = statement.statements.single;
  return sql.contains('SELECT id, title, is_archived FROM intentions') ||
      sql.contains('AS intention_archived');
}

Future<IntentionContributionResult<CalendarDate>> _failedComputation(
  ContributionRelationGraph graph,
  IntentionId id,
  List<IntentionContributionGroup<CalendarDate>> groups,
  List<ContributionOutgoingRelation> outgoing,
) => Isolate.run(() => throw StateError('CANARY-содержимое-графа'));
