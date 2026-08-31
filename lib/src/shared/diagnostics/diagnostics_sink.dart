abstract interface class DiagnosticsSink {
  void record(DiagnosticsEvent event);
}

enum DiagnosticsOperation {
  bootstrap,
  migration,
  catalogPageRead,
  intentionDetailRead,
  intentionCommand,
}

enum DiagnosticsOutcome { started, succeeded, failed }

enum DiagnosticsFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
  incompatibleSchema,
  unexpected,
}

enum IntentionCommandDiagnosticsType {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

final class DiagnosticsEvent {
  DiagnosticsEvent.bootstrap({
    required DiagnosticsOutcome outcome,
    Duration? duration,
    DiagnosticsFailureCode? failureCode,
    int? schemaVersion,
  }) : this._(
         operation: DiagnosticsOperation.bootstrap,
         outcome: outcome,
         duration: duration,
         failureCode: failureCode,
         schemaVersion: schemaVersion,
       );

  DiagnosticsEvent.migration({
    required DiagnosticsOutcome outcome,
    Duration? duration,
    DiagnosticsFailureCode? failureCode,
    required int fromSchemaVersion,
    required int toSchemaVersion,
  }) : this._(
         operation: DiagnosticsOperation.migration,
         outcome: outcome,
         duration: duration,
         failureCode: failureCode,
         fromSchemaVersion: fromSchemaVersion,
         toSchemaVersion: toSchemaVersion,
       );

  DiagnosticsEvent.catalogPageRead({
    required DiagnosticsOutcome outcome,
    Duration? duration,
    DiagnosticsFailureCode? failureCode,
    required int pageSize,
  }) : this._(
         operation: DiagnosticsOperation.catalogPageRead,
         outcome: outcome,
         duration: duration,
         failureCode: failureCode,
         pageSize: pageSize,
       );

  DiagnosticsEvent.intentionDetailRead({
    required DiagnosticsOutcome outcome,
    Duration? duration,
    DiagnosticsFailureCode? failureCode,
  }) : this._(
         operation: DiagnosticsOperation.intentionDetailRead,
         outcome: outcome,
         duration: duration,
         failureCode: failureCode,
       );

  DiagnosticsEvent.intentionCommand({
    required IntentionCommandDiagnosticsType commandType,
    required DiagnosticsOutcome outcome,
    Duration? duration,
    DiagnosticsFailureCode? failureCode,
  }) : this._(
         operation: DiagnosticsOperation.intentionCommand,
         outcome: outcome,
         duration: duration,
         failureCode: failureCode,
         commandType: commandType,
       );

  DiagnosticsEvent._({
    required this.operation,
    required this.outcome,
    this.duration,
    this.failureCode,
    this.pageSize,
    this.commandType,
    this.schemaVersion,
    this.fromSchemaVersion,
    this.toSchemaVersion,
  }) {
    final validOutcomeData = outcome == DiagnosticsOutcome.started
        ? duration == null && failureCode == null
        : duration != null &&
              (outcome == DiagnosticsOutcome.failed
                  ? failureCode != null
                  : failureCode == null);
    if (!validOutcomeData || (duration?.isNegative ?? false)) {
      throw ArgumentError(
        'Недопустимое сочетание outcome, duration и failure.',
      );
    }
    if (pageSize != null && (pageSize! < 1 || pageSize! > 100)) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    if (schemaVersion != null && schemaVersion! < 0) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
    if (fromSchemaVersion != null && fromSchemaVersion! < 0) {
      throw ArgumentError.value(fromSchemaVersion, 'fromSchemaVersion');
    }
    if (toSchemaVersion != null && toSchemaVersion! < 0) {
      throw ArgumentError.value(toSchemaVersion, 'toSchemaVersion');
    }
  }

  final DiagnosticsOperation operation;
  final DiagnosticsOutcome outcome;
  final Duration? duration;
  final DiagnosticsFailureCode? failureCode;
  final int? pageSize;
  final IntentionCommandDiagnosticsType? commandType;
  final int? schemaVersion;
  final int? fromSchemaVersion;
  final int? toSchemaVersion;

  Map<String, Object> toStructuredData() {
    final data = <String, Object>{
      'operation': operation.name,
      'outcome': outcome.name,
    };
    if (duration != null) {
      data['durationMicros'] = duration!.inMicroseconds;
    }
    if (failureCode != null) {
      data['failureCode'] = failureCode!.name;
    }
    if (pageSize != null) {
      data['pageSize'] = pageSize!;
    }
    if (commandType != null) {
      data['commandType'] = commandType!.name;
    }
    if (schemaVersion != null) {
      data['schemaVersion'] = schemaVersion!;
    }
    if (fromSchemaVersion != null) {
      data['fromSchemaVersion'] = fromSchemaVersion!;
    }
    if (toSchemaVersion != null) {
      data['toSchemaVersion'] = toSchemaVersion!;
    }
    return Map.unmodifiable(data);
  }
}
