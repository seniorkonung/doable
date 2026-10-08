import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/app/quick_creation/file_quick_creation_mode_store.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';

import '../app/quick_creation/controlled_mode_io.dart';

/// Отдельный процесс с настоящим файлом; stdin разрешает удержанную попытку.
Future<void> main(List<String> arguments) async {
  final directory = Directory(arguments[0]);
  final store = FileQuickCreationModeStore(
    localDataDirectory: directory,
    diagnosticsSink: _ReportingDiagnostics(arguments.contains('throw')),
  );
  if (arguments[1] == 'read') {
    _report({'mode': (await store.read()).storageKey});
    return;
  }

  final step = ModeWriteStep.values.byName(arguments[1]);
  final outcomes = arguments[2];
  final modes = arguments[3].split(',').map((key) {
    return QuickCreationMode.fromStorageKey(key) ??
        (throw StateError('Неизвестный режим рабочего процесса.'));
  }).toList();
  final attempts = [
    for (var i = 0; i < modes.length; i++)
      ModeWriteAttempt(holdAt: step, failAt: outcomes[i] == 'f' ? step : null),
  ];
  final io = ControlledModeIo(
    File.fromUri(directory.uri.resolve('settings/quick_creation_mode')),
    attempts,
  );
  final commands = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    await io.run(() async {
      final saves = [for (final mode in modes) store.save(mode)];
      for (var i = 0; i < attempts.length; i++) {
        final attempt = attempts[i];
        await attempt.held.future;
        _report({
          'held': i,
          'started': io.startedAttempts.length,
          'temporaryPath': attempt.temporaryPath,
        });
        if (!await commands.moveNext() || commands.current != 'release') {
          throw StateError('Не получено разрешение продолжить запись.');
        }
        attempt.release.complete();
        _report({
          'finished': i,
          'saved': await saves[i] is QuickCreationModeSaved,
          'committed': io.committedKeys,
        });
      }
    });
  } finally {
    await commands.cancel();
  }
}

void _report(Map<String, Object?> message) {
  stdout.writeln(jsonEncode({'pid': pid, ...message}));
}

final class _ReportingDiagnostics implements DiagnosticsSink {
  _ReportingDiagnostics(this.throwsAfterRecording);

  final bool throwsAfterRecording;

  @override
  void record(DiagnosticsEvent event) {
    DeveloperDiagnosticsSink((payload) {
      _report({'diagnostic': jsonDecode(payload)});
    }).record(event);
    if (throwsAfterRecording) throw StateError('Отказ получателя диагностики');
  }
}
