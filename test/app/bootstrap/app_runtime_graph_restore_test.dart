import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openFileBackedLocalDatabase;
import 'package:doable/src/data_transfer/application/graph_restore_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/graph_log_completeness_reference.dart';
import '../../support/held_snapshot_cleanup_fact_log.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/local_database_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabaseHarness harness;
  late Directory snapshots;
  final now = DateTime.utc(2026, 10, 18, 9);

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    )..createSync();
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

  test('восстановление копии из контейнера готового приложения пишет снимок '
      'замены только после очистки каталога снимков и заменяет граф '
      'состоянием копии', () async {
    final database = await harness.openReadyDatabase();
    final seeded = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
    await createTag(seeded, 'Дом');
    await seeded.insertManualBackup(since: null);
    final backupState = _lines(await referenceGraphRecords(database));
    await createTag(seeded, 'Сад');
    await harness.closePersistenceObjectGraph();
    final leftover = File.fromUri(
      snapshots.uri.resolve('прерванная запись.jsonl.gz.tmp'),
    )..createSync();
    final cleanupStarted = Completer<void>();
    final releaseCleanup = Completer<void>();
    final leftoverAtSnapshotWrite = <bool>[];
    final runtime = AppRuntime(
      connectionFactory: () =>
          openFileBackedLocalDatabase(harness.databaseFile),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      clock: () => now,
      graphFilesFactory: (log) async => (
        compaction: GraphLogCompaction(
          log: HeldSnapshotCleanupFactLog(log, () async {
            cleanupStarted.complete();
            await releaseCleanup.future;
          }),
          directory: snapshots,
          clock: () => now,
          diagnosticsSink: InMemoryDiagnosticsSink(),
          replacementSnapshotRunner: (write) {
            leftoverAtSnapshotWrite.add(leftover.existsSync());
            return runGraphReplacementSnapshotWriteInIsolate(write);
          },
        ),
        temporaryDirectory: Directory.fromUri(
          harness.temporaryDirectory.uri.resolve('tmp/'),
        ),
        documents: FileDocumentAccess(harness.temporaryDirectory),
      ),
    );
    addTearDown(runtime.shutdown);

    final ready = await runtime.bootstrap() as AppRuntimeReady;
    await cleanupStarted.future;
    final registry = ready.container.read(
      personalGraphRepositoryProvider,
    ) as GraphBackupRegistry;
    final backup = switch (await registry.watchBackups().first) {
      GraphBackupsReadSucceeded(:final backups) => backups.singleWhere(
        (backup) => backup.kind == GraphBackupKind.manual,
      ),
      GraphBackupsReadFailed() => throw TestFailure('Копии не прочитаны.'),
    };
    final accepted =
        ready.container
                .read(graphRestoreControllerProvider.notifier)
                .start(backup)
            as GraphBackupRestoreAccepted;
    await pumpEventQueue();

    // Восстановление принято, но запись снимка замены ждёт очистку.
    expect(leftoverAtSnapshotWrite, isEmpty);

    releaseCleanup.complete();

    expect(await accepted.future, isA<GraphBackupRestored>());
    expect(leftoverAtSnapshotWrite, [false]);
    await runtime.shutdown();
    expect(
      _lines(await referenceGraphRecords(await harness.openReadyDatabase())),
      backupState,
    );
  });
}

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
