import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
/// Сессию чтения плагин различает по пути копии: по нему отмена находит
/// чтение начала, ожидание решения и копирование.
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
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) => _MethodChannelDocumentRead(document, destination, cancellation);
}

final class _MethodChannelDocumentRead implements DocumentRead {
  _MethodChannelDocumentRead(
    OpenedDocument document,
    File destination,
    Future<void> cancellation,
  ) : _arguments = {'destination': destination.path} {
    _started = _channel.invokeMethod<void>('beginDocumentRead', {
      ..._arguments,
      'document': document.uri,
      'prefixLimit': documentPrefixByteLimit,
      'chunkSize': documentPrefixChunkSize,
    });
    unawaited(cancellation.then((_) => _cancel()));
  }

  static const _channel = MethodChannelDocumentAccess._channel;
  final Map<String, String> _arguments;
  late final Future<void> _started;
  var _finished = false;

  @override
  late final Stream<List<int>> prefix = _prefix();

  Stream<List<int>> _prefix() async* {
    try {
      await _started;
      var read = 0;
      while (read < documentPrefixByteLimit) {
        final bytes = await _channel.invokeMethod<Uint8List>(
          'readDocumentPrefix',
          _arguments,
        );
        if (bytes == null) throw DocumentReadFailure.unknown;
        if (bytes.isEmpty) return;
        read += bytes.length;
        yield bytes;
      }
    } on PlatformException catch (error) {
      throw switch (error.code) {
        MethodChannelDocumentAccess._copyCancelled =>
          DocumentReadFailure.cancelled,
        MethodChannelDocumentAccess._documentNotRead =>
          DocumentReadFailure.unreadable,
        _ => DocumentReadFailure.unknown,
      };
    }
  }

  @override
  Future<DocumentCopy> copy() async {
    try {
      await _started;
      await _channel.invokeMethod<void>('copyReadDocument', _arguments);
      return const DocumentCopied();
    } on PlatformException catch (error) {
      return switch (error.code) {
        MethodChannelDocumentAccess._documentNotRead => const DocumentNotRead(),
        MethodChannelDocumentAccess._storageFull =>
          const DocumentCopyStorageFull(),
        MethodChannelDocumentAccess._copyCancelled =>
          const DocumentCopyCancelled(),
        _ => const DocumentCopyFailed(),
      };
    } finally {
      _finished = true;
    }
  }

  @override
  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    try {
      await _channel.invokeMethod<void>('finishDocumentRead', _arguments);
    } on PlatformException {
      // Завершённая или отменённая сессия уже освобождает свои ресурсы.
    }
  }

  Future<void> _cancel() async {
    if (_finished) return;
    try {
      await _channel.invokeMethod<void>('cancelCopy', _arguments);
    } on PlatformException {
      // Неотменённое чтение завершится своим исходом.
    }
  }
}
