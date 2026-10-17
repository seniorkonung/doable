import 'dart:async';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory snapshots;
  late InMemoryDiagnosticsSink diagnostics;
  late _CloseTrackingObserver database;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('doable_runtime_snapshots_');
    snapshots = Directory.fromUri(root.uri.resolve('graph_snapshots/'))
      ..createSync();
    diagnostics = InMemoryDiagnosticsSink();
    database = _CloseTrackingObserver();
  });

  tearDown(() => root.delete(recursive: true));

  AppRuntime runtimeWith(AppGraphLogCompactionFactory compactionFactory) {
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        database,
      ),
      diagnosticsSink: diagnostics,
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphLogCompactionFactory: compactionFactory,
    );
    addTearDown(runtime.shutdown);
    return runtime;
  }

  /// Сжатие, для которого каждый пакет после снимка превышает порог.
  /// [readRegistry] заменяет чтение реестра снимков — первое обращение
  /// очистки каталога к базе.
  GraphLogCompaction compactionOver(
    ObservableGraphFactLog log, {
    required Future<Set<String>> Function(GraphFactLog log) readRegistry,
    required GraphSnapshotWriteRunner runner,
  }) => GraphLogCompaction(
    log: _RegistryReadOverride(log, readRegistry),
    directory: snapshots,
    clock: () => DateTime.utc(2026, 10, 17, 9),
    diagnosticsSink: diagnostics,
    threshold: 0,
    runner: runner,
  );

  Future<void> confirmCommand(AppRuntimeReady ready) async {
    expect(
      await ready.container
          .read(personalGraphRepositoryProvider)
          .execute(CreateTag(TagName.fromInput('Тег'))),
      isA<GraphCommandSucceeded>(),
    );
  }

  test('очищает каталог снимков до запуска сжатия, не задерживая готовность '
      'и команды графа', () async {
    final leftover = File.fromUri(
      snapshots.uri.resolve('прерванная запись.jsonl.gz.tmp'),
    )..createSync();
    final cleanupStarted = Completer<void>();
    final releaseCleanup = Completer<void>();
    final leftoverAtWrite = <bool>[];
    final writeStarted = Completer<void>();
    final runtime = runtimeWith(
      (log) async => compactionOver(
        log,
        readRegistry: (log) async {
          cleanupStarted.complete();
          await releaseCleanup.future;
          return log.readSnapshotFileNames();
        },
        runner: (write) {
          leftoverAtWrite.add(leftover.existsSync());
          writeStarted.complete();
          return runGraphSnapshotWriteInIsolate(write);
        },
      ),
    );

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await cleanupStarted.future;
    await confirmCommand(ready);
    await pumpEventQueue();

    // Пакет после снимка уже превышает порог, но сжатие ждёт очистку.
    expect(leftoverAtWrite, isEmpty);

    releaseCleanup.complete();
    await writeStarted.future;
    await runtime.shutdown();

    expect(leftoverAtWrite, [false]);
  });

  test('выключение дожидается идущего сжатия и только затем закрывает '
      'базу', () async {
    final commandConfirmed = Completer<void>();
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final runtime = runtimeWith(
      (log) async => compactionOver(
        log,
        // Сжатие сверяет порог уже после пакета команды.
        readRegistry: (log) async {
          await commandConfirmed.future;
          return log.readSnapshotFileNames();
        },
        runner: (write) async {
          writeStarted.complete();
          await releaseWrite.future;
          return runGraphSnapshotWriteInIsolate(write);
        },
      ),
    );
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await confirmCommand(ready);
    commandConfirmed.complete();
    await writeStarted.future;

    var shutdownCompleted = false;
    final shutdown = runtime.shutdown().then((_) => shutdownCompleted = true);
    await pumpEventQueue();

    expect(shutdownCompleted, isFalse);
    expect(database.closeCalls, 0);

    releaseWrite.complete();
    await shutdown;

    expect(database.closeCalls, 1);
    expect(
      diagnostics.events.whereType<GraphLogCompactionDiagnosticsEvent>().map(
        (event) => event.status,
      ),
      [isA<DiagnosticsSucceeded>()],
    );
  });

  test('отказ очистки не мешает командам, сжатию и выключению', () async {
    final commandConfirmed = Completer<void>();
    final writeStarted = Completer<void>();
    final runtime = runtimeWith(
      (log) async => compactionOver(
        log,
        readRegistry: (_) async {
          await commandConfirmed.future;
          throw SqliteException(
            extendedResultCode: SqlError.SQLITE_IOERR,
            message: 'реестр снимков не прочитан',
          );
        },
        runner: (write) {
          writeStarted.complete();
          return runGraphSnapshotWriteInIsolate(write);
        },
      ),
    );

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await confirmCommand(ready);
    commandConfirmed.complete();
    await writeStarted.future;
    await runtime.shutdown();

    expect(database.closeCalls, 1);
  });

  test('production размещает снимки в graph_snapshots внутри '
      'app_flutter', () async {
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    final applicationDocuments = Directory.fromUri(
      root.uri.resolve('app_flutter/'),
    )..createSync();
    final temporary = Directory.fromUri(root.uri.resolve('cache/'))
      ..createSync();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return switch (call.method) {
        'getTemporaryDirectory' => temporary.path,
        'getApplicationDocumentsDirectory' => applicationDocuments.path,
        _ => throw UnsupportedError('Неожиданный вызов path_provider'),
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(pathProviderChannel, null),
    );
    final leftover = File.fromUri(
      applicationDocuments.uri.resolve(
        'graph_snapshots/прерванная запись.jsonl.gz.tmp',
      ),
    )..createSync(recursive: true);
    final runtime = AppRuntime.production();
    addTearDown(runtime.shutdown);

    expect(await runtime.bootstrap(), isA<AppRuntimeReady>());
    await runtime.shutdown();

    expect(leftover.existsSync(), isFalse);
  });
}

final class _CloseTrackingObserver extends LocalDatabaseConnectionObserver {
  var closeCalls = 0;

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}

/// Лог фактов, в котором чтение реестра снимков выполняет
/// [_readSnapshotFileNames], а остальные операции — исходный лог.
final class _RegistryReadOverride implements ObservableGraphFactLog {
  const _RegistryReadOverride(this._log, this._readSnapshotFileNames);

  final ObservableGraphFactLog _log;
  final Future<Set<String>> Function(GraphFactLog log) _readSnapshotFileNames;

  @override
  Stream<int> get confirmedPositions => _log.confirmedPositions;

  @override
  Future<int> readCurrentPosition() => _log.readCurrentPosition();

  @override
  Future<List<StoredGraphFactPackage>> readPackages({
    required int after,
    required int upTo,
  }) => _log.readPackages(after: after, upTo: upTo);

  @override
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after}) =>
      _log.readGraphRecords(after: after);

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) =>
      _log.readSnapshotAtOrBefore(position);

  @override
  Future<Set<String>> readSnapshotFileNames() => _readSnapshotFileNames(_log);

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) =>
      _log.registerSnapshot(snapshot);

  @override
  Future<List<String>> removeHistoryBefore(int boundary) =>
      _log.removeHistoryBefore(boundary);
}
