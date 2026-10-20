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

  /// Ожидание перед ответом на отмену копирования, как у канала плагина,
  /// ответ которого приходит не в том же кадре.
  Future<void> Function()? beforeCancellationAnswer;

  /// Отказ копирования вместо копии: [DocumentNotRead],
  /// [DocumentCopyStorageFull] или [DocumentCopyFailed].
  DocumentCopy? copyFailure;

  /// Сигнал сразу после отправки ответа копирования, до его обработки
  /// вызывающим: отмена может быть принята уже после ответа плагина.
  void Function()? afterCopyAnswer;

  /// Копирования документов в порядке начала. Каждое завершается, когда
  /// закончило работу с файлом приложения, в том числе брошенное отменой.
  final copies = <Future<void>>[];

  @override
  Future<DocumentOpening> openDocument() => openingDialog();

  /// Сигнал ответа порции до её обработки модулем формата.
  void Function()? afterPrefixAnswer;

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) => _FileDocumentRead(this, document, destination, cancellation);
}

/// Как плагин, сохраняет начало и продолжает тот же открытый поток.
final class _FileDocumentRead implements DocumentRead {
  _FileDocumentRead(
    this._documents,
    this._document,
    this._destination,
    Future<void> cancellation,
  ) {
    unawaited(
      cancellation.then((_) async {
        await _documents.beforeCancellationAnswer?.call();
        _cancelled = true;
        if (_copyOutcome case final outcome? when !outcome.isCompleted) {
          outcome.complete(const DocumentCopyCancelled());
        }
      }),
    );
  }

  final FileDocumentAccess _documents;
  final OpenedDocument _document;
  final File _destination;
  final _beginning = <List<int>>[];
  RandomAccessFile? _input;
  Completer<DocumentCopy>? _copyOutcome;
  var _cancelled = false;

  @override
  late final Stream<List<int>> prefix = _prefix();

  Stream<List<int>> _prefix() async* {
    try {
      if (_cancelled) throw DocumentReadFailure.cancelled;
      final input = _input = File.fromUri(Uri.parse(_document.uri)).openSync();
      var read = 0;
      while (read < documentPrefixByteLimit) {
        if (_cancelled) throw DocumentReadFailure.cancelled;
        final bytes = input.readSync(documentPrefixChunkSize);
        if (bytes.isEmpty) return;
        _beginning.add(bytes);
        read += bytes.length;
        _documents.afterPrefixAnswer?.call();
        yield bytes;
      }
    } on FileSystemException {
      throw DocumentReadFailure.unreadable;
    }
  }

  @override
  Future<DocumentCopy> copy() {
    final outcome = _copyOutcome = Completer<DocumentCopy>();
    _documents.copies.add(_copy(outcome));
    return outcome.future;
  }

  Future<void> _copy(Completer<DocumentCopy> outcome) async {
    try {
      await _documents.beforeCopy?.call();
      if (_cancelled) {
        if (!outcome.isCompleted) {
          outcome.complete(const DocumentCopyCancelled());
        }
        return;
      }
      if (_documents.copyFailure case final failure?) {
        outcome.complete(failure);
        _documents.afterCopyAnswer?.call();
        return;
      }
      final output = await _destination.open(mode: FileMode.write);
      try {
        for (final bytes in _beginning) {
          if (_cancelled) break;
          await output.writeFrom(bytes);
        }
        while (!_cancelled) {
          final bytes = await _input!.read(8192);
          if (bytes.isEmpty) break;
          if (!_cancelled) await output.writeFrom(bytes);
        }
      } finally {
        await output.close();
      }
      if (!outcome.isCompleted) {
        outcome.complete(
          _cancelled ? const DocumentCopyCancelled() : const DocumentCopied(),
        );
      }
    } finally {
      await _input?.close();
      if (_cancelled && await _destination.exists()) {
        await _destination.delete();
      }
    }
  }

  @override
  Future<void> finish() async {
    // Брошенное копирование владеет потоком до фактического завершения.
    if (_copyOutcome == null) await _input?.close();
  }
}
