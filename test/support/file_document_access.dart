import 'dart:io';

import 'package:doable/src/data_transfer/application/document_access.dart';

/// Доступ к документам без системных диалогов: документ — новый файл
/// каталога [_directory], в который копируется файл приложения.
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
}
