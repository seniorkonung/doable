@Tags(['slow', 'statistics-performance'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/contribution_statistics_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  for (final profile in ContributionStatisticsProfile.values) {
    test('точность и ограниченная материализация: ${profile.name}', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _StatisticsTrace();
      late sqlite.Database raw;
      final database = await harness.openReadyDatabase(
        observer: trace,
        setup: (connection) => raw = connection,
      );
      final fixture = ContributionStatisticsFixture(profile);
      final preparation = Stopwatch()..start();
      fixture.populate(raw);
      preparation.stop();
      final volume = fixture.volume(null);
      expect(
        raw.select('SELECT COUNT(*) AS n FROM daily_choices').single['n'],
        volume.choices,
      );
      expect(
        raw
            .select('SELECT COUNT(*) AS n FROM daily_choice_path_steps')
            .single['n'],
        volume.steps,
      );
      _report({
        'profile': profile.name,
        'environment': Platform.operatingSystem,
        'dart': Platform.version,
        'temporaryDirectory': Directory.systemTemp.path,
        'sqlite': sqlite.sqlite3.version.libVersion,
        'choices': volume.choices,
        'steps': volume.steps,
        ...fixture.distribution(null),
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'graphBytes': fixture.graphBytes,
        'journalMode': raw.select('PRAGMA journal_mode').single.values.single!,
        'synchronous': raw.select('PRAGMA synchronous').single.values.single!,
        'tempStore': raw.select('PRAGMA temp_store').single.values.single!,
        'warmups': 3,
        'repetitions': 40,
      });
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 6, 15),
        InMemoryDiagnosticsSink(),
      );
      var commandNumber = 0;
      for (final archived in [false, true]) {
        if (archived) fixture.archivePathParts(raw);
        final archivedSteps =
            raw.select(
                  '''SELECT COUNT(*) AS n
          FROM daily_choice_path_steps s JOIN long_term_relations r
          ON r.id = s.long_term_relation_id WHERE r.is_archived = 1''',
                ).single['n']
                as int;
        _report({
          'profile': profile.name,
          'archived': archived,
          'archivedSteps': archivedSteps,
          'archivedIntentions':
              raw.select('''SELECT COUNT(*) AS n
            FROM intentions WHERE is_archived = 1''').single['n']
                  as int,
          'archivedRelations':
              raw.select('''SELECT COUNT(*) AS n
            FROM long_term_relations WHERE is_archived = 1''').single['n']
                  as int,
        });
        for (final period in [StatisticsMonth(2026, 6), StatisticsYear(2026)]) {
          final volume = fixture.volume(period);
          final firstDate = period.firstDate.toCanonicalString();
          final lastDate = period.lastDate.toCanonicalString();
          expect(
            raw
                .select(
                  '''SELECT COUNT(*) AS n
            FROM daily_choice_path_steps s JOIN daily_choices c
            ON c.id = s.daily_choice_id
            WHERE c.choice_date BETWEEN ? AND ?''',
                  [firstDate, lastDate],
                )
                .single['n'],
            volume.steps,
          );
          for (final view in const [
            StatisticsView.sourceIntentions,
            StatisticsView.intermediateIntentions,
            StatisticsView.selectedActions,
          ]) {
            final expected = fixture.expected(period, view);
            // Продолжение проверяется, если вид содержит больше одной порции.
            final offsets = [
              0,
              if (expected.length > 100) ((expected.length - 1) ~/ 100) * 100,
            ];
            for (final offset in offsets) {
              final queue = <Duration>[];
              final requests = <Duration>[];
              final commands = <Duration>[];
              final cursorPreparation = <Duration>[];
              final sql = <List<Duration>>[];
              for (var sample = -3; sample < 40; sample++) {
                StatisticsCursor? cursor;
                StatisticsQuery query() => StatisticsQuery(
                  period: period,
                  view: view,
                  localDate: CalendarDate.fromParts(2026, 6, 15),
                  pageSize: 100,
                  cursor: cursor,
                );
                // Курсор готовится отдельно: реальная команда меняет ревизию.
                final cursorWatch = Stopwatch()..start();
                for (var preceding = 0; preceding < offset; preceding += 100) {
                  final precedingPage = _page(
                    await repository.getStatisticsPage(query()),
                  );
                  _expectItems(precedingPage, expected, preceding);
                  cursor = precedingPage.nextCursor;
                  expect(cursor, isNotNull);
                }
                cursorWatch.stop();
                final commandWatch = Stopwatch();
                final readStarted = Completer<void>();
                trace.arm(readStarted.complete);
                // Команда вызывается в зоне потребителя, вне зоны транзакции.
                final command = readStarted.future.then((_) async {
                  commandWatch.start();
                  final result = await repository.execute(
                    UpdateIntention(
                      id: (IntentionId.decode(
                        ContributionStatisticsFixture.id(50000),
                      ) as IntentionIdDecodingSuccess).id,
                      title: 'Замер команды ${commandNumber++}',
                      description: null,
                    ),
                  );
                  commandWatch.stop();
                  expect(result, isA<ResultSuccess<Object>>());
                });
                final requestWatch = Stopwatch()..start();
                final page = _page(await repository.getStatisticsPage(query()));
                requestWatch.stop();
                expect(trace.transactionDuration, isNotNull);
                final queueDuration = trace.transactionDuration!;
                await command;
                _expectItems(page, expected, offset);
                expect(
                  trace.selects.length,
                  lessThanOrEqualTo(offset == 0 ? 3 : 2),
                  reason: 'порция не повторяет дорогой агрегат ради числа элементов',
                );
                expect(
                  page.nextCursor == null,
                  offset + 100 >= expected.length,
                );
                if (offset == 0) {
                  final first = page as StatisticsFirstPage;
                  expect(first.totalItems, expected.length);
                  expect(first.summary.counts.planned, volume.choices);
                  expect(first.summary.counts.contribution, volume.completed);
                  expect(first.summary.uncompleted.missed, volume.missed);
                  expect(first.summary.uncompleted.upcoming, volume.upcoming);
                }
                // Сводка — не более двух групп на дату; остальные строки —
                // порция с запасом и названия её элементов.
                final days =
                    DateTime.utc(
                          period.lastDate.year,
                          period.lastDate.month,
                          period.lastDate.day,
                        )
                        .difference(
                          DateTime.utc(
                            period.firstDate.year,
                            period.firstDate.month,
                            period.firstDate.day,
                          ),
                        )
                        .inDays +
                    1;
                expect(
                  trace.rows,
                  lessThanOrEqualTo(
                    (offset == 0 ? 2 * days : 0) + 101 + page.items.length,
                  ),
                );
                if (sample >= 0) {
                  queue.add(queueDuration);
                  requests.add(requestWatch.elapsed);
                  commands.add(commandWatch.elapsed);
                  cursorPreparation.add(cursorWatch.elapsed);
                  for (var index = 0; index < trace.selects.length; index++) {
                    if (sql.length == index) sql.add([]);
                    sql[index].add(trace.selects[index]);
                  }
                  if (sample % 10 == 0) {
                    _report({
                      'profile': profile.name,
                      'archived': archived,
                      'period': period is StatisticsMonth ? 'month' : 'year',
                      'view': view.name,
                      'offset': offset,
                      'completedSamples': sample + 1,
                      'requestMs': requestWatch.elapsedMicroseconds / 1000,
                    });
                  }
                }
              }
              _report({
                'profile': profile.name,
                'archived': archived,
                'period': period is StatisticsMonth ? 'month' : 'year',
                'view': view.name,
                'offset': offset,
                'periodChoices': volume.choices,
                'periodSteps': volume.steps,
                ...fixture.distribution(period),
                'queueP95Ms': _p95(queue),
                'requestP95Ms': _p95(requests),
                'commandP95Ms': _p95(commands),
                'cursorPreparationP95Ms': _p95(cursorPreparation),
                'selectP95Ms': sql.map(_p95).toList(),
              });
              // Бюджеты согласованы для двух целевых профилей задачи 1.5.
              final budgetMs = period is StatisticsMonth ? 150 : 1250;
              for (final (label, samples) in [
                ('удержание очереди', queue),
                ('полное чтение', requests),
                ('подтверждение команды', commands),
              ]) {
                expect(
                  _p95(samples),
                  lessThanOrEqualTo(budgetMs),
                  reason:
                      'p95: $label, ${profile.name}, ${view.name}, '
                      'порция $offset, период $firstDate — $lastDate',
                );
              }
            }
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}

StatisticsPage _page(StatisticsPageResult result) {
  expect(result, isA<StatisticsPageSuccess>());
  return (result as StatisticsPageSuccess).value;
}

void _expectItems(
  StatisticsPage page,
  List<FixtureContribution> expected,
  int offset,
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
}

double _p95(List<Duration> samples) {
  final sorted = samples.map((duration) => duration.inMicroseconds).toList()
    ..sort();
  return sorted[max(0, (sorted.length * 0.95).ceil() - 1)] / 1000;
}

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));

final class _StatisticsTrace extends LocalDatabaseConnectionObserver {
  final _transaction = Stopwatch();
  final _select = Stopwatch();
  final selects = <Duration>[];
  bool _armed = false;
  bool _recording = false;
  void Function()? _onFirstSelect;
  Duration? transactionDuration;
  var rows = 0;

  void arm(void Function() onFirstSelect) {
    _armed = true;
    rows = 0;
    selects.clear();
    transactionDuration = null;
    _onFirstSelect = onFirstSelect;
  }

  @override
  void onTransactionStarted() {
    if (!_armed) return;
    _armed = false;
    _recording = true;
    _transaction
      ..reset()
      ..start();
  }

  @override
  void onTransactionFinished() {
    if (!_recording) return;
    transactionDuration = _transaction.elapsed;
    _recording = false;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_recording && statement.operation == LocalDatabaseSqlOperation.select) {
      _select
        ..reset()
        ..start();
      final callback = _onFirstSelect;
      _onFirstSelect = null;
      callback?.call();
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> selected,
  ) {
    if (_recording) {
      rows += selected.length;
      selects.add(_select.elapsed);
    }
    return selected;
  }
}
