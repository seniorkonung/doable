import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
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
  late File exported;
  late _CompactionOutcomes outcomes;
  var now = DateTime.utc(2026, 10, 18, 9);
  final writtenAt = DateTime.utc(2026, 10, 18, 12, 30);
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
    exported = File.fromUri(
      harness.temporaryDirectory.uri.resolve('export.jsonl.gz'),
    );
    outcomes = _CompactionOutcomes();
  });

  tearDown(() => harness.dispose());

  GraphLogCompaction compactionOver(
    ObservableGraphFactLog log, {
    GraphSnapshotWriteRunner runner = runGraphSnapshotWriteInIsolate,
    GraphStateWriteRunner stateWriteRunner = runGraphStateWriteInIsolate,
  }) => GraphLogCompaction(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: outcomes,
    threshold: _threshold,
    runner: runner,
    stateWriteRunner: stateWriteRunner,
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

  Future<Tag> createTag(String name) async =>
      (await confirm<TagCreated>(CreateTag(TagName.fromInput(name)))).tag;

  Future<Intention> createIntention(
    String title, {
    IntentionReadiness readiness = IntentionReadiness.notReady,
    Set<TagId> tagIds = const {},
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: readiness,
      tagIds: tagIds,
    ),
  )).intention;

  Future<LongTermRelation> relate(
    Intention source,
    Intention related, {
    LongTermRelationType type = LongTermRelationType.need,
  }) async => (await confirm<LongTermRelationCreated>(
    CreateLongTermRelation(
      sourceIntentionId: source.id,
      relatedIntentionId: related.id,
      type: type,
      priority: RelationPriority.p2,
      description: null,
    ),
  )).relation;

  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      tagNumber++;
      await createTag('Тег $tagNumber');
    }
    // Сигнал о пакете доходит до сжатия после подтверждения команды.
    await pumpEventQueue();
  }

  Future<void> writeState(
    GraphLogCompaction compaction, {
    void Function(double share)? onProgress,
  }) => compaction.writeCurrentState(
    exported,
    writtenAt: writtenAt,
    onProgress: onProgress ?? (_) {},
  );

  Future<List<String>> exportedRecords() async => _lines(
    await (await GraphFormatFile.read(exported.openRead())).records.toList(),
  );

  Future<List<String>> referenceState() async =>
      _lines(await referenceGraphRecords(database));

  test(
    'файл состояния после команд всех видов читается модулем формата в '
    'выгрузку базы на позиции записи с моментом записи в заголовке',
    () async {
      final home = await createTag('Дом');
      final sport = await createTag('Спорт');
      final health = await createIntention(
        'Здоровье',
        tagIds: {home.id, sport.id},
      );
      final running = await createIntention(
        'Бегать',
        readiness: IntentionReadiness.ready,
      );
      final swimming = await createIntention('Плавать');
      final needRunning = await relate(health, running);
      await relate(health, swimming, type: LongTermRelationType.can);
      await relate(swimming, running);
      await confirm<DailyChoiceCreated>(
        CreateDailyChoice(
          sourceIntentionId: health.id,
          selectedIntentionId: running.id,
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: needRunning.id,
              sourceIntentionId: health.id,
              type: needRunning.type,
              relatedIntentionId: running.id,
            ),
          ]),
          date: CalendarDate.fromParts(2026, 10, 18),
          description: null,
          isCompleted: false,
        ),
      );
      await store().writeSnapshot(await repository.readCurrentPosition());
      await confirm(
        RemoveTagAssignment(tagId: home.id, intentionId: health.id),
      );
      await confirm(AssignTag(tagId: home.id, intentionId: health.id));
      await confirm(ArchiveIntention(swimming.id));
      await createIntention('Читать', tagIds: {sport.id});
      final expected = await referenceState();

      await writeState(compactionOver(repository));

      final reading = await GraphFormatFile.read(exported.openRead());
      expect(reading.header.writtenAt, writtenAt);
      expect(_lines(await reading.records.toList()), expected);
    },
  );

  test(
    'архивирование намерения со связями во время записи подтверждается до '
    'её окончания, а файл содержит намерение и связи до архивирования',
    () async {
      final health = await createIntention('Здоровье');
      await relate(health, await createIntention('Бегать'));
      await relate(health, await createIntention('Плавать'));
      final expected = await referenceState();
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
      var written = false;
      final write = writeState(compaction).whenComplete(() => written = true);
      await packagesReached.future;

      expect(
        await repository.execute(ArchiveIntention(health.id)),
        isA<GraphCommandSucceeded>(),
      );

      expect(written, isFalse);
      expect(await referenceState(), isNot(expected));
      releasePackages.complete();
      await write;
      expect(await exportedRecords(), expected);
    },
  );

  test('сжатие, завершившееся во время записи, не мешает ей собрать '
      'состояние на позиции записи', () async {
    await confirmCommands(1);
    await store().writeSnapshot(1);
    await confirmCommands(1);
    final expected = await referenceState();
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
    final write = writeState(compaction);
    await packagesReached.future;

    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    releasePackages.complete();
    await write;
    await compaction.shutdown();
    expect(await exportedRecords(), expected);
  });

  test('ход записи растёт до полного к её окончанию', () async {
    final home = await createTag('Дом');
    await createIntention('Здоровье', tagIds: {home.id});
    await createIntention('Бегать');
    final progress = <double>[];

    await writeState(compactionOver(repository), onProgress: progress.add);

    expect(progress, hasLength(greaterThan(1)));
    for (var index = 1; index < progress.length; index++) {
      expect(progress[index], greaterThan(progress[index - 1]));
    }
    expect(progress.last, 1);
  });

  test('отказ записи файла удаляет файл, а после него сжатие удаляет историю, '
      'которую держало чтение', () async {
    await confirmCommands(1);
    await store().writeSnapshot(1);
    await confirmCommands(1);
    final compaction = compactionOver(
      repository,
      stateWriteRunner: writeGraphStateFailingOn(exported),
    );

    await expectLater(
      writeState(compaction),
      throwsA(isA<FileSystemException>()),
    );

    expect(await exported.exists(), isFalse);
    compaction.start();
    final compacted = outcomes.next;
    await confirmCommands(_threshold);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await compaction.shutdown();
    final latest = await repository.readSnapshotAtOrBefore(_threshold + 2);
    expect(latest?.position, _threshold + 2);
    expect(await repository.readSnapshotFileNames(), {latest?.fileName});
  });

  test('изменённый байт базового снимка даёт отказ повреждения снимка и не '
      'оставляет файла', () async {
    await confirmCommands(2);
    final damaged = await store().writeSnapshot(2);
    await confirmCommands(1);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);

    await expectLater(
      writeState(compactionOver(repository)),
      throwsA(isA<GraphSnapshotCorruption>()),
    );

    expect(await exported.exists(), isFalse);
  });

  test('первая запись, обнаружившая повреждённый последний снимок при числе '
      'пакетов меньше порога, дожидается его пересборки и читается в выгрузку '
      'базы', () async {
    await confirmCommands(2);
    final damaged = await store().writeSnapshot(2);
    await confirmCommands(1);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);
    final expected = await referenceState();
    final compaction = compactionOver(repository)..start();

    await writeState(compaction);

    final rebuilt = await repository.readSnapshotAtOrBefore(3);
    expect(rebuilt?.position, 3);
    expect(await repository.readSnapshotFileNames(), {rebuilt?.fileName});
    expect(await exportedRecords(), expected);
    await compaction.shutdown();
  });

  test('запись, обнаружившая повреждение во время задержанного сжатия, '
      'дожидается его и завершается успешно, а снимок записывается один '
      'раз', () async {
    await confirmCommands(1);
    final damaged = await store().writeSnapshot(1);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);
    final writeReached = Completer<void>();
    final releaseWrite = Completer<void>();
    final corruptionFound = Completer<void>();
    var attempts = 0;
    final compaction = compactionOver(
      repository,
      runner: (write) async {
        attempts++;
        if (!writeReached.isCompleted) writeReached.complete();
        await releaseWrite.future;
        return runGraphSnapshotWriteInIsolate(write);
      },
      stateWriteRunner: (write) async {
        try {
          await runGraphStateWriteInIsolate(write);
        } on GraphSnapshotCorruption {
          if (!corruptionFound.isCompleted) corruptionFound.complete();
          rethrow;
        }
      },
    )..start();
    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    await writeReached.future;
    final expected = await referenceState();
    final write = writeState(compaction);
    await corruptionFound.future;

    releaseWrite.complete();

    await write;
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await compaction.shutdown();
    expect(attempts, 1);
    expect(await exportedRecords(), expected);
  });

  test('запись, дождавшаяся неудачной пересборки повреждённого последнего '
      'снимка, отказывает повреждением снимка и не оставляет файла', () async {
    await confirmCommands(2);
    final damaged = await store().writeSnapshot(2);
    await confirmCommands(1);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);
    final compaction = compactionOver(
      repository,
      runner: writeGraphSnapshotFailingOnTemporaryFiles,
    )..start();

    await expectLater(
      writeState(compaction),
      throwsA(isA<GraphSnapshotCorruption>()),
    );

    expect(outcomes.recorded.single.status, isA<DiagnosticsFailed>());
    expect(await exported.exists(), isFalse);
    await compaction.shutdown();
  });

  test('после выключения сжатия повреждение, обнаруженное записью, '
      'пересборку не запускает', () async {
    await confirmCommands(2);
    final damaged = await store().writeSnapshot(2);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    await _flipByte(damagedFile, await damagedFile.length() ~/ 2);
    final compaction = compactionOver(repository)..start();
    await compaction.shutdown();

    await expectLater(
      writeState(compaction),
      throwsA(isA<GraphSnapshotCorruption>()),
    );
    // Повторное выключение дождалось бы запущенной пересборки.
    await compaction.shutdown();

    expect(await repository.readSnapshotFileNames(), {damaged.fileName});
  });
}

/// Получатель диагностики, по которому проверка дожидается окончания
/// сжатия: исход сжатия сообщается после удаления истории.
final class _CompactionOutcomes implements DiagnosticsSink {
  final _outcomes =
      StreamController<GraphLogCompactionDiagnosticsEvent>.broadcast();

  /// Исходы сжатий в порядке их окончания.
  final recorded = <GraphLogCompactionDiagnosticsEvent>[];

  /// Исход следующего сжатия.
  Future<GraphLogCompactionDiagnosticsEvent> get next => _outcomes.stream.first;

  @override
  void record(DiagnosticsEvent event) {
    if (event is! GraphLogCompactionDiagnosticsEvent) return;
    recorded.add(event);
    _outcomes.add(event);
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

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
