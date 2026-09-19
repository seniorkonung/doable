import 'dart:async';

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
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

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
    implements PersonalGraphRepository {
  Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>?
  _pendingCommand;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return await _executeIntention(command as IntentionCommand)
        as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    final pending =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _pendingCommand = pending;
    return pending.future;
  }

  void complete(Result<ConfirmedGraphResult<IntentionCommandSuccess>> result) {
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
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) =>
      throw UnsupportedError('Подробное чтение не используется в этих тестах.');
}

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
