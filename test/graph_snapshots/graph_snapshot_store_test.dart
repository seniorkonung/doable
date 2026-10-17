import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import '../support/encoded_diagnostics_log.dart';
import '../support/forwarding_graph_fact_log.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late DateTime now;
  late EncodedDiagnosticsLog diagnostics;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    database = await harness.openReadyDatabase();
    now = DateTime.utc(2026, 10, 17, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    diagnostics = EncodedDiagnosticsLog();
  });

  tearDown(() => harness.dispose());

  GraphSnapshotStore storeOver(GraphFactLog log) => GraphSnapshotStore(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: diagnostics,
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

  File snapshotFile(GraphSnapshotEntry snapshot) =>
      File.fromUri(snapshots.uri.resolve(snapshot.fileName));

  test('снимок, собранный из прежнего снимка и пакетов после него, читается '
      'в состояние, совпадающее с базой', () async {
    final store = storeOver(repository);
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
    final choice = (await confirm<DailyChoiceCreated>(
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
        date: CalendarDate.fromParts(2026, 10, 17),
        description: null,
        isCompleted: false,
      ),
    )).choice;
    await store.writeSnapshot(await repository.readCurrentPosition());

    await confirm(
      RenameTag(tagId: sport.id, name: TagName.fromInput('Физкультура')),
    );
    await confirm(RemoveTagAssignment(tagId: home.id, intentionId: health.id));
    await confirm(AssignTag(tagId: home.id, intentionId: health.id));
    await confirm(DeleteDailyChoice(choice.id));
    await confirm(ArchiveIntention(swimming.id));
    await createIntention('Читать');
    final position = await repository.readCurrentPosition();
    await store.writeSnapshot(position);
    await repository.removeHistoryBefore(position);

    final state = await store.readStateAt(position);

    final expected = await referenceGraphRecords(database);
    expect(
      await repository.readPackages(after: 0, upTo: position),
      isEmpty,
      reason: 'состояние должно читаться только из снимка',
    );
    expect(_counts(state.counts), _countsOf(expected));
    expect(_lines(await state.records.toList()), _lines(expected));
  });

  test('снимок регистрируется, когда его файл уже записан под окончательным '
      'именем, с позицией, размером и SHA-256 файла', () async {
    await createTag('Дом');
    late Set<String> namesAtRegistration;
    late Uint8List bytesAtRegistration;
    final store = storeOver(
      _InterceptingLog(
        repository,
        beforeRegistration: (snapshot) async {
          namesAtRegistration = await _fileNamesIn(snapshots);
          bytesAtRegistration = await snapshotFile(snapshot).readAsBytes();
        },
      ),
    );

    final snapshot = await store.writeSnapshot(1);

    expect(namesAtRegistration, {snapshot.fileName});
    expect(snapshot.position, 1);
    expect(snapshot.byteSize, bytesAtRegistration.length);
    expect(snapshot.checksum, sha256.convert(bytesAtRegistration).bytes);
    expect(await repository.readSnapshotFileNames(), {snapshot.fileName});
  });

  test('отказ регистрации удаляет записанный файл снимка', () async {
    await createTag('Дом');
    final store = storeOver(
      _InterceptingLog(
        repository,
        beforeRegistration: (_) async =>
            throw const FileSystemException('Нет места.'),
      ),
    );

    await expectLater(
      store.writeSnapshot(1),
      throwsA(isA<FileSystemException>()),
    );
    expect(await repository.readSnapshotFileNames(), isEmpty);
    expect(await _fileNamesIn(snapshots), isEmpty);
  });

  for (final (damage, corrupt) in <(String, Future<void> Function(File))>[
    // Распаковка не читает байт ОС в заголовке gzip, поэтому записи
    // читаются, и подмену выдаёт только контрольная сумма.
    ('изменённый байт заголовка gzip', (file) => _flipByte(file, 9)),
    (
      'изменённый байт сжатых записей',
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
    test('$damage снимка даёт отказ повреждения при чтении и записи без '
        'регистрации нового снимка', () async {
      final store = storeOver(repository);
      await createTag('Дом');
      await createIntention('Здоровье');
      final damaged = await store.writeSnapshot(
        await repository.readCurrentPosition(),
      );
      await createIntention('Бегать');
      final position = await repository.readCurrentPosition();
      await corrupt(snapshotFile(damaged));
      final namesBeforeWrite = await _fileNamesIn(snapshots);

      await expectLater(
        store.readStateAt(position),
        throwsA(isA<GraphSnapshotCorruption>()),
      );
      await expectLater(
        store.writeSnapshot(position),
        throwsA(isA<GraphSnapshotCorruption>()),
      );
      expect(await repository.readSnapshotFileNames(), {damaged.fileName});
      expect(await _fileNamesIn(snapshots), namesBeforeWrite);
    });
  }

  test('очистка удаляет из каталога только незарегистрированные и временные '
      'файлы', () async {
    final store = storeOver(repository);
    await createTag('Дом');
    await store.writeSnapshot(1);
    await createTag('Спорт');
    final registered = await store.writeSnapshot(2);
    await repository.removeHistoryBefore(2);
    await File.fromUri(
      snapshots.uri.resolve('${const Uuid().v4()}.jsonl.gz.tmp'),
    ).writeAsBytes([1, 2, 3]);

    await store.removeUnregisteredFiles();

    expect(await _fileNamesIn(snapshots), {registered.fileName});
  });

  test('очистка до появления каталога снимков завершается успешно', () async {
    final store = storeOver(repository);

    await store.removeUnregisteredFiles();

    expect(await snapshots.exists(), isFalse);
  });

  test('очистка диагностируется успехом без имён и числа удалённых '
      'файлов', () async {
    await File.fromUri(
      snapshots.uri.resolve('${const Uuid().v4()}.jsonl.gz.tmp'),
    ).create(recursive: true);

    await storeOver(repository).removeUnregisteredFiles();

    expect(diagnostics.events, [
      {'operation': 'graphSnapshotCleanup', 'outcome': 'succeeded'},
    ]);
  });

  test('отказ чтения реестра при очистке диагностируется этапом чтения '
      'реестра и категорией повреждения базы', () async {
    await snapshots.create(recursive: true);
    final store = storeOver(
      _InterceptingLog(
        repository,
        beforeFileNames: () async => throw sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'database disk image is malformed',
        ),
      ),
    );

    await expectLater(
      store.removeUnregisteredFiles(),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(diagnostics.events, [
      {
        'operation': 'graphSnapshotCleanup',
        'stage': 'registryRead',
        'outcome': 'failed',
        'failureCode': 'corruption',
      },
    ]);
  });

  test('отказ удаления файла при очистке диагностируется этапом удаления '
      'файлов и категорией недоступности хранилища', () async {
    // Непустой каталог не удаляется без рекурсии, как файл при отказе ОС.
    await File.fromUri(snapshots.uri.resolve('${const Uuid().v4()}/вложенный'))
        .create(recursive: true);

    await expectLater(
      storeOver(repository).removeUnregisteredFiles(),
      throwsA(isA<FileSystemException>()),
    );
    expect(diagnostics.events, [
      {
        'operation': 'graphSnapshotCleanup',
        'stage': 'fileRemoval',
        'outcome': 'failed',
        'failureCode': 'unavailable',
      },
    ]);
  });
}

/// Лог фактов, который перед операцией вызывает действие теста: осмотр
/// каталога снимков или отказ вместо операции.
final class _InterceptingLog extends ForwardingGraphFactLog {
  _InterceptingLog(
    super.source, {
    this.beforeRegistration = _proceedWith,
    this.beforeFileNames = _proceed,
  });

  final Future<void> Function(GraphSnapshotEntry snapshot) beforeRegistration;
  final Future<void> Function() beforeFileNames;

  static Future<void> _proceedWith(GraphSnapshotEntry _) async {}

  static Future<void> _proceed() async {}

  @override
  Future<Set<String>> readSnapshotFileNames() async {
    await beforeFileNames();
    return super.readSnapshotFileNames();
  }

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) async {
    await beforeRegistration(snapshot);
    await super.registerSnapshot(snapshot);
  }
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
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

typedef _Counts = ({
  int tags,
  int intentions,
  int tagAssignments,
  int longTermRelations,
  int dailyChoices,
});

_Counts _counts(GraphRecordCounts counts) => (
  tags: counts.tags,
  intentions: counts.intentions,
  tagAssignments: counts.tagAssignments,
  longTermRelations: counts.longTermRelations,
  dailyChoices: counts.dailyChoices,
);

_Counts _countsOf(List<GraphEntityRecord> records) => (
  tags: records.whereType<TagRecord>().length,
  intentions: records.whereType<IntentionRecord>().length,
  tagAssignments: records.whereType<TagAssignmentRecord>().length,
  longTermRelations: records.whereType<LongTermRelationRecord>().length,
  dailyChoices: records.whereType<DailyChoiceRecord>().length,
);
