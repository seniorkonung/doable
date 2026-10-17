import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticsSink', () {
    test('успех чтения агрегатов статистики кодируется без данных графа', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      recordDiagnosticsSafely(
        sink,
        const StatisticsReadDiagnosticsEvent(
          readType: StatisticsReadDiagnosticsType.homePage,
          stage: StatisticsReadDiagnosticsStage.sourceData,
          status: DiagnosticsSucceeded(Duration(microseconds: 1234)),
        ),
      );

      expect(jsonDecode(messages.single), {
        'operation': 'statisticsRead',
        'readType': 'homePage',
        'stage': 'sourceData',
        'outcome': 'succeeded',
        'durationMicros': 1234,
      });
    });

    test('отказ чтения названий статистики кодируется без данных графа', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      recordDiagnosticsSafely(
        sink,
        const StatisticsReadDiagnosticsEvent(
          readType: StatisticsReadDiagnosticsType.homePage,
          stage: StatisticsReadDiagnosticsStage.titles,
          status: DiagnosticsFailed(
            duration: Duration(microseconds: 5678),
            code: DiagnosticsFailureCode.corruption,
          ),
        ),
      );

      expect(jsonDecode(messages.single), {
        'operation': 'statisticsRead',
        'readType': 'homePage',
        'stage': 'titles',
        'outcome': 'failed',
        'durationMicros': 5678,
        'failureCode': 'corruption',
      });
    });

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

    for (final (description, event, expected)
        in <(String, DiagnosticsEvent, Map<String, Object>)>[
          (
            'успех записи снимка',
            GraphSnapshotWriteDiagnosticsEvent.succeeded(
              duration: const Duration(microseconds: 11),
            ),
            {
              'operation': 'graphSnapshotWrite',
              'outcome': 'succeeded',
              'durationMicros': 11,
            },
          ),
          (
            'отказ записи снимка из-за повреждённого прежнего снимка',
            GraphSnapshotWriteDiagnosticsEvent.failed(
              stage: GraphSnapshotWriteDiagnosticsStage.stateAssembly,
              duration: const Duration(microseconds: 12),
              code: DiagnosticsFailureCode.snapshotCorruption,
            ),
            {
              'operation': 'graphSnapshotWrite',
              'stage': 'stateAssembly',
              'outcome': 'failed',
              'durationMicros': 12,
              'failureCode': 'snapshotCorruption',
            },
          ),
          (
            'успех пересборки снимка',
            GraphSnapshotRebuildDiagnosticsEvent.succeeded(
              duration: const Duration(microseconds: 21),
            ),
            {
              'operation': 'graphSnapshotRebuild',
              'outcome': 'succeeded',
              'durationMicros': 21,
            },
          ),
          (
            'отказ пересборки снимка',
            GraphSnapshotRebuildDiagnosticsEvent.failed(
              stage: GraphSnapshotRebuildDiagnosticsStage.databaseRead,
              duration: const Duration(microseconds: 22),
              code: DiagnosticsFailureCode.unavailable,
            ),
            {
              'operation': 'graphSnapshotRebuild',
              'stage': 'databaseRead',
              'outcome': 'failed',
              'durationMicros': 22,
              'failureCode': 'unavailable',
            },
          ),
          (
            'успех сжатия лога',
            GraphLogCompactionDiagnosticsEvent.succeeded(
              duration: const Duration(microseconds: 31),
            ),
            {
              'operation': 'graphLogCompaction',
              'outcome': 'succeeded',
              'durationMicros': 31,
            },
          ),
          (
            'отказ сжатия лога',
            GraphLogCompactionDiagnosticsEvent.failed(
              stage: GraphLogCompactionDiagnosticsStage.historyRemoval,
              duration: const Duration(microseconds: 32),
              code: DiagnosticsFailureCode.unexpected,
            ),
            {
              'operation': 'graphLogCompaction',
              'stage': 'historyRemoval',
              'outcome': 'failed',
              'durationMicros': 32,
              'failureCode': 'unexpected',
            },
          ),
          (
            'успех очистки каталога снимков',
            GraphSnapshotCleanupDiagnosticsEvent.succeeded(
              duration: const Duration(microseconds: 41),
            ),
            {
              'operation': 'graphSnapshotCleanup',
              'outcome': 'succeeded',
              'durationMicros': 41,
            },
          ),
          (
            'отказ очистки каталога снимков',
            GraphSnapshotCleanupDiagnosticsEvent.failed(
              stage: GraphSnapshotCleanupDiagnosticsStage.fileRemoval,
              duration: const Duration(microseconds: 42),
              code: DiagnosticsFailureCode.unavailable,
            ),
            {
              'operation': 'graphSnapshotCleanup',
              'stage': 'fileRemoval',
              'outcome': 'failed',
              'durationMicros': 42,
              'failureCode': 'unavailable',
            },
          ),
          (
            'успех экспорта графа',
            GraphExportDiagnosticsEvent.succeeded(
              duration: const Duration(microseconds: 51),
            ),
            {
              'operation': 'graphExport',
              'outcome': 'succeeded',
              'durationMicros': 51,
            },
          ),
          (
            'отказ экспорта графа из-за повреждённого снимка',
            GraphExportDiagnosticsEvent.failed(
              stage: GraphExportDiagnosticsStage.temporaryFileWrite,
              duration: const Duration(microseconds: 52),
              code: DiagnosticsFailureCode.snapshotCorruption,
            ),
            {
              'operation': 'graphExport',
              'stage': 'temporaryFileWrite',
              'outcome': 'failed',
              'durationMicros': 52,
              'failureCode': 'snapshotCorruption',
            },
          ),
        ]) {
      test('$description кодируется только операцией, этапом отказа, исходом, '
          'длительностью и категорией отказа', () {
        final messages = <String>[];
        final sink = DeveloperDiagnosticsSink(messages.add);

        sink.record(event);

        expect(jsonDecode(messages.single), expected);
      });
    }

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
