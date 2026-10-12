import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticsSink', () {
    test('начало чтения состояний дней кодируется без данных запроса', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      sink.record(
        const DailyChoiceDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsStarted(),
        ),
      );

      expect(jsonDecode(messages.single), {
        'operation': 'dailyChoiceDayStatusesRead',
        'stage': 'read',
        'outcome': 'started',
      });
    });

    test('успех чтения состояний дней кодируется только с длительностью', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      sink.record(
        const DailyChoiceDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(Duration(microseconds: 1234)),
        ),
      );

      expect(jsonDecode(messages.single), {
        'operation': 'dailyChoiceDayStatusesRead',
        'stage': 'read',
        'outcome': 'succeeded',
        'durationMicros': 1234,
      });
    });

    test(
      'отказ чтения состояний дней кодируется только с безопасной категорией '
      'и длительностью',
      () {
        final messages = <String>[];
        final sink = DeveloperDiagnosticsSink(messages.add);

        sink.record(
          const DailyChoiceDayStatusesReadDiagnosticsEvent(
            status: DiagnosticsFailed(
              duration: Duration(microseconds: 5678),
              code: DiagnosticsFailureCode.corruption,
            ),
          ),
        );

        expect(jsonDecode(messages.single), {
          'operation': 'dailyChoiceDayStatusesRead',
          'stage': 'read',
          'outcome': 'failed',
          'durationMicros': 5678,
          'failureCode': 'corruption',
        });
      },
    );

    test('падающий писатель не повторяет диагностическое событие тега', () {
      var attempts = 0;
      final sink = DeveloperDiagnosticsSink((_) {
        attempts += 1;
        throw StateError('CANARY-личные-данные');
      });

      expect(
        () => sink.record(
          const TagDetailReadDiagnosticsEvent(
            stage: TagReadDiagnosticsStage.read,
            status: DiagnosticsFailed(
              duration: Duration(microseconds: 5),
              code: DiagnosticsFailureCode.notFound,
            ),
          ),
        ),
        returnsNormally,
      );
      expect(attempts, 1);
    });

    test(
      'защитная запись подавляет ошибку произвольного получателя без повтора',
      () {
        final sink = _ThrowingDiagnosticsSink();
        const event = BootstrapDiagnosticsEvent(
          schemaVersion: 1,
          status: DiagnosticsStarted(),
        );

        expect(() => recordDiagnosticsSafely(sink, event), returnsNormally);

        expect(sink.attemptedEvents, [same(event)]);
      },
    );
  });
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-diagnostics-sink-failure');
  }
}
