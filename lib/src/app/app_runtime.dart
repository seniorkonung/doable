import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/local/app_database.dart';
import '../data/local/bootstrap/local_data_bootstrap.dart';
import '../data/local/bootstrap/local_data_bootstrap_result.dart';
import '../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../graph/application/graph_command_coordinator.dart';
import '../graph/application/personal_graph_repository.dart';
import '../graph/application/personal_graph_repository_provider.dart';
import '../graph/data/drift_personal_graph_repository.dart';
import '../graph_snapshots/graph_fact_log.dart';
import '../graph_snapshots/graph_log_compaction.dart';
import '../graph_snapshots/graph_snapshot_store.dart';
import '../intention/application/intention_id_generator.dart';
import '../long_term_relation/application/long_term_relation_id_generator.dart';
import '../shared/diagnostics/developer_diagnostics_sink.dart';
import '../shared/diagnostics/diagnostics_sink.dart';
import 'quick_creation/file_quick_creation_mode_store.dart';
import 'quick_creation/quick_creation_mode.dart';
import 'quick_creation/quick_creation_mode_controller.dart';
import 'quick_creation/quick_creation_mode_store.dart';
import 'routing/app_router_provider.dart';

typedef AppPersonalGraphRepositoryFactory = PersonalGraphRepository Function(
  AppDatabase database,
);

/// Создаёт сжатие лога фактов готового графа над его логом [log].
typedef AppGraphLogCompactionFactory = Future<GraphLogCompaction> Function(
  ObservableGraphFactLog log,
);

/// Граф над готовой базой: репозиторий и лог фактов, если его ведёт этот
/// репозиторий.
typedef _AppGraph = ({
  PersonalGraphRepository repository,
  ObservableGraphFactLog? factLog,
});

typedef _AppGraphFactory = _AppGraph Function(AppDatabase database);

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
  /// [dailyChoiceLocalDateSource] заменяет часы устройства как источник
  /// локального сегодня каталога дневных выборов во всём контейнере приложения;
  /// без него используется [readDeviceLocalDay].
  /// [quickCreationModeStore] принадлежит этому runtime и обслуживает единый
  /// контроллер независимо от подготовки и команд личного графа.
  /// [graphLogCompactionFactory] подключает снимки графа: после подготовки
  /// хранилища runtime очищает каталог снимков и затем запускает сжатие лога
  /// фактов, а выключение дожидается сжатия и только потом закрывает базу.
  /// Лог фактов ведёт репозиторий по умолчанию, поэтому с
  /// [repositoryFactory] сжатие не подключается.
  factory AppRuntime({
    required LocalDataConnectionFactory connectionFactory,
    required DiagnosticsSink diagnosticsSink,
    required QuickCreationModeStore quickCreationModeStore,
    AppPersonalGraphRepositoryFactory? repositoryFactory,
    AppGraphLogCompactionFactory? graphLogCompactionFactory,
    DailyChoiceLocalDateSource? dailyChoiceLocalDateSource,
  }) {
    assert(
      repositoryFactory == null || graphLogCompactionFactory == null,
      'Сжатие ведётся над логом фактов репозитория по умолчанию.',
    );
    final _AppGraphFactory graphFactory = switch (repositoryFactory) {
      final createRepository? => (database) => (
        repository: createRepository(database),
        factLog: null,
      ),
      null => (database) {
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.now().toUtc(),
          diagnosticsSink,
          relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
        );
        return (repository: repository, factLog: repository);
      },
    };
    return AppRuntime._(
      LocalDataBootstrap(
        connectionFactory: connectionFactory,
        diagnosticsSink: diagnosticsSink,
      ),
      graphFactory,
      graphLogCompactionFactory,
      dailyChoiceLocalDateSource ?? readDeviceLocalDay,
      quickCreationModeStore,
    );
  }

  factory AppRuntime.production() {
    final diagnosticsSink = DeveloperDiagnosticsSink();
    return AppRuntime(
      connectionFactory: openAndroidProductionDatabaseConnection,
      diagnosticsSink: diagnosticsSink,
      // На Android это app_flutter, исключённый из backup и transfer.
      // https://pub.dev/documentation/path_provider/latest/path_provider/getApplicationDocumentsDirectory.html
      quickCreationModeStore: FileQuickCreationModeStore.withDirectoryProvider(
        localDataDirectoryProvider: getApplicationDocumentsDirectory,
        diagnosticsSink: diagnosticsSink,
      ),
      graphLogCompactionFactory: (log) async => GraphLogCompaction(
        log: log,
        directory: GraphSnapshotStore.directoryIn(
          await getApplicationDocumentsDirectory(),
        ),
        clock: () => DateTime.now().toUtc(),
        diagnosticsSink: diagnosticsSink,
      ),
    );
  }

  AppRuntime._(
    this._localDataBootstrap,
    this._graphFactory,
    this._graphLogCompactionFactory,
    this._dailyChoiceLocalDateSource,
    this._quickCreationModeStore,
  );

  final LocalDataBootstrap _localDataBootstrap;
  final _AppGraphFactory _graphFactory;
  final AppGraphLogCompactionFactory? _graphLogCompactionFactory;
  final DailyChoiceLocalDateSource _dailyChoiceLocalDateSource;
  final QuickCreationModeStore _quickCreationModeStore;
  // Одна загрузка и одна очередь на runtime, в том числе при повторе bootstrap.
  late final Future<QuickCreationMode> _initialQuickCreationMode =
      _quickCreationModeStore.read();
  var _lifecycle = _AppRuntimeLifecycle.running;
  Future<AppRuntimeBootstrapResult>? _bootstrapping;
  AppRuntimeReady? _ready;
  GraphCommandCoordinator? _commandCoordinator;

  /// Запуск снимков графа: завершается запущенным сжатием либо `null`, если
  /// сжатие не запущено.
  Future<GraphLogCompaction?>? _graphSnapshots;
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
    final loadingMode = _initialQuickCreationMode;
    final result = await _localDataBootstrap.open();
    if (_lifecycle != _AppRuntimeLifecycle.running) {
      throw StateError('Bootstrap завершился после начала shutdown.');
    }

    return switch (result) {
      LocalDataReady(:final database) => await _createReadyGraph(
        database,
        loadingMode,
      ),
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
    Future<QuickCreationMode> loadingMode,
  ) async {
    final initialMode = await loadingMode;
    if (_lifecycle != _AppRuntimeLifecycle.running) {
      throw StateError('Режим загружен после начала shutdown.');
    }
    ProviderContainer? container;
    try {
      final (:repository, :factLog) = _graphFactory(database);
      container = ProviderContainer(
        overrides: [
          quickCreationModeControllerProvider.overrideWith(
            () => QuickCreationModeController(
              initialMode: initialMode,
              store: _quickCreationModeStore,
            ),
          ),
          personalGraphRepositoryProvider.overrideWithValue(repository),
          dailyChoiceLocalDateSourceProvider.overrideWithValue(
            _dailyChoiceLocalDateSource,
          ),
        ],
        retry: (retryCount, error) => null,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      container.read(appRouterProvider);
      _commandCoordinator = coordinator;
      if ((factLog, _graphLogCompactionFactory) case (
        final log?,
        final createCompaction?,
      )) {
        _graphSnapshots = _startGraphSnapshots(createCompaction, log);
      }
      return _ready = AppRuntimeReady(container);
    } on Object {
      container?.dispose();
      await _localDataBootstrap.close();
      return const AppRuntimeUnexpectedFailure();
    }
  }

  /// Очищает каталог снимков и затем, если выключение ещё не началось,
  /// запускает сжатие лога фактов. Готовность и команды графа этого не ждут.
  Future<GraphLogCompaction?> _startGraphSnapshots(
    AppGraphLogCompactionFactory createCompaction,
    ObservableGraphFactLog log,
  ) async {
    final GraphLogCompaction compaction;
    try {
      compaction = await createCompaction(log);
    } on Object {
      // Без каталога снимков сжатие не запускается; следующий запуск
      // пробует снова.
      return null;
    }
    try {
      await compaction.removeUnregisteredFiles();
    } on Object {
      // Отказ записан диагностикой очистки. Оставшиеся файлы сжатию не
      // мешают, их удалит очистка следующего запуска.
    }
    if (_lifecycle != _AppRuntimeLifecycle.running) return null;
    return compaction..start();
  }

  Future<void> shutdown() {
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;

    _lifecycle = _AppRuntimeLifecycle.closing;
    final draining = _commandCoordinator?.shutdown() ?? Future<void>.value();
    final compacting = _stopGraphSnapshots();
    _ready?.container.dispose();
    final shuttingDown = _finishShutdown(draining, compacting);
    _shuttingDown = shuttingDown;
    return shuttingDown;
  }

  /// Дожидается очистки каталога снимков и идущего сжатия; новые пакеты
  /// сжатие больше не запускают.
  Future<void> _stopGraphSnapshots() async {
    final compaction = await _graphSnapshots;
    await compaction?.shutdown();
  }

  Future<void> _finishShutdown(
    Future<void> draining,
    Future<void> compacting,
  ) async {
    try {
      await draining;
      await compacting;
      await _localDataBootstrap.close();
    } finally {
      _lifecycle = _AppRuntimeLifecycle.closed;
    }
  }
}

enum _AppRuntimeLifecycle { running, closing, closed }
