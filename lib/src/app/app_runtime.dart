import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/local/app_database.dart'
    show AppDatabase, openAndroidProductionDatabaseConnection;
import '../data/local/bootstrap/local_data_bootstrap.dart';
import '../data/local/bootstrap/local_data_bootstrap_result.dart';
import '../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../data_transfer/application/document_access.dart';
import '../data_transfer/application/graph_composition.dart';
import '../data_transfer/application/graph_composition_provider.dart';
import '../data_transfer/application/graph_export.dart';
import '../data_transfer/application/graph_export_provider.dart';
import '../data_transfer/application/graph_replacement.dart';
import '../data_transfer/application/graph_restore.dart';
import '../data_transfer/application/graph_restore_provider.dart';
import '../data_transfer/data/method_channel_document_access.dart';
import '../graph/application/graph_command_coordinator.dart';
import '../graph/application/personal_graph_repository.dart';
import '../graph/application/personal_graph_repository_provider.dart';
import '../graph/data/drift_personal_graph_repository.dart';
import '../graph_backups/graph_backup_registry.dart';
import '../graph_backups/graph_backups.dart';
import '../graph_backups/graph_backups_provider.dart';
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

/// Файлы графа вне базы: сжатие лога фактов в снимки, каталог временных
/// файлов операций с данными и документы, которые человек выбирает
/// системными диалогами.
typedef AppGraphFiles = ({
  GraphLogCompaction compaction,
  Directory temporaryDirectory,
  DocumentAccess documents,
});

/// Создаёт файлы готового графа над его логом фактов [log].
typedef AppGraphFilesFactory = Future<AppGraphFiles> Function(
  ObservableGraphFactLog log,
);

/// Граф над готовой базой: репозиторий, а также лог фактов, состав графа,
/// реестр копий и замена графа, если их ведёт этот репозиторий.
typedef _AppGraph = ({
  PersonalGraphRepository repository,
  ObservableGraphFactLog? factLog,
  GraphCompositionSource? composition,
  GraphBackupRegistry? backupRegistry,
  GraphReplacement? replacement,
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
  /// [graphFilesFactory] подключает файлы графа вне базы. После подготовки
  /// хранилища runtime удаляет временные файлы прежних запусков, очищает
  /// каталог снимков и затем запускает сжатие лога фактов. Экспорт графа
  /// пишет состояние через то же сжатие и начинает запись временного файла
  /// только после удаления временных файлов прежних запусков. Резервные
  /// копии ведутся над тем же сжатием: после подготовки хранилища и при
  /// каждом возвращении приложения на передний план runtime проверяет фоном,
  /// нужна ли ежедневная копия. Восстановление копии пишет снимок замены
  /// через то же сжатие только после очистки каталога снимков и заменяет граф
  /// репозиторием в монопольном режиме координатора. Выключение дожидается
  /// идущего экспорта, восстановления, сжатия и создания копии и только потом
  /// закрывает базу.
  /// Лог фактов, состав графа, реестр копий и замену графа ведёт репозиторий
  /// по умолчанию, поэтому с [repositoryFactory] файлы графа, состав графа и
  /// копии не подключаются.
  /// [clock] заменяет системные часы как часы устройства для репозитория по
  /// умолчанию, экспорта и резервных копий.
  factory AppRuntime({
    required LocalDataConnectionFactory connectionFactory,
    required DiagnosticsSink diagnosticsSink,
    required QuickCreationModeStore quickCreationModeStore,
    AppPersonalGraphRepositoryFactory? repositoryFactory,
    AppGraphFilesFactory? graphFilesFactory,
    DailyChoiceLocalDateSource? dailyChoiceLocalDateSource,
    DateTime Function()? clock,
  }) {
    assert(
      repositoryFactory == null || graphFilesFactory == null,
      'Файлы графа ведутся над логом фактов репозитория по умолчанию.',
    );
    final readClock = clock ?? () => DateTime.now().toUtc();
    final _AppGraphFactory graphFactory = switch (repositoryFactory) {
      final createRepository? => (database) => (
        repository: createRepository(database),
        factLog: null,
        composition: null,
        backupRegistry: null,
        replacement: null,
      ),
      null => (database) {
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          readClock,
          diagnosticsSink,
          relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
        );
        return (
          repository: repository,
          factLog: repository,
          composition: repository,
          backupRegistry: repository,
          replacement: repository,
        );
      },
    };
    return AppRuntime._(
      LocalDataBootstrap(
        connectionFactory: connectionFactory,
        diagnosticsSink: diagnosticsSink,
      ),
      graphFactory,
      graphFilesFactory,
      dailyChoiceLocalDateSource ?? readDeviceLocalDay,
      quickCreationModeStore,
      diagnosticsSink,
      readClock,
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
      graphFilesFactory: (log) async {
        final applicationDocuments = await getApplicationDocumentsDirectory();
        return (
          compaction: GraphLogCompaction(
            log: log,
            directory: GraphSnapshotStore.directoryIn(applicationDocuments),
            clock: () => DateTime.now().toUtc(),
            diagnosticsSink: diagnosticsSink,
          ),
          // Внутри app_flutter, поэтому исключён из backup и transfer.
          temporaryDirectory: Directory.fromUri(
            applicationDocuments.uri.resolve('tmp/'),
          ),
          documents: const MethodChannelDocumentAccess(),
        );
      },
    );
  }

  AppRuntime._(
    this._localDataBootstrap,
    this._graphFactory,
    this._graphFilesFactory,
    this._dailyChoiceLocalDateSource,
    this._quickCreationModeStore,
    this._diagnosticsSink,
    this._clock,
  );

  final LocalDataBootstrap _localDataBootstrap;
  final _AppGraphFactory _graphFactory;
  final AppGraphFilesFactory? _graphFilesFactory;
  final DailyChoiceLocalDateSource _dailyChoiceLocalDateSource;
  final QuickCreationModeStore _quickCreationModeStore;
  final DiagnosticsSink _diagnosticsSink;
  final DateTime Function() _clock;
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

  /// Сообщает о возвращениях приложения на передний план, пока выключение не
  /// началось.
  AppLifecycleListener? _foregroundReturns;

  /// Последняя запущенная проверка ежедневной копии. Копии делаются по
  /// одной, поэтому она завершается после всех предыдущих.
  Future<void>? _dailyGraphBackup;
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
      final (
        :repository,
        :factLog,
        :composition,
        :backupRegistry,
        :replacement,
      ) = _graphFactory(
        database,
      );
      final files = switch ((factLog, _graphFilesFactory)) {
        (final log?, final createFiles?) => await createFiles(log),
        _ => null,
      };
      if (_lifecycle != _AppRuntimeLifecycle.running) {
        throw StateError('Файлы графа созданы после начала shutdown.');
      }
      final export = switch (files) {
        final files? => GraphExport(
          documents: files.documents,
          compaction: files.compaction,
          temporaryDirectory: _removeTemporaryFiles(files.temporaryDirectory),
          clock: _clock,
          diagnosticsSink: _diagnosticsSink,
        ),
        null => null,
      };
      final backups = switch ((files, backupRegistry)) {
        (final files?, final registry?) => GraphBackups(
          registry: registry,
          compaction: files.compaction,
          clock: _clock,
          diagnosticsSink: _diagnosticsSink,
        ),
        _ => null,
      };
      final snapshotFilesCleaned = Completer<void>();
      final restore = switch ((files, backupRegistry, replacement)) {
        (final files?, final registry?, final replacement?) => GraphRestore(
          backups: registry,
          compaction: files.compaction,
          replacement: replacement,
          snapshotFiles: snapshotFilesCleaned.future,
        ),
        _ => null,
      };
      container = ProviderContainer(
        overrides: [
          quickCreationModeControllerProvider.overrideWith(
            () => QuickCreationModeController(
              initialMode: initialMode,
              store: _quickCreationModeStore,
            ),
          ),
          personalGraphRepositoryProvider.overrideWithValue(repository),
          if (composition != null)
            graphCompositionSourceProvider.overrideWithValue(composition),
          dailyChoiceLocalDateSourceProvider.overrideWithValue(
            _dailyChoiceLocalDateSource,
          ),
          if (export != null)
            graphExportControllerProvider.overrideWith(
              () => GraphExportController(export),
            ),
          if (backups != null) graphBackupsProvider.overrideWithValue(backups),
          if (restore != null)
            graphRestoreControllerProvider.overrideWith(
              () => GraphRestoreController(restore),
            ),
        ],
        retry: (retryCount, error) => null,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      container.read(appRouterProvider);
      _commandCoordinator = coordinator;
      if (files != null) {
        _graphSnapshots = _startGraphSnapshots(
          files.compaction,
          cleaned: snapshotFilesCleaned,
        );
      }
      if (backups != null) _startDailyGraphBackups(backups);
      return _ready = AppRuntimeReady(container);
    } on Object {
      container?.dispose();
      await _localDataBootstrap.close();
      return const AppRuntimeUnexpectedFailure();
    }
  }

  /// Удаляет каталог временных файлов [directory] вместе с файлами,
  /// которые оставили прерванные операции прежних запусков; операция этого
  /// запуска создаёт каталог заново. Завершается каталогом, в который можно
  /// писать временные файлы этого запуска. Готовность и команды графа этого
  /// не ждут.
  Future<Directory> _removeTemporaryFiles(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Каталога нет, или часть файлов не удалена. Оставшиеся файлы
      // операциям не мешают, их удалит очистка следующего запуска.
    }
    return directory;
  }

  /// Очищает каталог снимков, завершает [cleaned] и затем, если выключение
  /// ещё не началось, запускает сжатие лога фактов [compaction]. Готовность
  /// и команды графа этого не ждут.
  Future<GraphLogCompaction?> _startGraphSnapshots(
    GraphLogCompaction compaction, {
    required Completer<void> cleaned,
  }) async {
    try {
      await compaction.removeUnregisteredFiles();
    } on Object {
      // Отказ записан диагностикой очистки. Оставшиеся файлы сжатию и
      // снимку замены не мешают, их удалит очистка следующего запуска.
    }
    cleaned.complete();
    if (_lifecycle != _AppRuntimeLifecycle.running) return null;
    return compaction..start();
  }

  /// Проверяет, нужна ли ежедневная копия [backups], сейчас и при каждом
  /// возвращении приложения на передний план, пока выключение не началось.
  /// Готовность и команды графа проверки не ждут, а её отказ сообщается
  /// исходом и не мешает работе.
  void _startDailyGraphBackups(GraphBackups backups) {
    void makeDailyBackupIfDue() =>
        _dailyGraphBackup = backups.makeDailyBackupIfDue();
    _foregroundReturns = AppLifecycleListener(onResume: makeDailyBackupIfDue);
    makeDailyBackupIfDue();
  }

  Future<void> shutdown() {
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;

    _lifecycle = _AppRuntimeLifecycle.closing;
    _foregroundReturns?.dispose();
    // Координатор дожидается принятых команд и идущего экспорта.
    final draining = _commandCoordinator?.shutdown() ?? Future<void>.value();
    final compacting = _stopGraphSnapshots();
    final backingUp = _dailyGraphBackup ?? Future<void>.value();
    _ready?.container.dispose();
    final shuttingDown = _finishShutdown(draining, compacting, backingUp);
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
    Future<void> backingUp,
  ) async {
    try {
      await draining;
      await compacting;
      await backingUp;
      await _localDataBootstrap.close();
    } finally {
      _lifecycle = _AppRuntimeLifecycle.closed;
    }
  }
}

enum _AppRuntimeLifecycle { running, closing, closed }
