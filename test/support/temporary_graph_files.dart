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
final class TemporaryGraphFiles {
  factory TemporaryGraphFiles() {
    final root = Directory.systemTemp.createTempSync('doable_graph_files_');
    addTearDown(() => root.deleteSync(recursive: true));
    return TemporaryGraphFiles._(
      root,
      FileDocumentAccess(
        Directory.fromUri(root.uri.resolve('documents/'))..createSync(),
      ),
    );
  }

  TemporaryGraphFiles._(this._root, this.documents);

  final Directory _root;
  final FileDocumentAccess documents;

  /// Фабрика файлов графа для `AppRuntime.graphFilesFactory`.
  Future<AppGraphFiles> create(ObservableGraphFactLog log) async => (
    compaction: GraphLogCompaction(
      log: log,
      directory: Directory.fromUri(_root.uri.resolve('graph_snapshots/')),
      clock: () => DateTime.now().toUtc(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ),
    temporaryDirectory: Directory.fromUri(_root.uri.resolve('tmp/')),
    documents: documents,
  );
}
