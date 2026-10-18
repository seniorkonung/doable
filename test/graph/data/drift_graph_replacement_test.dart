import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        AppDatabase,
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_log_completeness_reference.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Эталонный файл формата версии 1: все виды записей, архивированные
/// намерение и связь и путь через архивированную связь к намерению без
/// готовности к действию.
const _goldenPath = 'test/graph_format/golden/graph_format_v1.jsonl';

void main() {
  late LocalDatabaseHarness harness;
  late _StatementProbe probe;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late GraphSnapshotStore store;
  late String golden;
  late DateTime now;
  var snapshotNumber = 0;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    probe = _StatementProbe();
    database = await harness.openReadyDatabase(observer: probe);
    now = DateTime.utc(2026, 10, 18, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
    snapshots = await Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    ).create();
    store = GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    golden = await File(_goldenPath).readAsString();
  });

  tearDown(() => harness.dispose());

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
      readiness: IntentionReadiness.notReady,
      tagIds: tagIds,
    ),
  )).intention;

  /// Непустой прежний граф: тег, намерение и назначение тега.
  Future<void> createPreviousGraph() async {
    final home = await createTag('Дача');
    await createIntention('Бег трусцой', tagIds: {home.id});
  }

  /// Записывает в каталог снимков снимок замены с записями эталонного
  /// файла, строки которого изменяет [edit], как его запишет хранилище
  /// снимков, и возвращает его.
  Future<UnregisteredGraphSnapshot> goldenSnapshot({
    String Function(String jsonl) edit = _unchanged,
  }) async {
    final bytes = gzip.encode(utf8.encode(edit(golden)));
    final fileName = 'замена-${++snapshotNumber}.jsonl.gz';
    await File.fromUri(snapshots.uri.resolve(fileName))
        .writeAsBytes(bytes, flush: true);
    return UnregisteredGraphSnapshot(
      directory: snapshots,
      fileName: fileName,
      byteSize: bytes.length,
      checksum: Uint8List.fromList(sha256.convert(bytes).bytes),
      counts: GraphRecordCounts(
        tags: 2,
        intentions: 4,
        tagAssignments: 3,
        longTermRelations: 3,
        dailyChoices: 2,
      ),
    );
  }

  Future<void> replace(
    UnregisteredGraphSnapshot snapshot, {
    void Function(double share)? onProgress,
    bool Function()? isCancelled,
  }) => repository.replaceGraph(
    snapshot,
    onProgress: onProgress ?? (_) {},
    isCancelled: isCancelled ?? () => false,
  );

  Future<List<String>> graphLines() async =>
      _lines(await referenceGraphRecords(database));

  Future<List<GraphBackupEntry>> backups() async {
    final read = await repository.watchBackups().first;
    return (read as GraphBackupsReadSucceeded).backups;
  }

  Future<List<List<Object?>>> rows(String query) async => [
    for (final row in await database.customSelect(query).get())
      row.data.values.toList(),
  ];

  /// Граф, копии, лог и реестр снимков.
  Future<List<Object>> storedState() async => [
    await graphLines(),
    await rows('SELECT * FROM graph_backups ORDER BY id'),
    await rows(
      'SELECT position, kind, snapshot_id FROM graph_log_packages '
      'ORDER BY position',
    ),
    await rows('SELECT * FROM graph_snapshots ORDER BY id'),
    await repository.readCurrentPosition(),
  ];

  test('замена непустого графа снимком со всеми видами записей даёт граф '
      'снимка и пакет «сброс» с этим снимком, а выгрузка базы совпадает с '
      'состоянием из снимка замены и последующих пакетов', () async {
    await createPreviousGraph();
    final position = await repository.readCurrentPosition();
    final snapshot = await goldenSnapshot();

    await replace(snapshot);

    expect(await graphLines(), _recordLines(golden));
    final reset = await repository.readPackages(
      after: position,
      upTo: position + 1,
    );
    expect(reset, [
      isA<StoredGraphResetPackage>()
          .having((package) => package.position, 'позиция', position + 1)
          .having(
            (package) => package.snapshot.fileName,
            'снимок',
            snapshot.fileName,
          ),
    ]);
    await createTag('Спорт и отдых');
    final state = await store.readStateAt(
      await repository.readCurrentPosition(),
    );
    expect(_lines(await state.records.toList()), await graphLines());
  });

  test('копия перед заменой получает позицию до сброса и сводку с '
      'предыдущей копии, а её состояние собирается в прежний граф', () async {
    final home = await createTag('Дача');
    final running = await createIntention('Бег трусцой', tagIds: {home.id});
    await repository.insertManualBackup(since: null);
    await confirm<IntentionSaved>(
      UpdateIntention(
        id: running.id,
        title: 'Бег трусцой',
        description: 'Утром',
      ),
    );
    await createTag('Дом');
    final previous = await graphLines();
    final position = await repository.readCurrentPosition();
    now = DateTime.utc(2026, 10, 18, 21);

    await replace(await goldenSnapshot());

    final backup = (await backups()).first;
    expect(backup.kind, GraphBackupKind.beforeReplacement);
    expect(backup.position, position);
    expect(backup.madeAt, now);
    expect(_shown(backup.summary), (added: 1, changed: 1, deleted: 0));
    final state = await store.readStateAt(backup.position);
    expect(_lines(await state.records.toList()), previous);
  });

  test('замена пустого графа не добавляет копию перед заменой', () async {
    await replace(await goldenSnapshot());

    expect(await backups(), isEmpty);
    expect(await graphLines(), _recordLines(golden));
  });

  test('поиск по названию находит намерения нового графа, а не '
      'прежнего', () async {
    await createIntention('Бег трусцой');

    await replace(await goldenSnapshot());

    final page = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: 'Бег',
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 10,
      ),
    );
    expect(
      [
        for (final item
            in (page as ResultSuccess<IntentionCatalogPage>).value.items)
          item.title,
      ],
      ['Бегать по утрам 🏃'],
    );
  });

  test('ход замены растёт до полного к её окончанию', () async {
    await createPreviousGraph();
    final progress = <double>[];

    await replace(await goldenSnapshot(), onProgress: progress.add);

    expect(progress, hasLength(greaterThan(1)));
    for (var index = 1; index < progress.length; index++) {
      expect(progress[index], greaterThan(progress[index - 1]));
    }
    expect(progress.last, 1);
  });

  group('отказ откатывает всю замену', () {
    final failurePoints = <String, bool Function(LocalDatabaseSqlStatement)>{
      'удаление прежнего графа': _deletes,
      'вставка записей снимка': _insertsRecords,
      'вставка копии перед заменой': (statement) =>
          _insertsInto(statement, 'graph_backups'),
      'регистрация снимка': (statement) =>
          _insertsInto(statement, 'graph_snapshots'),
      'запись пакета «сброс»': (statement) =>
          _insertsInto(statement, 'graph_log_packages'),
    };
    for (final MapEntry(key: point, value: fails) in failurePoints.entries) {
      test('отказ на шаге «$point» оставляет граф, копии, лог и реестр '
          'снимков прежними', () async {
        await createPreviousGraph();
        final before = await storedState();
        final snapshot = await goldenSnapshot();
        probe.failsBefore = fails;

        await expectLater(replace(snapshot), throwsA(isA<StateError>()));

        probe.failsBefore = null;
        expect(await storedState(), before);
      });
    }

    test('отказ сверки количеств после вставки оставляет граф, копии, лог и '
        'реестр снимков прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot();
      var insertedRecords = false;
      probe
        ..onStatement = (statement) {
          if (_insertsRecords(statement)) insertedRecords = true;
        }
        ..failsBefore = (statement) =>
            insertedRecords && _countsRecords(statement);

      await expectLater(replace(snapshot), throwsA(isA<StateError>()));

      probe
        ..failsBefore = null
        ..onStatement = null;
      expect(await storedState(), before);
    });

    final cancellationPoints =
        <String, bool Function(LocalDatabaseSqlStatement)>{
          'удаления прежнего графа': _deletes,
          'вставки записей снимка': _insertsRecords,
        };
    for (final MapEntry(key: point, value: cancels)
        in cancellationPoints.entries) {
      test('отмена во время $point оставляет граф, копии, лог и реестр '
          'снимков прежними', () async {
        await createPreviousGraph();
        final before = await storedState();
        final snapshot = await goldenSnapshot();
        var cancelled = false;
        probe.onStatement = (statement) {
          if (cancels(statement)) cancelled = true;
        };

        await expectLater(
          replace(snapshot, isCancelled: () => cancelled),
          throwsA(isA<GraphReplacementCancelled>()),
        );

        probe.onStatement = null;
        expect(cancelled, isTrue);
        expect(await storedState(), before);
      });
    }

    test('совпадение названий тегов отклоняется схемой и оставляет граф, '
        'копии, лог и реестр снимков прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot(
        edit: (jsonl) => jsonl.replaceFirst('"name":"Спорт"', '"name":"Дом"'),
      );

      await expectLater(
        replace(snapshot),
        throwsA(
          isA<Object>().having(
            classifySqliteFailure,
            'категория отказа',
            isA<SqliteConstraintFailure>(),
          ),
        ),
      );

      expect(await storedState(), before);
    });

    test('путь дневного выбора, который не доходит до выбранного намерения, '
        'отклоняет записи снимка и оставляет граф, копии, лог и реестр '
        'снимков прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot(
        edit: (jsonl) => jsonl.replaceFirst(
          '"selectedIntentionId":"1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f13"',
          '"selectedIntentionId":"1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f12"',
        ),
      );

      await expectLater(
        replace(snapshot),
        throwsA(isA<GraphReplacementRecordsRejected>()),
      );

      expect(await storedState(), before);
    });

    test('нехватка места при вставке записей снимка относится к нехватке '
        'места и оставляет граф, копии, лог и реестр снимков '
        'прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      // Длинные описания занимают страницы переполнения, которых в базе нет.
      final snapshot = await goldenSnapshot(
        edit: (jsonl) => jsonl.replaceAll(
          '"description":null,"actionReady"',
          '"description":"${'ж' * 4000}","actionReady"',
        ),
      );
      final pageCount = await database
          .customSelect('PRAGMA page_count')
          .getSingle();
      await database.customStatement(
        'PRAGMA max_page_count = ${pageCount.read<int>('page_count')}',
      );

      await expectLater(
        replace(snapshot),
        throwsA(
          isA<Object>().having(
            classifySqliteFailure,
            'категория отказа',
            isA<SqliteStorageFullFailure>(),
          ),
        ),
      );

      expect(await storedState(), before);
    });

    test('снимок замены с изменённым байтом даёт отказ повреждения снимка и '
        'оставляет граф, копии, лог и реестр снимков прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot();
      final file = File.fromUri(snapshots.uri.resolve(snapshot.fileName));
      final bytes = await file.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0xff;
      await file.writeAsBytes(bytes);

      await expectLater(
        replace(snapshot),
        throwsA(isA<GraphSnapshotCorruption>()),
      );

      expect(await storedState(), before);
    });
  });
}

String _unchanged(String jsonl) => jsonl;

/// Строки записей файла формата без строки заголовка.
List<String> _recordLines(String jsonl) =>
    (jsonl.split('\n')..removeLast()).skip(1).toList();

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

/// Сводка так, как её показывает список копий: числа или признак замены.
Object _shown(GraphChangeSummary summary) => switch (summary) {
  GraphChangeCounts(:final added, :final changed, :final deleted) => (
    added: added,
    changed: changed,
    deleted: deleted,
  ),
  GraphDataReplaced() => 'Данные заменены',
};

bool _deletes(LocalDatabaseSqlStatement statement) =>
    statement.statements.any((query) => query.startsWith('DELETE FROM'));

bool _insertsRecords(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.batch;

bool _insertsInto(LocalDatabaseSqlStatement statement, String table) =>
    statement.operation == LocalDatabaseSqlOperation.insert &&
    statement.statements.single.startsWith('INSERT INTO "$table"');

/// Чтение количеств записей всех видов: только оно считает назначения
/// тегов.
bool _countsRecords(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.select &&
    statement.statements.single.contains('count(*) FROM tag_assignments');

/// Перед оператором отказывает, когда его выбирает [failsBefore], а после
/// оператора сообщает о нём [onStatement].
final class _StatementProbe extends LocalDatabaseConnectionObserver {
  bool Function(LocalDatabaseSqlStatement statement)? failsBefore;
  void Function(LocalDatabaseSqlStatement statement)? onStatement;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failsBefore?.call(statement) ?? false) {
      throw StateError('Внедрённый отказ');
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) =>
      onStatement?.call(statement);
}
