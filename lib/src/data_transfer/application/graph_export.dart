import 'dart:io';

import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_snapshots/graph_log_compaction.dart';
import '../../graph_snapshots/graph_snapshot_store.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import 'document_access.dart';

/// Имя временного файла экспорта. Координатор принимает не больше одного
/// экспорта одновременно, поэтому имя не меняется.
const _temporaryFileName = 'graph_export.jsonl.gz';

/// Экспорт всего графа в документ, который человек выбирает системным
/// диалогом сохранения (ADR-0037).
///
/// Состояние графа на текущей позиции пишется в отдельном изоляте во
/// временный файл, который затем копируется в документ. База получает от
/// записи только короткие операции лога, поэтому команды графа
/// подтверждаются и во время экспорта.
///
/// Исход экспорта сообщается в [DiagnosticsSink]; отказ диагностики исход
/// экспорта не меняет.
final class GraphExport {
  GraphExport({
    required this._documents,
    required this._compaction,
    required this._temporaryDirectory,
    required this._clock,
    required this._diagnosticsSink,
  });

  final DocumentAccess _documents;

  /// Сжатие лога фактов, которое ведёт отметки чтения истории и пересборку
  /// повреждённого снимка.
  final GraphLogCompaction _compaction;

  /// Каталог временных файлов приложения.
  final Directory _temporaryDirectory;
  final DateTime Function() _clock;
  final DiagnosticsSink _diagnosticsSink;

  /// Открывает системный диалог сохранения с именем документа по умолчанию
  /// `Doable <местная дата>.jsonl.gz`.
  ///
  /// Диалог, который не открылся, диагностируется отказом экспорта; отмена
  /// диалога события не даёт.
  Future<DocumentCreation> chooseDocument() async {
    final stopwatch = Stopwatch()..start();
    final creation = await _documents.createDocument(
      suggestedName: _documentName(_clock()),
    );
    if (creation case DocumentCreationFailed()) {
      _recordFailure(
        GraphExportDiagnosticsStage.documentCreation,
        stopwatch,
        DiagnosticsFailureCode.unavailable,
      );
    }
    return creation;
  }

  /// Пишет в документ [document] состояние графа на текущей позиции с
  /// моментом экспорта в заголовке; [onProgress] получает долю записанных
  /// записей.
  ///
  /// Отказ записи документа — [GraphExportOutcome.failed], отказ записи
  /// состояния — исключение [GraphLogCompaction.writeCurrentState].
  /// Временный файл удаляется при любом исходе.
  Future<GraphExportOutcome> write(
    CreatedDocument document, {
    required void Function(double share) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final file = File.fromUri(
      _temporaryDirectory.uri.resolve(_temporaryFileName),
    );
    try {
      await _writeTemporaryFile(file, stopwatch, onProgress: onProgress);
      switch (await _documents.writeDocument(document, source: file)) {
        case DocumentWritten():
          recordDiagnosticsSafely(
            _diagnosticsSink,
            GraphExportDiagnosticsEvent.succeeded(duration: stopwatch.elapsed),
          );
          return GraphExportOutcome.succeeded;
        case DocumentWriteFailed():
          _recordFailure(
            GraphExportDiagnosticsStage.documentWrite,
            stopwatch,
            DiagnosticsFailureCode.unavailable,
          );
          return GraphExportOutcome.failed;
      }
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Файла нет: при отказе его удалила запись состояния. Иначе файл
        // удалит очистка временного каталога при запуске.
      }
    }
  }

  /// Пишет состояние графа на текущей позиции во временный файл [file].
  /// Запись состояния — операция модуля снимков, поэтому её отказ
  /// классифицируется так же, как отказы снимков.
  Future<void> _writeTemporaryFile(
    File file,
    Stopwatch stopwatch, {
    required void Function(double share) onProgress,
  }) async {
    try {
      await _temporaryDirectory.create(recursive: true);
      await _compaction.writeCurrentState(
        file,
        writtenAt: _clock(),
        onProgress: onProgress,
      );
    } on Object catch (error) {
      _recordFailure(
        GraphExportDiagnosticsStage.temporaryFileWrite,
        stopwatch,
        graphSnapshotFailureCode(error),
      );
      rethrow;
    }
  }

  void _recordFailure(
    GraphExportDiagnosticsStage stage,
    Stopwatch stopwatch,
    DiagnosticsFailureCode code,
  ) => recordDiagnosticsSafely(
    _diagnosticsSink,
    GraphExportDiagnosticsEvent.failed(
      stage: stage,
      duration: stopwatch.elapsed,
      code: code,
    ),
  );
}

/// Дата записывается по ISO 8601 независимо от языка интерфейса, поэтому
/// в имени нет знаков, недопустимых в именах файлов.
String _documentName(DateTime moment) {
  final local = moment.toLocal();
  final date = CalendarDate.fromParts(local.year, local.month, local.day);
  return 'Doable ${date.toCanonicalString()}.jsonl.gz';
}
