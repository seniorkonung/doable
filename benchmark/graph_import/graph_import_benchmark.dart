import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/in_memory_diagnostics_sink.dart';
import '../support/benchmark.dart';
import '../support/graph_file_import.dart';
import '../support/graph_log_database.dart';
import '../support/graph_log_fixture.dart';
import '../support/graph_log_memory_worker.dart';
import '../support/graph_replacement_timing.dart';

/// Замеров импорта профиля в серии. Импорт профиля длится больше
/// полутора минут, а его замеры расходятся на доли процента. С третьим
/// замером запуск бенчмарка вместе с подготовкой графа и файла профиля и
/// замером памяти длился бы дольше 10 минут. Прогрев не нужен: первый
/// импорт процесса, который ещё компилирует код замены, длится столько же,
/// сколько следующий.
const _importSeriesSamples = 2;

/// Бюджет наибольшей длительности импорта профиля в серии.
const _importBudgetMs = 140000;

void main() {
  // Графы и файлы общие для наборов и строятся при первом обращении: граф
  // профиля строится больше минуты. Импорт заменяет граф записями файла, а
  // файл записан из того же графа, поэтому граф остаётся прежним.
  final trace = GraphReplacementTrace();
  final smaller = _ImportOnce(graphLogProfileEntities ~/ 10, trace);
  final profile = _ImportOnce(graphLogProfileEntities, trace);
  tearDownAll(() async {
    await smaller.dispose();
    await profile.dispose();
  });

  test('бенчмарк импорта: память не растёт с размером файла вместе с '
      'памятью SQLite', () async {
    final peaks = <int>[];
    for (final shared in [smaller, profile]) {
      final import = await shared.import;
      final graph = import.graph;
      final memory = await graph.measureMemory(
        GraphLogMemoryOperation.import,
        document: import.document,
      );
      expect(memory.records, graph.fixture.entities);
      peaks.add(memory.growthBytes);
      _report({
        'benchmark': 'graphImportMemory',
        'entities': graph.fixture.entities,
        'documentBytes': await import.document.length(),
        'importLiveHeapAndMallocPeakMiB': _mebibytes(memory.growthBytes),
      });
    }
    final [smallerPeak, profilePeak] = peaks;
    final growth = profilePeak - smallerPeak;
    _report({
      'case': 'profile/import',
      'metric': 'рост пика живых данных и памяти malloc с размером файла',
      'growthMiB': _mebibytes(growth),
      'noiseMiB': _mebibytes(graphLogMemoryNoiseBytes),
      'status': growth < graphLogMemoryNoiseBytes ? 'withinNoise' : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('бенчмарк импорта: длительность импорта на профиле', () async {
    const benchmarkCase = 'profile/import';
    if (!benchmarkIncludes(benchmarkCase)) return;
    final import = await profile.import;
    final samples = <_ImportSample>[];
    while (samples.length < min(benchmarkSamples, _importSeriesSamples)) {
      samples.add(await import.run());
    }
    final slowest = samples
        .map((sample) => sample.total)
        .reduce((first, second) => first > second ? first : second);
    _report({
      'benchmark': 'graphImportParts',
      'entities': import.graph.fixture.entities,
      'documentBytes': await import.document.length(),
      'samples': [for (final sample in samples) sample.toJson()],
    });
    _report({
      'case': benchmarkCase,
      'metric': 'длительность импорта',
      'maxMs': _milliseconds(slowest),
      'budgetMs': _importBudgetMs,
      'samples': samples.length,
      'budgetStatus': samples.length < _importSeriesSamples
          ? 'smoke'
          : slowest.inMilliseconds <= _importBudgetMs
          ? 'withinBudget'
          : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Импорт файла графа из [_entities] сущностей, который готовится при
/// первом обращении и освобождается в конце.
final class _ImportOnce {
  _ImportOnce(this._entities, this._trace);

  final int _entities;
  final GraphReplacementTrace _trace;
  Future<_Import>? _import;

  Future<_Import> get import => _import ??= _Import.prepare(_entities, _trace);

  Future<void> dispose() async {
    if (_import case final import?) await (await import).dispose();
  }
}

/// Длительность импорта от выбранного документа до замены графа: чтения
/// файла — копирования документа во временный файл и чтения заголовка — и
/// замены графа записями файла с её частями.
final class _ImportSample {
  const _ImportSample(this.fileReading, this.replacement);

  final Duration fileReading;
  final GraphReplacementSample replacement;

  Duration get total => fileReading + replacement.total;

  Map<String, Object> toJson() => {
    'totalMs': _milliseconds(total),
    'fileReadingMs': _milliseconds(fileReading),
    ...replacement.partsToJson(),
  };
}

/// Импорт файла экспорта графа [graph] в этот же непустой граф операцией
/// приложения. Документ — состояние графа на текущей позиции, записанное в
/// файл формата так же, как его записывает экспорт.
final class _Import {
  _Import._(this.graph, this.document, this._import, this._trace);

  static Future<_Import> prepare(
    int entities,
    GraphReplacementTrace trace,
  ) async {
    final graph = await GraphLogDatabase.prepare(entities, observer: trace);
    final directory = graph.harness.temporaryDirectory.uri;
    final document = File.fromUri(directory.resolve('documents/graph.gz'));
    await document.parent.create();
    final compaction = GraphLogCompaction(
      log: graph.repository,
      directory: graph.snapshots,
      clock: () => GraphLogDatabase.now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    await Zone.root.run(
      () => compaction.writeCurrentState(
        document,
        writtenAt: GraphLogDatabase.now,
        onProgress: (_) {},
      ),
    );
    return _Import._(
      graph,
      document,
      BenchmarkGraphImport(
        graph.repository,
        document: document,
        snapshots: graph.snapshots,
        temporary: Directory.fromUri(directory.resolve('tmp/')),
        clock: () => GraphLogDatabase.now,
      ),
      trace,
    );
  }

  final GraphLogDatabase graph;
  final File document;
  final BenchmarkGraphImport _import;
  final GraphReplacementTrace _trace;

  /// Импортирует документ от его выбора до замены графа; ожидание
  /// подтверждения человеком в замер не входит.
  Future<_ImportSample> run() async {
    final reading = Stopwatch();
    late final GraphReplacementTiming replacement;
    await Zone.root.run(() async {
      final file = await _import.readChosenFile(
        onDocumentChosen: reading.start,
      );
      reading.stop();
      replacement = GraphReplacementTiming.start(_trace);
      await _import.importFile(file, onProgress: replacement.onProgress);
    });
    return _ImportSample(reading.elapsed, replacement.finish());
  }

  Future<void> dispose() async {
    await _import.dispose();
    await graph.dispose();
  }
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;

double _mebibytes(int bytes) => (bytes / (1 << 20) * 10).round() / 10;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
