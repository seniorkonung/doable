import 'dart:async';
import 'dart:io';

import '../../data/local/sqlite_failure_classifier.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_format/graph_format_codec.dart';
import '../../graph_format/graph_format_file.dart';
import '../../graph_format/graph_format_records.dart';
import '../../graph_snapshots/graph_log_compaction.dart';
import '../../graph_snapshots/graph_snapshot_store.dart';
import 'document_access.dart';
import 'graph_replacement.dart';

/// Число попыток импорта в процессе. Каждая копирует документ в свой
/// временный файл, даже если импорт собран заново, а файлы прежних
/// процессов удаляет очистка временного каталога при запуске.
var _importAttempts = 0;

/// Импорт файла экспорта, который человек выбирает системным диалогом
/// выбора, атомарной заменой всего графа его содержимым (ADR-0036,
/// ADR-0037).
///
/// Выбранный документ копируется во временный файл приложения, и из копии
/// читается только заголовок: дата сохранения и количества записей, по
/// которым человек подтверждает замену. Импорт, принятый координатором,
/// проверяет записи файла, пишет их в снимок замены в отдельном изоляте —
/// команды графа в это время подтверждаются как обычно, — и заменяет граф
/// этим снимком в монопольном режиме координатора. Прежнее состояние
/// непустого графа транзакция замены сохраняет копией перед заменой.
final class GraphImport {
  GraphImport({
    required this._documents,
    required this._compaction,
    required this._replacement,
    required this._temporaryDirectory,
    required this._snapshotFiles,
  });

  final DocumentAccess _documents;

  /// Сжатие лога фактов, которое пишет снимок замены.
  final GraphLogCompaction _compaction;
  final GraphReplacement _replacement;

  /// Каталог временных файлов приложения. Он становится доступен, когда из
  /// него удалены файлы прежних запусков, поэтому их очистка не затрагивает
  /// временные файлы этого импорта.
  final Future<Directory> _temporaryDirectory;

  /// Завершается, когда из каталога снимков удалены незарегистрированные
  /// файлы прежних запусков. Снимок замены пишется только после этого, иначе
  /// очистка удалила бы его до регистрации.
  final Future<void> _snapshotFiles;

  /// Открывает системный диалог выбора файла, копирует выбранный документ
  /// во временный файл и читает его заголовок.
  ///
  /// [onDocumentChosen] вызывается, как только человек выбрал документ, до
  /// начала копирования. Завершение [cancellation] до исхода прекращает
  /// чтение: копирование завершается сразу, даже если поставщик документа
  /// держит его открытие или чтение, а уже скопированный файл удаляется.
  /// Каждая попытка копирует документ в свой временный файл, имя которого
  /// отличается и от временного файла экспорта, поэтому копирование,
  /// брошенное отменой и закончившееся позже, не затрагивает файлы следующих
  /// попыток.
  ///
  /// Отмена диалога и чтения — [GraphImportFileReadingCancelled]. Диалог,
  /// который не открылся, и отказы копирования и чтения заголовка —
  /// [GraphImportFileReadingFailed]. После отмены и отказа граф не меняется,
  /// а временного файла не остаётся: копию, брошенную отменой, удаляет само
  /// копирование, когда поставщик ответит.
  Future<GraphImportFileReading> readChosenFile({
    required void Function() onDocumentChosen,
    required Future<void> cancellation,
  }) async {
    final File copy;
    try {
      // Каталог создаётся до диалога: право чтения выбранного документа
      // отпускает только его копирование.
      final directory = await (await _temporaryDirectory).create(
        recursive: true,
      );
      copy = File.fromUri(
        directory.uri.resolve('graph_import_${++_importAttempts}.jsonl.gz'),
      );
    } on Object catch (error) {
      return GraphImportFileReadingFailed(_failureOf(error));
    }

    final OpenedDocument document;
    switch (await _documents.openDocument()) {
      case DocumentOpened(document: final opened):
        document = opened;
      case DocumentOpeningCancelled():
        return const GraphImportFileReadingCancelled();
      case DocumentOpeningFailed():
        return const GraphImportFileReadingFailed(GraphImportFailure.unknown);
    }
    onDocumentChosen();

    var isCancelled = false;
    unawaited(cancellation.then((_) => isCancelled = true));
    switch (await _documents.copyDocument(
      document,
      destination: copy,
      cancellation: cancellation,
    )) {
      case DocumentCopied():
        break;
      case DocumentCopyCancelled():
        return const GraphImportFileReadingCancelled();
      case DocumentNotRead():
        return const GraphImportFileReadingFailed(
          GraphImportFailure.documentUnreadable,
        );
      case DocumentCopyStorageFull():
        return const GraphImportFileReadingFailed(
          GraphImportFailure.storageFull,
        );
      case DocumentCopyFailed():
        return const GraphImportFileReadingFailed(GraphImportFailure.unknown);
    }

    try {
      final reading = await GraphFormatFile.read(copy.openRead());
      // Записи читает импорт, принятый координатором; отмена подписки
      // закрывает файл.
      await reading.records.listen(null).cancel();
      if (!isCancelled) {
        return GraphImportFileRead(GraphImportFile._(copy, reading.header));
      }
      await _deleteTemporaryFile(copy);
      return const GraphImportFileReadingCancelled();
    } on Object catch (error) {
      await _deleteTemporaryFile(copy);
      return GraphImportFileReadingFailed(_failureOf(error));
    }
  }

  /// Заменяет граф записями прочитанного файла [file]; саму замену выполняет
  /// [exclusive] импорта, принятого координатором.
  ///
  /// Записи файла читаются построчно, повышаются до текущей версии формата,
  /// проверяются предметными типами и сверяются с количествами заголовка, а
  /// затем пишутся в снимок замены. Транзакция замены проверяет их правилами
  /// схемы хранилища и общей проверкой пути дневного выбора. Временный файл
  /// удаляется, как только записан снимок замены или его запись прекращена.
  ///
  /// [onProgress] получает ход обеих фаз. Отмена, принятая [cancellation],
  /// прекращает запись снимка замены между записями, а замену — между
  /// пакетами операторов, откатывая её транзакцию, и даёт
  /// [GraphImportCancelled]. После точки невозврата замены [cancellation]
  /// отмену не принимает, и импорт завершается так же, как без неё. После
  /// отказа и отмены граф, копии, лог и реестр снимков остаются прежними, а
  /// файл снимка замены удаляется.
  Future<GraphImportOutcome> importFile(
    GraphImportFile file,
    GraphExclusiveReplacement<GraphImported> exclusive, {
    required void Function(GraphReplacementProgress progress) onProgress,
    required GraphReplacementCancellation cancellation,
  }) async {
    UnregisteredGraphSnapshot? snapshot;
    try {
      final written = await _writeSnapshot(
        file,
        onProgress: (share) => onProgress(
          GraphReplacementProgress(GraphReplacementPhase.snapshotWrite, share),
        ),
        cancelled: cancellation.requested,
      );
      snapshot = written;
      return await exclusive.replace(() {
        onProgress(
          const GraphReplacementProgress(GraphReplacementPhase.replacement, 0),
        );
        return _replacement.replaceGraph(
          written,
          onProgress: (share) => onProgress(
            GraphReplacementProgress(GraphReplacementPhase.replacement, share),
          ),
          cancellation: cancellation,
        );
      });
    } on GraphReplacementSnapshotCancelled {
      // Запись снимка замены при отмене удаляет свой файл.
      return const GraphImportCancelled();
    } on GraphReplacementCancelled {
      await snapshot?.delete();
      return const GraphImportCancelled();
    } on Object catch (error) {
      await snapshot?.delete();
      return GraphImportFailed(_failureOf(error));
    }
  }

  Future<UnregisteredGraphSnapshot> _writeSnapshot(
    GraphImportFile file, {
    required void Function(double share) onProgress,
    required Future<void> cancelled,
  }) async {
    try {
      await _snapshotFiles;
      return await _compaction.writeReplacementSnapshotOfFile(
        file._copy,
        onProgress: onProgress,
        cancelled: cancelled,
      );
    } finally {
      await file.discard();
    }
  }
}

/// Копия выбранного документа во временном файле приложения с прочитанным
/// заголовком. Её один раз импортирует [GraphImport.importFile] или
/// отбрасывает [discard].
final class GraphImportFile {
  const GraphImportFile._(this._copy, this.header);

  final File _copy;

  /// Заголовок файла: дата сохранения и количества записей каждого вида.
  /// Записи файла с ними ещё не сверены.
  final GraphFormatHeader header;

  /// Удаляет временный файл, например когда человек отказался от импорта.
  Future<void> discard() => _deleteTemporaryFile(_copy);
}

Future<void> _deleteTemporaryFile(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Файла нет, или его удалит очистка временного каталога при запуске.
  }
}

/// Исход чтения файла, выбранного для импорта.
sealed class GraphImportFileReading {
  const GraphImportFileReading();
}

/// Документ скопирован во временный файл, а заголовок прочитан.
final class GraphImportFileRead extends GraphImportFileReading {
  const GraphImportFileRead(this.file);

  final GraphImportFile file;
}

/// Человек не выбрал документ или отменил чтение; отказом это не считается.
final class GraphImportFileReadingCancelled extends GraphImportFileReading {
  const GraphImportFileReadingCancelled();
}

/// Файл не прочитан, и импорт не удался.
final class GraphImportFileReadingFailed extends GraphImportFileReading {
  const GraphImportFileReadingFailed(this.failure);

  final GraphImportFailure failure;
}

/// Категория отказа импорта [error] на любом шаге.
///
/// Нарушение правил данных графа обнаруживают чтение файла формата, схема
/// хранилища и проверка записей в транзакции замены, а нехватку места —
/// SQLite и файловая система.
GraphImportFailure _failureOf(Object error) => switch (error) {
  GraphFormatCorruption() ||
  GraphReplacementRecordsRejected() => GraphImportFailure.invalidFile,
  GraphFormatVersionTooNew() => GraphImportFailure.newerFormatVersion,
  _ => switch (classifySqliteFailure(error)) {
    SqliteStorageFullFailure() => GraphImportFailure.storageFull,
    SqliteConstraintFailure() => GraphImportFailure.invalidFile,
    SqliteCorruptionFailure() ||
    SqliteUnavailableFailure() ||
    SqliteUnexpectedFailure() => GraphImportFailure.unknown,
  },
};
