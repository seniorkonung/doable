import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/contribution_statistics_fixture.dart';
import '../support/benchmark.dart';
import '../support/intention_statistics_fixture.dart';
import '../../test/support/graph_seed.dart';
import '../../test/support/local_database_harness.dart';

const _readZone = #intentionStatisticsCostRead;

enum _SectionState { cold, warm, rebuilt, readRace, computeRace }

void main() {
  for (final profile in IntentionStatisticsProfile.values) {
    test('бенчмарк раздела: ${profile.name}', () async {
      final fullRun = Stopwatch()..start();
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _ReadTrace();
      late sqlite.Database raw;
      final database = await harness.openReadyDatabase(
        setup: (connection) => raw = connection,
        observer: trace,
      );
      final fixture = IntentionStatisticsFixture(profile);
      final preparation = Stopwatch()..start();
      fixture.populate(raw);
      preparation.stop();
      expect(_scalar(raw, 'SELECT COUNT(*) FROM intentions'), 50000);
      expect(_scalar(raw, 'SELECT COUNT(*) FROM long_term_relations'), 150000);
      expect(_scalar(raw, 'SELECT COUNT(*) FROM daily_choices'), 109500);
      final totalSteps = _scalar(
        raw,
        'SELECT COUNT(*) FROM daily_choice_path_steps',
      );
      expect(totalSteps, switch (profile) {
        IntentionStatisticsProfile.shortPaths => 382370,
        IntentionStatisticsProfile.longPaths => 3285000,
        IntentionStatisticsProfile.manyBreakdowns => 146000,
      });
      _report({
        'profile': profile.name,
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'intentions': 50000,
        'relations': 150000,
        'choices': 109500,
        'steps': totalSteps,
        'warmups': benchmarkWarmups,
        'repetitions': benchmarkSamples,
        ...await _environment(raw, harness),
      });
      var commandNumber = 0;
      final renameId = _intentionId(50000);
      final changedRelationId = _relationId(
        profile == IntentionStatisticsProfile.manyBreakdowns
            ? 150500
            : 100000 + fixture.intention - 1,
      );
      DriftPersonalGraphRepository createRepository() =>
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 6, 15),
            trace,
            intentionStatisticsRunner: trace.compute,
          );
      Future<void> rename(DriftPersonalGraphRepository repository) async {
        expect(
          await repository.execute(
            UpdateIntention(
              id: renameId,
              title: 'Замер ${commandNumber++}',
              description: null,
            ),
          ),
          isA<ResultSuccess<Object>>(),
        );
      }

      for (final archived in [false, true]) {
        if (archived) fixture.archivePathParts(raw);
        _report({
          'profile': profile.name,
          'archived': archived,
          'archivedIntentions': _scalar(
            raw,
            'SELECT COUNT(*) FROM intentions WHERE is_archived = 1',
          ),
          'archivedRelations': _scalar(
            raw,
            'SELECT COUNT(*) FROM long_term_relations WHERE is_archived = 1',
          ),
          'archivedSteps': _scalar(raw, '''SELECT COUNT(*)
              FROM daily_choice_path_steps s JOIN long_term_relations r
                ON r.id = s.long_term_relation_id WHERE r.is_archived = 1'''),
        });
        for (final period in [StatisticsMonth(2026, 6), StatisticsYear(2026)]) {
          final referenceWatch = Stopwatch()..start();
          final originalRelationArchived =
              raw
                  .select(
                    'SELECT is_archived FROM long_term_relations WHERE id = ?',
                    [changedRelationId.toCanonicalString()],
                  )
                  .single
                  .values
                  .single ==
              1;
          final reference = fixture.reference(raw, period);
          final expected = {
            for (final view in StatisticsView.values)
              view: reference.section(view),
          };
          seedRawGraph(raw, () {
            raw.execute(
              'UPDATE long_term_relations SET is_archived = ? WHERE id = ?',
              [
                originalRelationArchived ? 0 : 1,
                changedRelationId.toCanonicalString(),
              ],
            );
          });
          final changedReference = fixture.reference(raw, period);
          final changedExpected = {
            for (final view in StatisticsView.values)
              view: changedReference.section(view),
          };
          if (!archived) {
            expect(
              changedExpected[StatisticsView.throughRelations]!
                  .breakdowns[StatisticsBreakdown.relations],
              isNot(
                equals(
                  expected[StatisticsView.throughRelations]!
                      .breakdowns[StatisticsBreakdown.relations],
                ),
              ),
              reason: 'команда меняет разбивку, а не только ревизию',
            );
          }
          seedRawGraph(raw, () {
            raw.execute(
              'UPDATE long_term_relations SET is_archived = ? WHERE id = ?',
              [
                originalRelationArchived ? 1 : 0,
                changedRelationId.toCanonicalString(),
              ],
            );
          });
          referenceWatch.stop();
          final choices = _periodCount(raw, 'daily_choices', period);
          final steps = _periodCount(raw, 'daily_choice_path_steps', period);
          expect(expected.values.first.periodCounts.planned, choices);
          expect(choices, period is StatisticsMonth ? 3000 : 36500);
          if (profile == IntentionStatisticsProfile.longPaths) {
            expect(steps, period is StatisticsMonth ? 90000 : 1095000);
          }
          if (profile == IntentionStatisticsProfile.manyBreakdowns) {
            for (final section in expected.values) {
              expect(
                section.breakdowns.values.map((rows) => rows.length),
                everyElement(greaterThan(100)),
              );
            }
          }
          _report({
            'profile': profile.name,
            'archived': archived,
            'period': period is StatisticsMonth ? 'month' : 'year',
            'referenceMs': referenceWatch.elapsedMilliseconds,
            'choices': choices,
            'steps': steps,
            ...reference.distribution,
            'breakdownSizes': {
              for (final entry in expected.entries)
                entry.key.name: {
                  for (final rows in entry.value.breakdowns.entries)
                    rows.key.name: rows.value.length,
                },
            },
          });
          for (final view in StatisticsView.values) {
            IntentionStatisticsQuery query() => IntentionStatisticsQuery(
              intentionId: _intentionId(fixture.intention),
              period: period,
              view: view,
              localDate: CalendarDate.fromParts(2026, 6, 15),
              pageSize: 100,
            );
            for (final state in _SectionState.values) {
              final benchmarkCase =
                  '${profile.name}/${archived ? 'archived' : 'active'}/${period is StatisticsMonth ? 'month' : 'year'}/${view.name}/${state.name}';
              if (!benchmarkIncludes(benchmarkCase)) continue;
              final race =
                  state == _SectionState.readRace ||
                  state == _SectionState.computeRace;
              // Очередь и изолят общие у четырёх видов; гонка проверяется
              // один раз на их владельце, с реальным подсчётом через связи.
              if (race && view != StatisticsView.throughRelations) continue;
              var repository = createRepository();
              final samples = <String, List<Duration>>{};
              final statePreparation = Stopwatch()..start();
              if (state != _SectionState.cold) {
                await repository.loadStatisticsRelationSnapshot();
              }
              statePreparation.stop();
              var relationArchived = originalRelationArchived;
              for (
                var sample = -benchmarkWarmups;
                sample < benchmarkSamples;
                sample++
              ) {
                final setup = Stopwatch()..start();
                switch (state) {
                  case _SectionState.cold:
                    repository = createRepository();
                  case _SectionState.warm ||
                      _SectionState.readRace ||
                      _SectionState.computeRace:
                    await rename(repository);
                  case _SectionState.rebuilt:
                    final result = relationArchived
                        ? await repository.execute(
                            RestoreLongTermRelation(changedRelationId),
                          )
                        : await repository.execute(
                            ArchiveLongTermRelation(changedRelationId),
                          );
                    expect(result, isA<GraphCommandSucceeded>());
                    relationArchived = !relationArchived;
                }
                setup.stop();
                final commandStarted = Completer<void>();
                final commandWatch = Stopwatch();
                trace.arm(
                  onRead: state == _SectionState.readRace
                      ? commandStarted.complete
                      : null,
                  onCompute: state == _SectionState.computeRace
                      ? commandStarted.complete
                      : null,
                );
                // Команда остаётся в зоне потребителя, вне транзакции Drift.
                final command = race
                    ? commandStarted.future.then((_) async {
                        commandWatch.start();
                        await rename(repository);
                        commandWatch.stop();
                        if (state == _SectionState.computeRace) {
                          expect(
                            trace.computeFinished,
                            isFalse,
                            reason: 'команда подтверждается до конца настоящего изолята',
                          );
                        }
                      })
                    : null;
                final request = Stopwatch()..start();
                final result = await runZoned(
                  () => repository.getIntentionStatisticsSection(query()),
                  zoneValues: {_readZone: true},
                );
                request.stop();
                if (command != null) await command;
                trace.disarm();
                final currentExpected =
                    relationArchived == originalRelationArchived
                    ? expected[view]!
                    : changedExpected[view]!;
                if (race) {
                  expect(
                    result,
                    isA<IntentionStatisticsSectionError>().having(
                      (value) => value.failure,
                      'устаревшая попытка',
                      isA<StatisticsSnapshotExpired>(),
                    ),
                  );
                  expect(trace.titleRows, 0);
                  expect(
                    trace.attempts[StatisticsReadDiagnosticsStage.sourceData],
                    1,
                  );
                  expect(
                    trace.attempts[StatisticsReadDiagnosticsStage.computation],
                    1,
                  );
                  if (state == _SectionState.computeRace) {
                    expect(trace.heartbeats, greaterThan(0));
                  }
                } else {
                  final section = _section(result);
                  _expectSection(section, currentExpected, period, view);
                  expect(
                    trace.titleRows,
                    _firstPages(section.details).values
                        .fold<int>(0, (sum, page) => sum + page.items.length),
                  );
                  if (sample == 0) {
                    for (final entry in _firstPages(section.details).entries) {
                      _expectRows(
                        entry.value.items,
                        currentExpected.breakdowns[entry.key]!,
                        0,
                        raw,
                      );
                    }
                  }
                }
                expect(trace.titleRows, lessThanOrEqualTo(200));
                expect(
                  trace.snapshotPageRows,
                  everyElement(lessThanOrEqualTo(512)),
                );
                expect(trace.transactions, isNotEmpty);
                if (sample >= 0) {
                  _collect(samples, 'request', request.elapsed);
                  _collect(samples, 'statePreparation', setup.elapsed);
                  _collect(
                    samples,
                    'queueMax',
                    trace.transactions.reduce((a, b) => a > b ? a : b),
                  );
                  _collect(
                    samples,
                    'queueTotal',
                    trace.transactions.fold(
                      Duration.zero,
                      (sum, value) => sum + value,
                    ),
                  );
                  for (final entry in trace.stages.entries) {
                    _collect(samples, entry.key.name, entry.value);
                  }
                  if (race) _collect(samples, 'command', commandWatch.elapsed);
                }
                if (race) {
                  final freshWatch = Stopwatch()..start();
                  final fresh = _section(
                    await repository.getIntentionStatisticsSection(query()),
                  );
                  freshWatch.stop();
                  _expectSection(fresh, currentExpected, period, view);
                  if (sample >= 0) {
                    _collect(samples, 'freshRequest', freshWatch.elapsed);
                  }
                }
              }
              _reportSeries(
                profile,
                archived,
                period,
                view,
                state.name,
                statePreparation.elapsed,
                samples,
              );
              _reportBudgets(benchmarkCase, samples, period, state);
              if (relationArchived != originalRelationArchived) {
                expect(
                  await repository.execute(
                    originalRelationArchived
                        ? ArchiveLongTermRelation(changedRelationId)
                        : RestoreLongTermRelation(changedRelationId),
                  ),
                  isA<GraphCommandSucceeded>(),
                );
              }
            }

            // Курсоры и предыдущие порции готовятся отдельно от замера.
            // Продолжения читают только названия и архивные отметки своего среза.
            for (final kind in view.breakdowns) {
              final benchmarkCase =
                  '${profile.name}/${archived ? 'archived' : 'active'}/${period is StatisticsMonth ? 'month' : 'year'}/${view.name}/last-${kind.name}';
              if (!benchmarkIncludes(benchmarkCase)) continue;
              final rows = expected[view]!.breakdowns[kind]!;
              if (rows.length <= 100) continue;
              final repository = createRepository();
              final samples = <String, List<Duration>>{};
              for (
                var sample = -benchmarkWarmups;
                sample < benchmarkSamples;
                sample++
              ) {
                final cursorPreparation = Stopwatch()..start();
                final section = _section(
                  await repository.getIntentionStatisticsSection(query()),
                );
                StatisticsBreakdownPage<Object> page = _firstPages(
                  section.details,
                )[kind]!;
                var offset = 0;
                final lastOffset = ((rows.length - 1) ~/ 100) * 100;
                while (offset + page.items.length < lastOffset) {
                  cursorPreparation.stop();
                  _expectRows(page.items, rows, offset, raw);
                  offset += page.items.length;
                  cursorPreparation.start();
                  page = _continuation(
                    await repository.getIntentionStatisticsBreakdown<Object>(
                      page.nextCursor!,
                    ),
                  );
                }
                cursorPreparation.stop();
                _expectRows(page.items, rows, offset, raw);
                offset += page.items.length;
                expect(offset, lastOffset);
                final cursor = page.nextCursor!;
                final commandStarted = Completer<void>();
                final commandWatch = Stopwatch();
                trace.arm(onRead: commandStarted.complete);
                final command = commandStarted.future.then((_) async {
                  commandWatch.start();
                  await rename(repository);
                  commandWatch.stop();
                });
                final request = Stopwatch()..start();
                final last = _continuation(
                  await runZoned(
                    () => repository.getIntentionStatisticsBreakdown<Object>(
                      cursor,
                    ),
                    zoneValues: {_readZone: true},
                  ),
                );
                request.stop();
                await command;
                trace.disarm();
                expect(
                  last.revision.compareTo(section.revision),
                  GraphRevisionOrder.same,
                );
                expect(last.nextCursor, isNull);
                _expectRows(last.items, rows, lastOffset, raw);
                expect(trace.titleRows, last.items.length);
                expect(trace.stages.keys, [
                  StatisticsReadDiagnosticsStage.titles,
                ]);
                if (sample >= 0) {
                  _collect(samples, 'request', request.elapsed);
                  _collect(samples, 'command', commandWatch.elapsed);
                  _collect(
                    samples,
                    'cursorPreparation',
                    cursorPreparation.elapsed,
                  );
                  _collect(
                    samples,
                    'queueMax',
                    trace.transactions.reduce((a, b) => a > b ? a : b),
                  );
                  _collect(
                    samples,
                    'queueTotal',
                    trace.transactions.fold(
                      Duration.zero,
                      (sum, value) => sum + value,
                    ),
                  );
                  _collect(samples, 'titles', trace.stages.values.single);
                }
                expect(
                  await repository.getIntentionStatisticsBreakdown(cursor),
                  isA<IntentionStatisticsBreakdownError<Object>>().having(
                    (value) => value.failure,
                    'курсор после команды',
                    isA<StatisticsSnapshotExpired>(),
                  ),
                );
              }
              _reportSeries(
                profile,
                archived,
                period,
                view,
                'last-${kind.name}',
                Duration.zero,
                samples,
              );
              _reportBudgets(benchmarkCase, samples, period, null);
            }
          }
        }
      }
      _report({
        'profile': profile.name,
        'fullRunMs': fullRun.elapsedMilliseconds,
      });
    }, timeout: const Timeout(Duration(hours: 2)));
  }
}

IntentionStatisticsSection _section(IntentionStatisticsSectionResult result) {
  expect(result, isA<IntentionStatisticsSectionSuccess>());
  return (result as IntentionStatisticsSectionSuccess).value;
}

StatisticsBreakdownContinuationPage<T> _continuation<T>(
  IntentionStatisticsBreakdownResult<T> result,
) {
  expect(result, isA<IntentionStatisticsBreakdownSuccess<T>>());
  return (result as IntentionStatisticsBreakdownSuccess<T>).value;
}

Map<StatisticsBreakdown, StatisticsBreakdownFirstPage<Object>> _firstPages(
  IntentionStatisticsViewDetails details,
) => switch (details) {
  IntentionStatisticsSourceDetails(:final selectedActions) => {
    StatisticsBreakdown.selectedActions: selectedActions,
  },
  IntentionStatisticsIntermediateDetails(
    :final sourceIntentions,
    :final selectedActions,
  ) =>
    {
      StatisticsBreakdown.sourceIntentions: sourceIntentions,
      StatisticsBreakdown.selectedActions: selectedActions,
    },
  IntentionStatisticsSelectedDetails(:final sourceIntentions) => {
    StatisticsBreakdown.sourceIntentions: sourceIntentions,
  },
  IntentionStatisticsThroughRelationsDetails(
    :final relations,
    :final selectedActions,
  ) =>
    {
      StatisticsBreakdown.relations: relations,
      StatisticsBreakdown.selectedActions: selectedActions,
    },
};

void _expectSection(
  IntentionStatisticsSection section,
  IntentionFixtureSection expected,
  StatisticsPeriod period,
  StatisticsView view,
) {
  expect(
    (section.periodCounts.planned, section.periodCounts.contribution),
    (expected.periodCounts.planned, expected.periodCounts.contribution),
  );
  for (final kind in StatisticsView.values) {
    final counts = expected.cards[kind]!;
    expect(
      (section.cards[kind].planned, section.cards[kind].contribution),
      (counts.planned, counts.contribution),
    );
  }
  expect(section.details.uncompleted.missed, expected.uncompleted.missed);
  expect(section.details.uncompleted.upcoming, expected.uncompleted.upcoming);
  if (section.details case IntentionStatisticsThroughRelationsDetails(
    :final explicitPathChoices,
  )) {
    expect(explicitPathChoices, expected.explicitPathChoices);
  }
  switch (section.calendar) {
    case IntentionStatisticsMonthCalendar(:final statuses):
      expect(
        {
          for (final entry in statuses.entries)
            entry.key.toCanonicalString(): entry.value,
        },
        {
          for (final entry in expected.days.entries)
            entry.key: entry.value.planned == entry.value.contribution
                ? DailyChoiceDayStatus.allCompleted
                : DailyChoiceDayStatus.hasIncomplete,
        },
      );
    case IntentionStatisticsYearCalendar(:final months):
      expect(months, hasLength(12));
      for (var month = 1; month <= 12; month++) {
        final expectedMonth = expected.days.entries.where(
          (entry) => int.parse(entry.key.substring(5, 7)) == month,
        );
        expect(
          (months[month - 1].planned, months[month - 1].contribution),
          (
            expectedMonth.fold<int>(0, (a, b) => a + b.value.planned),
            expectedMonth.fold<int>(0, (a, b) => a + b.value.contribution),
          ),
        );
      }
  }
  expect(section.calendar.period, period);
  final pages = _firstPages(section.details);
  expect(pages.keys, expected.breakdowns.keys);
  for (final kind in pages.keys) {
    final rows = expected.breakdowns[kind]!;
    expect(pages[kind]!.totalItems, rows.length);
    expect(pages[kind]!.items.length, lessThanOrEqualTo(100));
    expect(pages[kind]!.nextCursor == null, rows.length <= 100);
    expect(_rowCounts(pages[kind]!.items), rows.take(100));
  }
}

Iterable<FixtureBreakdownRow> _rowCounts(Iterable<Object> items) => items.map(
  (item) => switch (item) {
    StatisticsRelationItem(:final id, :final relatedIntention) => (
      id: id.toCanonicalString(),
      planned: relatedIntention.counts.planned,
      contribution: relatedIntention.counts.contribution,
    ),
    StatisticsItem(:final id, :final counts) => (
      id: id.toCanonicalString(),
      planned: counts.planned,
      contribution: counts.contribution,
    ),
    _ => throw StateError('Неизвестная строка разбивки'),
  },
);

void _expectRows(
  List<Object> items,
  List<FixtureBreakdownRow> expected,
  int offset,
  sqlite.Database raw,
) {
  expect(items.length, lessThanOrEqualTo(100));
  expect(_rowCounts(items), expected.skip(offset).take(100));
  for (final item in items) {
    if (item is StatisticsRelationItem) {
      final row = raw
          .select(
            '''SELECT r.is_archived, i.is_archived AS intention_archived
        FROM long_term_relations r JOIN intentions i
          ON i.id = r.related_intention_id WHERE r.id = ?''',
            [item.id.toCanonicalString()],
          )
          .single;
      expect(
        item.scope,
        row['is_archived'] == 1 ? RelationScope.archived : RelationScope.active,
      );
      expect(
        item.relatedIntention.archiveState,
        row['intention_archived'] == 1
            ? IntentionArchiveState.archived
            : IntentionArchiveState.active,
      );
    } else if (item is StatisticsItem) {
      final row = raw.select(
        'SELECT is_archived FROM intentions WHERE id = ?',
        [item.id.toCanonicalString()],
      ).single;
      expect(
        item.archiveState,
        row['is_archived'] == 1
            ? IntentionArchiveState.archived
            : IntentionArchiveState.active,
      );
    }
  }
}

IntentionId _intentionId(int number) => (IntentionId.decode(
  ContributionStatisticsFixture.id(number),
) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  ContributionStatisticsFixture.id(number),
) as LongTermRelationIdDecodingSuccess).id;

int _scalar(sqlite.Database db, String sql) =>
    db.select(sql).single.values.single as int;
int _periodCount(
  sqlite.Database db,
  String table,
  StatisticsPeriod period,
) => _scalar(
  db,
  table == 'daily_choices'
      ? "SELECT COUNT(*) FROM daily_choices WHERE choice_date BETWEEN '${period.firstDate.toCanonicalString()}' AND '${period.lastDate.toCanonicalString()}'"
      : "SELECT COUNT(*) FROM daily_choice_path_steps s JOIN daily_choices c ON c.id = s.daily_choice_id WHERE c.choice_date BETWEEN '${period.firstDate.toCanonicalString()}' AND '${period.lastDate.toCanonicalString()}'",
);

void _collect(
  Map<String, List<Duration>> samples,
  String key,
  Duration value,
) => (samples[key] ??= []).add(value);

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
void _reportSeries(
  IntentionStatisticsProfile profile,
  bool archived,
  StatisticsPeriod period,
  StatisticsView view,
  String series,
  Duration preparation,
  Map<String, List<Duration>> samples,
) => _report({
  'profile': profile.name,
  'archived': archived,
  'period': period is StatisticsMonth ? 'month' : 'year',
  'view': view.name,
  'series': series,
  'statePreparationMs': preparation.inMicroseconds / 1000,
  for (final entry in samples.entries)
    '${entry.key}P95Ms': benchmarkP95(entry.value),
});

// Бюджеты Phase 3 обоснованы измерениями задачи 3.6 в решении 10 дизайна.
// null обозначает продолжение: его готовый результат не пересчитывается.
void _reportBudgets(
  String benchmarkCase,
  Map<String, List<Duration>> samples,
  StatisticsPeriod period,
  _SectionState? state,
) {
  final month = period is StatisticsMonth;
  final continuation = state == null;
  final reload = state == _SectionState.cold || state == _SectionState.rebuilt;
  final budgets = <String, int>{
    'queueMax': continuation ? 10 : (month ? 200 : 2000),
    'queueTotal': continuation ? 10 : (month ? 500 : 2250),
    'sourceData': month ? 200 : 2000,
    'relationSnapshot': reload ? 800 : 5,
    'computation': month ? 200 : 350,
    'titles': 10,
    'request': continuation
        ? 10
        : reload
        ? (month ? 1200 : 3000)
        : (month ? 350 : 2250),
    'freshRequest': month ? 350 : 2250,
    'command': state == _SectionState.readRace ? (month ? 250 : 2000) : 50,
  };
  for (final entry in samples.entries) {
    if (budgets[entry.key] case final limit?) {
      reportBenchmarkBudget(benchmarkCase, entry.key, entry.value, limit);
    }
  }
}

Future<Map<String, Object>> _environment(
  sqlite.Database raw,
  LocalDatabaseHarness harness,
) async => {
  'os': (await Process.run('uname', ['-srmo'])).stdout.toString().trim(),
  'cpu': File('/proc/cpuinfo')
      .readAsLinesSync()
      .firstWhere((line) => line.startsWith('model name'))
      .split(':')
      .last
      .trim(),
  'memory': File('/proc/meminfo').readAsLinesSync().first,
  'filesystem': (await Process.run('findmnt', [
    '-n',
    '-o',
    'FSTYPE,SOURCE',
    '-T',
    harness.databaseFile.path,
  ])).stdout.toString().trim(),
  'dart': Platform.version,
  'drift': RegExp(r'drift:\n(?:[^\n]*\n)*?    version: "([^"]+)"')
      .firstMatch(File('pubspec.lock').readAsStringSync())!
      .group(1)!,
  'sqlite': sqlite.sqlite3.version.libVersion,
  'connection': 'NativeDatabase, synchronous, file-backed',
  for (final pragma in [
    'journal_mode',
    'synchronous',
    'temp_store',
    'cache_size',
    'foreign_keys',
    'busy_timeout',
  ])
    pragma: raw.select('PRAGMA $pragma').single.values.single!,
};

final class _ReadTrace extends LocalDatabaseConnectionObserver
    implements DiagnosticsSink {
  final transactions = <Duration>[];
  final stages = <StatisticsReadDiagnosticsStage, Duration>{};
  final attempts = <StatisticsReadDiagnosticsStage, int>{};
  final snapshotPageRows = <int>[];
  final _transaction = Stopwatch();
  bool _armed = false;
  int titleRows = 0, heartbeats = 0;
  bool computeFinished = false;
  void Function()? _onRead, _onCompute;

  bool get _reading => _armed && Zone.current[_readZone] == true;
  void arm({void Function()? onRead, void Function()? onCompute}) {
    transactions.clear();
    stages.clear();
    attempts.clear();
    snapshotPageRows.clear();
    titleRows = 0;
    heartbeats = 0;
    computeFinished = false;
    _onRead = onRead;
    _onCompute = onCompute;
    _armed = true;
  }

  void disarm() {
    _armed = false;
    _onRead = null;
    _onCompute = null;
  }

  Future<IntentionContributionResult<CalendarDate>> compute(
    ContributionRelationGraph graph,
    IntentionId id,
    List<IntentionContributionGroup<CalendarDate>> groups,
    List<ContributionOutgoingRelation> outgoing,
  ) async {
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => heartbeats++,
    );
    try {
      final result = runIntentionContributionInIsolate(
        graph,
        id,
        groups,
        outgoing,
      );
      final callback = _onCompute;
      _onCompute = null;
      callback?.call();
      return await result;
    } finally {
      computeFinished = true;
      heartbeat.cancel();
    }
  }

  @override
  void record(DiagnosticsEvent event) {
    if (!_reading || event is! StatisticsReadDiagnosticsEvent) return;
    switch (event.status) {
      case DiagnosticsStarted():
        attempts.update(event.stage, (count) => count + 1, ifAbsent: () => 1);
      case DiagnosticsSucceeded(:final duration) ||
          DiagnosticsFailed(:final duration):
        stages[event.stage] = duration;
    }
  }

  @override
  void onTransactionStarted() {
    if (_reading) {
      _transaction
        ..reset()
        ..start();
    }
  }

  @override
  void onTransactionFinished() {
    if (_reading) transactions.add(_transaction.elapsed);
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_reading && statement.operation == LocalDatabaseSqlOperation.select) {
      final callback = _onRead;
      _onRead = null;
      callback?.call();
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (_reading && rows.isNotEmpty && rows.first.containsKey('title')) {
      titleRows += rows.length;
    }
    if (_reading &&
        rows.isNotEmpty &&
        rows.first.containsKey('creation_sequence')) {
      snapshotPageRows.add(rows.length);
    }
    return rows;
  }
}
