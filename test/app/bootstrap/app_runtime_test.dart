import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        AppDatabase,
        ConfiguredLocalDatabaseConnection,
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_read_contract_test_fallback.dart';

const _unsupportedSchemaVersion = AppDatabase.currentSchemaVersion + 1;

void main() {
  group('AppRuntime', () {
    test(
      'создаёт один модуль графа в одном container без automatic retry',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        var repositoryFactoryCalls = 0;
        final runtime = AppRuntime(
          connectionFactory: openInMemoryLocalDatabase,
          diagnosticsSink: InMemoryDiagnosticsSink(),
          repositoryFactory: (_) {
            repositoryFactoryCalls += 1;
            return repository;
          },
        );
        addTearDown(runtime.shutdown);

        final bootstrapping = runtime.bootstrap();
        expect(runtime.bootstrap(), same(bootstrapping));
        final result = await bootstrapping;

        expect(result, isA<AppRuntimeReady>());
        final ready = result as AppRuntimeReady;
        expect(
          ready.container.read(personalGraphRepositoryProvider),
          same(repository),
        );
        final coordinator = ready.container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        expect(coordinator, same(runtime.commandCoordinator));
        final router = ready.container.read(appRouterProvider);
        expect(ready.container.read(appRouterProvider), same(router));
        expect(ready.container.retry!(0, Exception('отказ provider')), isNull);

        final repeated = await runtime.bootstrap();
        expect(repeated, same(ready));
        expect(repositoryFactoryCalls, 1);
      },
    );

    test('повторяет bootstrap только после retryable outcome', () async {
      var connectionAttempts = 0;
      final runtime = AppRuntime(
        connectionFactory: () {
          connectionAttempts += 1;
          if (connectionAttempts == 1) {
            return openInMemoryLocalDatabase(
              setup: (_) => throw SqliteException(
                extendedResultCode: SqlError.SQLITE_BUSY,
                message: 'временная недоступность',
              ),
            );
          }
          return openInMemoryLocalDatabase();
        },
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(runtime.shutdown);

      expect(await runtime.bootstrap(), isA<AppRuntimeRetryableFailure>());
      expect(await runtime.bootstrap(), isA<AppRuntimeReady>());
      expect(connectionAttempts, 2);
    });

    test('типизированно отображает non-ready outcomes', () async {
      final scenarios =
          <
            ({
              ConfiguredLocalDatabaseConnection Function() connectionFactory,
              Matcher result,
            })
          >[
            (
              connectionFactory: () => openInMemoryLocalDatabase(
                setup: (_) => throw SqliteException(
                  extendedResultCode: SqlError.SQLITE_NOTADB,
                  message: 'повреждение',
                ),
              ),
              result: isA<AppRuntimeCorruption>(),
            ),
            (
              connectionFactory: () => openInMemoryLocalDatabase(
                setup: (_) => throw StateError('неожиданный отказ'),
              ),
              result: isA<AppRuntimeUnexpectedFailure>(),
            ),
            (
              connectionFactory: () => openInMemoryLocalDatabase(
                setup: (database) => database.execute(
                  'PRAGMA user_version = $_unsupportedSchemaVersion',
                ),
              ),
              result: isA<AppRuntimeIncompatibleSchema>()
                  .having(
                    (result) => result.expectedSchemaVersion,
                    'ожидаемая версия',
                    AppDatabase.currentSchemaVersion,
                  )
                  .having(
                    (result) => result.detectedSchemaVersion,
                    'обнаруженная версия',
                    _unsupportedSchemaVersion,
                  ),
            ),
          ];

      for (final scenario in scenarios) {
        var repositoryFactoryCalls = 0;
        final runtime = AppRuntime(
          connectionFactory: scenario.connectionFactory,
          diagnosticsSink: InMemoryDiagnosticsSink(),
          repositoryFactory: (_) {
            repositoryFactoryCalls += 1;
            return _ControlledPersonalGraphRepository();
          },
        );
        addTearDown(runtime.shutdown);

        expect(await runtime.bootstrap(), scenario.result);
        expect(repositoryFactoryCalls, 0);
        await runtime.shutdown();
      }
    });

    test('закрывает готовую базу при отказе создания provider graph', () async {
      final closeObserver = _CloseTrackingObserver();
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          closeObserver,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => throw StateError('отказ composition'),
      );
      addTearDown(runtime.shutdown);

      expect(await runtime.bootstrap(), isA<AppRuntimeUnexpectedFailure>());
      expect(closeObserver.closeCalls, 1);
      expect(() => runtime.commandCoordinator, throwsStateError);

      await runtime.shutdown();
      expect(closeObserver.closeCalls, 1);
    });

    test('shutdown синхронно останавливает graph и закрывает базу после operations', () async {
      final repository = _ControlledPersonalGraphRepository();
      final closeObserver = _CloseTrackingObserver();
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          closeObserver,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final coordinator = runtime.commandCoordinator;
      final accepted = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(title: 'Намерение', description: null),
      ) as IntentionCommandAccepted;

      final shutdown = runtime.shutdown();

      expect(runtime.shutdown(), same(shutdown));
      expect(
        coordinator.acceptCreation(
          IntentionCreationFormKey(),
          const CreateIntention(title: 'Другое', description: null),
        ),
        isA<GraphCommandCoordinatorDraining>(),
      );
      expect(
        () => ready.container.read(personalGraphRepositoryProvider),
        throwsStateError,
      );
      expect(runtime.bootstrap, throwsStateError);
      expect(closeObserver.closeCalls, 0);

      repository.complete(const ResultFailure(IntentionUnavailableFailure()));
      await accepted.future;
      await shutdown;

      expect(closeObserver.closeCalls, 1);
    });

    test(
      'подключает создание связи к coordinator времени жизни приложения',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final closeObserver = _CloseTrackingObserver();
        final runtime = AppRuntime(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            openInMemoryLocalDatabase(),
            closeObserver,
          ),
          diagnosticsSink: InMemoryDiagnosticsSink(),
          repositoryFactory: (_) => repository,
        );
        addTearDown(runtime.shutdown);
        await runtime.bootstrap();
        final coordinator = runtime.commandCoordinator;
        final accepted = coordinator.acceptRelationCreation(
          LongTermRelationCreationFormKey(),
          CreateLongTermRelation(
            sourceIntentionId: _intentionId(_relationSourceUuid),
            relatedIntentionId: _intentionId(_relationRelatedUuid),
            type: LongTermRelationType.need,
            priority: RelationPriority.p2,
            description: null,
          ),
        ) as LongTermRelationCommandAccepted;

        final shutdown = runtime.shutdown();

        expect(closeObserver.closeCalls, 0);
        expect(
          coordinator.acceptRelationCreation(
            LongTermRelationCreationFormKey(),
            CreateLongTermRelation(
              sourceIntentionId: _intentionId(_relationSourceUuid),
              relatedIntentionId: _intentionId(_relationRelatedUuid),
              type: LongTermRelationType.can,
              priority: RelationPriority.p4,
              description: null,
            ),
          ),
          isA<GraphCommandCoordinatorDraining>(),
        );

        repository.complete(
          const GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >(LongTermRelationUnavailableFailure()),
        );
        await accepted.future;
        await shutdown;

        expect(closeObserver.closeCalls, 1);
      },
    );

    test(
      'shutdown дожидается массового удаления и освобождает весь набор',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final closeObserver = _CloseTrackingObserver();
        final runtime = AppRuntime(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            openInMemoryLocalDatabase(),
            closeObserver,
          ),
          diagnosticsSink: InMemoryDiagnosticsSink(),
          repositoryFactory: (_) => repository,
        );
        addTearDown(runtime.shutdown);
        await runtime.bootstrap();
        final coordinator = runtime.commandCoordinator;
        final intentionId = _intentionId(_relationSourceUuid);
        final relationId = _relationId(_relationRelatedUuid);
        final choiceId = _choiceId(_relationRelatedUuid);
        final accepted = coordinator.acceptBlockingRelationsDelete(
          DeleteBlockingRelations(
            intentionId: intentionId,
            references: {
              LongTermBlockingRelationReference(relationId),
              DailyChoiceBlockingRelationReference(choiceId),
            },
          ),
          presentationTitle: 'Намерение',
        ) as BlockingRelationsDeleteAccepted;
        coordinator.releaseInitiatorPresentation(accepted.token);

        final shutdown = runtime.shutdown();
        expect(coordinator.isRunning(intentionId), isTrue);
        expect(coordinator.isRelationRunning(relationId), isTrue);
        expect(coordinator.isDailyChoiceRunning(choiceId), isTrue);
        expect(closeObserver.closeCalls, 0);
        expect(
          coordinator.acceptBlockingRelationsDelete(
            DeleteBlockingRelations.longTerm(
              intentionId: _intentionId(_relationRelatedUuid),
              relationIds: {_relationId(_relationSourceUuid)},
            ),
            presentationTitle: 'Другое',
          ),
          isA<GraphCommandCoordinatorDraining>(),
        );

        repository.complete(
          const GraphCommandFailed<
            BlockingRelationsDeleted,
            DeleteBlockingRelationsFailure
          >(DeleteBlockingRelationsUnavailableFailure()),
        );
        final completion = await accepted.future;
        expect(completion.token, same(accepted.token));
        expect(coordinator.isRunning(intentionId), isFalse);
        expect(coordinator.isRelationRunning(relationId), isFalse);
        expect(coordinator.isDailyChoiceRunning(choiceId), isFalse);
        await shutdown;
        expect(closeObserver.closeCalls, 1);
      },
    );

    test('shutdown дожидается принятой дневной команды', () async {
      final repository = _ControlledPersonalGraphRepository();
      final closeObserver = _CloseTrackingObserver();
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          closeObserver,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(runtime.shutdown);
      await runtime.bootstrap();
      final coordinator = runtime.commandCoordinator;
      final choiceId = _choiceId(_relationRelatedUuid);
      final accepted = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(choiceId),
      ) as DailyChoiceCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);

      final shutdown = runtime.shutdown();
      expect(coordinator.isDailyChoiceRunning(choiceId), isTrue);
      expect(closeObserver.closeCalls, 0);
      expect(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(choiceId)),
        isA<GraphCommandCoordinatorDraining>(),
      );

      repository.complete(
        const GraphCommandFailed<
          DailyChoiceCommandSuccess,
          DailyChoiceCommandFailure
        >(DailyChoiceUnavailableFailure()),
      );
      await accepted.future;
      await shutdown;
      expect(closeObserver.closeCalls, 1);
    });

    test('shutdown дожидается команды тега до закрытия базы', () async {
      final repository = _ControlledPersonalGraphRepository();
      final closeObserver = _CloseTrackingObserver();
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          closeObserver,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(runtime.shutdown);
      await runtime.bootstrap();
      final coordinator = runtime.commandCoordinator;
      final tagId =
          (TagId.decode(_relationSourceUuid) as TagIdDecodingSuccess).id;
      final accepted =
          coordinator.acceptTagDelete(DeleteTag(tagId)) as TagCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);

      final shutdown = runtime.shutdown();
      expect(coordinator.isTagRunning(tagId), isTrue);
      expect(closeObserver.closeCalls, 0);
      expect(
        coordinator.acceptTagDelete(DeleteTag(tagId)),
        isA<GraphCommandCoordinatorDraining>(),
      );

      repository.complete(const TagCommandFailed(TagUnavailableFailure()));
      final completion = await accepted.future;
      expect(completion.isFailure, isTrue);
      await shutdown;
      expect(closeObserver.closeCalls, 1);
    });

    test(
      'shutdown ждёт in-flight bootstrap и не создаёт provider graph',
      () async {
        final openingStarted = Completer<void>();
        final allowOpening = Completer<void>();
        final lifecycleObserver = _ControlledLifecycleObserver(
          openingStarted: openingStarted,
          allowOpening: allowOpening,
        );
        var repositoryFactoryCalls = 0;
        final runtime = AppRuntime(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            openInMemoryLocalDatabase(),
            lifecycleObserver,
          ),
          diagnosticsSink: InMemoryDiagnosticsSink(),
          repositoryFactory: (_) {
            repositoryFactoryCalls += 1;
            return _ControlledPersonalGraphRepository();
          },
        );
        addTearDown(() async {
          if (!allowOpening.isCompleted) allowOpening.complete();
          await runtime.shutdown();
        });

        final bootstrapping = runtime.bootstrap();
        await openingStarted.future;
        final shutdown = runtime.shutdown();

        expect(runtime.bootstrap, throwsStateError);
        expect(repositoryFactoryCalls, 0);
        expect(lifecycleObserver.closeCalls, 0);

        allowOpening.complete();
        await expectLater(bootstrapping, throwsStateError);
        await shutdown;

        expect(repositoryFactoryCalls, 0);
        expect(lifecycleObserver.closeCalls, 1);
      },
    );
  });
}

final class _ControlledPersonalGraphRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  Completer<Object>? _pendingCommand;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final pending = Completer<Object>();
    _pendingCommand = pending;
    return await pending.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void complete(Object result) {
    _pendingCommand!.complete(result);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => throw UnsupportedError('Группы связей не используются в этих тестах.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в этих тестах.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) =>
      throw UnsupportedError('Подробное чтение не используется в этих тестах.');
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID fixture.',
  ),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Некорректный UUID fixture связи.',
      ),
    };

DailyChoiceId _choiceId(String value) => switch (DailyChoiceId.decode(value)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  InvalidDailyChoiceIdDecoding() => throw StateError(
    'Некорректный UUID fixture дневного выбора.',
  ),
};

const _relationSourceUuid = '018f47c2-6b7d-7abc-8def-0123456789ab';
const _relationRelatedUuid = '018f47c2-6b7d-7abc-8def-0123456789ac';

final class _CloseTrackingObserver extends LocalDatabaseConnectionObserver {
  var closeCalls = 0;

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}

final class _ControlledLifecycleObserver
    extends LocalDatabaseConnectionObserver {
  _ControlledLifecycleObserver({
    required this.openingStarted,
    required this.allowOpening,
  });

  final Completer<void> openingStarted;
  final Completer<void> allowOpening;
  var closeCalls = 0;

  @override
  Future<void> beforeOpen() async {
    if (!openingStarted.isCompleted) openingStarted.complete();
    await allowOpening.future;
  }

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}
