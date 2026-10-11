import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticsSink', () {
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

    test('отметка избранного и её снятие кодируются видом команды намерения '
        'с этапом и безопасной категорией', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      for (final event in const [
        IntentionCommandDiagnosticsEvent.markFavorite(
          stage: FavoriteMarkCommandDiagnosticsStage.write,
          status: DiagnosticsSucceeded(Duration(milliseconds: 2)),
        ),
        IntentionCommandDiagnosticsEvent.unmarkFavorite(
          stage: FavoriteMarkCommandDiagnosticsStage.validation,
          status: DiagnosticsFailed(
            duration: Duration(milliseconds: 3),
            code: DiagnosticsFailureCode.notFound,
          ),
        ),
        IntentionCommandDiagnosticsEvent.markFavorite(
          stage: FavoriteMarkCommandDiagnosticsStage.write,
          status: DiagnosticsFailed(
            duration: Duration(milliseconds: 4),
            code: DiagnosticsFailureCode.unavailable,
          ),
        ),
      ]) {
        sink.record(event);
      }

      expect(messages.map(jsonDecode), [
        {
          'operation': 'intentionCommand',
          'stage': 'write',
          'outcome': 'succeeded',
          'durationMicros': 2000,
          'commandType': 'markFavorite',
        },
        {
          'operation': 'intentionCommand',
          'stage': 'validation',
          'outcome': 'failed',
          'durationMicros': 3000,
          'failureCode': 'notFound',
          'commandType': 'unmarkFavorite',
        },
        {
          'operation': 'intentionCommand',
          'stage': 'write',
          'outcome': 'failed',
          'durationMicros': 4000,
          'failureCode': 'unavailable',
          'commandType': 'markFavorite',
        },
      ]);
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
