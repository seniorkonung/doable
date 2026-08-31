import 'dart:convert';
import 'dart:developer' as developer;

import 'diagnostics_sink.dart';

typedef DiagnosticsLogWriter = void Function(String message);

final class DeveloperDiagnosticsSink implements DiagnosticsSink {
  DeveloperDiagnosticsSink([DiagnosticsLogWriter? write])
    : _write = write ?? _writeToDeveloperLog;

  final DiagnosticsLogWriter _write;

  @override
  void record(DiagnosticsEvent event) {
    _write(jsonEncode(event.toStructuredData()));
  }

  static void _writeToDeveloperLog(String message) {
    developer.log(message, name: 'doable.diagnostics');
  }
}
