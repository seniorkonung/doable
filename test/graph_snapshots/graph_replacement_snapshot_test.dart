import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/failing_snapshot_temporary_files.dart';
import '../support/forwarding_graph_fact_log.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

/// Порог проверок: несколько пакетов вместо производственного значения.
const _threshold = 3;

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late _CompactionOutcomes outcomes;
  var now = DateTime.utc(2026, 10, 18, 9);
  var tagNumber = 0;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    outcomes = _CompactionOutcomes();
  });

  tearDown(() => harness.dispose());

  GraphLogCompaction compactionOver(
    ObservableGraphFactLog log, {
    GraphReplacementSnapshotWriteRunner replacementSnapshotRunner =
        runGraphReplacementSnapshotWriteInIsolate,
  }) => GraphLogCompaction(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: outcomes,
    threshold: _threshold,
    replacementSnapshotRunner: replacementSnapshotRunner,
  );

  GraphSnapshotStore store() => GraphSnapshotStore(
    log: repository,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: InMemoryDiagnosticsSink(),
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

  Future<Tag> createTag(String name, {TagColor? color}) async =>
      (await confirm<TagCreated>(
        CreateTag(
          name: TagName.fromInput(name),
          color: color,
          placement: TagPlacement.first,
        ),
      )).tag;

  Future<Intention> createIntention(
    String title, {
    Set<TagId> tagIds = const {},
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: IntentionReadiness.notReady,
      tagIds: tagIds,
    ),
  )).intention;

  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      tagNumber++;
      await createTag('Тег $tagNumber');
    }
    // Сигнал о пакете доходит до сжатия после подтверждения команды.
    await pumpEventQueue();
  }

  /// Пишет снимок замены состояния на позиции копии [position] под
  /// отметкой чтения истории, которая выбирает это состояние.
  Future<UnregisteredGraphSnapshot> writeReplacementAt(
    GraphLogCompaction compaction,
    int position, {
    void Function(double share)? onProgress,
    Future<void>? cancelled,
  }) => compaction.readHistory(
    (history) async => compaction.writeReplacementSnapshot(
      await history.selectStateAt(position),
      onProgress: onProgress ?? (_) {},
      cancelled: cancelled ?? Completer<void>().future,
    ),
  );

  File fileOf(String fileName) => File.fromUri(snapshots.uri.resolve(fileName));

  Future<List<String>> snapshotRecords(String fileName) async => _lines(
    await (await GraphFormatFile.read(fileOf(fileName).openRead())).records
        .toList(),
  );

  Future<List<String>> referenceState() async =>
      _lines(await referenceGraphRecords(database));

  test('снимок замены на позиции копии читается модулем формата в выгрузку '
      'базы на этой позиции, совпадает с переданными размером, суммой и '
      'количествами и не зарегистрирован', () async {
    final home = await createTag('Дом', color: TagColor.blue);
    final health = await createIntention('Здоровье', tagIds: {home.id});
    final running = await createIntention('Бегать');
    await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: health.id,
        relatedIntentionId: running.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    await store().writeSnapshot(await repository.readCurrentPosition());
    await confirm(RemoveTagAssignment(tagId: home.id, intentionId: health.id));
    await createIntention('Плавать', tagIds: {home.id});
    final backupPosition = await repository.readCurrentPosition();
    final expected = await referenceState();
    await confirm(ArchiveIntention(health.id));
    await createTag('Спорт');

    final snapshot = await writeReplacementAt(
      compactionOver(repository),
      backupPosition,
    );

    final file = fileOf(snapshot.fileName);
    expect(await file.length(), snapshot.byteSize);
    expect(sha256.convert(await file.readAsBytes()).bytes, snapshot.checksum);
    final header = (await GraphFormatFile.read(file.openRead())).header;
    expect(_countsOf(header.counts), _countsOf(snapshot.counts));
    expect(await snapshotRecords(snapshot.fileName), expected);
    expect(
      await repository.readSnapshotFileNames(),
      isNot(contains(snapshot.fileName)),
    );
  });

  test('ход записи снимка замены растёт до полного к её окончанию', () async {
    final home = await createTag('Дом');
    await createIntention('Здоровье', tagIds: {home.id});
    await createIntention('Бегать');
    final progress = <double>[];

    await writeReplacementAt(
      compactionOver(repository),
      await repository.readCurrentPosition(),
      onProgress: progress.add,
    );

    expect(progress, hasLength(greaterThan(1)));
    for (var index = 1; index < progress.length; index++) {
      expect(progress[index], greaterThan(progress[index - 1]));
    }
    expect(progress.last, 1);
  });

  test('сжатие, завершившееся во время записи снимка замены, не мешает ей '
      'собрать состояние на позиции копии', () async {
    await confirmCommands(1);
    await store().writeSnapshot(1);
    await confirmCommands(1);
    final expected = await referenceState();
    await confirmCommands(1);
    final packagesReached = Completer<void>();
    final releasePackages = Completer<void>();
    final compaction = compactionOver(
      _InterceptingLog(
        repository,
        beforePackages: () async {
          if (packagesReached.isCompleted) return;
          packagesReached.complete();
          await releasePackages.future;
        },
      ),
    )..start();
    final write = writeReplacementAt(compaction, 2);
    await packagesReached.future;

    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    releasePackages.complete();
    final snapshot = await write;
    await compaction.shutdown();
    expect(await snapshotRecords(snapshot.fileName), expected);
  });

  test('отмена прекращает запись снимка замены и не оставляет его '
      'файла', () async {
    await confirmCommands(2);
    final base = await store().writeSnapshot(2);
    await confirmCommands(1);
    final packagesReached = Completer<void>();
    final releasePackages = Completer<void>();
    final compaction = compactionOver(
      _InterceptingLog(
        repository,
        beforePackages: () async {
          if (packagesReached.isCompleted) return;
          packagesReached.complete();
          await releasePackages.future;
        },
      ),
    );
    final cancellation = Completer<void>();
    final write = writeReplacementAt(
      compaction,
      3,
      cancelled: cancellation.future,
    );
    await packagesReached.future;

    cancellation.complete();
    releasePackages.complete();

    await expectLater(write, throwsA(isA<GraphReplacementSnapshotCancelled>()));
    expect(await _fileNamesIn(snapshots), {base.fileName});
  });

  test('отказ записи временного файла снимка замены из-за нехватки места '
      'относится к нехватке места и не оставляет файла', () async {
    await confirmCommands(2);
    final base = await store().writeSnapshot(2);
    await confirmCommands(1);
    final compaction = compactionOver(
      repository,
      replacementSnapshotRunner:
          writeGraphReplacementSnapshotFailingOnTemporaryFiles,
    );

    await expectLater(
      writeReplacementAt(compaction, 3),
      throwsA(
        isA<FileSystemException>().having(
          classifySqliteFailure,
          'категория отказа',
          isA<SqliteStorageFullFailure>(),
        ),
      ),
    );

    expect(await _fileNamesIn(snapshots), {base.fileName});
  });

  test('изменённый байт базового снимка даёт отказ повреждения снимка и не '
      'оставляет файла снимка замены', () async {
    await confirmCommands(2);
    final damaged = await store().writeSnapshot(2);
    await confirmCommands(1);
    final damagedFile = fileOf(damaged.fileName);
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);

    await expectLater(
      writeReplacementAt(compactionOver(repository), 3),
      throwsA(isA<GraphSnapshotCorruption>()),
    );

    expect(await _fileNamesIn(snapshots), {damaged.fileName});
  });
}

/// Получатель диагностики, по которому проверка дожидается окончания
/// сжатия: исход сжатия сообщается после удаления истории.
final class _CompactionOutcomes implements DiagnosticsSink {
  final _outcomes =
      StreamController<GraphLogCompactionDiagnosticsEvent>.broadcast();

  /// Исход следующего сжатия.
  Future<GraphLogCompactionDiagnosticsEvent> get next => _outcomes.stream.first;

  @override
  void record(DiagnosticsEvent event) {
    if (event is GraphLogCompactionDiagnosticsEvent) _outcomes.add(event);
  }
}

/// Лог фактов, который перед чтением пакетов вызывает задержку теста.
final class _InterceptingLog extends ForwardingGraphFactLog {
  _InterceptingLog(super.source, {required this.beforePackages});

  final Future<void> Function() beforePackages;

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) async {
    await beforePackages();
    return super.readPackages(after: after, upTo: upTo);
  }
}

Future<void> _flipByte(File file, int index) async {
  final bytes = await file.readAsBytes();
  bytes[index] ^= 0xff;
  await file.writeAsBytes(bytes);
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<int> _countsOf(GraphRecordCounts counts) => [
  counts.tags,
  counts.intentions,
  counts.tagAssignments,
  counts.longTermRelations,
  counts.dailyChoices,
];

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
