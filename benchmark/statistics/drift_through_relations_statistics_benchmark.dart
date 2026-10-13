import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/contribution_statistics_fixture.dart';
import '../support/benchmark.dart';
import '../../test/support/local_database_harness.dart';

const _readZone = #statisticsCostRead;

enum _Series { cold, warm, rebuilt, last, readRace, computeRace }

void main() {
  for (final profile in ContributionStatisticsProfile.values) {
    test('бенчмарк через связи: ${profile.name}', () async {
      final fullRun = Stopwatch()..start();
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _ReadTrace();
      late sqlite.Database raw;
      final database = await harness.openReadyDatabase(
        setup: (value) => raw = value,
        observer: trace,
      );
      final fixture = ContributionStatisticsFixture(profile);
      final preparation = Stopwatch()..start();
      fixture.populate(raw);
      preparation.stop();
      _expectVolume(raw, fixture, null);
      expect(_scalar(raw, 'SELECT COUNT(*) FROM intentions'), 50000);
      expect(_scalar(raw, 'SELECT COUNT(*) FROM long_term_relations'), 150000);
      _report({
        'profile': profile.name,
        'intentions': _scalar(raw, 'SELECT COUNT(*) FROM intentions'),
        'relations': _scalar(raw, 'SELECT COUNT(*) FROM long_term_relations'),
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'graphBytes': fixture.graphBytes,
        ..._volume(fixture, null),
        ...await _environment(raw, harness),
        'warmups': benchmarkWarmups,
        'repetitions': benchmarkSamples,
      });
      var commandNumber = 0;
      final cycleId = (LongTermRelationId.decode(
        ContributionStatisticsFixture.id(150999),
      ) as LongTermRelationIdDecodingSuccess).id;
      final renamedId = (IntentionId.decode(
        ContributionStatisticsFixture.id(50000),
      ) as IntentionIdDecodingSuccess).id;
      DriftPersonalGraphRepository createRepository() =>
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 6, 15),
            trace,
            statisticsReachabilityRunner: trace.compute,
          );
      Future<void> rename(DriftPersonalGraphRepository repository) async {
        expect(
          await repository.execute(
            UpdateIntention(
              id: renamedId,
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
          'archivedSteps': _scalar(
            raw,
            '''SELECT COUNT(*) FROM daily_choice_path_steps s
            JOIN long_term_relations r ON r.id = s.long_term_relation_id
            WHERE r.is_archived = 1''',
          ),
          'archivedIntentions': _scalar(
            raw,
            'SELECT COUNT(*) FROM intentions WHERE is_archived = 1',
          ),
          'archivedRelations': _scalar(
            raw,
            'SELECT COUNT(*) FROM long_term_relations WHERE is_archived = 1',
          ),
        });
        for (final period in [StatisticsMonth(2026, 6), StatisticsYear(2026)]) {
          _expectVolume(raw, fixture, period);
          final volume = fixture.volume(period);
          // Два эталона готовятся до создания репозитория. Затем снимок теряет
          // годность только из-за настоящих команд архивирования/восстановления.
          final referenceWatch = Stopwatch()..start();
          final originalCycleArchived =
              _scalar(
                raw,
                "SELECT is_archived FROM long_term_relations WHERE id = '${cycleId.toCanonicalString()}'",
              ) ==
              1;
          final expected = <bool, List<FixtureContribution>>{};
          for (final closed in [false, true]) {
            raw.execute(
              'UPDATE long_term_relations SET is_archived = ? WHERE id = ?',
              [closed ? 1 : 0, cycleId.toCanonicalString()],
            );
            expected[closed] = fixture.expectedThroughRelations(period, raw);
          }
          raw.execute(
            'UPDATE long_term_relations SET is_archived = ? WHERE id = ?',
            [originalCycleArchived ? 1 : 0, cycleId.toCanonicalString()],
          );
          referenceWatch.stop();
          expect(
            expected[false],
            isNot(equals(expected[true])),
            reason: 'разрыв цикла меняет числа, а не только ревизию',
          );
          _report({
            'profile': profile.name,
            'archived': archived,
            'period': period is StatisticsMonth ? 'month' : 'year',
            'referenceMs': referenceWatch.elapsedMilliseconds,
            'archivedPeriodSteps': _scalar(
              raw,
              '''SELECT COUNT(*)
              FROM daily_choice_path_steps s
              JOIN daily_choices c ON c.id = s.daily_choice_id
              JOIN long_term_relations r ON r.id = s.long_term_relation_id
              WHERE r.is_archived = 1 AND c.choice_date BETWEEN
              '${period.firstDate.toCanonicalString()}' AND '${period.lastDate.toCanonicalString()}' ''',
            ),
            ..._volume(fixture, period),
          });
          for (final series in _Series.values) {
            final benchmarkCase =
                '${profile.name}/${archived ? 'archived' : 'active'}/${period is StatisticsMonth ? 'month' : 'year'}/${series.name}';
            if (!benchmarkIncludes(benchmarkCase)) continue;
            var repository = createRepository();
            var cycleArchived = originalCycleArchived;
            final samples = <String, List<Duration>>{};
            void collect(String key, Duration value) =>
                (samples[key] ??= []).add(value);
            StatisticsQuery query([StatisticsCursor? cursor]) =>
                StatisticsQuery(
                  period: period,
                  view: StatisticsView.throughRelations,
                  localDate: CalendarDate.fromParts(2026, 6, 15),
                  pageSize: 100,
                  cursor: cursor,
                );
            final statePreparation = Stopwatch()..start();
            if (series != _Series.cold) {
              await repository.loadStatisticsRelationSnapshot();
            }
            statePreparation.stop();
            var groups = 0, snapshotRows = 0, snapshotPages = 0;
            for (
              var sample = -benchmarkWarmups;
              sample < benchmarkSamples;
              sample++
            ) {
              final prepareWatch = Stopwatch()..start();
              StatisticsCursor? cursor;
              var offset = 0;
              switch (series) {
                case _Series.cold:
                  repository = createRepository();
                case _Series.warm || _Series.readRace || _Series.computeRace:
                  await rename(repository);
                case _Series.rebuilt:
                  final result = cycleArchived
                      ? await repository.execute(
                          RestoreLongTermRelation(cycleId),
                        )
                      : await repository.execute(
                          ArchiveLongTermRelation(cycleId),
                        );
                  expect(result, isA<GraphCommandSucceeded>());
                  cycleArchived = !cycleArchived;
                case _Series.last:
                  final preceding = expected[cycleArchived]!;
                  final lastOffset = ((preceding.length - 1) ~/ 100) * 100;
                  while (offset < lastOffset) {
                    final page = _page(
                      await repository.getStatisticsPage(query(cursor)),
                    );
                    _expectPage(page, preceding, offset, volume);
                    cursor = page.nextCursor;
                    expect(cursor, isNotNull);
                    offset += page.items.length;
                  }
                  expect(cursor, isNotNull);
              }
              prepareWatch.stop();
              final commandWatch = Stopwatch();
              final commandStarted = Completer<void>();
              final race =
                  series == _Series.readRace || series == _Series.computeRace;
              final withCommand = race || series == _Series.last;
              trace.arm(
                onRead: series == _Series.readRace || series == _Series.last
                    ? commandStarted.complete
                    : null,
                onCompute: series == _Series.computeRace
                    ? commandStarted.complete
                    : null,
              );
              // Подписка создаётся в зоне потребителя; команда входит в общую
              // очередь снаружи транзакции и не наследует её зону Drift.
              final command = withCommand
                  ? commandStarted.future.then((_) async {
                      commandWatch.start();
                      await rename(repository);
                      commandWatch.stop();
                      if (series == _Series.computeRace) {
                        expect(
                          trace.computeFinished,
                          isFalse,
                          reason: 'подтверждение команды не ждёт окончания реального подсчёта',
                        );
                      }
                    })
                  : null;
              final requestWatch = Stopwatch()..start();
              final result = await runZoned(
                () => repository.getStatisticsPage(query(cursor)),
                zoneValues: {_readZone: true},
              );
              requestWatch.stop();
              if (command != null) await command;
              trace.disarm();
              if (race) {
                expect(result, isA<StatisticsPageError>());
                expect(
                  (result as StatisticsPageError).failure,
                  isA<StatisticsSnapshotExpired>(),
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
                if (series == _Series.computeRace) {
                  expect(trace.heartbeats, greaterThan(0));
                }
              } else {
                final page = _page(result);
                _expectPage(page, expected[cycleArchived]!, offset, volume);
                expect(
                  trace.titleRows,
                  page.items.length,
                  reason: 'отображаемые данные читаются только для возвращаемого среза',
                );
                expect(
                  trace.snapshotPageRows,
                  everyElement(lessThanOrEqualTo(512)),
                );
                if (series == _Series.last) {
                  expect(trace.attempts.keys, [
                    StatisticsReadDiagnosticsStage.titles,
                  ]);
                } else {
                  expect(
                    trace.attempts[StatisticsReadDiagnosticsStage.computation],
                    1,
                  );
                  expect(
                    trace.snapshotPageRows.isEmpty,
                    series == _Series.warm,
                  );
                }
              }
              groups = max(groups, trace.groups);
              snapshotRows = max(
                snapshotRows,
                trace.snapshotPageRows.fold<int>(0, (a, b) => a + b),
              );
              snapshotPages = max(snapshotPages, trace.snapshotPageRows.length);
              if (sample >= 0) {
                collect('request', requestWatch.elapsed);
                collect('preparation', prepareWatch.elapsed);
                collect(
                  'queueMax',
                  trace.transactions.reduce((a, b) => a > b ? a : b),
                );
                collect(
                  'queueTotal',
                  trace.transactions.fold(Duration.zero, (a, b) => a + b),
                );
                for (final MapEntry(key: stage, value: duration)
                    in trace.stages.entries) {
                  collect(stage.name, duration);
                }
                if (withCommand) collect('command', commandWatch.elapsed);
              }
            }
            _report({
              'profile': profile.name,
              'archived': archived,
              'period': period is StatisticsMonth ? 'month' : 'year',
              'series': series.name,
              'statePreparationMs': statePreparation.elapsedMicroseconds / 1000,
              'groups': groups,
              'snapshotRows': snapshotRows,
              'snapshotPages': snapshotPages,
              for (final MapEntry(key: key, value: values) in samples.entries)
                '${key}P95Ms': benchmarkP95(values),
            });
            // Бюджеты Phase 2 установлены после 48 серий замеров задачи 2.7;
            // их обоснование и область действия — в решении 10 дизайна.
            final month = period is StatisticsMonth;
            final reload = series == _Series.cold || series == _Series.rebuilt;
            final budgets = <String, int>{
              'queueMax': month ? 100 : 1000,
              'queueTotal': month ? 350 : 1250,
              'sourceData': month ? 100 : 1000,
              'relationSnapshot': reload ? 800 : 5,
              'computation': 100,
              'titles': 10,
              'request': series == _Series.last
                  ? 10
                  : reload
                  ? (month ? 1000 : 1750)
                  : (month ? 150 : 1000),
              'command': series == _Series.readRace ? (month ? 150 : 1000) : 50,
            };
            for (final MapEntry(key: key, value: values) in samples.entries) {
              if (budgets[key] case final budget?) {
                reportBenchmarkBudget(benchmarkCase, key, values, budget);
              }
            }
            // После гонки актуальные числа проверяются отдельным запросом;
            // его время не смешивается с отклонённой попыткой.
            final actual = _page(await repository.getStatisticsPage(query()));
            _expectPage(actual, expected[cycleArchived]!, 0, volume);
            // Восстановление исходного состояния тоже проходит через команду.
            if (cycleArchived != originalCycleArchived) {
              expect(
                await repository.execute(
                  originalCycleArchived
                      ? ArchiveLongTermRelation(cycleId)
                      : RestoreLongTermRelation(cycleId),
                ),
                isA<GraphCommandSucceeded>(),
              );
            }
          }
        }
      }
      _report({
        'profile': profile.name,
        'fullRunMs': fullRun.elapsedMilliseconds,
      });
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}

StatisticsPage _page(StatisticsPageResult result) {
  expect(result, isA<StatisticsPageSuccess>());
  return (result as StatisticsPageSuccess).value;
}

void _expectPage(
  StatisticsPage page,
  List<FixtureContribution> expected,
  int offset,
  ({int choices, int steps, int completed, int missed, int upcoming}) volume,
) {
  expect(page.items.length, lessThanOrEqualTo(100));
  expect(
    page.items.map(
      (item) => (
        id: item.id.toCanonicalString(),
        planned: item.counts.planned,
        contribution: item.counts.contribution,
      ),
    ),
    expected.skip(offset).take(100),
  );
  expect(
    page.nextCursor == null,
    offset + page.items.length == expected.length,
  );
  if (offset == 0) {
    final first = page as StatisticsFirstPage;
    expect(first.totalItems, expected.length);
    expect(first.summary.counts.planned, volume.choices);
    expect(first.summary.counts.contribution, volume.completed);
    expect(first.summary.uncompleted.missed, volume.missed);
    expect(first.summary.uncompleted.upcoming, volume.upcoming);
  }
}

int _scalar(sqlite.Database database, String sql) =>
    database.select(sql).single.values.single as int;

void _expectVolume(
  sqlite.Database database,
  ContributionStatisticsFixture fixture,
  StatisticsPeriod? period,
) {
  final where = period == null
      ? ''
      : " WHERE c.choice_date BETWEEN '${period.firstDate.toCanonicalString()}' AND '${period.lastDate.toCanonicalString()}'";
  final volume = fixture.volume(period);
  expect(
    _scalar(database, 'SELECT COUNT(*) FROM daily_choices c$where'),
    volume.choices,
  );
  expect(
    _scalar(database, '''SELECT COUNT(*) FROM daily_choice_path_steps s
    JOIN daily_choices c ON c.id = s.daily_choice_id$where'''),
    volume.steps,
  );
}

Map<String, Object> _volume(
  ContributionStatisticsFixture fixture,
  StatisticsPeriod? period,
) => {
  'choices': fixture.volume(period).choices,
  'steps': fixture.volume(period).steps,
  ...fixture.distribution(period),
};

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
  'temporaryDirectory': harness.temporaryDirectory.path,
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

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));

final class _ReadTrace extends LocalDatabaseConnectionObserver
    implements DiagnosticsSink {
  final transactions = <Duration>[];
  final stages = <StatisticsReadDiagnosticsStage, Duration>{};
  final attempts = <StatisticsReadDiagnosticsStage, int>{};
  final snapshotPageRows = <int>[];
  final _transaction = Stopwatch();
  bool _armed = false;
  int titleRows = 0, groups = 0, heartbeats = 0;
  bool computeFinished = false;
  void Function()? _onRead, _onCompute;

  void arm({void Function()? onRead, void Function()? onCompute}) {
    transactions.clear();
    stages.clear();
    attempts.clear();
    snapshotPageRows.clear();
    titleRows = 0;
    groups = 0;
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

  bool get _reading => _armed && Zone.current[_readZone] == true;

  Future<List<ContributionReachabilityEntry>> compute(
    ContributionRelationGraph graph,
    List<ContributionSeedGroup> groups,
  ) async {
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => heartbeats++,
    );
    try {
      final result = runContributionReachabilityInIsolate(graph, groups);
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
        attempts.update(event.stage, (value) => value + 1, ifAbsent: () => 1);
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
    if (_reading && rows.isNotEmpty) {
      if (rows.first.containsKey('title')) titleRows += rows.length;
      if (rows.first.containsKey('seed_key')) groups += rows.length;
      if (rows.first.containsKey('creation_sequence')) {
        snapshotPageRows.add(rows.length);
      }
    }
    return rows;
  }
}
