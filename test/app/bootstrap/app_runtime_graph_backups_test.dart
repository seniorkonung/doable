import 'dart:async';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/forwarding_graph_fact_log.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/local_database_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabaseHarness harness;
  late _CloseTrackingObserver database;
  late DateTime now;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    database = _CloseTrackingObserver();
    now = DateTime(2026, 10, 5, 9);
  });

  Future<void> createTag(
    PersonalGraphRepository repository,
    String name,
  ) async {
    expect(
      await repository.execute(
        CreateTag(
          name: TagName.fromInput(name),
          color: null,
          placement: TagPlacement.first,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
  }

  /// Записывает в файл базы тег «Дом», ежедневную копию 5 октября в 09:00 и
  /// после неё теги [tagsAfterBackup].
  Future<void> seedGraph({List<String> tagsAfterBackup = const []}) async {
    final repository = DriftPersonalGraphRepository(
      await harness.openReadyDatabase(),
      UuidV7IntentionIdGenerator(),
      () => now.toUtc(),
      InMemoryDiagnosticsSink(),
    );
    await createTag(repository, 'Дом');
    expect(
      await repository.insertDailyBackup(
        dayStart: DateTime(2026, 10, 5, 3),
        since: null,
      ),
      isTrue,
    );
    for (final name in tagsAfterBackup) {
      await createTag(repository, name);
    }
    await harness.closePersistenceObjectGraph();
  }

  /// Runtime над файлом базы с часами [now]; [hold] задерживает первое
  /// чтение пакетов лога — подсчёт сводки ежедневной копии.
  AppRuntime runtimeWith({_PackageReadHold? hold}) {
    final files = harness.temporaryDirectory.uri;
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(harness.databaseFile),
        database,
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      clock: () => now.toUtc(),
      graphFilesFactory: (log) async => (
        compaction: GraphLogCompaction(
          log: hold == null ? log : _HeldPackageReads(log, hold),
          directory: Directory.fromUri(files.resolve('graph_snapshots/')),
          clock: () => now.toUtc(),
          diagnosticsSink: InMemoryDiagnosticsSink(),
        ),
        temporaryDirectory: Directory.fromUri(files.resolve('tmp/')),
        documents: FileDocumentAccess(harness.temporaryDirectory),
      ),
    );
    addTearDown(runtime.shutdown);
    return runtime;
  }

  /// Наблюдение списка копий: от новых к старым по созданию.
  Stream<List<GraphBackupEntry>> watchBackups(GraphBackupRegistry registry) =>
      registry.watchBackups().map(
        (read) => (read as GraphBackupsReadSucceeded).backups,
      );

  Stream<List<GraphBackupEntry>> watchRuntimeBackups(AppRuntimeReady ready) =>
      watchBackups(
        ready.container.read(personalGraphRepositoryProvider)
            as GraphBackupRegistry,
      );

  /// Уводит приложение в фон и возвращает его на передний план.
  void returnToForeground() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  test('после подготовки хранилища делает ежедневную копию фоном, не '
      'задерживая готовность и команды графа', () async {
    await seedGraph(tagsAfterBackup: ['Дача']);
    now = DateTime(2026, 10, 6, 8, 15);
    final hold = _PackageReadHold();
    final runtime = runtimeWith(hold: hold);

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await hold.reached.future;
    await createTag(
      ready.container.read(personalGraphRepositoryProvider),
      'Сад',
    );
    hold.release();

    final backups = await watchRuntimeBackups(ready)
        .firstWhere((backups) => backups.length == 2);
    expect(backups.first.kind, GraphBackupKind.daily);
    expect(backups.first.madeAt.toLocal(), DateTime(2026, 10, 6, 8, 15));
  });

  test('при возвращении на передний план после смены дня делает ежедневную '
      'копию, только если граф изменялся, а команды копию не делают', () async {
    await seedGraph();
    now = DateTime(2026, 10, 5, 20);
    final runtime = runtimeWith();
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    final graphBackups = ready.container.read(graphBackupsProvider);
    // Копии делаются по одной, поэтому вызов завершается после проверки при
    // запуске.
    await graphBackups.makeDailyBackupIfDue();

    now = DateTime(2026, 10, 6, 8, 15);
    returnToForeground();
    await graphBackups.makeDailyBackupIfDue();
    expect(await watchRuntimeBackups(ready).first, hasLength(1));

    await createTag(
      ready.container.read(personalGraphRepositoryProvider),
      'Дача',
    );
    await pumpEventQueue();
    expect(await watchRuntimeBackups(ready).first, hasLength(1));

    returnToForeground();
    final backups = await watchRuntimeBackups(ready)
        .firstWhere((backups) => backups.length == 2);
    expect(backups.first.kind, GraphBackupKind.daily);
    expect(backups.first.madeAt.toLocal(), DateTime(2026, 10, 6, 8, 15));
  });

  test('выключение дожидается идущего создания ежедневной копии и только '
      'затем закрывает базу', () async {
    await seedGraph(tagsAfterBackup: ['Дача']);
    now = DateTime(2026, 10, 6, 8, 15);
    final hold = _PackageReadHold();
    final runtime = runtimeWith(hold: hold);
    await runtime.bootstrap();
    await hold.reached.future;

    var shutdownCompleted = false;
    final shutdown = runtime.shutdown().then((_) => shutdownCompleted = true);
    await pumpEventQueue();

    expect(shutdownCompleted, isFalse);
    expect(database.closeCalls, 0);

    hold.release();
    await shutdown;

    expect(database.closeCalls, 1);
    final reopened = DriftPersonalGraphRepository(
      await harness.openReadyDatabase(),
      UuidV7IntentionIdGenerator(),
      () => now.toUtc(),
      InMemoryDiagnosticsSink(),
    );
    expect(await watchBackups(reopened).first, hasLength(2));
  });
}

final class _CloseTrackingObserver extends LocalDatabaseConnectionObserver {
  var closeCalls = 0;

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}

/// Задержка первого чтения пакетов лога: [reached] завершается, когда оно
/// начато, а продолжается оно после [release].
final class _PackageReadHold {
  final reached = Completer<void>();
  final _released = Completer<void>();

  void release() => _released.complete();
}

/// Лог фактов, в котором первое чтение пакетов ждёт [_PackageReadHold], а
/// остальные операции выполняет исходный лог.
final class _HeldPackageReads extends ForwardingGraphFactLog {
  _HeldPackageReads(super.source, this._hold);

  _PackageReadHold? _hold;

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) async {
    if (_hold case final hold?) {
      _hold = null;
      hold.reached.complete();
      await hold._released.future;
    }
    return super.readPackages(after: after, upTo: upTo);
  }
}
