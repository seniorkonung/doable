import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('DiagnosticsSink', () {
    test('сохраняет закрытые типизированные события без telemetry', () {
      final sink = InMemoryDiagnosticsSink();

      for (final event in _events()) {
        sink.record(event);
      }

      expect(sink.events.map((event) => event.runtimeType), [
        BootstrapDiagnosticsEvent,
        MigrationDiagnosticsEvent,
        CatalogPageReadDiagnosticsEvent,
        IntentionDetailReadDiagnosticsEvent,
        IntentionCommandDiagnosticsEvent,
      ]);
      expect(sink.events[0].status, isA<DiagnosticsStarted>());
      expect(sink.events[1].status, isA<DiagnosticsSucceeded>());
      expect(sink.events[3].status, isA<DiagnosticsFailed>());
    });

    test('production adapter записывает только allowlist полей', () {
      const titleCanary = 'CANARY-title-личное-намерение';
      const descriptionCanary = 'CANARY-description-секретный-текст';
      const idCanary = 'c0ffee00-cafe-4bad-8ace-0123456789ab';
      const cursorCanary = 'CANARY-cursor-boundary';
      const sqlCanary = 'CANARY-SQL-PARAMETER';
      const exceptionCanary = 'CANARY-database-exception';
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      for (final event in _events()) {
        sink.record(event);
      }

      expect(messages.map(jsonDecode), [
        {'operation': 'bootstrap', 'outcome': 'started', 'schemaVersion': 1},
        {
          'operation': 'migration',
          'outcome': 'succeeded',
          'durationMicros': 24000,
          'fromSchemaVersion': 1,
          'toSchemaVersion': 2,
        },
        {
          'operation': 'catalogPageRead',
          'outcome': 'succeeded',
          'durationMicros': 8000,
          'pageSize': 100,
        },
        {
          'operation': 'intentionDetailRead',
          'outcome': 'failed',
          'durationMicros': 3000,
          'failureCode': 'unavailable',
        },
        {
          'operation': 'intentionCommand',
          'outcome': 'failed',
          'durationMicros': 12000,
          'failureCode': 'conflict',
          'commandType': 'archive',
        },
      ]);
      for (final canary in [
        titleCanary,
        descriptionCanary,
        idCanary,
        cursorCanary,
        sqlCanary,
        exceptionCanary,
      ]) {
        expect(messages.join(), isNot(contains(canary)));
      }
    });

    test('production adapter подавляет ошибки writer для каждого события без повторной записи', () {
      var writeAttempts = 0;
      final sink = DeveloperDiagnosticsSink((_) {
        writeAttempts += 1;
        throw StateError('CANARY-diagnostics-writer-failure');
      });

      for (final event in _events()) {
        expect(() => sink.record(event), returnsNormally);
      }

      expect(writeAttempts, _events().length);
    });
  });
}

List<DiagnosticsEvent> _events() => [
  const BootstrapDiagnosticsEvent(
    schemaVersion: 1,
    status: DiagnosticsStarted(),
  ),
  const MigrationDiagnosticsEvent(
    fromSchemaVersion: 1,
    toSchemaVersion: 2,
    status: DiagnosticsSucceeded(Duration(milliseconds: 24)),
  ),
  const CatalogPageReadDiagnosticsEvent(
    pageSize: 100,
    status: DiagnosticsSucceeded(Duration(milliseconds: 8)),
  ),
  const IntentionDetailReadDiagnosticsEvent(
    status: DiagnosticsFailed(
      duration: Duration(milliseconds: 3),
      code: DiagnosticsFailureCode.unavailable,
    ),
  ),
  const IntentionCommandDiagnosticsEvent(
    commandType: IntentionCommandDiagnosticsType.archive,
    status: DiagnosticsFailed(
      duration: Duration(milliseconds: 12),
      code: DiagnosticsFailureCode.conflict,
    ),
  ),
];
