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
    try {
      _write(jsonEncode(_encode(event)));
    } on Object {
      // Diagnostics остаётся best-effort: повторная запись здесь недопустима.
    }
  }

  static void _writeToDeveloperLog(String message) {
    developer.log(message, name: 'doable.diagnostics');
  }
}

Map<String, Object> _encode(DiagnosticsEvent event) => switch (event) {
  BootstrapDiagnosticsEvent(:final schemaVersion) => {
    'operation': 'bootstrap',
    ..._encodeStatus(event.status),
    'schemaVersion': ?schemaVersion,
  },
  MigrationDiagnosticsEvent(:final fromSchemaVersion, :final toSchemaVersion) =>
    {
      'operation': 'migration',
      ..._encodeStatus(event.status),
      'fromSchemaVersion': fromSchemaVersion,
      'toSchemaVersion': toSchemaVersion,
    },
  CatalogPageReadDiagnosticsEvent(:final pageSize) => {
    'operation': 'catalogPageRead',
    ..._encodeStatus(event.status),
    'pageSize': pageSize,
  },
  IntentionDetailReadDiagnosticsEvent() => {
    'operation': 'intentionDetailRead',
    ..._encodeStatus(event.status),
  },
  IntentionCommandDiagnosticsEvent(:final commandType) => {
    'operation': 'intentionCommand',
    ..._encodeStatus(event.status),
    'commandType': commandType.name,
  },
};

Map<String, Object> _encodeStatus(DiagnosticsStatus status) => switch (status) {
  DiagnosticsStarted() => {'outcome': 'started'},
  DiagnosticsSucceeded(:final duration) => {
    'outcome': 'succeeded',
    'durationMicros': duration.inMicroseconds,
  },
  DiagnosticsFailed(:final duration, :final code) => {
    'outcome': 'failed',
    'durationMicros': duration.inMicroseconds,
    'failureCode': code.name,
  },
};
