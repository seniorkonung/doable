import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, LocalDatabaseSqlOperation, LocalDatabaseSqlStatement;
import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show CouldNotRollBackException;
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';
import '../../support/graph_log_completeness_reference.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/transaction_storage_exhaustion.dart';

/// Эталонный файл формата версии 1: все виды записей, синий и бесцветный
/// теги, архивированные намерение и связь и пути действий через
/// архивированную связь, удалённое намерение и удалённую связь.
const _goldenPath = 'test/graph_format/golden/graph_format_v1.jsonl';

/// Идентификаторы сущностей эталонного файла.
const _goldenHealthId = '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f11';
const _goldenRunningId = '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f12';
const _goldenFiveKilometersId = '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f13';
const _goldenSportTagId = '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e12';
const _goldenHealthRunningRelationId = '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b11';
const _goldenActionId = '5e6f7a8b-9c0d-4eaf-b012-3a4b5c6d7e11';

/// Количества записей эталонного файла.
final _goldenCounts = _goldenCountsWith();

/// Количества записей эталонного файла с другим числом надгробий.
GraphRecordCounts _goldenCountsWith({
  int deletedIntentions = 1,
  int deletedRelationPairs = 1,
}) => GraphRecordCounts(
  tags: 2,
  intentions: 4,
  deletedIntentions: deletedIntentions,
  tagAssignments: 3,
  longTermRelations: 3,
  deletedRelationPairs: deletedRelationPairs,
  actions: 3,
);

void main() {
  late LocalDatabaseHarness harness;
  late _StatementProbe probe;
  late AppDatabase database;
  late EncodedDiagnosticsLog diagnostics;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late GraphSnapshotStore store;
  late String golden;
  late DateTime now;
  var snapshotNumber = 0;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    probe = _StatementProbe();
    database = await harness.openReadyDatabase(
      setup: (connection) => probe.storage = connection,
      observer: probe,
    );
    now = DateTime.utc(2026, 10, 18, 9);
    diagnostics = EncodedDiagnosticsLog();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
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

  /// Непустой прежний граф: зелёный тег, намерение и назначение тега.
  Future<void> createPreviousGraph() async {
    final home = await createTag('Дача', color: TagColor.green);
    await createIntention('Бег трусцой', tagIds: {home.id});
  }

  /// Записывает в каталог снимков снимок замены с записями эталонного
  /// файла, строки которого изменяет [edit], а количества записей —
  /// [counts], как его запишет хранилище снимков, и возвращает его.
  Future<UnregisteredGraphSnapshot> goldenSnapshot({
    String Function(String jsonl) edit = _unchanged,
    GraphRecordCounts? counts,
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
      counts: counts ?? _goldenCounts,
    );
  }

  Future<ConfirmedGraphReplacement> replace(
    UnregisteredGraphSnapshot snapshot, {
    void Function(double share)? onProgress,
    GraphReplacementCancellation? cancellation,
  }) => repository.replaceGraph(
    snapshot,
    onProgress: onProgress ?? (_) {},
    cancellation: cancellation ?? GraphReplacementCancellation(),
  );

  Future<List<String>> graphLines() async =>
      _lines(await referenceGraphRecords(database));

  Future<List<GraphBackupEntry>> backups() async {
    final read = await repository.watchBackups().first;
    return (read as GraphBackupsReadSucceeded).backups;
  }

  /// События создания копий без длительности.
  List<Map<String, Object?>> backupCreations() => [
    for (final event in diagnostics.events)
      if (event['operation'] == 'graphBackupCreation') event,
  ];

  Future<GraphRevision> intentionRevision(IntentionId id) async =>
      _revisionOf(await repository.watchIntention(id).first);

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

  group('правило входящей связи вспомогательного намерения', () {
    for (final violation in [
      'нет связи',
      'только архивная связь',
      'архивное без связи',
    ]) {
      test('$violation отклоняется без изменения графа и копий', () async {
        await createPreviousGraph();
        final before = await storedState();
        final snapshot = await goldenSnapshot(
          edit: (jsonl) {
            return jsonl
                .split('\n')
                .map((line) {
                  if (line.isEmpty) return line;
                  final record = jsonDecode(line) as Map<String, dynamic>;
                  if (violation == 'нет связи' &&
                      record['id'] == _goldenHealthId) {
                    record['intentionKind'] = 'supporting';
                  }
                  if (violation == 'только архивная связь') {
                    if (record['id'] == _goldenFiveKilometersId) {
                      record['intentionKind'] = 'supporting';
                    }
                    if (record['kind'] == 'longTermRelation' &&
                        record['relatedIntentionId'] ==
                            _goldenFiveKilometersId) {
                      record['archived'] = true;
                    }
                  }
                  if (violation == 'архивное без связи') {
                    if (record['kind'] == 'longTermRelation' &&
                        record['relatedIntentionId'] ==
                            '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f14') {
                      record['relatedIntentionId'] = _goldenHealthId;
                    }
                    if (record['kind'] == 'action' &&
                        (record['path'] as List).contains(
                          '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f14',
                        )) {
                      (record['path'] as List).removeLast();
                    }
                  }
                  return jsonEncode(record);
                })
                .join('\n');
          },
        );
        await expectLater(
          replace(snapshot),
          throwsA(isA<GraphReplacementRecordsRejected>()),
        );
        expect(await storedState(), before);
      });
    }
  });

  test('замена непустого графа снимком со всеми видами записей даёт граф '
      'снимка и пакет «сброс» с этим снимком, а выгрузка базы совпадает с '
      'состоянием из снимка замены и последующих пакетов', () async {
    await createPreviousGraph();
    final position = await repository.readCurrentPosition();
    final snapshot = await goldenSnapshot();

    await replace(snapshot);

    expect(await graphLines(), _recordLines(golden));
    expect(
      await rows(
        'SELECT package.position AS package_position, package.kind, '
        'snapshot.position AS snapshot_position, snapshot.file_name '
        'FROM graph_log_packages AS package '
        'LEFT JOIN graph_snapshots AS snapshot '
        'ON snapshot.id = package.snapshot_id '
        'WHERE package.position > $position',
      ),
      [
        [position + 1, 'reset', position + 1, snapshot.fileName],
      ],
    );
    await createTag('Спорт и отдых');
    final state = await store.readStateAt(
      await repository.readCurrentPosition(),
    );
    expect(_lines(await state.records.toList()), await graphLines());
  });

  test('замена графа с действиями и надгробиями удаляет их вместе с путями, '
      'не создавая надгробий удалённых связей и намерений прежнего графа, '
      'считает их в ходе замены и даёт граф снимка', () async {
    final raw = probe.storage;
    seedRawGraph(raw, () {
      for (final (number, title) in [(1, 'Здоровье'), (2, 'Бегать')]) {
        seedIntention(raw, seedUuid(number), title);
      }
      seedIntention(raw, seedUuid(3), 'Плавать');
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(1), seedUuid(3));
      seedAction(raw, id: seedUuid(11), path: [seedUuid(1), seedUuid(2)]);
      seedAction(raw, id: seedUuid(12), path: [seedUuid(1), seedUuid(3)]);
      raw
        ..execute('DELETE FROM long_term_relations WHERE id = ?', [
          seedUuid(102),
        ])
        ..execute('DELETE FROM intentions WHERE id = ?', [seedUuid(3)]);
    });
    expect(
      await rows(
        'SELECT (SELECT count(*) FROM deleted_intentions), '
        '(SELECT count(*) FROM deleted_relation_pairs)',
      ),
      [
        [1, 1],
      ],
    );
    final progress = <double>[];

    await replace(await goldenSnapshot(), onProgress: progress.add);

    expect(await graphLines(), _recordLines(golden));
    expect(progress.last, 1);
  });

  test('копия перед заменой получает позицию до сброса и сводку с '
      'предыдущей копии, а её состояние собирается в прежний граф; создание '
      'копии диагностируется её видом и успехом', () async {
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
    expect(backupCreations(), [
      {
        'operation': 'graphBackupCreation',
        'backupKind': 'beforeReplacement',
        'outcome': 'succeeded',
      },
    ]);
  });

  test('замена пустого графа не добавляет копию перед заменой и не '
      'диагностирует её создание', () async {
    await replace(await goldenSnapshot());

    expect(await backups(), isEmpty);
    expect(await graphLines(), _recordLines(golden));
    expect(backupCreations(), isEmpty);
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

  group('новая эпоха ревизий', () {
    test('результат замены несёт изменение «граф заменён» с ревизией новой '
        'эпохи: ревизии прежней эпохи с ней несравнимы, чтения после замены '
        'получают её, а следующая команда — более новую', () async {
      final running = await createIntention('Бег трусцой');
      final before = await intentionRevision(running.id);

      final replacement = await replace(await goldenSnapshot());

      expect(replacement.changes, [
        isA<GraphReplaced>().having(
          (change) => change.revision.compareTo(replacement.revision),
          'ревизия',
          GraphRevisionOrder.same,
        ),
      ]);
      expect(
        before.compareTo(replacement.revision),
        GraphRevisionOrder.differentEpoch,
      );
      expect(
        replacement.revision.compareTo(before),
        GraphRevisionOrder.differentEpoch,
      );
      expect(
        (await intentionRevision(running.id)).compareTo(replacement.revision),
        GraphRevisionOrder.same,
      );
      await createTag('Спорт и отдых');
      expect(
        (await intentionRevision(running.id)).compareTo(replacement.revision),
        GraphRevisionOrder.newer,
      );
    });

    test('после замены наблюдатели намерения, действия, '
        'долговременной связи и тега перечитывают их на '
        'ревизии новой эпохи', () async {
      await createPreviousGraph();
      final relation = _relationId(_goldenHealthRunningRelationId);
      final reads = <String, StreamIterator<_SnapshotRead>>{
        'намерение': StreamIterator(
          repository.watchIntention(_intentionId(_goldenRunningId)),
        ),
        'действие': StreamIterator(
          repository.watchAction(_actionId(_goldenActionId)),
        ),
        'долговременная связь': StreamIterator(
          repository.watchRelation(relation),
        ),
        'тег': StreamIterator(repository.watchTag(_tagId(_goldenSportTagId))),
      };
      for (final read in reads.values) {
        // Наблюдение, которое ждёт уведомления, завершает отмену только
        // после него, поэтому сбой теста не должен ждать отмены.
        addTearDown(() => unawaited(read.cancel()));
        expect(await read.moveNext(), isTrue);
      }

      final replacement = await replace(await goldenSnapshot());

      for (final MapEntry(key: watched, value: read) in reads.entries) {
        expect(await read.moveNext(), isTrue, reason: watched);
        expect(
          _revisionOf(read.current).compareTo(replacement.revision),
          GraphRevisionOrder.same,
          reason: watched,
        );
      }
    });

    test('после замены наблюдение состава выдаёт состав нового '
        'графа', () async {
      await createPreviousGraph();
      final reads = StreamIterator(repository.watchComposition());
      addTearDown(reads.cancel);
      expect(await reads.moveNext(), isTrue);

      await replace(await goldenSnapshot());

      expect(await reads.moveNext(), isTrue);
      expect(
        (reads.current as GraphCompositionReadSucceeded).composition,
        const GraphComposition(
          intentionCount: 4,
          relationCount: 3,
          actionCount: 3,
          tagCount: 2,
        ),
      );
    });

    test('после замены наблюдение списка копий выдаёт список, в котором '
        'первой стоит копия перед заменой', () async {
      await createPreviousGraph();
      await repository.insertManualBackup(since: null);
      final reads = StreamIterator(repository.watchBackups());
      addTearDown(reads.cancel);
      expect(await reads.moveNext(), isTrue);

      await replace(await goldenSnapshot());

      expect(await reads.moveNext(), isTrue);
      expect(
        [
          for (final backup
              in (reads.current as GraphBackupsReadSucceeded).backups)
            backup.kind,
        ],
        [GraphBackupKind.beforeReplacement, GraphBackupKind.manual],
      );
    });

    test('после замены наблюдатели лога получают позицию пакета '
        '«сброс»', () async {
      await createPreviousGraph();
      final position = await repository.readCurrentPosition();
      final confirmed = <int>[];
      final subscription = repository.confirmedPositions.listen(confirmed.add);
      addTearDown(subscription.cancel);

      await replace(await goldenSnapshot());
      await pumpEventQueue();

      expect(confirmed, [position + 1]);
    });

    test('снимок связей статистики, загруженный до замены, после неё '
        'собирается заново по новому графу', () async {
      await createPreviousGraph();
      await repository.loadStatisticsRelationSnapshot();

      await replace(await goldenSnapshot());

      expect(
        _relationEdges(await repository.loadStatisticsRelationSnapshot()),
        {
          (_goldenHealthId, _goldenRunningId),
          (_goldenHealthId, _goldenFiveKilometersId),
        },
      );
    });

    /// Проверяет, что прерванная [interruptedReplacement] замена непустого
    /// графа сохраняет эпоху ревизий и не сообщает о себе наблюдателям лога
    /// и списка копий.
    Future<void> expectEpochAndObserversUntouched(
      Future<void> Function(UnregisteredGraphSnapshot snapshot)
      interruptedReplacement,
    ) async {
      final running = await createIntention('Бег трусцой');
      final before = await intentionRevision(running.id);
      final backupReads = <GraphBackupsRead>[];
      final backupSubscription = repository.watchBackups().listen(
        backupReads.add,
      );
      addTearDown(backupSubscription.cancel);
      final confirmed = <int>[];
      final positionSubscription = repository.confirmedPositions.listen(
        confirmed.add,
      );
      addTearDown(positionSubscription.cancel);
      await repository.readCurrentPosition();
      await pumpEventQueue();
      expect(backupReads, hasLength(1));

      await interruptedReplacement(await goldenSnapshot());
      await pumpEventQueue();
      await repository.readCurrentPosition();
      await pumpEventQueue();

      expect(
        (await intentionRevision(running.id)).compareTo(before),
        GraphRevisionOrder.same,
      );
      expect(backupReads, hasLength(1));
      expect(confirmed, isEmpty);
    }

    test('отказ замены сохраняет эпоху ревизий и не сообщает о замене '
        'наблюдателям лога и списка копий', () async {
      await expectEpochAndObserversUntouched((snapshot) async {
        probe.failsBefore = (statement) =>
            _insertsInto(statement, 'graph_log_packages');
        await expectLater(replace(snapshot), throwsA(isA<StateError>()));
        probe.failsBefore = null;
      });
    });

    test('отмена замены сохраняет эпоху ревизий и не сообщает о замене '
        'наблюдателям лога и списка копий', () async {
      await expectEpochAndObserversUntouched(
        (snapshot) => expectLater(
          replace(
            snapshot,
            cancellation: GraphReplacementCancellation()..request(),
          ),
          throwsA(isA<GraphReplacementCancelled>()),
        ),
      );
    });
  });

  group('точка невозврата', () {
    test('отмена, запрошенная после включения захвата, принимается и '
        'откатывает замену: граф, копии, лог и реестр снимков остаются '
        'прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot();
      final cancellation = GraphReplacementCancellation();
      bool? accepted;
      probe.onStatement = (statement) {
        if (_enablesCapture(statement)) accepted = cancellation.request();
      };

      await expectLater(
        replace(snapshot, cancellation: cancellation),
        throwsA(isA<GraphReplacementCancelled>()),
      );

      probe.onStatement = null;
      expect(accepted, isTrue);
      expect(await storedState(), before);
    });

    test('отмена, запрошенная после точки невозврата, не принимается, а '
        'замена подтверждается с копией перед заменой и пакетом '
        '«сброс»', () async {
      await createPreviousGraph();
      final position = await repository.readCurrentPosition();
      final snapshot = await goldenSnapshot();
      late final GraphReplacementCancellation cancellation;
      bool? accepted;
      cancellation = GraphReplacementCancellation(
        onPointOfNoReturn: () => accepted = cancellation.request(),
      );

      await replace(snapshot, cancellation: cancellation);

      expect(accepted, isFalse);
      expect(await graphLines(), _recordLines(golden));
      expect(
        [for (final backup in await backups()) (backup.kind, backup.position)],
        [(GraphBackupKind.beforeReplacement, position)],
      );
      expect(
        await rows(
          'SELECT position, kind FROM graph_log_packages '
          'WHERE position > $position',
        ),
        [
          [position + 1, 'reset'],
        ],
      );
    });

    test('вызывающий узнаёт о прохождении точки невозврата до подтверждения '
        'транзакции замены', () async {
      await createPreviousGraph();
      final snapshot = await goldenSnapshot();
      final events = <String>[];
      probe.onTransactionEnd = () => events.add('транзакция завершена');

      await replace(
        snapshot,
        cancellation: GraphReplacementCancellation(
          onPointOfNoReturn: () => events.add('точка невозврата'),
        ),
      );

      probe.onTransactionEnd = null;
      expect(events, ['точка невозврата', 'транзакция завершена']);
    });
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

    final backupStages =
        <String, (String, bool Function(LocalDatabaseSqlStatement))>{
          // Сводка копии начинается с поиска предыдущей копии.
          'подсчёт сводки': (
            'changeSummary',
            (statement) =>
                statement.operation == LocalDatabaseSqlOperation.select &&
                statement.statements.single.contains('FROM "graph_backups"'),
          ),
          'запись в реестр копий': (
            'registration',
            (statement) => _insertsInto(statement, 'graph_backups'),
          ),
        };
    for (final MapEntry(key: point, value: (stage, fails))
        in backupStages.entries) {
      test('отказ этапа «$point» копии перед заменой диагностируется видом '
          'копии, этим этапом и категорией отказа', () async {
        await createPreviousGraph();
        await repository.insertManualBackup(since: null);
        final snapshot = await goldenSnapshot();
        probe.failsBefore = fails;

        await expectLater(replace(snapshot), throwsA(isA<StateError>()));

        probe.failsBefore = null;
        expect(backupCreations(), [
          {
            'operation': 'graphBackupCreation',
            'backupKind': 'beforeReplacement',
            'stage': stage,
            'outcome': 'failed',
            'failureCode': 'unexpected',
          },
        ]);
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
        final cancellation = GraphReplacementCancellation();
        var accepted = false;
        probe.onStatement = (statement) {
          if (cancels(statement)) accepted = cancellation.request();
        };

        await expectLater(
          replace(snapshot, cancellation: cancellation),
          throwsA(isA<GraphReplacementCancelled>()),
        );

        probe.onStatement = null;
        expect(accepted, isTrue);
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

    final brokenActionPaths =
        <String, (String Function(String jsonl), GraphRecordCounts)>{
          'звено пути действия без связи и без надгробия пары': (
            (jsonl) => jsonl
                .replaceFirst(
                  '"deletedRelationPairs":1',
                  '"deletedRelationPairs":0',
                )
                .replaceFirst(
                  RegExp(r'\{"kind":"deletedRelationPair"[^\n]*\n'),
                  '',
                ),
            _goldenCountsWith(deletedRelationPairs: 0),
          ),
          'надгробие намерения, которого нет ни в одном пути': (
            (jsonl) => jsonl
                .replaceFirst('"deletedIntentions":1', '"deletedIntentions":2')
                .replaceFirst(
                  '"title":"Заниматься йогой"}\n',
                  '"title":"Заниматься йогой"}\n'
                      '{"kind":"deletedIntention",'
                      '"id":"1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f16",'
                      '"title":"Медитировать"}\n',
                ),
            _goldenCountsWith(deletedIntentions: 2),
          ),
          'надгробие пары, которой нет ни в одном пути': (
            (jsonl) => jsonl
                .replaceFirst(
                  '"deletedRelationPairs":1',
                  '"deletedRelationPairs":2',
                )
                .replaceFirst(
                  '{"kind":"deletedRelationPair"',
                  '{"kind":"deletedRelationPair",'
                      '"sourceIntentionId":"$_goldenHealthId",'
                      '"relatedIntentionId":"1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f14",'
                      '"type":"can"}\n'
                      '{"kind":"deletedRelationPair"',
                ),
            _goldenCountsWith(deletedRelationPairs: 2),
          ),
        };
    for (final MapEntry(key: violation, value: (edit, counts))
        in brokenActionPaths.entries) {
      test('$violation отклоняет записи снимка и оставляет граф, копии, лог '
          'и реестр снимков прежними', () async {
        await createPreviousGraph();
        final before = await storedState();
        final snapshot = await goldenSnapshot(edit: edit, counts: counts);

        await expectLater(
          replace(snapshot),
          throwsA(isA<GraphReplacementRecordsRejected>()),
        );

        expect(await storedState(), before);
      });
    }

    test('нехватка места при вставке записей снимка относится к нехватке '
        'места и оставляет граф, копии, лог и реестр снимков '
        'прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      // Длинные описания занимают страницы переполнения, которых в базе нет.
      final snapshot = await goldenSnapshot(
        edit: (jsonl) => jsonl.replaceAll(
          '"description":null,"intentionKind"',
          '"description":"${'ж' * 4000}","intentionKind"',
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

    test('нехватка места, после которой SQLite сам откатил всю транзакцию, '
        'даёт отказ отката с нехваткой места в причине и оставляет граф, '
        'копии, лог и реестр снимков прежними', () async {
      await createPreviousGraph();
      final before = await storedState();
      final snapshot = await goldenSnapshot();
      probe.exhaustsBefore = (statement) =>
          _insertsInto(statement, 'graph_log_packages');

      await expectLater(
        replace(snapshot),
        throwsA(
          isA<CouldNotRollBackException>().having(
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

/// Значение наблюдения сущности: снимок на ревизии или отказ чтения.
typedef _SnapshotRead =
    GraphResult<GraphSnapshot<Object?>, GraphCommandFailure>;

GraphRevision _revisionOf(_SnapshotRead read) => switch (read) {
  GraphResultSuccess(:final value) => value.revision,
  GraphResultFailure(:final failure) => throw TestFailure(
    'Отказ чтения: $failure',
  ),
};

IntentionId _intentionId(String id) =>
    (IntentionId.decode(id) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String id) =>
    (LongTermRelationId.decode(id) as LongTermRelationIdDecodingSuccess).id;

ActionId _actionId(String id) =>
    (ActionId.decode(id) as ActionIdDecodingSuccess).id;

TagId _tagId(String id) => (TagId.decode(id) as TagIdDecodingSuccess).id;

/// Пары «исходное намерение, связанное намерение» активных связей снимка.
Set<(String, String)> _relationEdges(ContributionRelationGraph graph) => {
  for (var node = 0; node < graph.intentionIds.length; node++)
    for (
      var edge = graph.childOffsets[node];
      edge < graph.childOffsets[node + 1];
      edge++
    )
      (
        graph.intentionIds[node].toCanonicalString(),
        graph.intentionIds[graph.children[edge]].toCanonicalString(),
      ),
};

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

/// Включение захвата фактов: им замена заканчивает свою транзакцию.
bool _enablesCapture(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.update &&
    statement.statements.single.contains('SET "capture"') &&
    statement.arguments.single == 1;

/// Чтение количеств записей всех видов: только оно считает назначения
/// тегов.
bool _countsRecords(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.select &&
    statement.statements.single.contains('count(*) FROM tag_assignments');

/// Перед оператором исчерпывает место хранилища, как
/// [TransactionStorageExhaustion], или отказывает, когда его выбирает
/// [failsBefore], после оператора сообщает о нём [onStatement], а после
/// завершения транзакции — [onTransactionEnd].
final class _StatementProbe extends TransactionStorageExhaustion {
  bool Function(LocalDatabaseSqlStatement statement)? failsBefore;
  void Function(LocalDatabaseSqlStatement statement)? onStatement;
  void Function()? onTransactionEnd;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    super.beforeStatement(statement);
    if (failsBefore?.call(statement) ?? false) {
      throw StateError('Внедрённый отказ');
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) =>
      onStatement?.call(statement);

  @override
  void onTransactionFinished() => onTransactionEnd?.call();
}
