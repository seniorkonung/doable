import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
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
import 'package:uuid/uuid.dart';

import '../support/encoded_diagnostics_log.dart';
import '../support/failing_snapshot_temporary_files.dart';
import '../support/forwarding_graph_fact_log.dart';
import '../support/graph_history_rows.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

/// Порог проверок: несколько пакетов вместо производственного значения.
const _threshold = 3;

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late List<Future<GraphSnapshotEntry>> attempts;
  late EncodedDiagnosticsLog diagnostics;
  var now = DateTime.utc(2026, 10, 17, 9);
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
    attempts = [];
    diagnostics = EncodedDiagnosticsLog();
  });

  tearDown(() => harness.dispose());

  GraphSnapshotStore storeOver(GraphFactLog log) => GraphSnapshotStore(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );

  /// Сжатие с порогом проверок, которое запоминает каждую попытку записи
  /// снимка; [runner] выполняет запись в изоляте, а события диагностики
  /// получает [diagnosticsSink].
  GraphLogCompaction compactionOver(
    ObservableGraphFactLog log, {
    GraphSnapshotWriteRunner runner = runGraphSnapshotWriteInIsolate,
    DiagnosticsSink? diagnosticsSink,
  }) => GraphLogCompaction(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: diagnosticsSink ?? diagnostics,
    threshold: _threshold,
    runner: (write) {
      final attempt = runner(write);
      attempts.add(attempt);
      return attempt;
    },
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
    Set<TagId> tagIds = const {},
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: IntentionReadiness.ready,
      tagIds: tagIds,
    ),
  )).intention;

  /// Связь [source] → [related] и дневной выбор [related] по ней: записи
  /// последних секций формата.
  Future<void> relateAndChoose(Intention source, Intention related) async {
    final relation = (await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: source.id,
        relatedIntentionId: related.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    )).relation;
    await confirm(
      CreateDailyChoice(
        sourceIntentionId: source.id,
        selectedIntentionId: related.id,
        path: ConfirmedChoicePath([
          ConfirmedChoicePathStep(
            relationId: relation.id,
            sourceIntentionId: source.id,
            type: relation.type,
            relatedIntentionId: related.id,
          ),
        ]),
        date: CalendarDate.fromParts(2026, 10, 17),
        description: null,
        isCompleted: false,
      ),
    );
  }

  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      tagNumber++;
      await createTag('Тег $tagNumber');
    }
    // Сигнал о пакете доходит до сжатия после подтверждения команды.
    await pumpEventQueue();
  }

  File snapshotFile(GraphSnapshotEntry snapshot) =>
      File.fromUri(snapshots.uri.resolve(snapshot.fileName));

  Future<void> expectStateMatchesDatabase() async {
    final position = await repository.readCurrentPosition();
    final state = await storeOver(repository).readStateAt(position);
    expect(
      _lines(await state.records.toList()),
      _lines(await referenceGraphRecords(database)),
    );
  }

  for (final (damage, corrupt) in <(String, Future<void> Function(File))>[
    (
      'изменённый байт',
      (file) async => _flipByte(file, await file.length() ~/ 2),
    ),
    (
      'обрезанный файл',
      (file) async {
        final bytes = await file.readAsBytes();
        await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      },
    ),
    ('удалённый файл', (file) => file.delete()),
  ]) {
    test('$damage последнего снимка: сжатие пересобирает снимок из базы, и '
        'состояние из него и последующих пакетов совпадает с базой', () async {
      final home = await createTag('Дом');
      final health = await createIntention('Здоровье', tagIds: {home.id});
      await relateAndChoose(health, await createIntention('Бегать'));
      final damaged = await storeOver(repository)
          .writeSnapshot(await repository.readCurrentPosition());
      await corrupt(snapshotFile(damaged));
      final compaction = compactionOver(repository)..start();

      await confirmCommands(_threshold + 1);
      await compaction.shutdown();

      final position = await repository.readCurrentPosition();
      final rebuilt = await repository.readSnapshotAtOrBefore(position);
      expect(attempts, hasLength(1));
      expect(rebuilt?.position, position);
      expect(rebuilt?.fileName, isNot(damaged.fileName));
      expect(await repository.readSnapshotFileNames(), {rebuilt?.fileName});
      expect(await _fileNamesIn(snapshots), {rebuilt?.fileName});
      await confirm(ArchiveIntention(health.id));
      await expectStateMatchesDatabase();
    });
  }

  test('команды между порциями задержанной пересборки подтверждаются до её '
      'окончания и отражены в пересобранном снимке', () async {
    // Первая порция заканчивается посреди назначений тега «Дом»: 2 тега,
    // 60 намерений и 38 назначений.
    final home = await createTag('Дом');
    final sport = await createTag('Спорт');
    final intentions = [
      for (var index = 0; index < 60; index++)
        await createIntention('Намерение $index', tagIds: {home.id}),
    ];
    await relateAndChoose(intentions[0], intentions[1]);
    final damaged = await storeOver(repository)
        .writeSnapshot(await repository.readCurrentPosition());
    await snapshotFile(damaged).delete();
    final firstPortionRead = Completer<void>();
    final releasePortions = Completer<void>();
    final compaction = compactionOver(
      _FirstPortionPausingLog(repository, () async {
        firstPortionRead.complete();
        await releasePortions.future;
      }),
    )..start();
    await confirmCommands(_threshold + 1);
    await firstPortionRead.future;
    var rebuilt = false;
    unawaited(attempts.single.whenComplete(() => rebuilt = true));

    await createTag('Новый');
    await confirm(RenameTag(tagId: sport.id, name: TagName.fromInput('Бег')));
    await confirm(
      UpdateIntention(
        id: intentions[3].id,
        title: 'Намерение 3, изменённое',
        description: null,
      ),
    );
    await confirm(DeleteIntention(intentions[10].id));
    await confirm(
      RemoveTagAssignment(tagId: home.id, intentionId: intentions[5].id),
    );
    await confirm(AssignTag(tagId: home.id, intentionId: intentions[5].id));
    await createIntention('Позднее', tagIds: {sport.id});

    expect(rebuilt, isFalse);
    final position = await repository.readCurrentPosition();
    releasePortions.complete();
    await compaction.shutdown();
    await attempts.single;
    final snapshot = await repository.readSnapshotAtOrBefore(position);
    expect(snapshot?.position, position);
    expect(await repository.readPackages(after: 0, upTo: position), isEmpty);
    await expectStateMatchesDatabase();
  });

  test('пересборка, в диапазон которой попал пакет «сброс», не регистрирует '
      'снимок, а следующее по правилу повтора сжатие проходит', () async {
    // Сто один тег не умещается в одну порцию записей, поэтому замена графа
    // между порциями попадает в диапазон пакетов пересборки.
    for (var index = 0; index <= graphFactLogPortionLimit; index++) {
      await createTag('Метка $index');
    }
    final damaged = await storeOver(repository)
        .writeSnapshot(await repository.readCurrentPosition());
    await snapshotFile(damaged).delete();
    final firstPortionRead = Completer<void>();
    final releasePortions = Completer<void>();
    final compaction = compactionOver(
      _FirstPortionPausingLog(repository, () async {
        firstPortionRead.complete();
        await releasePortions.future;
      }),
    )..start();
    await confirmCommands(_threshold + 1);
    await firstPortionRead.future;
    final replaced = await insertSameGraphReplacement(
      database,
      snapshots: snapshots,
      position: await repository.readCurrentPosition(),
    );

    releasePortions.complete();
    await expectLater(attempts.single, throwsA(isA<GraphReplacedInRange>()));
    await compaction.shutdown();

    expect(await repository.readSnapshotFileNames(), {
      damaged.fileName,
      replaced.fileName,
    });
    expect(await _fileNamesIn(snapshots), {replaced.fileName});
    await confirmCommands(_threshold + 1);
    final next = compactionOver(repository)..start();
    await next.shutdown();

    final position = await repository.readCurrentPosition();
    expect(attempts, hasLength(2));
    expect((await attempts.last).position, position);
    expect(diagnostics.events, [
      {
        'operation': 'graphSnapshotWrite',
        'stage': 'stateAssembly',
        'outcome': 'failed',
        'failureCode': 'snapshotCorruption',
      },
      {
        'operation': 'graphSnapshotRebuild',
        'stage': 'stateAssembly',
        'outcome': 'failed',
        'failureCode': 'conflict',
      },
      {
        'operation': 'graphLogCompaction',
        'stage': 'snapshotWrite',
        'outcome': 'failed',
        'failureCode': 'conflict',
      },
      {'operation': 'graphSnapshotWrite', 'outcome': 'succeeded'},
      {'operation': 'graphLogCompaction', 'outcome': 'succeeded'},
    ]);
    await expectStateMatchesDatabase();
  });

  test('отказ записи при пересборке оставляет реестр, каталог и лог '
      'прежними', () async {
    await createTag('Дом');
    final damaged = await storeOver(repository).writeSnapshot(1);
    await _flipByte(
      snapshotFile(damaged),
      await snapshotFile(damaged).length() ~/ 2,
    );
    final compaction = compactionOver(
      repository,
      runner: writeGraphSnapshotFailingOnTemporaryFiles,
    )..start();

    await confirmCommands(_threshold + 1);
    await expectLater(attempts.single, throwsA(isA<FileSystemException>()));
    await compaction.shutdown();

    expect(await repository.readSnapshotFileNames(), {damaged.fileName});
    expect(await _fileNamesIn(snapshots), {damaged.fileName});
    expect(
      await repository.readPackages(after: 1, upTo: _threshold + 2),
      hasLength(_threshold + 1),
    );
  });

  test(
    'повреждённый последний снимок диагностируется отказом записи с '
    'категорией повреждения снимка, а пересборка и сжатие — успехом',
    () async {
      await createTag('Дом');
      final damaged = await storeOver(repository).writeSnapshot(1);
      await _flipByte(
        snapshotFile(damaged),
        await snapshotFile(damaged).length() ~/ 2,
      );
      final compaction = compactionOver(repository)..start();

      await confirmCommands(_threshold + 1);
      await compaction.shutdown();

      expect(diagnostics.events, [
        {
          'operation': 'graphSnapshotWrite',
          'stage': 'stateAssembly',
          'outcome': 'failed',
          'failureCode': 'snapshotCorruption',
        },
        {'operation': 'graphSnapshotRebuild', 'outcome': 'succeeded'},
        {'operation': 'graphLogCompaction', 'outcome': 'succeeded'},
      ]);
    },
  );

  test('отказ записи при пересборке из-за нехватки места диагностируется '
      'категорией нехватки места: пересборка — этапом чтения базы, а сжатие '
      '— этапом записи снимка', () async {
    await createTag('Дом');
    final damaged = await storeOver(repository).writeSnapshot(1);
    await snapshotFile(damaged).delete();
    final compaction = compactionOver(
      repository,
      runner: writeGraphSnapshotFailingOnTemporaryFiles,
    )..start();

    await confirmCommands(_threshold + 1);
    await compaction.shutdown();

    expect(diagnostics.events, [
      {
        'operation': 'graphSnapshotWrite',
        'stage': 'stateAssembly',
        'outcome': 'failed',
        'failureCode': 'snapshotCorruption',
      },
      {
        'operation': 'graphSnapshotRebuild',
        'stage': 'databaseRead',
        'outcome': 'failed',
        'failureCode': 'storageFull',
      },
      {
        'operation': 'graphLogCompaction',
        'stage': 'snapshotWrite',
        'outcome': 'failed',
        'failureCode': 'storageFull',
      },
    ]);
  });

  test('строка графа вне формы хранения диагностируется отказом пересборки и '
      'сжатия с категорией повреждения', () async {
    await createTag('Дом');
    final damaged = await storeOver(repository).writeSnapshot(1);
    await snapshotFile(damaged).delete();
    await seedGraph(
      database,
      () => database.customStatement(
        'INSERT INTO intentions (id, title, created_at, updated_at) '
        'VALUES (?, ?, 100, 100)',
        ['намерение вне формы', 'Изучать язык'],
      ),
    );
    final compaction = compactionOver(repository)..start();

    await confirmCommands(_threshold + 1);
    await compaction.shutdown();

    expect(diagnostics.events, [
      {
        'operation': 'graphSnapshotWrite',
        'stage': 'stateAssembly',
        'outcome': 'failed',
        'failureCode': 'snapshotCorruption',
      },
      {
        'operation': 'graphSnapshotRebuild',
        'stage': 'databaseRead',
        'outcome': 'failed',
        'failureCode': 'corruption',
      },
      {
        'operation': 'graphLogCompaction',
        'stage': 'snapshotWrite',
        'outcome': 'failed',
        'failureCode': 'corruption',
      },
    ]);
  });

  test('отказ получателя диагностики не меняет исход сжатия с пересборкой и '
      'очистки', () async {
    await createTag('Дом');
    final damaged = await storeOver(repository).writeSnapshot(1);
    await snapshotFile(damaged).delete();
    final compaction = compactionOver(
      repository,
      diagnosticsSink: _ThrowingDiagnosticsSink(),
    )..start();
    await confirmCommands(_threshold + 1);
    await compaction.shutdown();
    await File.fromUri(
      snapshots.uri.resolve('${const Uuid().v4()}.jsonl.gz.tmp'),
    ).writeAsBytes([1, 2, 3]);

    await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: _ThrowingDiagnosticsSink(),
    ).removeUnregisteredFiles();

    final position = await repository.readCurrentPosition();
    final rebuilt = await repository.readSnapshotAtOrBefore(position);
    expect(rebuilt?.position, position);
    expect(await _fileNamesIn(snapshots), {rebuilt?.fileName});
    await expectStateMatchesDatabase();
  });
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  @override
  void record(DiagnosticsEvent event) =>
      throw StateError('Получатель диагностики недоступен.');
}

/// Лог фактов, который после чтения первой порции записей графа ждёт
/// действия теста.
final class _FirstPortionPausingLog extends ForwardingGraphFactLog {
  _FirstPortionPausingLog(super.source, this._afterFirstPortion);

  final Future<void> Function() _afterFirstPortion;

  @override
  Future<GraphRecordPortion> readGraphRecords({
    GraphRecordOrderKey? after,
  }) async {
    final portion = await super.readGraphRecords(after: after);
    if (after == null) await _afterFirstPortion();
    return portion;
  }
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

Future<void> _flipByte(File file, int index) async {
  final bytes = await file.readAsBytes();
  bytes[index] ^= 0xff;
  await file.writeAsBytes(bytes);
}

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
