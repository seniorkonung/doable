import 'dart:async';
import 'dart:io';

import 'package:doable/src/data_transfer/application/document_access.dart';

/// Доступ к документам без системных диалогов: созданный документ — новый
/// файл каталога [_directory], в который копируется файл приложения, а
/// открытый документ — файл, который выбирает [openingDialog].
final class FileDocumentAccess implements DocumentAccess {
  FileDocumentAccess(this._directory);

  final Directory _directory;

  /// Имена по умолчанию открытых диалогов в порядке открытия.
  final suggestedNames = <String>[];

  /// Созданные документы в порядке создания.
  final created = <File>[];

  /// Ответ человека в открытом диалоге; по умолчанию он выбирает место
  /// нового документа [newDocument].
  late Future<DocumentCreation> Function() dialog = () async => newDocument();

  /// Задержка перед копированием файла в документ.
  Future<void> Function()? beforeWrite;

  /// Запись документа отказывает, как при отозванном доступе.
  var failsWrites = false;

  /// Адреса документов, работа с которыми завершена, в порядке завершения.
  final finished = <String>[];

  /// Создаёт пустой документ, как поставщик документов после выбора места.
  DocumentCreated newDocument() {
    final file = File.fromUri(
      _directory.uri.resolve('document-${created.length + 1}.jsonl.gz'),
    )..createSync();
    created.add(file);
    return DocumentCreated(CreatedDocument(file.uri.toString()));
  }

  @override
  Future<DocumentCreation> createDocument({required String suggestedName}) {
    suggestedNames.add(suggestedName);
    return dialog();
  }

  @override
  Future<DocumentWrite> writeDocument(
    CreatedDocument document, {
    required File source,
  }) async {
    await beforeWrite?.call();
    if (failsWrites) return const DocumentWriteFailed();
    await source.copy(File.fromUri(Uri.parse(document.uri)).path);
    return const DocumentWritten();
  }

  @override
  Future<void> finishDocument(
    CreatedDocument document, {
    required CreatedDocumentOutcome outcome,
  }) async {
    finished.add(document.uri);
    if (outcome == CreatedDocumentOutcome.failed) {
      await File.fromUri(Uri.parse(document.uri)).delete();
    }
  }

  /// Ответ человека в открытом диалоге выбора; по умолчанию он закрывает
  /// диалог, не выбрав документ.
  Future<DocumentOpening> Function() openingDialog = () async =>
      const DocumentOpeningCancelled();

  /// Выбор файла [file] в диалоге выбора.
  DocumentOpened chosen(File file) =>
      DocumentOpened(OpenedDocument(file.uri.toString()));

  /// Ожидание ответа поставщика на открытие документа перед копированием,
  /// как у облачного поставщика, который сначала загружает документ.
  Future<void> Function()? beforeCopy;

  /// Отказ копирования вместо копии: [DocumentNotRead],
  /// [DocumentCopyStorageFull] или [DocumentCopyFailed].
  DocumentCopy? copyFailure;

  @override
  Future<DocumentOpening> openDocument() => openingDialog();

  /// Как плагин, отмена сразу завершает копирование, а брошенное копирование
  /// копию не оставляет.
  @override
  Future<DocumentCopy> copyDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) {
    final outcome = Completer<DocumentCopy>();
    unawaited(
      cancellation.then((_) {
        if (!outcome.isCompleted)
          outcome.complete(const DocumentCopyCancelled());
      }),
    );
    unawaited(_copy(document, destination, outcome));
    return outcome.future;
  }

  Future<void> _copy(
    OpenedDocument document,
    File destination,
    Completer<DocumentCopy> outcome,
  ) async {
    await beforeCopy?.call();
    if (outcome.isCompleted) return;
    if (copyFailure case final failure?) {
      outcome.complete(failure);
      return;
    }
    await File.fromUri(Uri.parse(document.uri)).copy(destination.path);
    if (outcome.isCompleted) {
      await destination.delete();
    } else {
      outcome.complete(const DocumentCopied());
    }
  }
}
