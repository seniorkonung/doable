import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../application/document_access.dart';

/// Доступ к документам через встроенный плагин Android
/// `DocumentAccessPlugin.kt`.
///
/// Плагин отвечает на создание и открытие документа его адресом или `null`
/// при отмене, а на копирование и завершение работы с документом — пустым
/// ответом. Отказ открыть диалог, записать документ или скопировать открытый
/// документ плагин передаёт ошибкой канала, которая здесь становится
/// типизированным отказом. Выбор файла с данными документа не даёт, а
/// отменённое копирование — копии, поэтому плагин тоже передаёт их ошибкой
/// канала со своим кодом.
///
/// Копирование открытого документа плагин различает по пути копии: по нему
/// отмена находит копирование.
final class MethodChannelDocumentAccess implements DocumentAccess {
  const MethodChannelDocumentAccess();

  static const _channel = MethodChannel(
    'software.doable.doable/document_access',
  );
  static const _existingFile = 'existing_file';
  static const _documentNotRead = 'document_not_read';
  static const _storageFull = 'storage_full';
  static const _copyCancelled = 'copy_cancelled';

  @override
  Future<DocumentCreation> createDocument({
    required String suggestedName,
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>('createDocument', {
        'name': suggestedName,
      });
      return uri == null
          ? const DocumentCreationCancelled()
          : DocumentCreated(CreatedDocument(uri));
    } on PlatformException catch (error) {
      return error.code == _existingFile
          ? const ExistingFileChosen()
          : const DocumentCreationFailed();
    }
  }

  @override
  Future<DocumentWrite> writeDocument(
    CreatedDocument document, {
    required File source,
  }) async {
    try {
      await _channel.invokeMethod<void>('writeDocument', {
        'source': source.path,
        'document': document.uri,
      });
      return const DocumentWritten();
    } on PlatformException {
      return const DocumentWriteFailed();
    }
  }

  @override
  Future<void> finishDocument(
    CreatedDocument document, {
    required CreatedDocumentOutcome outcome,
  }) async {
    try {
      await _channel.invokeMethod<void>('finishDocument', {
        'document': document.uri,
        'succeeded': outcome == CreatedDocumentOutcome.succeeded,
      });
    } on PlatformException {
      // Право, которое не удалось отпустить, плагин отпустит при следующем
      // запуске приложения.
    }
  }

  @override
  Future<DocumentOpening> openDocument() async {
    try {
      final uri = await _channel.invokeMethod<String>('openDocument');
      return uri == null
          ? const DocumentOpeningCancelled()
          : DocumentOpened(OpenedDocument(uri));
    } on PlatformException {
      return const DocumentOpeningFailed();
    }
  }

  @override
  Future<DocumentCopy> copyDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) async {
    // Отмена отправляется после вызова копирования, поэтому плагин получает
    // её, уже начав копирование.
    final copying = _channel.invokeMethod<void>('copyDocument', {
      'document': document.uri,
      'destination': destination.path,
    });
    unawaited(cancellation.then((_) => _cancelCopy(destination)));
    try {
      await copying;
      return const DocumentCopied();
    } on PlatformException catch (error) {
      return switch (error.code) {
        _documentNotRead => const DocumentNotRead(),
        _storageFull => const DocumentCopyStorageFull(),
        _copyCancelled => const DocumentCopyCancelled(),
        _ => const DocumentCopyFailed(),
      };
    }
  }

  Future<void> _cancelCopy(File destination) async {
    try {
      await _channel.invokeMethod<void>('cancelCopy', {
        'destination': destination.path,
      });
    } on PlatformException {
      // Неотменённое копирование завершится своим исходом.
    }
  }
}
