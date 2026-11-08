import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/benchmark.dart';
import '../support/contribution_statistics_fixture.dart';
import '../../test/support/intention_cascade_execution.dart';
import '../../test/support/graph_seed.dart';
import '../../test/support/intention_holding_reference.dart';
import '../../test/support/local_database_harness.dart';

const _readZone = #intentionHoldingRead;

/// Связь 1000 → 1001 первой полосы. Без неё вспомогательное 1001 доступно
/// только из неудерживаемого цикла 998 и 999, поэтому её архивирование и
/// восстановление меняют удержание, а не только ревизию.
const _toggledRelation = 101000;

/// Загруженные строки: конец неудерживаемого цикла, первые главные и
/// вспомогательное 1001, удержание которого зависит от [_toggledRelation].
final _loadedNodes = [
  for (
    var node = ContributionStatisticsFixture.firstMainIntention - 50;
    node < ContributionStatisticsFixture.firstMainIntention + 50;
    node++
  )
    node,
];

enum _Series { cold, relationChanged, commandDuringBuild, built }

void main() {
  test('бенчмарк индекса удержания', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final trace = _BuildTrace();
    late sqlite.Database raw;
    final database = await harness.openReadyDatabase(
      setup: (value) => raw = value,
      observer: trace,
    );
    // Профиль длинных путей не архивирует первые звенья цепочек: у каждого
    // активного вспомогательного остаётся активная входящая связь.
    final fixture = ContributionStatisticsFixture(
      ContributionStatisticsProfile.longPaths,
    );
    final preparation = Stopwatch()..start();
    fixture
      ..populate(raw)
      ..assignIntentionKinds(raw);
    preparation.stop();
    expect(_scalar(raw, 'SELECT COUNT(*) FROM intentions'), 50000);
    expect(_scalar(raw, 'SELECT COUNT(*) FROM long_term_relations'), 150000);
    expect(
      _scalar(raw, '''SELECT COUNT(*) FROM intentions i
        WHERE i.kind = 'supporting' AND NOT EXISTS (
          SELECT 1 FROM long_term_relations r
          WHERE r.related_intention_id = i.id
            AND (i.is_archived = 1 OR r.is_archived = 0))'''),
      0,
      reason: 'фикстура соблюдает правило входящей связи вспомогательного',
    );
    final relationId = (LongTermRelationId.decode(
      ContributionStatisticsFixture.id(_toggledRelation),
    ) as LongTermRelationIdDecodingSuccess).id;
    final relationArchived =
        _scalar(
          raw,
          "SELECT is_archived FROM long_term_relations WHERE id = '${relationId.toCanonicalString()}'",
        ) ==
        1;
    // Оба эталона вычисляются по сырым данным до создания репозитория.
    final expected = <bool, Map<IntentionId, IntentionHolding>>{};
    var heldIntentions = 0;
    for (final archived in [true, false]) {
      seedRawGraph(raw, () {
        raw.execute(
          'UPDATE long_term_relations SET is_archived = ? WHERE id = ?',
          [archived ? 1 : 0, relationId.toCanonicalString()],
        );
      });
      final held = _referenceHeld(raw);
      if (archived == relationArchived) heldIntentions = held.length;
      expected[archived] = {
        for (final node in _loadedNodes)
          _intention(node): held.contains(_intention(node))
              ? IntentionHolding.held
              : IntentionHolding.notHeld,
      };
    }
    expect(
      expected[false],
      isNot(equals(expected[true])),
      reason: 'изменение связи меняет удержание загруженной строки',
    );
    _report({
      'intentions': 50000,
      'relations': 150000,
      'supportingIntentions': _scalar(
        raw,
        "SELECT COUNT(*) FROM intentions WHERE kind = 'supporting'",
      ),
      'archivedIntentions': _scalar(
        raw,
        'SELECT COUNT(*) FROM intentions WHERE is_archived = 1',
      ),
      'archivedRelations': _scalar(
        raw,
        'SELECT COUNT(*) FROM long_term_relations WHERE is_archived = 1',
      ),
      'heldIntentions': heldIntentions,
      'preparationMs': preparation.elapsedMilliseconds,
      'samples': benchmarkSamples,
      'warmups': benchmarkWarmups,
    });

    final renamedId = _intention(49999);
    var commandNumber = 0;
    DriftPersonalGraphRepository createRepository() =>
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 11, 7),
          trace,
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

    for (final series in _Series.values) {
      final benchmarkCase = 'holding/${series.name}';
      if (!benchmarkIncludes(benchmarkCase)) continue;
      var repository = createRepository();
      var archived = relationArchived;
      if (series == _Series.built) {
        expect(
          await repository.getIntentionHolding(
            _loadedNodes.map(_intention).toSet(),
          ),
          isA<IntentionHoldingRead>(),
        );
      }
      final samples = <String, List<Duration>>{};
      void collect(String key, Duration value) =>
          (samples[key] ??= []).add(value);
      var pageRows = 0;
      for (
        var sample = -benchmarkWarmups;
        sample < benchmarkSamples;
        sample++
      ) {
        switch (series) {
          case _Series.cold || _Series.commandDuringBuild:
            repository = createRepository();
          case _Series.relationChanged:
            expect(
              await repository.execute(
                archived
                    ? await previewedRestoreRelation(repository, relationId)
                    : await previewedArchiveRelation(repository, relationId),
              ),
              isA<GraphCommandSucceeded>(),
            );
            archived = !archived;
          case _Series.built:
        }
        final commandWatch = Stopwatch();
        final commandStarted = Completer<void>();
        trace.arm(
          onRead: series == _Series.commandDuringBuild
              ? commandStarted.complete
              : null,
        );
        // Команда подписывается вне зоны чтения и входит в общую очередь
        // между короткими транзакциями построения.
        final command = series == _Series.commandDuringBuild
            ? commandStarted.future.then((_) async {
                commandWatch.start();
                await rename(repository);
                commandWatch.stop();
              })
            : null;
        final requestWatch = Stopwatch()..start();
        final result = await runZoned(
          () => repository.getIntentionHolding(
            _loadedNodes.map(_intention).toSet(),
          ),
          zoneValues: {_readZone: true},
        );
        requestWatch.stop();
        if (command != null) await command;
        trace.disarm();
        expect(result, isA<IntentionHoldingRead>());
        expect((result as IntentionHoldingRead).holdings, expected[archived]);
        if (series == _Series.built) {
          expect(trace.attempts, isEmpty);
          expect(trace.transactions, isEmpty);
        } else {
          expect(trace.attempts, {
            for (final stage in IntentionHoldingIndexDiagnosticsStage.values)
              stage: 1,
          });
          expect(trace.pageRows, everyElement(lessThanOrEqualTo(1024)));
          pageRows = trace.pageRows.fold(0, (a, b) => a + b);
        }
        if (sample < 0) continue;
        collect(
          series == _Series.built ? 'read' : 'build',
          requestWatch.elapsed,
        );
        if (series != _Series.built) {
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
        }
        if (command != null) collect('command', commandWatch.elapsed);
      }
      _report({
        'series': series.name,
        'pageRows': pageRows,
        for (final MapEntry(key: key, value: values) in samples.entries)
          '${key}P95Ms': benchmarkP95(values),
      });
      // Бюджеты повторяют снимок связей статистики (ADR-0026): построение
      // заново, занятие очереди одним чтением, команда во время построения и
      // чтение загруженных строк при построенном индексе.
      final budgets = <String, int>{
        if (series != _Series.commandDuringBuild) 'build': 800,
        'queueMax': 100,
        'command': 50,
        'read': 10,
      };
      for (final MapEntry(key: key, value: values) in samples.entries) {
        if (budgets[key] case final budget?) {
          reportBenchmarkBudget(benchmarkCase, key, values, budget);
        }
      }
      if (archived != relationArchived) {
        expect(
          await repository.execute(
            relationArchived
                ? await previewedArchiveRelation(repository, relationId)
                : await previewedRestoreRelation(repository, relationId),
          ),
          isA<GraphCommandSucceeded>(),
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

IntentionId _intention(int node) => (IntentionId.decode(
  ContributionStatisticsFixture.id(node + 1),
) as IntentionIdDecodingSuccess).id;

/// Удерживаемые намерения по независимому эталону над сырыми строками.
Set<IntentionId> _referenceHeld(sqlite.Database database) {
  IntentionId decode(Object? value) =>
      (IntentionId.decode(value as String) as IntentionIdDecodingSuccess).id;
  return referenceHeldIntentions(
    intentions: {
      for (final row in database.select(
        'SELECT id, kind, is_archived FROM intentions',
      ))
        decode(row['id']): (
          kind: IntentionKind.values.byName(row['kind'] as String),
          archiveState: row['is_archived'] == 1
              ? IntentionArchiveState.archived
              : IntentionArchiveState.active,
        ),
    },
    relations: [
      for (final row in database.select(
        '''SELECT source_intention_id, related_intention_id, is_archived
        FROM long_term_relations''',
      ))
        (
          source: decode(row['source_intention_id']),
          target: decode(row['related_intention_id']),
          scope: row['is_archived'] == 1
              ? RelationScope.archived
              : RelationScope.active,
        ),
    ],
  );
}

int _scalar(sqlite.Database database, String sql) =>
    database.select(sql).single.values.single as int;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));

/// Наблюдает только построение, запущенное в зоне чтения: транзакции очереди,
/// строки порций и длительности этапов из диагностики.
final class _BuildTrace extends LocalDatabaseConnectionObserver
    implements DiagnosticsSink {
  final transactions = <Duration>[];
  final stages = <IntentionHoldingIndexDiagnosticsStage, Duration>{};
  final attempts = <IntentionHoldingIndexDiagnosticsStage, int>{};
  final pageRows = <int>[];
  final _transaction = Stopwatch();
  bool _armed = false;
  void Function()? _onRead;

  void arm({void Function()? onRead}) {
    transactions.clear();
    stages.clear();
    attempts.clear();
    pageRows.clear();
    _onRead = onRead;
    _armed = true;
  }

  void disarm() {
    _armed = false;
    _onRead = null;
  }

  bool get _reading => _armed && Zone.current[_readZone] == true;

  @override
  void record(DiagnosticsEvent event) {
    if (!_reading || event is! IntentionHoldingIndexDiagnosticsEvent) return;
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
    if (_reading && rows.isNotEmpty && rows.first.containsKey('page_key')) {
      pageRows.add(rows.length);
    }
    return rows;
  }
}
