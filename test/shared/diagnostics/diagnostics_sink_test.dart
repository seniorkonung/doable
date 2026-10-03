import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('DiagnosticsSink', () {
    test(
      'операции и этапы тегов кодируются закрытым набором безопасных полей',
      () {
        final messages = <String>[];
        final sink = DeveloperDiagnosticsSink(messages.add);

        for (final commandType in TagCommandDiagnosticsType.values) {
          for (final stage in TagCommandDiagnosticsStage.values) {
            sink.record(
              TagCommandDiagnosticsEvent(
                commandType: commandType,
                stage: stage,
                status: const DiagnosticsFailed(
                  duration: Duration(microseconds: 17),
                  code: DiagnosticsFailureCode.conflict,
                ),
              ),
            );
          }
        }
        for (final stage in TagReadDiagnosticsStage.values) {
          sink.record(
            TaggedEntitiesPageReadDiagnosticsEvent(
              stage: stage,
              status: const DiagnosticsFailed(
                duration: Duration(microseconds: 31),
                code: DiagnosticsFailureCode.corruption,
              ),
            ),
          );
          sink.record(
            TagCatalogReadDiagnosticsEvent(
              stage: stage,
              status: const DiagnosticsSucceeded(Duration(microseconds: 23)),
            ),
          );
          sink.record(
            TagDetailReadDiagnosticsEvent(
              stage: stage,
              status: const DiagnosticsStarted(),
            ),
          );
        }

        expect(messages.map((message) => jsonDecode(message)), [
          for (final commandType in TagCommandDiagnosticsType.values)
            for (final stage in TagCommandDiagnosticsStage.values)
              {
                'operation': 'tagCommand',
                'commandType': commandType.name,
                'stage': stage.name,
                'outcome': 'failed',
                'durationMicros': 17,
                'failureCode': 'conflict',
              },
          for (final stage in TagReadDiagnosticsStage.values) ...[
            {
              'operation': 'taggedEntitiesPageRead',
              'stage': stage.name,
              'outcome': 'failed',
              'durationMicros': 31,
              'failureCode': 'corruption',
            },
            {
              'operation': 'tagCatalogRead',
              'stage': stage.name,
              'outcome': 'succeeded',
              'durationMicros': 23,
            },
            {
              'operation': 'tagDetailRead',
              'stage': stage.name,
              'outcome': 'started',
            },
          ],
        ]);
        for (final canary in [
          'CANARY-название-тега',
          'c0ffee00-cafe-4bad-8ace-0123456789ab',
          'CANARY-name-key',
          'CANARY-assignment',
          'CANARY-SQL-PARAMETER',
          'CANARY-database-exception',
        ]) {
          expect(messages.join(), isNot(contains(canary)));
        }
      },
    );

    test(
      'отказ диагностики не меняет подтверждённый результат команды тега',
      () {
        final sink = _ThrowingDiagnosticsSink();
        const event = TagCommandDiagnosticsEvent(
          commandType: TagCommandDiagnosticsType.delete,
          stage: TagCommandDiagnosticsStage.write,
          status: DiagnosticsSucceeded(Duration(microseconds: 7)),
        );

        String confirmedResult() {
          recordDiagnosticsSafely(sink, event);
          return 'подтверждено';
        }

        expect(confirmedResult(), 'подтверждено');
        expect(sink.attemptedEvents, [same(event)]);
      },
    );

    test('создание схемы использует общий канал без нового вида события', () {
      final messages = <String>[];
      DeveloperDiagnosticsSink(messages.add).record(
        const MigrationDiagnosticsEvent(
          fromSchemaVersion: 0,
          toSchemaVersion: 1,
          status: DiagnosticsSucceeded(Duration(microseconds: 29)),
        ),
      );

      expect(jsonDecode(messages.single), {
        'operation': 'migration',
        'fromSchemaVersion': 0,
        'toSchemaVersion': 1,
        'outcome': 'succeeded',
        'durationMicros': 29,
      });
    });

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

    test('событие подсказок кодирует этап и категорию без данных графа', () {
      final messages = <String>[];
      DeveloperDiagnosticsSink(messages.add).record(
        const ChoicePathSuggestionReadDiagnosticsEvent(
          stage: ChoicePathSuggestionReadStage.pathValidation,
          status: DiagnosticsFailed(
            duration: Duration(milliseconds: 3),
            code: DiagnosticsFailureCode.corruption,
          ),
        ),
      );
      expect(messages.map(jsonDecode), [
        {
          'operation': 'choicePathSuggestionRead',
          'stage': 'pathValidation',
          'outcome': 'failed',
          'durationMicros': 3000,
          'failureCode': 'corruption',
        },
      ]);
    });

    test('событие продолжений кодирует только безопасные поля', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);
      sink.record(
        const ChoicePathContinuationReadDiagnosticsEvent(
          stage: ChoicePathContinuationReadStage.read,
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

    test('чтение согласования кодируется отдельной операцией, а повтор из-за '
        'новой ревизии — завершением, а не отказом', () {
      final events = [
        const CatalogReconciliationReadDiagnosticsEvent.started(pageSize: 50),
        CatalogReconciliationReadDiagnosticsEvent.completed(
          pageSize: 50,
          duration: const Duration(milliseconds: 2),
          completion: CatalogReconciliationReadCompletion.portion,
        ),
        CatalogReconciliationReadDiagnosticsEvent.completed(
          pageSize: 50,
          duration: const Duration(milliseconds: 3),
          completion: CatalogReconciliationReadCompletion.retry,
        ),
        CatalogReconciliationReadDiagnosticsEvent.failed(
          pageSize: 50,
          duration: const Duration(milliseconds: 4),
          code: DiagnosticsFailureCode.validation,
        ),
        CatalogReconciliationReadDiagnosticsEvent.failed(
          pageSize: 50,
          duration: const Duration(milliseconds: 5),
          code: DiagnosticsFailureCode.unavailable,
        ),
      ];
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      for (final event in events) {
        sink.record(event);
      }

      expect(events.map((event) => event.status.runtimeType), [
        DiagnosticsStarted,
        DiagnosticsSucceeded,
        DiagnosticsSucceeded,
        DiagnosticsFailed,
        DiagnosticsFailed,
      ]);
      expect(events.map((event) => event.completion), [
        null,
        CatalogReconciliationReadCompletion.portion,
        CatalogReconciliationReadCompletion.retry,
        null,
        null,
      ]);
      expect(messages.map(jsonDecode), [
        {
          'operation': 'catalogReconciliationRead',
          'outcome': 'started',
          'pageSize': 50,
        },
        {
          'operation': 'catalogReconciliationRead',
          'outcome': 'succeeded',
          'durationMicros': 2000,
          'pageSize': 50,
          'completion': 'portion',
        },
        {
          'operation': 'catalogReconciliationRead',
          'outcome': 'succeeded',
          'durationMicros': 3000,
          'pageSize': 50,
          'completion': 'retry',
        },
        {
          'operation': 'catalogReconciliationRead',
          'outcome': 'failed',
          'durationMicros': 4000,
          'failureCode': 'validation',
          'pageSize': 50,
        },
        {
          'operation': 'catalogReconciliationRead',
          'outcome': 'failed',
          'durationMicros': 5000,
          'failureCode': 'unavailable',
          'pageSize': 50,
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

    test('этап несут только отметка избранного и её снятие', () {
      for (final commandType in IntentionCommandDiagnosticsType.values) {
        IntentionCommandDiagnosticsEvent withoutStage() =>
            IntentionCommandDiagnosticsEvent(
              commandType: commandType,
              status: const DiagnosticsStarted(),
            );

        switch (commandType) {
          case IntentionCommandDiagnosticsType.markFavorite ||
              IntentionCommandDiagnosticsType.unmarkFavorite:
            expect(withoutStage, throwsAssertionError);
          case IntentionCommandDiagnosticsType.create ||
              IntentionCommandDiagnosticsType.update ||
              IntentionCommandDiagnosticsType.enableReadiness ||
              IntentionCommandDiagnosticsType.disableReadiness ||
              IntentionCommandDiagnosticsType.archive ||
              IntentionCommandDiagnosticsType.restore ||
              IntentionCommandDiagnosticsType.delete:
            expect(withoutStage().stage, isNull);
        }
      }
    });

    test('падающий писатель не повторяет диагностическое событие отметки', () {
      var attempts = 0;
      final sink = DeveloperDiagnosticsSink((_) {
        attempts++;
        throw StateError('CANARY-diagnostics-writer-failure');
      });

      expect(
        () => sink.record(
          const IntentionCommandDiagnosticsEvent.markFavorite(
            stage: FavoriteMarkCommandDiagnosticsStage.write,
            status: DiagnosticsSucceeded(Duration(milliseconds: 1)),
          ),
        ),
        returnsNormally,
      );
      expect(attempts, 1);
    });

    test('чтение списка избранных намерений кодируется отдельной операцией '
        'с этапом, исходом и безопасной категорией', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      for (final stage in FavoriteIntentionsReadDiagnosticsStage.values) {
        for (final status in const [
          DiagnosticsStarted(),
          DiagnosticsSucceeded(Duration(milliseconds: 2)),
          DiagnosticsFailed(
            duration: Duration(milliseconds: 3),
            code: DiagnosticsFailureCode.unavailable,
          ),
          DiagnosticsFailed(
            duration: Duration(milliseconds: 4),
            code: DiagnosticsFailureCode.corruption,
          ),
          DiagnosticsFailed(
            duration: Duration(milliseconds: 5),
            code: DiagnosticsFailureCode.unexpected,
          ),
        ]) {
          sink.record(
            FavoriteIntentionsReadDiagnosticsEvent(
              stage: stage,
              status: status,
            ),
          );
        }
      }

      expect(FavoriteIntentionsReadDiagnosticsStage.values.map((s) => s.name), [
        'read',
        'validation',
      ]);
      expect(messages.map(jsonDecode), [
        for (final stage in ['read', 'validation']) ...[
          {
            'operation': 'favoriteIntentionsRead',
            'stage': stage,
            'outcome': 'started',
          },
          {
            'operation': 'favoriteIntentionsRead',
            'stage': stage,
            'outcome': 'succeeded',
            'durationMicros': 2000,
          },
          {
            'operation': 'favoriteIntentionsRead',
            'stage': stage,
            'outcome': 'failed',
            'durationMicros': 3000,
            'failureCode': 'unavailable',
          },
          {
            'operation': 'favoriteIntentionsRead',
            'stage': stage,
            'outcome': 'failed',
            'durationMicros': 4000,
            'failureCode': 'corruption',
          },
          {
            'operation': 'favoriteIntentionsRead',
            'stage': stage,
            'outcome': 'failed',
            'durationMicros': 5000,
            'failureCode': 'unexpected',
          },
        ],
      ]);
    });

    test('падающий писатель не повторяет диагностическое событие чтения '
        'списка избранных намерений', () {
      var attempts = 0;
      final sink = DeveloperDiagnosticsSink((_) {
        attempts++;
        throw StateError('CANARY-diagnostics-writer-failure');
      });

      expect(
        () => sink.record(
          const FavoriteIntentionsReadDiagnosticsEvent(
            stage: FavoriteIntentionsReadDiagnosticsStage.validation,
            status: DiagnosticsFailed(
              duration: Duration(milliseconds: 1),
              code: DiagnosticsFailureCode.corruption,
            ),
          ),
        ),
        returnsNormally,
      );
      expect(attempts, 1);
    });

    test('перестановка избранного кодируется отдельной операцией с этапом, '
        'исходом, длительностью и безопасной категорией', () {
      const failureCodes = [
        DiagnosticsFailureCode.validation,
        DiagnosticsFailureCode.conflict,
        DiagnosticsFailureCode.unavailable,
        DiagnosticsFailureCode.corruption,
        DiagnosticsFailureCode.unexpected,
      ];
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      sink.record(const FavoriteOrderCommandDiagnosticsEvent.started());
      sink.record(
        FavoriteOrderCommandDiagnosticsEvent.moved(
          duration: const Duration(microseconds: 1500),
        ),
      );
      sink.record(
        FavoriteOrderCommandDiagnosticsEvent.unchanged(
          duration: const Duration(milliseconds: 2),
        ),
      );
      for (final stage in FavoriteOrderCommandDiagnosticsStage.values) {
        for (final code in failureCodes) {
          sink.record(
            FavoriteOrderCommandDiagnosticsEvent.failed(
              stage: stage,
              duration: const Duration(milliseconds: 3),
              code: code,
            ),
          );
        }
      }

      expect(FavoriteOrderCommandDiagnosticsStage.values.map((s) => s.name), [
        'read',
        'validation',
        'write',
      ]);
      expect(messages.map(jsonDecode), [
        {
          'operation': 'favoriteOrderCommand',
          'stage': 'read',
          'outcome': 'started',
        },
        {
          'operation': 'favoriteOrderCommand',
          'stage': 'write',
          'outcome': 'succeeded',
          'durationMicros': 1500,
          'completion': 'moved',
        },
        {
          'operation': 'favoriteOrderCommand',
          'stage': 'validation',
          'outcome': 'succeeded',
          'durationMicros': 2000,
          'completion': 'unchanged',
        },
        for (final stage in ['read', 'validation', 'write'])
          for (final code in [
            'validation',
            'conflict',
            'unavailable',
            'corruption',
            'unexpected',
          ])
            {
              'operation': 'favoriteOrderCommand',
              'stage': stage,
              'outcome': 'failed',
              'durationMicros': 3000,
              'failureCode': code,
            },
      ]);
    });

    test('конструкторы события перестановки допускают только согласованные '
        'сочетания этапа, статуса и вида завершения', () {
      const started = FavoriteOrderCommandDiagnosticsEvent.started();
      final moved = FavoriteOrderCommandDiagnosticsEvent.moved(
        duration: const Duration(milliseconds: 4),
      );
      final unchanged = FavoriteOrderCommandDiagnosticsEvent.unchanged(
        duration: const Duration(milliseconds: 5),
      );
      final conflict = FavoriteOrderCommandDiagnosticsEvent.failed(
        stage: FavoriteOrderCommandDiagnosticsStage.validation,
        duration: const Duration(milliseconds: 6),
        code: DiagnosticsFailureCode.conflict,
      );

      expect(started.stage, FavoriteOrderCommandDiagnosticsStage.read);
      expect(started.status, isA<DiagnosticsStarted>());
      expect(started.completion, isNull);

      expect(moved.stage, FavoriteOrderCommandDiagnosticsStage.write);
      expect(
        moved.status,
        isA<DiagnosticsSucceeded>().having(
          (status) => status.duration,
          'duration',
          const Duration(milliseconds: 4),
        ),
      );
      expect(moved.completion, FavoriteOrderCommandDiagnosticsCompletion.moved);

      expect(unchanged.stage, FavoriteOrderCommandDiagnosticsStage.validation);
      expect(
        unchanged.status,
        isA<DiagnosticsSucceeded>().having(
          (status) => status.duration,
          'duration',
          const Duration(milliseconds: 5),
        ),
      );
      expect(
        unchanged.completion,
        FavoriteOrderCommandDiagnosticsCompletion.unchanged,
      );

      expect(conflict.stage, FavoriteOrderCommandDiagnosticsStage.validation);
      expect(
        conflict.status,
        isA<DiagnosticsFailed>()
            .having(
              (status) => status.duration,
              'duration',
              const Duration(milliseconds: 6),
            )
            .having(
              (status) => status.code,
              'code',
              DiagnosticsFailureCode.conflict,
            ),
      );
      expect(conflict.completion, isNull);
    });

    test('конфликт перестановки на этапе проверки сериализуется только '
        'разрешёнными полями без данных личного графа', () {
      final messages = <String>[];
      final sink = DeveloperDiagnosticsSink(messages.add);

      for (final event in [
        const FavoriteOrderCommandDiagnosticsEvent.started(),
        FavoriteOrderCommandDiagnosticsEvent.failed(
          stage: FavoriteOrderCommandDiagnosticsStage.validation,
          duration: const Duration(milliseconds: 7),
          code: DiagnosticsFailureCode.conflict,
        ),
        FavoriteOrderCommandDiagnosticsEvent.moved(
          duration: const Duration(milliseconds: 8),
        ),
        FavoriteOrderCommandDiagnosticsEvent.unchanged(
          duration: const Duration(milliseconds: 9),
        ),
      ]) {
        sink.record(event);
      }

      expect(messages, hasLength(4));
      for (final message in messages) {
        expect(
          (jsonDecode(message) as Map<String, Object?>).keys,
          everyElement(
            isIn(const {
              'operation',
              'stage',
              'outcome',
              'durationMicros',
              'failureCode',
              'completion',
            }),
          ),
        );
      }
      expect(jsonDecode(messages[1]), {
        'operation': 'favoriteOrderCommand',
        'stage': 'validation',
        'outcome': 'failed',
        'durationMicros': 7000,
        'failureCode': 'conflict',
      });
      for (final canary in [
        'CANARY-название-избранного',
        'CANARY-описание-избранного',
        'c0ffee00-cafe-4bad-8ace-0123456789ab',
        'position',
        'favorite_intentions',
        'CANARY-SQL-PARAMETER',
        'CANARY-database-exception',
      ]) {
        expect(messages.join(), isNot(contains(canary)));
      }
    });

    test('падающий писатель не повторяет диагностическое событие '
        'перестановки избранного', () {
      var attempts = 0;
      final sink = DeveloperDiagnosticsSink((_) {
        attempts++;
        throw StateError('CANARY-diagnostics-writer-failure');
      });

      expect(
        () => sink.record(
          FavoriteOrderCommandDiagnosticsEvent.failed(
            stage: FavoriteOrderCommandDiagnosticsStage.write,
            duration: const Duration(milliseconds: 1),
            code: DiagnosticsFailureCode.unavailable,
          ),
        ),
        returnsNormally,
      );
      expect(attempts, 1);
    });

    test('отказ получателя не меняет подтверждённую перестановку и не '
        'повторяет запись события', () {
      final sink = _ThrowingDiagnosticsSink();
      final event = FavoriteOrderCommandDiagnosticsEvent.moved(
        duration: const Duration(milliseconds: 2),
      );

      String confirmedResult() {
        recordDiagnosticsSafely(sink, event);
        return 'порядок подтверждён';
      }

      expect(confirmedResult(), 'порядок подтверждён');
      expect(sink.attemptedEvents, [same(event)]);
    });

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
          'fromSchemaVersion': 0,
          'toSchemaVersion': 1,
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
    fromSchemaVersion: 0,
    toSchemaVersion: 1,
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
