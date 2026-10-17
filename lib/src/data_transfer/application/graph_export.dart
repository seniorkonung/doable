import 'dart:io';

import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_snapshots/graph_log_compaction.dart';
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
final class GraphExport {
  GraphExport({
    required this._documents,
    required this._compaction,
    required this._temporaryDirectory,
    required this._clock,
  });

  final DocumentAccess _documents;

  /// Сжатие лога фактов, которое ведёт отметки чтения истории и пересборку
  /// повреждённого снимка.
  final GraphLogCompaction _compaction;

  /// Каталог временных файлов приложения.
  final Directory _temporaryDirectory;
  final DateTime Function() _clock;

  /// Открывает системный диалог сохранения с именем документа по умолчанию
  /// `Doable <местная дата>.jsonl.gz`.
  Future<DocumentCreation> chooseDocument() =>
      _documents.createDocument(suggestedName: _documentName(_clock()));

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
    final file = File.fromUri(
      _temporaryDirectory.uri.resolve(_temporaryFileName),
    );
    try {
      await _temporaryDirectory.create(recursive: true);
      await _compaction.writeCurrentState(
        file,
        writtenAt: _clock(),
        onProgress: onProgress,
      );
      return switch (await _documents.writeDocument(document, source: file)) {
        DocumentWritten() => GraphExportOutcome.succeeded,
        DocumentWriteFailed() => GraphExportOutcome.failed,
      };
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Файла нет: при отказе его удалила запись состояния. Иначе файл
        // удалит очистка временного каталога при запуске.
      }
    }
  }
}

/// Дата записывается по ISO 8601 независимо от языка интерфейса, поэтому
/// в имени нет знаков, недопустимых в именах файлов.
String _documentName(DateTime moment) {
  final local = moment.toLocal();
  final date = CalendarDate.fromParts(local.year, local.month, local.day);
  return 'Doable ${date.toCanonicalString()}.jsonl.gz';
}
