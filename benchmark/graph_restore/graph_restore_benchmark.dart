import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/data_transfer/application/graph_restore.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/benchmark.dart';
import '../support/graph_backup_restore.dart';
import '../support/graph_log_database.dart';
import '../support/graph_log_fixture.dart';
import '../support/graph_log_memory_worker.dart';

/// Наибольшее число пакетов после снимка, при котором сжатие ещё не
/// начинается: восстановление собирает состояние копии из снимка и всех
/// этих пакетов.
const _rangePackages = graphLogCompactionThreshold;

/// Замеров восстановления профиля в серии. Восстановление длится около двух
/// минут, а его замеры расходятся на проценты. С третьим замером
/// запуск бенчмарка вместе с подготовкой графа профиля и замером памяти
/// длился бы дольше 10 минут. Прогрев не нужен: первое восстановление
/// процесса, которое ещё компилирует код замены, длится столько же, сколько
/// следующие.
const _restoreSeriesSamples = 2;

/// Бюджет наибольшей длительности восстановления профиля в серии.
const _restoreBudgetMs = 155000;

void main() {
  // Графы общие для наборов и строятся при первом обращении: граф профиля
  // строится больше минуты. Восстановление заменяет граф состоянием копии, а
  // копия сделана без последующих изменений, поэтому граф остаётся прежним.
  final trace = _RestoreTrace();
  final smaller = _RestoreOnce(graphLogProfileEntities ~/ 10, trace);
  final profile = _RestoreOnce(graphLogProfileEntities, trace);
  tearDownAll(() async {
    await smaller.dispose();
    await profile.dispose();
  });

  test('бенчмарк восстановления копии: память не растёт с размером графа '
      'вместе с памятью SQLite', () async {
    final peaks = <int>[];
    for (final shared in [smaller, profile]) {
      final graph = (await shared.restore).graph;
      final memory = await graph.measureMemory(GraphLogMemoryOperation.restore);
      expect(memory.records, graph.fixture.entities);
      peaks.add(memory.growthBytes);
      _report({
        'benchmark': 'graphRestoreMemory',
        'entities': graph.fixture.entities,
        'rangePackages': _rangePackages,
        'restoreLiveHeapAndMallocPeakMiB': _mebibytes(memory.growthBytes),
      });
    }
    final [smallerPeak, profilePeak] = peaks;
    final growth = profilePeak - smallerPeak;
    _report({
      'case': 'profile/restore',
      'metric': 'рост пика живых данных и памяти malloc с размером графа',
      'growthMiB': _mebibytes(growth),
      'noiseMiB': _mebibytes(graphLogMemoryNoiseBytes),
      'status': growth < graphLogMemoryNoiseBytes ? 'withinNoise' : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('бенчмарк восстановления копии: поисковый индекс в длительности '
      'замены', () async {
    // Доля поискового индекса не зависит от размера графа, а на графе в
    // десять раз меньше профиля замер в десять раз короче.
    final restore = await smaller.restore;
    final withTriggers = await restore.run();
    final (:withoutTriggers, :rebuild) = await restore
        .runWithoutSearchIndexTriggers();
    _report({
      'benchmark': 'graphRestoreSearchIndex',
      'entities': restore.graph.fixture.entities,
      'intentions': restore.graph.fixture.intentions,
      'replacementWithIndexTriggersMs': _milliseconds(withTriggers.replacement),
      'replacementWithoutIndexTriggersMs': _milliseconds(
        withoutTriggers.replacement,
      ),
      'indexRebuildMs': _milliseconds(rebuild),
    });
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('бенчмарк восстановления копии: длительность восстановления на '
      'профиле', () async {
    const benchmarkCase = 'profile/restore';
    if (!benchmarkIncludes(benchmarkCase)) return;
    final restore = await profile.restore;
    final samples = <_RestoreSample>[];
    while (samples.length < min(benchmarkSamples, _restoreSeriesSamples)) {
      samples.add(await restore.run());
    }
    final slowest = samples
        .map((sample) => sample.total)
        .reduce((first, second) => first > second ? first : second);
    _report({
      'benchmark': 'graphRestoreParts',
      'entities': restore.graph.fixture.entities,
      'rangePackages': _rangePackages,
      'samples': [for (final sample in samples) sample.toJson()],
    });
    _report({
      'case': benchmarkCase,
      'metric': 'длительность восстановления копии',
      'maxMs': _milliseconds(slowest),
      'budgetMs': _restoreBudgetMs,
      'samples': samples.length,
      'budgetStatus': samples.length < _restoreSeriesSamples
          ? 'smoke'
          : slowest.inMilliseconds <= _restoreBudgetMs
          ? 'withinBudget'
          : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Восстановление над графом из [_entities] сущностей, которое готовится при
/// первом обращении и освобождается в конце.
final class _RestoreOnce {
  _RestoreOnce(this._entities, this._trace);

  final int _entities;
  final _RestoreTrace _trace;
  Future<_Restore>? _restore;

  Future<_Restore> get restore =>
      _restore ??= _Restore.prepare(_entities, _trace);

  Future<void> dispose() async {
    if (_restore case final restore?) await (await restore).dispose();
  }
}

/// Длительность восстановления и его частей: записи снимка замены, удаления
/// прежнего графа, вставки записей снимка и остатка замены — сверки
/// количеств, строк копии перед заменой, снимка и пакета «сброс», COMMIT и
/// публикации исхода. Время операторов SQL удаления, вставки и проверки
/// путей входит в длительность своих частей.
final class _RestoreSample {
  const _RestoreSample({
    required this.total,
    required this.snapshotWrite,
    required this.deletion,
    required this.insertion,
    required this.sql,
  });

  final Duration total;
  final Duration snapshotWrite;
  final Duration deletion;
  final Duration insertion;
  final _ReplacementSql sql;

  /// Фаза 2: замена графа в монопольном режиме координатора.
  Duration get replacement => total - snapshotWrite;

  Map<String, Object> toJson() => {
    'totalMs': _milliseconds(total),
    'snapshotWriteMs': _milliseconds(snapshotWrite),
    'replacementMs': _milliseconds(replacement),
    'deletionMs': _milliseconds(deletion),
    'deletionSqlMs': _milliseconds(sql.deletion),
    'insertionMs': _milliseconds(insertion),
    'insertionSqlMs': _milliseconds(sql.insertion),
    'pathVerificationSqlMs': _milliseconds(sql.pathVerification),
    'replacementRestMs': _milliseconds(replacement - deletion - insertion),
  };
}

/// Восстановление ручной копии графа [graph], сделанной после
/// [_rangePackages] пакетов от базового снимка, операцией приложения.
final class _Restore {
  _Restore._(this.graph, this._restore, this._backup, this._trace);

  static Future<_Restore> prepare(int entities, _RestoreTrace trace) async {
    final graph = await GraphLogDatabase.prepare(entities, observer: trace);
    await graph.confirmEdits(_rangePackages);
    final restore = BenchmarkGraphRestore(
      graph.repository,
      snapshots: graph.snapshots,
      clock: () => GraphLogDatabase.now,
    );
    await restore.makeManualBackup();
    return _Restore._(graph, restore, await restore.readManualBackup(), trace);
  }

  final GraphLogDatabase graph;
  final BenchmarkGraphRestore _restore;
  final GraphBackupEntry _backup;
  final _RestoreTrace _trace;

  /// Восстанавливает копию от подтверждения до замены графа.
  Future<_RestoreSample> run() async {
    final stopwatch = Stopwatch();
    Duration? replacementStart;
    Duration? deletionEnd;
    Duration? insertionEnd;
    void onProgress(GraphRestoreProgress progress) {
      if (progress.phase != GraphRestorePhase.replacement) return;
      final elapsed = stopwatch.elapsed;
      replacementStart ??= elapsed;
      // Прежний граф и снимок замены — одно состояние копии, а ход замены
      // считает удалённые и вставленные записи, поэтому удаление
      // заканчивается на половине хода.
      if (progress.share >= 0.5) deletionEnd ??= elapsed;
      if (progress.share == 1) insertionEnd ??= elapsed;
    }

    await Zone.root.run(() {
      _trace.start();
      stopwatch.start();
      return _restore.restore(_backup, onProgress: onProgress);
    });
    stopwatch.stop();
    final sql = _trace.stop();
    if ((replacementStart, deletionEnd, insertionEnd) case (
      final replacementStart?,
      final deletionEnd?,
      final insertionEnd?,
    )) {
      return _RestoreSample(
        total: stopwatch.elapsed,
        snapshotWrite: replacementStart,
        deletion: deletionEnd - replacementStart,
        insertion: insertionEnd - deletionEnd,
        sql: sql,
      );
    }
    throw StateError('Ход замены не дошёл до конца удаления и вставки.');
  }

  /// Восстанавливает копию без триггеров поискового индекса намерений, а
  /// затем возвращает их и перестраивает индекс по таблице намерений, как
  /// перестроила бы его замена графа без этих триггеров.
  Future<({_RestoreSample withoutTriggers, Duration rebuild})>
  runWithoutSearchIndexTriggers() async {
    final triggers = [
      for (final row in graph.raw.select(
        "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' "
        "AND tbl_name = 'intentions' AND name LIKE 'intentions_fts_%'",
      ))
        (name: row['name'] as String, sql: row['sql'] as String),
    ];
    expect(triggers, hasLength(3));
    for (final trigger in triggers) {
      graph.raw.execute('DROP TRIGGER ${trigger.name}');
    }
    final _RestoreSample sample;
    try {
      sample = await run();
    } finally {
      for (final trigger in triggers) {
        graph.raw.execute(trigger.sql);
      }
    }
    final stopwatch = Stopwatch()..start();
    graph.raw.execute(
      "INSERT INTO intention_titles_fts(intention_titles_fts) "
      "VALUES ('rebuild')",
    );
    return (withoutTriggers: sample, rebuild: stopwatch.elapsed);
  }

  Future<void> dispose() async {
    await _restore.dispose();
    await graph.dispose();
  }
}

/// Время операторов SQL замены графа по видам.
typedef _ReplacementSql = ({
  Duration deletion,
  Duration insertion,
  Duration pathVerification,
});

/// Время операторов SQL восстановления: удаления прежнего графа, пакетов
/// вставки записей снимка и чтений шагов вставленных путей.
final class _RestoreTrace extends LocalDatabaseConnectionObserver {
  final _statement = Stopwatch();
  var _recording = false;
  var _deletion = Duration.zero;
  var _insertion = Duration.zero;
  var _pathVerification = Duration.zero;

  void start() {
    _deletion = Duration.zero;
    _insertion = Duration.zero;
    _pathVerification = Duration.zero;
    _recording = true;
  }

  _ReplacementSql stop() {
    _recording = false;
    return (
      deletion: _deletion,
      insertion: _insertion,
      pathVerification: _pathVerification,
    );
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_recording) return;
    _statement
      ..reset()
      ..start();
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_recording) return;
    final elapsed = _statement.elapsed;
    final [sql, ...] = statement.statements;
    if (statement.operation == LocalDatabaseSqlOperation.batch) {
      _insertion += elapsed;
    } else if (sql.startsWith('DELETE FROM')) {
      _deletion += elapsed;
    } else if (sql.contains('daily_choice_path_steps')) {
      _pathVerification += elapsed;
    }
  }
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;

double _mebibytes(int bytes) => (bytes / (1 << 20) * 10).round() / 10;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
