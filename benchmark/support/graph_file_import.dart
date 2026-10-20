import 'dart:async';
import 'dart:io';

import 'package:doable/src/data_transfer/application/graph_import.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test/support/file_document_access.dart';
import '../../test/support/in_memory_diagnostics_sink.dart';

/// Импорт файла экспорта операцией приложения: человек выбирает в системном
/// диалоге выбора документ [document], импорт копирует его во временный
/// файл каталога [temporary] и читает заголовок, а после подтверждения
/// координатор принимает импорт и заменяет граф в монопольном режиме.
///
/// Документ копирует подмена доступа к документам: на устройстве его читают
/// потоки `ContentResolver` поставщика документов.
final class BenchmarkGraphImport {
  BenchmarkGraphImport(
    DriftPersonalGraphRepository repository, {
    required File document,
    required Directory snapshots,
    required Directory temporary,
    required DateTime Function() clock,
  }) : _compaction = GraphLogCompaction(
         log: repository,
         directory: snapshots,
         clock: clock,
         diagnosticsSink: InMemoryDiagnosticsSink(),
       ),
       _container = ProviderContainer(
         overrides: [
           personalGraphRepositoryProvider.overrideWithValue(repository),
         ],
       ) {
    final documents = FileDocumentAccess(document.parent);
    documents.openingDialog = () async => documents.chosen(document);
    _import = GraphImport(
      documents: documents,
      compaction: _compaction,
      replacement: repository,
      temporaryDirectory: Future.value(temporary),
      snapshotFiles: Future.value(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
  }

  final GraphLogCompaction _compaction;
  final ProviderContainer _container;
  late final GraphImport _import;

  /// Копирует выбранный документ во временный файл и читает его заголовок;
  /// [onDocumentChosen] вызывается, как только документ выбран.
  Future<GraphImportFile> readChosenFile({
    void Function()? onDocumentChosen,
  }) async {
    final reading = await _import.readChosenFile(
      onDocumentChosen: onDocumentChosen ?? () {},
      cancellation: GraphImportReadingCancellation(),
    );
    return switch (reading) {
      GraphImportFileRead(:final file) => file,
      GraphImportFileReadingCancelled() || GraphImportFileReadingFailed() =>
        throw StateError('Файл не прочитан: $reading.'),
    };
  }

  /// Импортирует прочитанный файл [file], как после подтверждения импорта:
  /// координатор принимает импорт, который заменяет граф записями файла;
  /// [onProgress] получает ход обеих фаз.
  Future<void> importFile(
    GraphImportFile file, {
    void Function(GraphReplacementProgress progress)? onProgress,
  }) async {
    final start = _container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptImport(
          (exclusive) => _import.importFile(
            file,
            exclusive,
            onProgress: onProgress ?? (_) {},
            cancellation: GraphReplacementCancellation(),
          ),
        );
    final outcome = await (start as GraphImportAccepted).future;
    if (outcome is! GraphImported) {
      throw StateError('Файл не импортирован: $outcome.');
    }
  }

  Future<void> dispose() async {
    await _container.read(graphCommandCoordinatorProvider.notifier).shutdown();
    _container.dispose();
    await _compaction.shutdown();
  }
}
