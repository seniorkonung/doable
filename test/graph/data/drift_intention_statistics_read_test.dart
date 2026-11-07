import 'dart:isolate';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
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
  late PersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  PersonalGraphRepository createRepository({
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
    await seedGraph(database, () async {
      for (final (number, source, target) in _relations.skip(4)) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority, created_at, updated_at)
           VALUES (?, ?, ?, 'need', 2, 0, 0)''',
          [
            durabilityUuid(number),
            durabilityUuid(source),
            durabilityUuid(target),
          ],
        );
      }
    });
    repository = createRepository();
  });
  tearDown(() => harness.dispose());

  IntentionStatisticsQuery query({
    StatisticsView? view = StatisticsView.throughRelations,
    StatisticsPeriod? period,
    int intention = 2,
    int pageSize = 1,
  }) => IntentionStatisticsQuery(
    intentionId: durabilityIntention(intention),
    period: period ?? StatisticsMonth(2026, 10),
    view: view,
    pageSize: pageSize,
  );

  /// Действие с путём вдоль связей [relations]: исходное намерение первой
  /// связи и связанные намерения всех связей по порядку.
  Future<void> addAction(
    int number,
    List<int> relations, {
    String date = '2026-10-12',
    bool completed = true,
  }) => seedGraph(database, () async {
    final path = [
      _relations.singleWhere((r) => r.$1 == relations.first).$2,
      for (final relation in relations)
        _relations.singleWhere((r) => r.$1 == relation).$3,
    ];
    await database.customStatement(
      '''INSERT INTO actions
         (id, title, date, priority, is_completed, created_at, updated_at)
         VALUES (?, 'Действие', ?, 4, ?, 1, 1)''',
      [durabilityUuid(number), date, completed ? 1 : 0],
    );
    for (final (position, intention) in path.indexed) {
      await database.customStatement(insertActionPathItem, [
        durabilityUuid(number),
        position,
        durabilityUuid(intention),
        position == 0 ? null : durabilityUuid(path[position - 1]),
        actionPathRole(position, path.length),
      ]);
    }
  });

  test('раздел собирает четыре карточки и календарь выбранного вида', () async {
    await addAction(201, [102], date: '2026-10-01');
    await addAction(202, [101, 102], date: '2026-10-11');
    await addAction(203, [101, 102], date: '2026-10-11', completed: false);
    await addAction(204, [101], completed: false);
    await addAction(205, [107], date: '2026-10-13');

    for (final view in StatisticsView.values) {
      final section = _value(
        await repository.getIntentionStatisticsSection(query(view: view)),
      );
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
          StatisticsView.rootIntentions => {1: ActionDayStatus.allCompleted},
          StatisticsView.intermediateIntentions => {
            11: ActionDayStatus.hasIncomplete,
          },
          StatisticsView.terminalIntentions => {
            12: ActionDayStatus.hasIncomplete,
          },
          StatisticsView.throughRelations => {
            1: ActionDayStatus.allCompleted,
            11: ActionDayStatus.hasIncomplete,
            12: ActionDayStatus.hasIncomplete,
            13: ActionDayStatus.allCompleted,
          },
        },
      );

      final year = _value(
        await repository.getIntentionStatisticsSection(
          query(view: view, period: StatisticsYear(2026)),
        ),
      );
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
      final page = _value(
        await repository.getIntentionStatisticsBreakdown(cursor),
      );
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
        await addAction(201 + i, paths[i]);
      }
      for (final view in StatisticsView.values) {
        final section = _value(
          await repository.getIntentionStatisticsSection(query(view: view)),
        );
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
          case IntentionStatisticsRootDetails(:final terminalIntentions):
            await intentions(terminalIntentions, [(4, 1), (3, 1), (1, 1)]);
          case IntentionStatisticsIntermediateDetails(
            :final rootIntentions,
            :final terminalIntentions,
          ):
            await intentions(rootIntentions, [(4, 2), (1, 2)]);
            await intentions(terminalIntentions, [(3, 2), (4, 1), (1, 1)]);
          case IntentionStatisticsTerminalDetails(:final rootIntentions):
            await intentions(rootIntentions, [(4, 1), (1, 1)]);
          case IntentionStatisticsThroughRelationsDetails(
            :final terminalIntentions,
            :final relations,
            :final explicitPathActions,
          ):
            expect(explicitPathActions, 9);
            await intentions(terminalIntentions, [(3, 3), (4, 2), (1, 2)]);
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
    await addAction(201, [101, 102]);
    await addAction(202, [101, 108]);
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
    final section = _value(
      await repository.getIntentionStatisticsSection(query()),
    );
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
    final actions = await collect(details.terminalIntentions, section.revision);
    expect(actions.first.id, durabilityIntention(4));
    expect(actions.first.archiveState, IntentionArchiveState.archived);
  });

  test(
    'отсутствующее намерение отличается от пустого периода и вида',
    () async {
      expect(
        await repository.getIntentionStatisticsSection(query(intention: 999)),
        _readFailure(isA<StatisticsIntentionNotFoundFailure>()),
      );
      expect(_computations(diagnostics), 0);
      final empty = _value(
        await repository.getIntentionStatisticsSection(query()),
      );
      expect(_counts(empty.selectedCounts), (0, 0));
      expect(
        (empty.calendar as IntentionStatisticsMonthCalendar).statuses,
        isEmpty,
      );
      final details =
          empty.details as IntentionStatisticsThroughRelationsDetails;
      expect(details.relations.totalItems, 0);
      expect(details.relations.nextCursor, isNull);
      expect(details.terminalIntentions.items, isEmpty);
      await addAction(201, [102]);
      repository = createRepository();
      final emptyView = _value(
        await repository.getIntentionStatisticsSection(
          query(view: StatisticsView.terminalIntentions),
        ),
      );
      expect(_counts(emptyView.periodCounts), (1, 1));
      expect(_counts(emptyView.selectedCounts), (0, 0));
      expect(
        (emptyView.details as IntentionStatisticsTerminalDetails)
            .rootIntentions
            .totalItems,
        0,
      );
    },
  );

  test(
    'команда завершается во время изолята, устаревшая попытка не повторяется',
    () async {
      await addAction(201, [101, 102]);
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
      final reading = repository.getIntentionStatisticsSection(query());
      final rejected = expectLater(
        reading,
        completion(_readFailure(isA<StatisticsSnapshotExpired>())),
      );
      reading.then<void>((_) => completed = true);
      final gate = await started.first as SendPort;
      addTearDown(() => gate.send(null));
      await Future<void>(() {});
      expect(completed, isFalse);
      expect(
        await repository.execute(
          UpdateActionFields(
            actionId: seedActionId(201),
            patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(false)),
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
      final fresh = _value(
        await repository.getIntentionStatisticsSection(query()),
      );
      expect(_counts(fresh.selectedCounts), (1, 0));
      expect(_counts(fresh.cards.intermediateIntentions), (1, 0));
      expect(
        (fresh.calendar as IntentionStatisticsMonthCalendar)
            .statuses
            .values
            .single,
        ActionDayStatus.hasIncomplete,
      );
      expect(probe.sourceReads, 2);
      expect(probe.snapshotReads, 1);
      expect(_computations(diagnostics), 2);
    },
  );

  test(
    'смена ревизии и эпохи отклоняет продолжение до чтения названий',
    () async {
      await addAction(201, [102]);
      await addAction(202, [108]);
      final section = _value(
        await repository.getIntentionStatisticsSection(query()),
      );
      final cursor =
          (section.details as IntentionStatisticsThroughRelationsDetails)
              .terminalIntentions
              .nextCursor!;
      final titleReads = probe.titleRows.length;
      await expectLater(
        createRepository().getIntentionStatisticsBreakdown(cursor),
        completion(_readFailure(isA<StatisticsSnapshotExpired>())),
      );
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(4))),
        isA<GraphCommandSucceeded>(),
      );
      await expectLater(
        repository.getIntentionStatisticsBreakdown(cursor),
        completion(_readFailure(isA<StatisticsSnapshotExpired>())),
      );
      expect(probe.titleRows, hasLength(titleReads));
      expect(probe.sourceReads, 1);
      expect(_computations(diagnostics), 1);
    },
  );

  test('кэш сохраняет два результата, а вытесненный курсор не пересчитывает раздел', () async {
    await addAction(201, [102]);
    await addAction(202, [108]);
    final first = _value(
      await repository.getIntentionStatisticsSection(query()),
    );
    final firstCursor =
        (first.details as IntentionStatisticsThroughRelationsDetails)
            .terminalIntentions
            .nextCursor!;
    final wider = _value(
      await repository.getIntentionStatisticsSection(query(pageSize: 2)),
    );
    expect(
      (wider.details as IntentionStatisticsThroughRelationsDetails)
          .terminalIntentions
          .items,
      hasLength(2),
    );
    final year = _value(
      await repository.getIntentionStatisticsSection(
        query(period: StatisticsYear(2026)),
      ),
    );
    final yearCursor =
        (year.details as IntentionStatisticsThroughRelationsDetails)
            .terminalIntentions
            .nextCursor!;
    _value(
      await repository.getIntentionStatisticsSection(
        query(period: StatisticsMonth(2026, 11)),
      ),
    );
    await expectLater(
      repository.getIntentionStatisticsBreakdown(firstCursor),
      completion(_readFailure(isA<StatisticsSnapshotExpired>())),
    );
    expect(
      _value(await repository.getIntentionStatisticsBreakdown(yearCursor))
          .items
          .single
          .id,
      durabilityIntention(3),
    );
    expect(probe.sourceReads, 3);
    expect(_computations(diagnostics), 3);
    _value(await repository.getIntentionStatisticsSection(query()));
    expect(probe.sourceReads, 4);
  });

  test(
    'ключ кэша различает намерение и заданный вид без смены ревизии',
    () async {
      await addAction(201, [102], completed: false);
      final source = _value(
        await repository.getIntentionStatisticsSection(
          query(view: StatisticsView.rootIntentions),
        ),
      );
      final other = _value(
        await repository.getIntentionStatisticsSection(
          query(view: StatisticsView.rootIntentions, intention: 3),
        ),
      );
      final opened = _value(
        await repository.getIntentionStatisticsSection(query(view: null)),
      );
      expect(_counts(source.selectedCounts), (1, 0));
      expect(_counts(other.selectedCounts), (0, 0));
      expect(opened.query.view, isNull);
      expect(opened.view, StatisticsView.rootIntentions);
      expect(opened.details, isA<IntentionStatisticsRootDetails>());
      expect(_counts(opened.selectedCounts), (1, 0));
      expect(
        opened.revision.compareTo(source.revision),
        GraphRevisionOrder.same,
      );
      expect(probe.sourceReads, 3);
    },
  );

  test(
    'отказ второй разбивки отклоняет целый раздел с диагностикой этапа',
    () async {
      await addAction(201, [101, 102]);
      probe.failTitleRead = 2;
      await expectLater(
        repository.getIntentionStatisticsSection(
          query(view: StatisticsView.intermediateIntentions),
        ),
        completion(_readFailure(isA<StatisticsReadUnavailableFailure>())),
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
    await addAction(201, [101, 102]);
    repository = createRepository(runner: _failedComputation);
    await expectLater(
      repository.getIntentionStatisticsSection(query()),
      completion(_readFailure(isA<StatisticsReadUnexpectedFailure>())),
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
    await addAction(201, [102]);
    await addAction(202, [108]);
    final first = _value(
      await repository.getIntentionStatisticsSection(query()),
    );
    final cursor = (first.details as IntentionStatisticsThroughRelationsDetails)
        .relations
        .nextCursor!;
    probe.failTitleRead = probe.titleReads + 1;
    await expectLater(
      repository.getIntentionStatisticsBreakdown(cursor),
      completion(_readFailure(isA<StatisticsReadUnavailableFailure>())),
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
    final next = _value(
      await repository.getIntentionStatisticsBreakdown(cursor),
    );
    expect(next.items.single.id, durabilityRelation(108));
    expect(probe.sourceReads, 1);
    expect(_computations(diagnostics), 1);
  });

  test('повреждение архивной отметки связи отклоняет целый раздел', () async {
    await addAction(201, [101, 102]);
    probe.corruptRelationArchive = true;
    await expectLater(
      repository.getIntentionStatisticsSection(query()),
      completion(_readFailure(isA<StatisticsReadCorruptionFailure>())),
    );
  });
}

T _value<T>(GraphResult<T, StatisticsReadFailure> result) {
  expect(result, isA<GraphResultSuccess<T, StatisticsReadFailure>>());
  return (result as GraphResultSuccess<T, StatisticsReadFailure>).value;
}

Matcher _readFailure(Matcher failure) =>
    isA<GraphResultFailure<Object?, StatisticsReadFailure>>().having(
      (result) => result.failure,
      'причина отказа',
      failure,
    );

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
    if (statement.statements.single.contains('path_rows')) {
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
