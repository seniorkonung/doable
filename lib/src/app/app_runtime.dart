import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import '../data/local/bootstrap/local_data_bootstrap.dart';
import '../data/local/bootstrap/local_data_bootstrap_result.dart';
import '../graph/application/graph_command_coordinator.dart';
import '../graph/application/personal_graph_repository.dart';
import '../graph/application/personal_graph_repository_provider.dart';
import '../graph/data/drift_personal_graph_repository.dart';
import '../intention/application/intention_id_generator.dart';
import '../long_term_relation/application/long_term_relation_id_generator.dart';
import '../shared/diagnostics/developer_diagnostics_sink.dart';
import '../shared/diagnostics/diagnostics_sink.dart';
import 'routing/app_router_provider.dart';

typedef AppPersonalGraphRepositoryFactory = PersonalGraphRepository Function(
  AppDatabase database,
);

sealed class AppRuntimeBootstrapResult {
  const AppRuntimeBootstrapResult();
}

final class AppRuntimeReady extends AppRuntimeBootstrapResult {
  const AppRuntimeReady(this.container);

  final ProviderContainer container;
}

final class AppRuntimeRetryableFailure extends AppRuntimeBootstrapResult {
  const AppRuntimeRetryableFailure();
}

final class AppRuntimeCorruption extends AppRuntimeBootstrapResult {
  const AppRuntimeCorruption();
}

final class AppRuntimeUnexpectedFailure extends AppRuntimeBootstrapResult {
  const AppRuntimeUnexpectedFailure();
}

final class AppRuntimeIncompatibleSchema extends AppRuntimeBootstrapResult {
  const AppRuntimeIncompatibleSchema({
    required this.expectedSchemaVersion,
    required this.detectedSchemaVersion,
  });

  final int expectedSchemaVersion;
  final int detectedSchemaVersion;
}

final class AppRuntime {
  factory AppRuntime({
    required LocalDataConnectionFactory connectionFactory,
    required DiagnosticsSink diagnosticsSink,
    AppPersonalGraphRepositoryFactory? repositoryFactory,
  }) {
    final resolvedRepositoryFactory =
        repositoryFactory ??
        (database) => DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.now().toUtc(),
          diagnosticsSink,
          relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
        );
    return AppRuntime._(
      LocalDataBootstrap(
        connectionFactory: connectionFactory,
        diagnosticsSink: diagnosticsSink,
      ),
      resolvedRepositoryFactory,
    );
  }

  factory AppRuntime.production() {
    final diagnosticsSink = DeveloperDiagnosticsSink();
    return AppRuntime(
      connectionFactory: openAndroidProductionDatabaseConnection,
      diagnosticsSink: diagnosticsSink,
    );
  }

  AppRuntime._(this._localDataBootstrap, this._repositoryFactory);

  final LocalDataBootstrap _localDataBootstrap;
  final AppPersonalGraphRepositoryFactory _repositoryFactory;
  var _lifecycle = _AppRuntimeLifecycle.running;
  Future<AppRuntimeBootstrapResult>? _bootstrapping;
  AppRuntimeReady? _ready;
  GraphCommandCoordinator? _commandCoordinator;
  Future<void>? _shuttingDown;

  GraphCommandCoordinator get commandCoordinator {
    final coordinator = _commandCoordinator;
    if (coordinator == null) {
      throw StateError('Coordinator недоступен до готовности AppRuntime.');
    }
    return coordinator;
  }

  Future<AppRuntimeBootstrapResult> bootstrap() {
    if (_lifecycle != _AppRuntimeLifecycle.running) {
      throw StateError('Нельзя запустить bootstrap после начала shutdown.');
    }

    final ready = _ready;
    if (ready != null) return Future.value(ready);
    final existingBootstrapping = _bootstrapping;
    if (existingBootstrapping != null) return existingBootstrapping;

    late final Future<AppRuntimeBootstrapResult> bootstrapping;
    bootstrapping = _bootstrap().whenComplete(() {
      if (identical(_bootstrapping, bootstrapping)) {
        _bootstrapping = null;
      }
    });
    _bootstrapping = bootstrapping;
    return bootstrapping;
  }

  Future<AppRuntimeBootstrapResult> _bootstrap() async {
    final result = await _localDataBootstrap.open();
    if (_lifecycle != _AppRuntimeLifecycle.running) {
      throw StateError('Bootstrap завершился после начала shutdown.');
    }

    return switch (result) {
      LocalDataReady(:final database) => await _createReadyGraph(database),
      LocalDataRetryableFailure() => const AppRuntimeRetryableFailure(),
      LocalDataCorruption() => const AppRuntimeCorruption(),
      LocalDataUnexpectedFailure() => const AppRuntimeUnexpectedFailure(),
      LocalDataIncompatibleSchema(
        :final expectedSchemaVersion,
        :final detectedSchemaVersion,
      ) =>
        AppRuntimeIncompatibleSchema(
          expectedSchemaVersion: expectedSchemaVersion,
          detectedSchemaVersion: detectedSchemaVersion,
        ),
    };
  }

  Future<AppRuntimeBootstrapResult> _createReadyGraph(
    AppDatabase database,
  ) async {
    ProviderContainer? container;
    try {
      final repository = _repositoryFactory(database);
      container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      container.read(appRouterProvider);
      _commandCoordinator = coordinator;
      return _ready = AppRuntimeReady(container);
    } on Object {
      container?.dispose();
      await _localDataBootstrap.close();
      return const AppRuntimeUnexpectedFailure();
    }
  }

  Future<void> shutdown() {
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;

    _lifecycle = _AppRuntimeLifecycle.closing;
    final draining = _commandCoordinator?.shutdown() ?? Future<void>.value();
    _ready?.container.dispose();
    final shuttingDown = _finishShutdown(draining);
    _shuttingDown = shuttingDown;
    return shuttingDown;
  }

  Future<void> _finishShutdown(Future<void> draining) async {
    try {
      await draining;
      await _localDataBootstrap.close();
    } finally {
      _lifecycle = _AppRuntimeLifecycle.closed;
    }
  }
}

enum _AppRuntimeLifecycle { running, closing, closed }
