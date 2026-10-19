import 'dart:async';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/data_transfer/application/graph_composition_provider.dart';
import 'package:doable/src/data_transfer/application/graph_export_provider.dart';
import 'package:doable/src/data_transfer/application/graph_import_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/graph_import_files.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory temporary;
  late FileDocumentAccess documents;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('doable_runtime_import_');
    temporary = Directory.fromUri(root.uri.resolve('tmp/'))..createSync();
    documents = FileDocumentAccess(
      Directory.fromUri(root.uri.resolve('documents/'))..createSync(),
    );
    final chosen = File.fromUri(root.uri.resolve('chosen.jsonl.gz'))
      ..writeAsBytesSync(graphExportFileOf(referenceGraphFileLines()));
    documents.openingDialog = () async => documents.chosen(chosen);
  });

  tearDown(() => root.delete(recursive: true));

  /// Runtime с файлами графа в [root]: сжатием, которое пишет состояние для
  /// экспорта изолятом [stateWriteRunner], а снимок замены —
  /// [replacementSnapshotRunner], каталогом временных файлов
  /// [temporaryDirectory] и документами [documents].
  AppRuntime runtimeWith({
    LocalDataConnectionFactory connectionFactory = openInMemoryLocalDatabase,
    GraphStateWriteRunner stateWriteRunner = runGraphStateWriteInIsolate,
    GraphReplacementSnapshotWriteRunner replacementSnapshotRunner =
        runGraphReplacementSnapshotWriteInIsolate,
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
          clock: () => DateTime.utc(2026, 10, 19, 9),
          diagnosticsSink: InMemoryDiagnosticsSink(),
          stateWriteRunner: stateWriteRunner,
          replacementSnapshotRunner: replacementSnapshotRunner,
        ),
        temporaryDirectory: temporaryDirectory ?? temporary,
        documents: documents,
      ),
    );
    addTearDown(runtime.shutdown);
    return runtime;
  }

  /// Дожидается, пока импорт в контейнере [ready] ждёт подтверждения.
  Future<void> awaitConfirmation(AppRuntimeReady ready) {
    final awaiting = Completer<void>();
    final subscription = ready.container.listen(graphImportControllerProvider, (
      _,
      state,
    ) {
      if (state is GraphImportAwaitingConfirmation && !awaiting.isCompleted) {
        awaiting.complete();
      }
    });
    return awaiting.future.whenComplete(subscription.close);
  }

  test('временный каталог очищается при запуске один раз, экспорт и импорт '
      'пишут временные файлы только после очистки, а импорт заменяет граф '
      'записями выбранного файла', () async {
    final leftover = File.fromUri(
      temporary.uri.resolve('прерванный импорт.jsonl.gz'),
    )..createSync();
    final releaseCleanup = Completer<void>();
    final cleanup = _HeldDeletion(temporary, () => releaseCleanup.future);
    final leftoverAtStateWrite = <bool>[];
    final leftoverAtDocumentCopy = <bool>[];
    documents.beforeCopy = () async =>
        leftoverAtDocumentCopy.add(leftover.existsSync());
    final runtime = runtimeWith(
      temporaryDirectory: cleanup,
      stateWriteRunner: (write) {
        leftoverAtStateWrite.add(leftover.existsSync());
        return runGraphStateWriteInIsolate(write);
      },
    );
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    final container = ready.container;
    expect(
      await container
          .read(personalGraphRepositoryProvider)
          .execute(CreateTag(TagName.fromInput('Дом'))),
      isA<GraphCommandSucceeded>(),
    );
    final confirmation = awaitConfirmation(ready);
    final importing = container
        .read(graphImportControllerProvider.notifier)
        .start();
    final exported = runtime.commandCoordinator.completions
        .where((completion) => completion is GraphExportCompletion)
        .cast<GraphExportCompletion>()
        .first;
    await container.read(graphExportControllerProvider.notifier).start();
    await pumpEventQueue();

    // Экспорт принят, а импорт начат, но оба ждут очистку.
    expect(leftoverAtStateWrite, isEmpty);
    expect(leftoverAtDocumentCopy, isEmpty);

    releaseCleanup.complete();

    expect((await exported).outcome, GraphExportOutcome.succeeded);
    await confirmation;
    container.read(graphImportControllerProvider.notifier).confirm();
    expect(await (await importing)!.future, isA<GraphImported>());
    expect(leftoverAtStateWrite, [false]);
    expect(leftoverAtDocumentCopy, [false]);
    expect(cleanup.deletions, 1);
    expect(
      await container
          .read(graphCompositionSourceProvider)
          .watchComposition()
          .first,
      isA<GraphCompositionReadSucceeded>().having(
        (read) => read.composition,
        'состав',
        const GraphComposition(
          intentionCount: 4,
          relationCount: 3,
          dailyChoiceCount: 2,
          tagCount: 2,
        ),
      ),
    );
  });

  test('выключение дожидается импорта, принятого координатором, и только '
      'затем закрывает базу', () async {
    final database = _CloseTrackingObserver();
    final snapshotWriteStarted = Completer<void>();
    final releaseSnapshotWrite = Completer<void>();
    final runtime = runtimeWith(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        database,
      ),
      replacementSnapshotRunner: (write) async {
        snapshotWriteStarted.complete();
        await releaseSnapshotWrite.future;
        return runGraphReplacementSnapshotWriteInIsolate(write);
      },
    );
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    final accepted = await ready.container
        .read(graphImportControllerProvider.notifier)
        .start();
    await snapshotWriteStarted.future;

    var shutdownCompleted = false;
    final shutdown = runtime.shutdown().then((_) => shutdownCompleted = true);
    await pumpEventQueue();

    expect(shutdownCompleted, isFalse);
    expect(database.closeCalls, 0);

    releaseSnapshotWrite.complete();
    await shutdown;

    expect(database.closeCalls, 1);
    expect(await accepted!.future, isA<GraphImported>());
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
/// так проверка задерживает очистку и считает удаления.
final class _HeldDeletion implements Directory {
  _HeldDeletion(this._directory, this._beforeDelete);

  final Directory _directory;
  final Future<void> Function() _beforeDelete;
  var deletions = 0;

  @override
  Uri get uri => _directory.uri;

  @override
  String get path => _directory.path;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deletions += 1;
    await _beforeDelete();
    return _directory.delete(recursive: recursive);
  }

  @override
  Future<Directory> create({bool recursive = false}) =>
      _directory.create(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
