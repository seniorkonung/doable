import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase,
        openInMemoryLocalDatabase;
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data_transfer/application/graph_export_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/graph_log_completeness_reference.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/local_database_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory temporary;
  late FileDocumentAccess documents;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('doable_runtime_export_');
    temporary = Directory.fromUri(root.uri.resolve('tmp/'))..createSync();
    documents = FileDocumentAccess(
      Directory.fromUri(root.uri.resolve('documents/'))..createSync(),
    );
  });

  tearDown(() => root.delete(recursive: true));

  /// Runtime с файлами графа в [root]: сжатием с порогом [threshold] и
  /// диагностикой [compactionDiagnostics], которое пишет состояние для
  /// экспорта изолятом [stateWriteRunner], каталогом временных файлов
  /// [temporaryDirectory] и документами [documents].
  AppRuntime runtimeWith({
    LocalDataConnectionFactory connectionFactory = openInMemoryLocalDatabase,
    int threshold = graphLogCompactionThreshold,
    DiagnosticsSink? compactionDiagnostics,
    GraphStateWriteRunner stateWriteRunner = runGraphStateWriteInIsolate,
    Directory? temporaryDirectory,
  }) {
    final runtime = AppRuntime(
      connectionFactory: connectionFactory,
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: (log) async => (
        compaction: GraphLogCompaction(
          log: log,
          directory: Directory.fromUri(root.uri.resolve('graph_snapshots/')),
          clock: () => DateTime.utc(2026, 10, 18, 9),
          diagnosticsSink: compactionDiagnostics ?? InMemoryDiagnosticsSink(),
          threshold: threshold,
          stateWriteRunner: stateWriteRunner,
        ),
        temporaryDirectory: temporaryDirectory ?? temporary,
        documents: documents,
      ),
    );
    addTearDown(runtime.shutdown);
    return runtime;
  }

  /// Завершение следующего экспорта, опубликованное координатором.
  Future<GraphExportCompletion> nextExport(AppRuntime runtime) => runtime
      .commandCoordinator
      .completions
      .where((completion) => completion is GraphExportCompletion)
      .cast<GraphExportCompletion>()
      .first;

  Future<void> startExport(AppRuntimeReady ready) =>
      ready.container.read(graphExportControllerProvider.notifier).start();

  Future<void> confirmTag(AppRuntimeReady ready, String name) async {
    expect(
      await ready.container
          .read(personalGraphRepositoryProvider)
          .execute(
            CreateTag(
              name: TagName.fromInput(name),
              color: null,
              placement: TagPlacement.first,
            ),
          ),
      isA<GraphCommandSucceeded>(),
    );
  }

  test('удаляет временные файлы прежних запусков раньше, чем экспорт пишет '
      'временный файл, не задерживая готовность и команды графа', () async {
    final leftover = File.fromUri(
      temporary.uri.resolve('прерванный экспорт.jsonl.gz'),
    )..createSync();
    final releaseCleanup = Completer<void>();
    final leftoverAtStateWrite = <bool>[];
    final runtime = runtimeWith(
      temporaryDirectory: _ControlledDeletion(
        temporary,
        () => releaseCleanup.future,
      ),
      stateWriteRunner: (write) {
        leftoverAtStateWrite.add(leftover.existsSync());
        return runGraphStateWriteInIsolate(write);
      },
    );

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await confirmTag(ready, 'Дом');
    final exported = nextExport(runtime);
    await startExport(ready);
    await pumpEventQueue();

    // Экспорт принят, но запись временного файла ждёт очистку.
    expect(
      ready.container.read(graphExportControllerProvider),
      isA<GraphExportRunning>(),
    );
    expect(leftoverAtStateWrite, isEmpty);

    releaseCleanup.complete();

    expect((await exported).outcome, GraphExportOutcome.succeeded);
    expect(leftoverAtStateWrite, [false]);
  });

  test('отказ очистки временного каталога не мешает готовности, командам и '
      'экспорту', () async {
    final runtime = runtimeWith(
      temporaryDirectory: _ControlledDeletion(
        temporary,
        () async => throw FileSystemException(
          'Каталог не удалён.',
          temporary.path,
          const OSError('Permission denied', 13),
        ),
      ),
    );

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await confirmTag(ready, 'Дом');
    final exported = nextExport(runtime);
    await startExport(ready);

    expect((await exported).outcome, GraphExportOutcome.succeeded);
  });

  test('экспорт из контейнера готового приложения пишет в документ состояние '
      'на своей позиции, хотя во время экспорта сжатие с небольшим порогом '
      'записало новый снимок и удалило историю до него', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final database = await harness.openReadyDatabase();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.now().toUtc(),
      InMemoryDiagnosticsSink(),
    );
    Future<T> confirm<T extends GraphCommandOutcome>(
      GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
    ) async {
      final result = await repository.execute(command);
      final confirmed =
          (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
              as ConfirmedGraphResult;
      return confirmed.value as T;
    }

    Future<Intention> createIntention(CreateIntention command) async =>
        (await confirm<IntentionSaved>(command)).intention;

    final home = (await confirm<TagCreated>(
      CreateTag(
        name: TagName.fromInput('Дом'),
        color: null,
        placement: TagPlacement.first,
      ),
    )).tag;
    final health = await createIntention(
      CreateIntention.withInitialState(
        title: 'Здоровье',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: {home.id},
      ),
    );
    final running = await createIntention(
      const CreateIntention(title: 'Бегать', description: null),
    );
    await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: health.id,
        relatedIntentionId: running.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    await confirm(ArchiveIntention(running.id));
    final expected = _lines(await referenceGraphRecords(database));
    await harness.closePersistenceObjectGraph();

    final compactions = _CompactionWatch();
    final stateWriteStarted = Completer<void>();
    final releaseStateWrite = Completer<void>();
    // Пять пакетов превышают порог, поэтому сжатие при запуске пишет снимок,
    // который становится базой экспорта, а три команды во время экспорта —
    // снова превышают порог.
    final runtime = runtimeWith(
      connectionFactory: () =>
          openFileBackedLocalDatabase(harness.databaseFile),
      threshold: 2,
      compactionDiagnostics: compactions,
      stateWriteRunner: (write) async {
        stateWriteStarted.complete();
        await releaseStateWrite.future;
        return runGraphStateWriteInIsolate(write);
      },
    );
    final launchCompaction = compactions.finished.first;
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    expect(await launchCompaction, isA<DiagnosticsSucceeded>());

    final exported = nextExport(runtime);
    await startExport(ready);
    await stateWriteStarted.future;
    final compactionDuringExport = compactions.finished.first;
    for (final name in ['Работа', 'Спорт', 'Чтение']) {
      await confirmTag(ready, name);
    }
    expect(await compactionDuringExport, isA<DiagnosticsSucceeded>());
    releaseStateWrite.complete();

    expect((await exported).outcome, GraphExportOutcome.succeeded);
    final reading = await GraphFormatFile.read(
      documents.created.single.openRead(),
    );
    expect(_lines(await reading.records.toList()), expected);
  });

  test('выключение дожидается идущего экспорта и только затем закрывает '
      'базу', () async {
    final database = _CloseTrackingObserver();
    final stateWriteStarted = Completer<void>();
    final releaseStateWrite = Completer<void>();
    final runtime = runtimeWith(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        database,
      ),
      stateWriteRunner: (write) async {
        stateWriteStarted.complete();
        await releaseStateWrite.future;
        return runGraphStateWriteInIsolate(write);
      },
    );
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await confirmTag(ready, 'Дом');
    final exported = nextExport(runtime);
    await startExport(ready);
    await stateWriteStarted.future;

    var shutdownCompleted = false;
    final shutdown = runtime.shutdown().then((_) => shutdownCompleted = true);
    await pumpEventQueue();

    expect(shutdownCompleted, isFalse);
    expect(database.closeCalls, 0);

    releaseStateWrite.complete();
    await shutdown;

    expect(database.closeCalls, 1);
    expect((await exported).outcome, GraphExportOutcome.succeeded);
    final reading = await GraphFormatFile.read(
      documents.created.single.openRead(),
    );
    expect(await reading.records.toList(), [isA<TagRecord>()]);
  });

  test('production удаляет оставшиеся файлы прежних запусков из tmp внутри '
      'app_flutter, пишет туда временный файл экспорта и копирует его в '
      'документ встроенным плагином', () async {
    final applicationDocuments = Directory.fromUri(
      root.uri.resolve('app_flutter/'),
    )..createSync();
    final cache = Directory.fromUri(root.uri.resolve('cache/'))..createSync();
    final productionTemporary = applicationDocuments.uri.resolve('tmp/');
    final leftover = File.fromUri(
      productionTemporary.resolve('прерванный экспорт.jsonl.gz'),
    )..createSync(recursive: true);
    final copiedSources = <({Uri directory, bool exists})>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return switch (call.method) {
        'getTemporaryDirectory' => cache.path,
        'getApplicationDocumentsDirectory' => applicationDocuments.path,
        _ => throw UnsupportedError('Неожиданный вызов path_provider'),
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(pathProviderChannel, null),
    );
    // Канал и его методы — протокол с плагином DocumentAccessPlugin.kt.
    const documentChannel = MethodChannel(
      'software.doable.doable/document_access',
    );
    messenger.setMockMethodCallHandler(documentChannel, (call) async {
      switch (call.method) {
        case 'createDocument':
          return 'content://software.doable.test/document/1';
        case 'writeDocument':
          final source = File(
            (call.arguments as Map<Object?, Object?>)['source']! as String,
          );
          copiedSources.add((
            directory: source.parent.uri,
            exists: source.existsSync(),
          ));
          return null;
      }
      throw UnsupportedError('Неожиданный вызов плагина документов');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(documentChannel, null),
    );
    final runtime = AppRuntime.production();
    addTearDown(runtime.shutdown);

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    final exported = nextExport(runtime);
    await startExport(ready);

    expect((await exported).outcome, GraphExportOutcome.succeeded);
    expect(copiedSources, [(directory: productionTemporary, exists: true)]);
    expect(leftover.existsSync(), isFalse);
    await runtime.shutdown();
  });
}

final class _CloseTrackingObserver extends LocalDatabaseConnectionObserver {
  var closeCalls = 0;

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}

/// Каталог [_directory], удаление которого сначала ждёт [_beforeDelete]:
/// так проверка задерживает очистку или внедряет отказ файловой системы.
final class _ControlledDeletion implements Directory {
  _ControlledDeletion(this._directory, this._beforeDelete);

  final Directory _directory;
  final Future<void> Function() _beforeDelete;

  @override
  Uri get uri => _directory.uri;

  @override
  String get path => _directory.path;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await _beforeDelete();
    return _directory.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Диагностика сжатия лога, которая сообщает об исходе каждого сжатия.
final class _CompactionWatch implements DiagnosticsSink {
  final _finished = StreamController<DiagnosticsStatus>.broadcast(sync: true);

  /// Исходы сжатий в порядке их окончания.
  Stream<DiagnosticsStatus> get finished => _finished.stream;

  @override
  void record(DiagnosticsEvent event) {
    if (event is GraphLogCompactionDiagnosticsEvent) {
      _finished.add(event.status);
    }
  }
}

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
