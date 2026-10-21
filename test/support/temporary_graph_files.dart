import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_document_access.dart';
import 'in_memory_diagnostics_sink.dart';

/// Файлы графа приложения в новом временном каталоге, который удаляется
/// после теста: снимки, временные файлы операций с данными и документы
/// [documents] без системных диалогов.
///
/// Удаление каталога зарегистрировано раньше выключения runtime, созданного
/// после этого объекта, поэтому выполняется после него.
///
/// [stateWriteRunner] запускает запись состояния графа для экспорта: так
/// проверка задерживает экспорт.
final class TemporaryGraphFiles {
  factory TemporaryGraphFiles({
    GraphStateWriteRunner stateWriteRunner = runGraphStateWriteInIsolate,
  }) {
    final root = Directory.systemTemp.createTempSync('doable_graph_files_');
    addTearDown(() => root.deleteSync(recursive: true));
    return TemporaryGraphFiles._(
      root,
      FileDocumentAccess(
        Directory.fromUri(root.uri.resolve('documents/'))..createSync(),
      ),
      stateWriteRunner,
    );
  }

  TemporaryGraphFiles._(this._root, this.documents, this._stateWriteRunner);

  final Directory _root;
  final FileDocumentAccess documents;
  final GraphStateWriteRunner _stateWriteRunner;

  /// Каталог снимков сжатия лога фактов.
  Directory get snapshots =>
      Directory.fromUri(_root.uri.resolve('graph_snapshots/'));

  /// Фабрика файлов графа для `AppRuntime.graphFilesFactory`.
  Future<AppGraphFiles> create(ObservableGraphFactLog log) async => (
    compaction: GraphLogCompaction(
      log: log,
      directory: snapshots,
      clock: () => DateTime.now().toUtc(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      stateWriteRunner: _stateWriteRunner,
    ),
    temporaryDirectory: Directory.fromUri(_root.uri.resolve('tmp/')),
    documents: documents,
  );
}
