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
  TagCommandDiagnosticsEvent(:final commandType, :final stage) => {
    'operation': 'tagCommand',
    'commandType': commandType.name,
    'stage': stage.name,
    ..._encodeStatus(event.status),
  },
  TagCatalogPageReadDiagnosticsEvent(:final stage) => {
    'operation': 'tagCatalogPageRead',
    'stage': stage.name,
    ..._encodeStatus(event.status),
  },
  TagDetailReadDiagnosticsEvent(:final stage) => {
    'operation': 'tagDetailRead',
    'stage': stage.name,
    ..._encodeStatus(event.status),
  },
  DailyChoiceReadDiagnosticsEvent() => {
    'operation': 'dailyChoiceDetailRead',
    'stage': 'read',
    ..._encodeStatus(event.status),
  },
  ChoicePathSuggestionReadDiagnosticsEvent(:final stage) => {
    'operation': 'choicePathSuggestionRead',
    'stage': stage.name,
    ..._encodeStatus(event.status),
  },
  DailyChoiceCatalogPageReadDiagnosticsEvent(
    :final pageSize,
    :final isContinuation,
  ) =>
    {
      'operation': 'dailyChoiceCatalogPageRead',
      'stage': 'read',
      'pageSize': pageSize,
      'isContinuation': isContinuation,
      ..._encodeStatus(event.status),
    },
  ChoicePathContinuationReadDiagnosticsEvent(
    :final stage,
    :final pageSize,
    :final isContinuation,
  ) =>
    {
      'operation': 'choicePathContinuationRead',
      'stage': stage.name,
      ..._encodeStatus(event.status),
      'pageSize': pageSize,
      'isContinuation': isContinuation,
    },
  DailyChoicePathValidationDiagnosticsEvent(:final commandType) => {
    'operation': 'dailyChoicePathValidation',
    'commandType': commandType.name,
    'stage': 'validation',
    ..._encodeStatus(event.status),
  },
  DailyChoiceCommandDiagnosticsEvent(:final commandType, :final stage) => {
    'operation': 'dailyChoiceCommand',
    'commandType': commandType.name,
    'stage': stage.name,
    ..._encodeStatus(event.status),
  },
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
  RelationCountsReadDiagnosticsEvent() => {
    'operation': 'relationCountsRead',
    ..._encodeStatus(event.status),
  },
  RelationGroupPageReadDiagnosticsEvent(
    :final pageSize,
    :final isContinuation,
    :final requiresNewSnapshot,
  ) =>
    {
      'operation': 'relationGroupPageRead',
      'stage': 'read',
      ..._encodeStatus(event.status),
      'pageSize': pageSize,
      'isContinuation': isContinuation,
      'requiresNewSnapshot': requiresNewSnapshot,
    },
  DailyChoiceGroupPageReadDiagnosticsEvent(
    :final pageSize,
    :final isContinuation,
    :final requiresNewSnapshot,
  ) =>
    {
      'operation': 'dailyChoiceGroupPageRead',
      'stage': 'read',
      ..._encodeStatus(event.status),
      'pageSize': pageSize,
      'isContinuation': isContinuation,
      'requiresNewSnapshot': requiresNewSnapshot,
    },
  LongTermRelationDetailReadDiagnosticsEvent() => {
    'operation': 'longTermRelationDetailRead',
    ..._encodeStatus(event.status),
  },
  SelectedRelationsReadDiagnosticsEvent() => {
    'operation': 'selectedRelationsRead',
    ..._encodeStatus(event.status),
  },
  IntentionCommandDiagnosticsEvent(:final commandType) => {
    'operation': 'intentionCommand',
    ..._encodeStatus(event.status),
    'commandType': commandType.name,
  },
  LongTermRelationCommandDiagnosticsEvent(:final commandType) => {
    'operation': 'longTermRelationCommand',
    ..._encodeStatus(event.status),
    'commandType': commandType.name,
  },
  BlockingRelationsDeleteDiagnosticsEvent() => {
    'operation': 'blockingRelationsDelete',
    ..._encodeStatus(event.status),
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
