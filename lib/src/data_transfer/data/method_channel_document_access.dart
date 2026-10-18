import 'dart:io';

import 'package:flutter/services.dart';

import '../application/document_access.dart';

/// Доступ к документам через встроенный плагин Android
/// `DocumentAccessPlugin.kt`.
///
/// Плагин отвечает на создание документа его адресом или `null` при отмене,
/// а на копирование и завершение работы с документом — пустым ответом. Отказ
/// открыть диалог или записать документ плагин передаёт ошибкой канала,
/// которая здесь становится типизированным отказом.
final class MethodChannelDocumentAccess implements DocumentAccess {
  const MethodChannelDocumentAccess();

  static const _channel = MethodChannel(
    'software.doable.doable/document_access',
  );

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
    } on PlatformException {
      return const DocumentCreationFailed();
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
}
