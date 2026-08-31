import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('DiagnosticsSink', () {
    test('сохраняет проверяемые структурированные события без telemetry', () {
      final sink = InMemoryDiagnosticsSink();

      sink.record(
        DiagnosticsEvent.bootstrap(
          outcome: DiagnosticsOutcome.started,
          schemaVersion: 1,
        ),
      );
      sink.record(
        DiagnosticsEvent.migration(
          outcome: DiagnosticsOutcome.succeeded,
          duration: Duration(milliseconds: 24),
          fromSchemaVersion: 1,
          toSchemaVersion: 2,
        ),
      );
      sink.record(
        DiagnosticsEvent.catalogPageRead(
          outcome: DiagnosticsOutcome.succeeded,
          duration: Duration(milliseconds: 8),
          pageSize: 100,
        ),
      );
      sink.record(
        DiagnosticsEvent.intentionDetailRead(
          outcome: DiagnosticsOutcome.failed,
          duration: Duration(milliseconds: 3),
          failureCode: DiagnosticsFailureCode.unavailable,
        ),
      );
      sink.record(
        DiagnosticsEvent.intentionCommand(
          commandType: IntentionCommandDiagnosticsType.archive,
          outcome: DiagnosticsOutcome.failed,
          duration: Duration(milliseconds: 12),
          failureCode: DiagnosticsFailureCode.conflict,
        ),
      );

      expect(sink.events.map((event) => event.operation), [
        DiagnosticsOperation.bootstrap,
        DiagnosticsOperation.migration,
        DiagnosticsOperation.catalogPageRead,
        DiagnosticsOperation.intentionDetailRead,
        DiagnosticsOperation.intentionCommand,
      ]);
      expect(sink.events[1].toStructuredData(), {
        'operation': 'migration',
        'outcome': 'succeeded',
        'durationMicros': 24000,
        'fromSchemaVersion': 1,
        'toSchemaVersion': 2,
      });
      expect(sink.events[2].toStructuredData()['pageSize'], 100);
      expect(sink.events[3].toStructuredData()['failureCode'], 'unavailable');
      expect(sink.events[4].toStructuredData()['commandType'], 'archive');
    });

    test('production adapter не записывает canary пользовательских данных', () {
      const titleCanary = 'CANARY-title-личное-намерение';
      const descriptionCanary = 'CANARY-description-секретный-текст';
      const idCanary = 'c0ffee00-cafe-4bad-8ace-0123456789ab';
      const cursorCanary = 'CANARY-cursor-boundary';
      const sqlCanary = 'CANARY-SQL-PARAMETER';
      const exceptionCanary = 'CANARY-database-exception';
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      sink.record(
        DiagnosticsEvent.intentionCommand(
          commandType: IntentionCommandDiagnosticsType.create,
          outcome: DiagnosticsOutcome.failed,
          duration: Duration(milliseconds: 7),
          failureCode: DiagnosticsFailureCode.validation,
        ),
      );

      expect(messages, hasLength(1));
      expect(jsonDecode(messages.single), {
        'operation': 'intentionCommand',
        'outcome': 'failed',
        'durationMicros': 7000,
        'failureCode': 'validation',
        'commandType': 'create',
      });
      for (final canary in [
        titleCanary,
        descriptionCanary,
        idCanary,
        cursorCanary,
        sqlCanary,
        exceptionCanary,
      ]) {
        expect(messages.single, isNot(contains(canary)));
      }
    });
  });
}
