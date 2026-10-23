import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, LocalDatabaseSqlOperation, LocalDatabaseSqlStatement;
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/data_transfer/application/graph_restore.dart';
import 'package:doable/src/data_transfer/application/graph_restore_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/encoded_diagnostics_log.dart';
import '../support/failing_snapshot_temporary_files.dart';
import '../support/forwarding_graph_fact_log.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/transaction_storage_exhaustion.dart';

/// Порог сжатия проверок: несколько пакетов вместо производственного
/// значения.
const _threshold = 3;

void main() {
  late LocalDatabaseHarness harness;
  late _StatementProbe probe;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late _InterceptedPackageReads log;
  late _CompactionOutcomes compactionOutcomes;
  late GraphLogCompaction compaction;
  late GraphBackups backups;
  late EncodedDiagnosticsLog diagnostics;
  late ProviderContainer container;
  late DateTime now;
  var replacementSnapshotRunner = runGraphReplacementSnapshotWriteInIsolate;
  var tagNumber = 0;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    probe = _StatementProbe();
    database = await harness.openReadyDatabase(
      setup: (connection) => probe.storage = connection,
      observer: probe,
    );
    now = DateTime(2026, 10, 5, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    log = _InterceptedPackageReads(repository);
    compactionOutcomes = _CompactionOutcomes();
    replacementSnapshotRunner = runGraphReplacementSnapshotWriteInIsolate;
    compaction = GraphLogCompaction(
      log: log,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: compactionOutcomes,
      threshold: _threshold,
      replacementSnapshotRunner: (write) => replacementSnapshotRunner(write),
    );
    addTearDown(compaction.shutdown);
    backups = GraphBackups(
      registry: repository,
      compaction: compaction,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    diagnostics = EncodedDiagnosticsLog();
    final restore = GraphRestore(
      backups: repository,
      compaction: compaction,
      replacement: repository,
      snapshotFiles: Future.value(),
      diagnosticsSink: diagnostics,
    );
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        graphRestoreControllerProvider.overrideWith(
          () => GraphRestoreController(restore),
        ),
      ],
    );
    addTearDown(() async {
      await container.read(graphCommandCoordinatorProvider.notifier).shutdown();
      container.dispose();
    });
  });

  GraphRestoreController controller() =>
      container.read(graphRestoreControllerProvider.notifier);

  Future<GraphBackupRestoreOutcome> restore(GraphBackupEntry backup) =>
      (controller().start(backup) as GraphBackupRestoreAccepted).future;

  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Tag> createTag(String name) async => (await confirm<TagCreated>(
    CreateTag(
      name: TagName.fromInput(name),
      color: null,
      placement: TagPlacement.first,
    ),
  )).tag;

  Future<Intention> createIntention(
    String title, {
    String? description,
    Set<TagId> tagIds = const {},
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: description,
      readiness: IntentionReadiness.notReady,
      tagIds: tagIds,
    ),
  )).intention;

  /// Подтверждает [count] команд, каждая из которых создаёт тег. Сигнал о
  /// пакете доходит до сжатия после подтверждения команды, поэтому сжатие
  /// проверяет порог по каждому пакету до следующей команды.
  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      await createTag('Тег ${++tagNumber}');
      await pumpEventQueue();
    }
  }

  Future<List<GraphBackupEntry>> storedBackups() async =>
      switch (await repository.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups,
        GraphBackupsReadFailed() => throw TestFailure('Копии не прочитаны.'),
      };

  Future<GraphBackupEntry> makeManualBackup() async {
    expect(await backups.makeManualBackup(), ManualGraphBackupOutcome.made);
    return (await storedBackups()).first;
  }

  Future<GraphBackupEntry> makeDailyBackup() async {
    expect(await backups.makeDailyBackupIfDue(), DailyGraphBackupOutcome.made);
    return (await storedBackups()).first;
  }

  Future<List<String>> graphState() async =>
      _lines(await referenceGraphRecords(database));

  Future<List<List<Object?>>> rows(String query) async => [
    for (final row in await database.customSelect(query).get())
      row.data.values.toList(),
  ];

  Future<List<int>> snapshotPositions() async => [
    for (final row in await rows(
      'SELECT position FROM graph_snapshots ORDER BY position',
    ))
      row.single! as int,
  ];

  /// Граф, копии, лог, реестр и каталог снимков.
  Future<List<Object>> storedState() async => [
    await graphState(),
    await rows('SELECT * FROM graph_backups ORDER BY id'),
    await rows(
      'SELECT position, kind, snapshot_id FROM graph_log_packages '
      'ORDER BY position',
    ),
    await rows('SELECT * FROM graph_snapshots ORDER BY id'),
    await _fileNamesIn(snapshots),
  ];

  /// Ручная копия, которую удалило окно хранения, хотя ежедневная копия с
  /// той же позицией хранится: ручная копия сделана перед ней, а новая
  /// ежедневная копия вытеснила копии, сделанные раньше этой ежедневной.
  Future<GraphBackupEntry> evictedManualBackupWithRetainedPosition() async {
    await createTag('Дом');
    await makeDailyBackup();
    await createTag('Сад');
    final manual = await makeManualBackup();
    now = now.add(const Duration(days: 1));
    final retained = await makeDailyBackup();
    expect(retained.position, manual.position);
    for (var day = 0; day < retainedDailyGraphBackups - 1; day++) {
      now = now.add(const Duration(days: 1));
      await confirmCommands(1);
      await makeDailyBackup();
    }
    final stored = await storedBackups();
    expect(stored.map((backup) => backup.kind), isNot(contains(manual.kind)));
    expect(stored.last.position, manual.position);
    return manual;
  }

  test('ежедневная копия после перевода часов вперёд и ручная копия после '
      'перевода назад восстанавливают ровно своё состояние, а прежнее '
      'состояние сохраняется копией перед заменой, восстановление которой '
      'возвращает граф к состоянию до восстановления', () async {
    final home = await createTag('Дом');
    final health = await createIntention('Здоровье', tagIds: {home.id});
    await makeDailyBackup();
    now = DateTime(2026, 10, 9, 9);
    await createIntention('Бегать');
    final daily = await makeDailyBackup();
    final dailyState = await graphState();
    now = DateTime(2026, 10, 6, 9);
    await createTag('Сад');
    final manual = await makeManualBackup();
    final manualState = await graphState();
    await confirm(ArchiveIntention(health.id));
    final beforeRestore = await graphState();

    expect(await restore(daily), isA<GraphBackupRestored>());
    expect(await graphState(), dailyState);
    final beforeReplacement = (await storedBackups()).first;
    expect(beforeReplacement.kind, GraphBackupKind.beforeReplacement);

    expect(await restore(manual), isA<GraphBackupRestored>());
    expect(await graphState(), manualState);

    expect(await restore(beforeReplacement), isA<GraphBackupRestored>());
    expect(await graphState(), beforeRestore);
  });

  test('восстановление собирает состояние копии, хотя во время него сжатие '
      'записало новый снимок, а базовый снимок копии новее снимка, который '
      'сохраняет самая старая копия', () async {
    compaction.start();
    var compacted = compactionOutcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await confirmCommands(1);
    final oldest = await makeManualBackup();
    compacted = compactionOutcomes.next;
    await confirmCommands(_threshold);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await confirmCommands(1);
    final backup = await makeManualBackup();
    final [oldestBase, backupBase] = await snapshotPositions();
    expect(oldestBase, lessThanOrEqualTo(oldest.position));
    expect(backupBase, greaterThan(oldest.position));
    final backupState = await graphState();
    final hold = log.holdNextRead();

    final restored = restore(backup);
    await hold.reached;
    compacted = compactionOutcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    hold.release();

    expect(await restored, isA<GraphBackupRestored>());
    expect(await graphState(), backupState);
  });

  test('пока хранится копия перед заменой, сжатие с небольшим порогом '
      'завершается успешно, удаляет снимок, не нужный ни одной копии, и '
      'сохраняет снимок замены, а копия перед заменой возвращает граф к '
      'состоянию до восстановления', () async {
    compaction.start();
    var compacted = compactionOutcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await confirmCommands(1);
    final backup = await makeManualBackup();
    compacted = compactionOutcomes.next;
    await confirmCommands(_threshold);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    await confirmCommands(2);
    final beforeRestore = await graphState();
    expect(await restore(backup), isA<GraphBackupRestored>());
    final beforeReplacement = (await storedBackups()).first;
    final [backupBase, beforeReplacementBase, replacement] =
        await snapshotPositions();
    expect(backupBase, lessThanOrEqualTo(backup.position));
    expect(beforeReplacementBase, greaterThan(backup.position));
    expect(
      beforeReplacementBase,
      lessThanOrEqualTo(beforeReplacement.position),
    );
    compacted = compactionOutcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());
    final unneeded = (await snapshotPositions()).last;
    expect(unneeded, greaterThan(replacement));

    compacted = compactionOutcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    final retained = await snapshotPositions();
    expect(retained, hasLength(4));
    expect(retained.take(3), [backupBase, beforeReplacementBase, replacement]);
    expect(retained.last, greaterThan(unneeded));
    expect(await restore(beforeReplacement), isA<GraphBackupRestored>());
    expect(await graphState(), beforeRestore);
  });

  test('восстановление диагностируется успехом без пользовательских '
      'данных', () async {
    final home = await createTag('Дом');
    await createIntention('Здоровье', tagIds: {home.id});
    final backup = await makeManualBackup();
    await createIntention('Бегать');

    expect(await restore(backup), isA<GraphBackupRestored>());

    expect(diagnostics.events, [
      {'operation': 'graphBackupRestore', 'outcome': 'succeeded'},
    ]);
  });

  test('ход восстановления сообщается долями обеих фаз по порядку, а после '
      'восстановления его нет', () async {
    final home = await createTag('Дом');
    await createIntention('Здоровье', tagIds: {home.id});
    final backup = await makeManualBackup();
    await createIntention('Бегать');
    final states = <GraphRestoreState>[];
    container.listen(
      graphRestoreControllerProvider,
      (_, state) => states.add(state),
    );

    await restore(backup);

    final progress = [
      for (final state in states)
        if (state case GraphRestoreRunning(:final progress)) progress,
    ];
    for (final phase in GraphReplacementPhase.values) {
      final shares = [
        for (final step in progress)
          if (step.phase == phase) step.share,
      ];
      expect(shares.first, 0);
      expect(shares.last, 1);
      for (var index = 1; index < shares.length; index++) {
        expect(shares[index], greaterThan(shares[index - 1]));
      }
    }
    final phases = [for (final step in progress) step.phase];
    expect(
      phases.indexOf(GraphReplacementPhase.replacement),
      greaterThan(phases.lastIndexOf(GraphReplacementPhase.snapshotWrite)),
    );
    expect(states.last, isA<GraphRestoreIdle>());
  });

  group('подсчёт изменений с копии', () {
    test('даёт числа добавленных и изменённых сущностей, а без изменений — '
        'нули', () async {
      final health = await createIntention('Здоровье');
      final backup = await makeManualBackup();

      expect(_shown(await controller().countChangesSince(backup)), (
        added: 0,
        changed: 0,
        deleted: 0,
      ));

      await createIntention('Бегать');
      await createIntention('Плавать');
      await confirm(ArchiveIntention(health.id));

      expect(_shown(await controller().countChangesSince(backup)), (
        added: 2,
        changed: 1,
        deleted: 0,
      ));
    });

    test('команды, подтверждённые во время подсчёта, его не ждут, а сжатие, '
        'завершившееся за это время, его не меняет: подсчёт описывает ровно '
        'изменения до позиции, на которой он начат', () async {
      compaction.start();
      final health = await createIntention('Здоровье');
      final backup = await makeManualBackup();
      await createIntention('Бегать');
      await confirm(ArchiveIntention(health.id));
      final hold = log.holdNextRead();
      final counted = controller().countChangesSince(backup);
      await hold.reached;

      final compacted = compactionOutcomes.next;
      await confirmCommands(_threshold + 1);
      expect((await compacted).status, isA<DiagnosticsSucceeded>());
      hold.release();

      expect(_shown(await counted), (added: 1, changed: 1, deleted: 0));
    });

    test('после замены графа даёт признак замены вместо чисел', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      expect(await restore(backup), isA<GraphBackupRestored>());

      expect(
        _shown(await controller().countChangesSince(backup)),
        'Данные заменялись',
      );
    });

    test('для копии, которую удалило окно хранения, не даёт чисел, хотя её '
        'позиция хранится другой копией', () async {
      final evicted = await evictedManualBackupWithRetainedPosition();

      expect(
        await controller().countChangesSince(evicted),
        isA<GraphChangesSinceBackupUncounted>(),
      );
    });

    test('при отказе чтения лога не даёт чисел', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      log.failReads = true;

      expect(
        await controller().countChangesSince(backup),
        isA<GraphChangesSinceBackupUncounted>(),
      );
    });
  });

  test('восстановление копии, которую удалило окно хранения, отказывает, '
      'диагностируется этапом записи снимка замены и категорией «не найдено» '
      'и ничего не меняет, хотя её позиция хранится другой копией', () async {
    final evicted = await evictedManualBackupWithRetainedPosition();
    final before = await storedState();

    expect(await restore(evicted), isA<GraphBackupRestoreFailed>());

    expect(await storedState(), before);
    expect(diagnostics.events, [
      {
        'operation': 'graphBackupRestore',
        'stage': 'snapshotWrite',
        'outcome': 'failed',
        'failureCode': 'notFound',
      },
    ]);
  });

  group('отмена', () {
    test('во время записи снимка замены прекращает эту запись и '
        'восстановление без изменений, без файла снимка замены и без события '
        'диагностики', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      final before = await storedState();
      final snapshotWrite = Completer<Object?>();
      replacementSnapshotRunner = (write) async {
        try {
          final snapshot = await runGraphReplacementSnapshotWriteInIsolate(
            write,
          );
          snapshotWrite.complete(snapshot);
          return snapshot;
        } on Object catch (error) {
          snapshotWrite.complete(error);
          rethrow;
        }
      };
      final hold = log.holdNextRead();
      final restored = restore(backup);
      await hold.reached;

      controller().cancel();
      expect(
        container.read(graphRestoreControllerProvider),
        isA<GraphRestoreCancelling>(),
      );
      hold.release();

      expect(await restored, isA<GraphBackupRestoreCancelled>());
      expect(
        await snapshotWrite.future,
        isA<GraphReplacementSnapshotCancelled>(),
      );
      expect(
        container.read(graphRestoreControllerProvider),
        isA<GraphRestoreIdle>(),
      );
      expect(await storedState(), before);
      expect(diagnostics.events, isEmpty);
    });

    test('во время замены откатывает её без изменений, без файла снимка '
        'замены и без события диагностики', () async {
      final home = await createTag('Дом');
      await createIntention('Здоровье', tagIds: {home.id});
      final backup = await makeManualBackup();
      await createTag('Сад');
      final before = await storedState();
      container.listen(graphRestoreControllerProvider, (_, state) {
        if (state case GraphRestoreRunning(
          progress: GraphReplacementProgress(
            phase: GraphReplacementPhase.replacement,
            share: > 0,
          ),
        )) {
          scheduleMicrotask(controller().cancel);
        }
      });

      expect(await restore(backup), isA<GraphBackupRestoreCancelled>());

      expect(await storedState(), before);
      expect(diagnostics.events, isEmpty);
    });

    test('непосредственно перед проверкой точки невозврата замены '
        'принимается и откатывает замену с исходом отмены без '
        'изменений', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      final before = await storedState();
      final states = <GraphRestoreState>[];
      container.listen(
        graphRestoreControllerProvider,
        (_, state) => states.add(state),
      );
      probe.onStatement = (statement) {
        if (_enablesCapture(statement)) controller().cancel();
      };

      expect(await restore(backup), isA<GraphBackupRestoreCancelled>());

      probe.onStatement = null;
      expect(states, isNot(contains(isA<GraphRestoreCommitting>())));
      expect(states.sublist(states.length - 2), [
        isA<GraphRestoreCancelling>(),
        isA<GraphRestoreIdle>(),
      ]);
      expect(await storedState(), before);
      expect(diagnostics.events, isEmpty);
    });

    test('после точки невозврата замены не принимается и не меняет состояние '
        'контроллера, а восстановление завершается успехом', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      final backupState = await graphState();
      await createTag('Сад');
      final states = <GraphRestoreState>[];
      container.listen(graphRestoreControllerProvider, (_, state) {
        states.add(state);
        if (state is GraphRestoreCommitting) controller().cancel();
      });

      expect(await restore(backup), isA<GraphBackupRestored>());

      expect(states, isNot(contains(isA<GraphRestoreCancelling>())));
      expect(states.sublist(states.length - 2), [
        isA<GraphRestoreCommitting>(),
        isA<GraphRestoreIdle>(),
      ]);
      expect(await graphState(), backupState);
      expect(diagnostics.events, [
        {'operation': 'graphBackupRestore', 'outcome': 'succeeded'},
      ]);
    });
  });

  group('нехватка места', () {
    test('при замене графа, после которой SQLite сам откатил всю транзакцию, '
        'даёт свой исход, диагностируемый этапом замены и категорией '
        'нехватки места, ничего не меняет и удаляет снимок замены', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      final before = await storedState();
      probe.exhaustsBefore = (statement) =>
          statement.operation == LocalDatabaseSqlOperation.insert &&
          statement.statements.single.startsWith(
            'INSERT INTO "graph_log_packages"',
          );

      expect(await restore(backup), isA<GraphBackupRestoreStorageFull>());

      expect(await storedState(), before);
      expect(diagnostics.events, [
        {
          'operation': 'graphBackupRestore',
          'stage': 'replacement',
          'outcome': 'failed',
          'failureCode': 'storageFull',
        },
      ]);
    });

    test('при записи снимка замены даёт свой исход, диагностируемый этапом '
        'записи снимка замены и категорией нехватки места, и ничего не '
        'меняет', () async {
      await createTag('Дом');
      final backup = await makeManualBackup();
      await createTag('Сад');
      final before = await storedState();
      replacementSnapshotRunner =
          writeGraphReplacementSnapshotFailingOnTemporaryFiles;

      expect(await restore(backup), isA<GraphBackupRestoreStorageFull>());

      expect(await storedState(), before);
      expect(diagnostics.events, [
        {
          'operation': 'graphBackupRestore',
          'stage': 'snapshotWrite',
          'outcome': 'failed',
          'failureCode': 'storageFull',
        },
      ]);
    });

    test('сценарий «Отказ восстановления диагностируется без содержимого»: '
        'при замене графа даёт свой исход, диагностируемый этапом замены и '
        'категорией нехватки места без пользовательских данных, ничего не '
        'меняет и удаляет снимок замены', () async {
      // Копия с длинными описаниями занимает страницы переполнения, которых
      // после их удаления и VACUUM в базе нет.
      final long = [
        for (var index = 0; index < 4; index++)
          await createIntention('Намерение $index', description: 'ж' * 4000),
      ];
      final backup = await makeManualBackup();
      for (final intention in long) {
        await confirm(DeleteIntention(intention.id));
      }
      await createTag('Дом');
      await database.customStatement('VACUUM');
      final pageCount = await database
          .customSelect('PRAGMA page_count')
          .getSingle();
      await database.customStatement(
        'PRAGMA max_page_count = ${pageCount.read<int>('page_count')}',
      );
      final before = await storedState();

      expect(await restore(backup), isA<GraphBackupRestoreStorageFull>());

      expect(await storedState(), before);
      expect(diagnostics.events, [
        {
          'operation': 'graphBackupRestore',
          'stage': 'replacement',
          'outcome': 'failed',
          'failureCode': 'storageFull',
        },
      ]);
    });
  });
}

/// Изменения с копии так, как их показывает подтверждение восстановления.
Object _shown(GraphChangesSinceBackup changes) => switch (changes) {
  GraphChangesSinceBackupCounted(
    summary: GraphChangeCounts(:final added, :final changed, :final deleted),
  ) =>
    (added: added, changed: changed, deleted: deleted),
  GraphChangesSinceBackupCounted(summary: GraphDataReplaced()) =>
    'Данные заменялись',
  GraphChangesSinceBackupUncounted() => 'Не посчитано',
};

/// Включение захвата фактов — последний оператор транзакции замены перед её
/// точкой невозврата.
bool _enablesCapture(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.update &&
    statement.statements.single.contains('SET "capture"') &&
    statement.arguments.single == 1;

/// Исчерпывает место хранилища, как [TransactionStorageExhaustion], а после
/// оператора сообщает о нём [onStatement].
final class _StatementProbe extends TransactionStorageExhaustion {
  void Function(LocalDatabaseSqlStatement statement)? onStatement;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) =>
      onStatement?.call(statement);
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

/// Задержка чтения пакетов лога: [reached] завершается, когда оно начато, а
/// продолжается оно после [release].
final class _ReadHold {
  final _reached = Completer<void>();
  final _released = Completer<void>();

  Future<void> get reached => _reached.future;

  void release() => _released.complete();
}

/// Лог фактов, в котором следующее после [holdNextRead] чтение пакетов ждёт
/// задержки, а пока [failReads] истинно, чтение пакетов отказывает.
final class _InterceptedPackageReads extends ForwardingGraphFactLog {
  _InterceptedPackageReads(super.source);

  _ReadHold? _hold;
  var failReads = false;

  _ReadHold holdNextRead() => _hold = _ReadHold();

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) async {
    if (failReads) throw StateError('Внедрённый отказ чтения лога.');
    if (_hold case final hold?) {
      _hold = null;
      hold._reached.complete();
      await hold._released.future;
    }
    return super.readPackages(after: after, upTo: upTo);
  }
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
