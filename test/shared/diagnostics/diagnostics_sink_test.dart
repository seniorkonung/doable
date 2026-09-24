import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('DiagnosticsSink', () {
    test('событие продолжений кодирует только безопасные поля', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);
      sink.record(
        const ChoicePathContinuationReadDiagnosticsEvent(
          pageSize: 50,
          isContinuation: true,
          status: DiagnosticsFailed(
            duration: Duration(milliseconds: 4),
            code: DiagnosticsFailureCode.conflict,
          ),
        ),
      );
      expect(messages.map(jsonDecode), [
        {
          'operation': 'choicePathContinuationRead',
          'stage': 'read',
          'outcome': 'failed',
          'durationMicros': 4000,
          'failureCode': 'conflict',
          'pageSize': 50,
          'isContinuation': true,
        },
      ]);
    });

    test(
      'дневные события различают чтение, проверку, запись и чтение результата',
      () {
        final messages = <String>[];
        final sink = DeveloperDiagnosticsSink(messages.add);
        final events = <DiagnosticsEvent>[
          const DailyChoiceReadDiagnosticsEvent(
            status: DiagnosticsSucceeded(Duration(milliseconds: 2)),
          ),
          const DailyChoiceCatalogPageReadDiagnosticsEvent(
            pageSize: 50,
            isContinuation: true,
            status: DiagnosticsFailed(
              duration: Duration(milliseconds: 1),
              code: DiagnosticsFailureCode.corruption,
            ),
          ),
          const DailyChoiceGroupPageReadDiagnosticsEvent(
            pageSize: 50,
            isContinuation: false,
            requiresNewSnapshot: false,
            status: DiagnosticsSucceeded(Duration(milliseconds: 2)),
          ),
          const DailyChoicePathValidationDiagnosticsEvent(
            commandType: DailyChoicePathCommandDiagnosticsType.create,
            status: DiagnosticsFailed(
              duration: Duration(milliseconds: 3),
              code: DiagnosticsFailureCode.conflict,
            ),
          ),
          const DailyChoiceCommandDiagnosticsEvent(
            commandType: DailyChoiceCommandDiagnosticsType.updateFields,
            stage: DailyChoiceCommandDiagnosticsStage.write,
            status: DiagnosticsFailed(
              duration: Duration(milliseconds: 5),
              code: DiagnosticsFailureCode.unexpected,
            ),
          ),
          const DailyChoiceCommandDiagnosticsEvent(
            commandType: DailyChoiceCommandDiagnosticsType.replacePath,
            stage: DailyChoiceCommandDiagnosticsStage.resultRead,
            status: DiagnosticsSucceeded(Duration(milliseconds: 7)),
          ),
        ];

        for (final event in events) {
          sink.record(event);
        }

        expect(messages.map(jsonDecode), [
          {
            'operation': 'dailyChoiceDetailRead',
            'stage': 'read',
            'outcome': 'succeeded',
            'durationMicros': 2000,
          },
          {
            'operation': 'dailyChoiceCatalogPageRead',
            'stage': 'read',
            'pageSize': 50,
            'isContinuation': true,
            'outcome': 'failed',
            'durationMicros': 1000,
            'failureCode': 'corruption',
          },
          {
            'operation': 'dailyChoiceGroupPageRead',
            'stage': 'read',
            'pageSize': 50,
            'isContinuation': false,
            'requiresNewSnapshot': false,
            'outcome': 'succeeded',
            'durationMicros': 2000,
          },
          {
            'operation': 'dailyChoicePathValidation',
            'commandType': 'create',
            'stage': 'validation',
            'outcome': 'failed',
            'durationMicros': 3000,
            'failureCode': 'conflict',
          },
          {
            'operation': 'dailyChoiceCommand',
            'commandType': 'updateFields',
            'stage': 'write',
            'outcome': 'failed',
            'durationMicros': 5000,
            'failureCode': 'unexpected',
          },
          {
            'operation': 'dailyChoiceCommand',
            'commandType': 'replacePath',
            'stage': 'resultRead',
            'outcome': 'succeeded',
            'durationMicros': 7000,
          },
        ]);
        for (final canary in [
          '2026-09-23',
          'c0ffee00-cafe-4bad-8ace-0123456789ab',
          'CANARY-route',
          'CANARY-description',
          'CANARY-SQL-PARAMETER',
          'CANARY-database-exception',
        ]) {
          expect(messages.join(), isNot(contains(canary)));
        }
      },
    );

    test('падающий получатель не влияет на исход дневной операции', () {
      final sink = _ThrowingDiagnosticsSink();
      const event = DailyChoiceCommandDiagnosticsEvent(
        commandType: DailyChoiceCommandDiagnosticsType.create,
        stage: DailyChoiceCommandDiagnosticsStage.validation,
        status: DiagnosticsFailed(
          duration: Duration(milliseconds: 1),
          code: DiagnosticsFailureCode.corruption,
        ),
      );

      expect(() => recordDiagnosticsSafely(sink, event), returnsNormally);
      expect(sink.attemptedEvents, [same(event)]);
    });

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
        RelationGroupPageReadDiagnosticsEvent,
        LongTermRelationDetailReadDiagnosticsEvent,
        IntentionCommandDiagnosticsEvent,
        LongTermRelationCommandDiagnosticsEvent,
        BlockingRelationsDeleteDiagnosticsEvent,
        SelectedRelationsReadDiagnosticsEvent,
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
          'operation': 'relationGroupPageRead',
          'stage': 'read',
          'outcome': 'failed',
          'durationMicros': 4000,
          'failureCode': 'conflict',
          'pageSize': 50,
          'isContinuation': true,
          'requiresNewSnapshot': true,
        },
        {
          'operation': 'longTermRelationDetailRead',
          'outcome': 'succeeded',
          'durationMicros': 6000,
        },
        {
          'operation': 'intentionCommand',
          'outcome': 'failed',
          'durationMicros': 12000,
          'failureCode': 'conflict',
          'commandType': 'archive',
        },
        {
          'operation': 'longTermRelationCommand',
          'outcome': 'succeeded',
          'durationMicros': 5000,
          'commandType': 'create',
        },
        {
          'operation': 'blockingRelationsDelete',
          'outcome': 'failed',
          'durationMicros': 7000,
          'failureCode': 'conflict',
        },
        {
          'operation': 'selectedRelationsRead',
          'outcome': 'succeeded',
          'durationMicros': 9000,
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

      expect(
        () => sink.record(
          const DailyChoiceCommandDiagnosticsEvent(
            commandType: DailyChoiceCommandDiagnosticsType.delete,
            stage: DailyChoiceCommandDiagnosticsStage.write,
            status: DiagnosticsSucceeded(Duration(milliseconds: 1)),
          ),
        ),
        returnsNormally,
      );

      expect(writeAttempts, _events().length + 1);
    });

    test(
      'защитная запись подавляет ошибку произвольного получателя без повтора',
      () {
        final sink = _ThrowingDiagnosticsSink();
        final event = _events().first;

        expect(() => recordDiagnosticsSafely(sink, event), returnsNormally);

        expect(sink.attemptedEvents, [same(event)]);
      },
    );
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
  const RelationGroupPageReadDiagnosticsEvent(
    pageSize: 50,
    isContinuation: true,
    requiresNewSnapshot: true,
    status: DiagnosticsFailed(
      duration: Duration(milliseconds: 4),
      code: DiagnosticsFailureCode.conflict,
    ),
  ),
  const LongTermRelationDetailReadDiagnosticsEvent(
    status: DiagnosticsSucceeded(Duration(milliseconds: 6)),
  ),
  const IntentionCommandDiagnosticsEvent(
    commandType: IntentionCommandDiagnosticsType.archive,
    status: DiagnosticsFailed(
      duration: Duration(milliseconds: 12),
      code: DiagnosticsFailureCode.conflict,
    ),
  ),
  const LongTermRelationCommandDiagnosticsEvent(
    commandType: LongTermRelationCommandDiagnosticsType.create,
    status: DiagnosticsSucceeded(Duration(milliseconds: 5)),
  ),
  const BlockingRelationsDeleteDiagnosticsEvent(
    status: DiagnosticsFailed(
      duration: Duration(milliseconds: 7),
      code: DiagnosticsFailureCode.conflict,
    ),
  ),
  const SelectedRelationsReadDiagnosticsEvent(
    status: DiagnosticsSucceeded(Duration(milliseconds: 9)),
  ),
];

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-diagnostics-sink-failure');
  }
}
