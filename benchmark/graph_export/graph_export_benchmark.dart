import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_export.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/file_document_access.dart';
import '../../test/support/in_memory_diagnostics_sink.dart';
import '../support/benchmark.dart';
import '../support/graph_log_database.dart';
import '../support/graph_log_fixture.dart';
import '../support/graph_log_memory_worker.dart';

/// Наибольшее число пакетов после снимка, при котором сжатие ещё не
/// начинается: экспорт собирает состояние из снимка и всех этих пакетов.
const _rangePackages = graphLogCompactionThreshold;

/// Замеров экспорта профиля в серии. Экспорт, как и сжатие, длится десятки
/// секунд, а его замеры расходятся на проценты. Прогрев не нужен: код
/// сборки и записи состояния уже скомпилирован подготовкой снимка профиля,
/// а изоляты одной группы делят код.
const _exportSeriesSamples = 3;

/// Бюджет наибольшей длительности экспорта профиля в серии.
const _exportBudgetMs = 45000;

void main() {
  // Графы общие для наборов и строятся при первом обращении: граф профиля
  // строится больше минуты. Экспорт граф не меняет.
  final smaller = _ExportOnce(graphLogProfileEntities ~/ 10);
  final profile = _ExportOnce(graphLogProfileEntities);
  tearDownAll(() async {
    await smaller.dispose();
    await profile.dispose();
  });

  test('бенчмарк экспорта: память не растёт с размером графа', () async {
    final peaks = <int>[];
    for (final shared in [smaller, profile]) {
      final graph = (await shared.export).graph;
      final memory = await graph.measureMemory(GraphLogMemoryOperation.export);
      expect(memory.records, graph.fixture.entities);
      peaks.add(memory.growthBytes);
      _report({
        'benchmark': 'graphExportMemory',
        'entities': graph.fixture.entities,
        'rangePackages': _rangePackages,
        'exportLiveHeapPeakMiB': _mebibytes(memory.growthBytes),
      });
    }
    final [smallerPeak, profilePeak] = peaks;
    final growth = profilePeak - smallerPeak;
    _report({
      'case': 'profile/export',
      'metric': 'рост пика живых данных с размером графа',
      'growthMiB': _mebibytes(growth),
      'noiseMiB': _mebibytes(graphLogMemoryNoiseBytes),
      'status': growth < graphLogMemoryNoiseBytes ? 'withinNoise' : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('бенчмарк экспорта: длительность экспорта на профиле', () async {
    const benchmarkCase = 'profile/export';
    if (!benchmarkIncludes(benchmarkCase)) return;
    final export = await profile.export;
    final samples = <_ExportSample>[];
    while (samples.length < min(benchmarkSamples, _exportSeriesSamples)) {
      samples.add(await export.run());
    }
    final slowest = samples
        .map((sample) => sample.total)
        .reduce((first, second) => first > second ? first : second);
    _report({
      'benchmark': 'graphExportParts',
      'entities': export.graph.fixture.entities,
      'rangePackages': _rangePackages,
      'documentBytes': samples.last.documentBytes,
      'samples': [
        for (final sample in samples)
          {
            'totalMs': _milliseconds(sample.total),
            'temporaryFileMs': _milliseconds(sample.temporaryFile),
            'documentWriteMs': _milliseconds(
              sample.total - sample.temporaryFile,
            ),
          },
      ],
    });
    _report({
      'case': benchmarkCase,
      'metric': 'длительность экспорта',
      'maxMs': _milliseconds(slowest),
      'budgetMs': _exportBudgetMs,
      'samples': samples.length,
      'budgetStatus': samples.length < _exportSeriesSamples
          ? 'smoke'
          : slowest.inMilliseconds <= _exportBudgetMs
          ? 'withinBudget'
          : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Экспорт графа из [_entities] сущностей, который готовится при первом
/// обращении и освобождается в конце.
final class _ExportOnce {
  _ExportOnce(this._entities);

  final int _entities;
  Future<_Export>? _export;

  Future<_Export> get export => _export ??= _Export.prepare(_entities);

  Future<void> dispose() async {
    if (_export case final export?) await (await export).graph.dispose();
  }
}

/// Длительность экспорта, её часть до начала копирования временного файла в
/// документ и размер документа.
typedef _ExportSample = ({
  Duration total,
  Duration temporaryFile,
  int documentBytes,
});

/// Экспорт приложения над графом [graph] с [_rangePackages] пакетами после
/// базового снимка. Документ — локальный файл, в который копируется
/// временный файл экспорта.
final class _Export {
  _Export._(this.graph, this._documents, this._export);

  static Future<_Export> prepare(int entities) async {
    final graph = await GraphLogDatabase.prepare(entities);
    await graph.confirmEdits(_rangePackages);
    final directory = graph.harness.temporaryDirectory.uri;
    final documents = FileDocumentAccess(
      await Directory.fromUri(directory.resolve('documents/')).create(),
    );
    return _Export._(
      graph,
      documents,
      GraphExport(
        documents: documents,
        compaction: GraphLogCompaction(
          log: graph.repository,
          directory: graph.snapshots,
          clock: () => GraphLogDatabase.now,
          diagnosticsSink: InMemoryDiagnosticsSink(),
        ),
        temporaryDirectory: Future.value(
          Directory.fromUri(directory.resolve('tmp/')),
        ),
        clock: () => GraphLogDatabase.now,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ),
    );
  }

  final GraphLogDatabase graph;
  final FileDocumentAccess _documents;
  final GraphExport _export;

  /// Экспортирует граф в новый документ от его выбора до записи, как после
  /// системного диалога сохранения, и удаляет документ.
  Future<_ExportSample> run() async {
    final DocumentCreated(:document) = _documents.newDocument();
    final stopwatch = Stopwatch();
    late Duration temporaryFile;
    _documents.beforeWrite = () async => temporaryFile = stopwatch.elapsed;
    final outcome = await Zone.root.run(() {
      stopwatch.start();
      return _export.write(document, onProgress: (_) {});
    });
    stopwatch.stop();
    expect(outcome, GraphExportOutcome.succeeded);
    final file = _documents.created.last;
    final sample = (
      total: stopwatch.elapsed,
      temporaryFile: temporaryFile,
      documentBytes: await file.length(),
    );
    await file.delete();
    return sample;
  }
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;

double _mebibytes(int bytes) => (bytes / (1 << 20) * 10).round() / 10;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
