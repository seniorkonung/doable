import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../shared/diagnostics/diagnostics_sink.dart';
import 'quick_creation_mode.dart';
import 'quick_creation_mode_store.dart';

/// Настройка установки в отдельном файле, без обращения к личному графу.
/// Один экземпляр владеет очередью всех полных попыток записи.
final class FileQuickCreationModeStore implements QuickCreationModeStore {
  FileQuickCreationModeStore({
    required Directory localDataDirectory,
    required DiagnosticsSink diagnosticsSink,
  }) : this.withDirectoryProvider(
         localDataDirectoryProvider: () async => localDataDirectory,
         diagnosticsSink: diagnosticsSink,
       );

  /// Получает каталог внутри попытки чтения или записи: отказ платформы
  /// обрабатывается так же, как недоступность самого файла настройки.
  FileQuickCreationModeStore.withDirectoryProvider({
    required this._localDataDirectoryProvider,
    required this._diagnosticsSink,
  });

  final Future<Directory> Function() _localDataDirectoryProvider;
  final DiagnosticsSink _diagnosticsSink;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<QuickCreationMode> read() async {
    final stopwatch = Stopwatch()..start();
    try {
      final files = await _resolveFiles();
      final key = utf8.decode(await files.mode.readAsBytes());
      final mode = QuickCreationMode.fromStorageKey(key);
      if (mode != null) return mode;
      _recordFailure(
        QuickCreationModeDiagnosticsStage.read,
        DiagnosticsFailureCode.corruption,
        stopwatch.elapsed,
      );
    } on PathNotFoundException {
      // Отсутствие файла или его каталога — штатное состояние новой установки.
    } on Object catch (error) {
      _recordFailure(QuickCreationModeDiagnosticsStage.read, switch (error) {
        FormatException() => DiagnosticsFailureCode.corruption,
        FileSystemException() => DiagnosticsFailureCode.unavailable,
        _ => DiagnosticsFailureCode.unexpected,
      }, stopwatch.elapsed);
    }
    return QuickCreationMode.intention;
  }

  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) {
    // Постановка синхронна; callback удерживает значение именно этого выбора.
    final saving = _pendingWrite.then((_) => _write(mode));
    _pendingWrite = saving.then<void>((_) {});
    return saving;
  }

  Future<QuickCreationModeSaveResult> _write(QuickCreationMode mode) async {
    final stopwatch = Stopwatch()..start();
    File? ownedTemporaryFile;
    try {
      final files = await _resolveFiles();
      await files.settings.create(recursive: true);
      final temporaryFile = File('${files.mode.path}.${const Uuid().v4()}.tmp');
      await temporaryFile.create(exclusive: true);
      ownedTemporaryFile = temporaryFile;
      // flush завершает запись до замены; основной файл заранее не удаляется.
      // https://api.dart.dev/dart-io/File/writeAsString.html
      // https://api.dart.dev/dart-io/File/rename.html
      await temporaryFile.writeAsString(mode.storageKey, flush: true);
      await temporaryFile.rename(files.mode.path);
      ownedTemporaryFile = null;
      return const QuickCreationModeSaved();
    } on Object catch (error) {
      final code = error is FileSystemException
          ? DiagnosticsFailureCode.unavailable
          : DiagnosticsFailureCode.unexpected;
      _recordFailure(
        QuickCreationModeDiagnosticsStage.write,
        code,
        stopwatch.elapsed,
      );
      return QuickCreationModeSaveFailed(code);
    } finally {
      if (ownedTemporaryFile != null) {
        try {
          await ownedTemporaryFile.delete();
        } on Object {
          // Очистка не меняет исход попытки и не создаёт вторую диагностику.
          // Оставшийся файл не читается и не используется следующей попыткой.
        }
      }
    }
  }

  Future<({Directory settings, File mode})> _resolveFiles() async {
    final Directory localData;
    try {
      localData = await _localDataDirectoryProvider();
    } on Object {
      throw const FileSystemException(
        'Каталог настройки установки недоступен.',
      );
    }
    return (
      settings: Directory.fromUri(localData.uri.resolve('settings/')),
      mode: File.fromUri(localData.uri.resolve('settings/quick_creation_mode')),
    );
  }

  void _recordFailure(
    QuickCreationModeDiagnosticsStage stage,
    DiagnosticsFailureCode code,
    Duration duration,
  ) {
    recordDiagnosticsSafely(
      _diagnosticsSink,
      QuickCreationModeDiagnosticsEvent(
        stage: stage,
        status: DiagnosticsFailed(duration: duration, code: code),
      ),
    );
  }
}
