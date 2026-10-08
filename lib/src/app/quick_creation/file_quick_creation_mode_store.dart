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
    required this._diagnosticsSink,
  }) : _settingsDirectory = Directory.fromUri(
         localDataDirectory.uri.resolve('settings/'),
       ),
       _modeFile = File.fromUri(
         localDataDirectory.uri.resolve('settings/quick_creation_mode'),
       );

  final Directory _settingsDirectory;
  final File _modeFile;
  final DiagnosticsSink _diagnosticsSink;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<QuickCreationMode> read() async {
    final stopwatch = Stopwatch()..start();
    try {
      final key = utf8.decode(await _modeFile.readAsBytes());
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
      await _settingsDirectory.create(recursive: true);
      final temporaryFile = File('${_modeFile.path}.${const Uuid().v4()}.tmp');
      await temporaryFile.create(exclusive: true);
      ownedTemporaryFile = temporaryFile;
      // flush завершает запись до замены; основной файл заранее не удаляется.
      // https://api.dart.dev/dart-io/File/writeAsString.html
      // https://api.dart.dev/dart-io/File/rename.html
      await temporaryFile.writeAsString(mode.storageKey, flush: true);
      await temporaryFile.rename(_modeFile.path);
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
