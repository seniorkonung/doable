import 'dart:async';
import 'dart:io';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        AppDatabase,
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
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
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_history_rows.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late _DeleteFailureProbe probe;
  late AppDatabase database;
  late EncodedDiagnosticsLog diagnostics;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late GraphSnapshotStore store;
  late DateTime now;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    probe = _DeleteFailureProbe();
    database = await harness.openReadyDatabase(observer: probe);
    now = DateTime.utc(2026, 10, 18, 9);
    diagnostics = EncodedDiagnosticsLog();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    store = GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
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

  Future<Tag> createTag(String name) async => (await confirm<TagCreated>(
    CreateTag(
      name: TagName.fromInput(name),
      color: null,
      placement: TagPlacement.first,
    ),
  )).tag;

  Future<Intention> createIntention(String title) async =>
      (await confirm<IntentionSaved>(
        CreateIntention(title: title, description: null),
      )).intention;

  Future<List<GraphBackupEntry>> backups() async {
    final read = await repository.watchBackups().first;
    return (read as GraphBackupsReadSucceeded).backups;
  }

  /// События удаления копий окном хранения без длительности.
  List<Map<String, Object?>> removals() => [
    for (final event in diagnostics.events)
      if (event['operation'] == 'graphBackupRemoval') event,
  ];

  /// Сводка с позиции последней копии, как её посчитает модуль копий.
  Future<GraphChangeTally?> tallySinceLastBackup() async {
    final last = (await backups()).firstOrNull;
    if (last == null) return null;
    return store.readHistory(
      (history) async => GraphChangeTally.ofRange(
        history,
        after: last.position,
        upTo: await history.readCurrentPosition(),
      ),
    );
  }

  /// Изменяет граф и делает ежедневную копию 9:00 [day] октября; день
  /// начинается в 03:00.
  Future<bool> dailyBackupOnOctober(int day) async {
    await createTag('Тег $day октября');
    now = DateTime.utc(2026, 10, day, 9);
    return repository.insertDailyBackup(
      dayStart: DateTime.utc(2026, 10, day, 3),
      since: await tallySinceLastBackup(),
    );
  }

  test('копии читаются от новых к старым по созданию, даже когда часы '
      'переведены назад, раньше момента последней копии', () async {
    expect(await dailyBackupOnOctober(18), isTrue);

    expect(await dailyBackupOnOctober(17), isTrue);

    expect(_moments(await backups()), [
      DateTime.utc(2026, 10, 17, 9),
      DateTime.utc(2026, 10, 18, 9),
    ]);
  });

  test('сводка продолжается командой, подтверждённой между подсчётом и '
      'вставкой, а копия получает позицию после этой команды', () async {
    final running = await createIntention('Бегать');
    await repository.insertManualBackup(since: null);
    await confirm<IntentionSaved>(
      UpdateIntention(id: running.id, title: 'Бегать', description: 'Утром'),
    );
    await createTag('Дом');
    final tally = await tallySinceLastBackup();

    await createTag('Дача');
    await repository.insertManualBackup(since: tally);

    final backup = (await backups()).first;
    expect(backup.position, await repository.readCurrentPosition());
    expect(_shown(backup.summary), (added: 2, changed: 1, deleted: 0));
  });

  test('первая копия считает добавленной каждую сущность состава графа, но '
      'не назначения тегов', () async {
    final home = await createTag('Дом');
    final health = await createIntention('Здоровье');
    final running = (await confirm<IntentionSaved>(
      CreateIntention.withInitialState(
        title: 'Бегать',
        description: null,
        readiness: IntentionReadiness.ready,
        tagIds: const {},
      ),
    )).intention;
    await confirm<TagAssignmentChanged>(
      AssignTag(tagId: home.id, intentionId: running.id),
    );
    final needRunning = (await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: health.id,
        relatedIntentionId: running.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    )).relation;
    await confirm<DailyChoiceCreated>(
      CreateDailyChoice(
        sourceIntentionId: health.id,
        selectedIntentionId: running.id,
        path: ConfirmedChoicePath([
          ConfirmedChoicePathStep(
            relationId: needRunning.id,
            sourceIntentionId: health.id,
            type: LongTermRelationType.need,
            relatedIntentionId: running.id,
          ),
        ]),
        date: CalendarDate.fromParts(2026, 10, 18),
        description: null,
        isCompleted: false,
      ),
    );

    await repository.insertManualBackup(since: null);

    final backup = (await backups()).single;
    expect(backup.position, await repository.readCurrentPosition());
    expect(_shown(backup.summary), (added: 5, changed: 0, deleted: 0));
  });

  test('копия, перед которой граф заменён после того, как вызывающий не '
      'нашёл копий, показывает «Данные заменены»', () async {
    await createTag('Дом');
    await insertSameGraphReplacement(
      database,
      snapshots: await snapshots.create(),
      position: await repository.readCurrentPosition(),
    );

    await repository.insertManualBackup(since: null);

    expect(_shown((await backups()).first.summary), _replaced);
  });

  test('пока ежедневных копий нет, ежедневная копия пустого графа не '
      'записывается', () async {
    final written = await repository.insertDailyBackup(
      dayStart: DateTime.utc(2026, 10, 18, 3),
      since: null,
    );

    expect(written, isFalse);
    expect(await backups(), isEmpty);
  });

  test('вторая ежедневная копия того же дня не записывается, даже после '
      'изменений графа', () async {
    await dailyBackupOnOctober(18);
    await createTag('Дача');
    now = DateTime.utc(2026, 10, 18, 21);

    final written = await repository.insertDailyBackup(
      dayStart: DateTime.utc(2026, 10, 18, 3),
      since: await tallySinceLastBackup(),
    );

    expect(written, isFalse);
    expect(_moments(await backups()), [DateTime.utc(2026, 10, 18, 9)]);
  });

  test('восьмая ежедневная копия удаляет самую старую ежедневную копию и '
      'ручную копию после неё, а наблюдение выдаёт список после вставки и '
      'удаления; диагностируется успехом только это удаление', () async {
    await dailyBackupOnOctober(1);
    now = DateTime.utc(2026, 10, 1, 12);
    await repository.insertManualBackup(since: await tallySinceLastBackup());
    for (var day = 2; day <= 7; day++) {
      await dailyBackupOnOctober(day);
    }
    expect(removals(), isEmpty);
    final lists = StreamIterator(repository.watchBackups());
    addTearDown(lists.cancel);
    expect(await lists.moveNext(), isTrue);
    expect(
      _moments((lists.current as GraphBackupsReadSucceeded).backups),
      hasLength(8),
    );

    expect(await dailyBackupOnOctober(8), isTrue);

    expect(await lists.moveNext(), isTrue);
    expect(_moments((lists.current as GraphBackupsReadSucceeded).backups), [
      for (var day = 8; day >= 2; day--) DateTime.utc(2026, 10, day, 9),
    ]);
    expect(removals(), [
      {'operation': 'graphBackupRemoval', 'outcome': 'succeeded'},
    ]);
  });

  test('отказ удаления копий окном хранения откатывает и вставку новой '
      'ежедневной копии и диагностируется категорией отказа', () async {
    for (var day = 1; day <= 7; day++) {
      await dailyBackupOnOctober(day);
    }
    final before = _moments(await backups());
    await createTag('Тег 8 октября');
    final tally = await tallySinceLastBackup();
    now = DateTime.utc(2026, 10, 8, 9);
    probe.failsDelete = true;

    await expectLater(
      repository.insertDailyBackup(
        dayStart: DateTime.utc(2026, 10, 8, 3),
        since: tally,
      ),
      throwsA(isA<StateError>()),
    );

    probe.failsDelete = false;
    expect(_moments(await backups()), before);
    expect(removals(), [
      {
        'operation': 'graphBackupRemoval',
        'outcome': 'failed',
        'failureCode': 'unexpected',
      },
    ]);
  });
}

const _replaced = 'Данные заменены';

/// Сводка так, как её показывает список копий: числа или признак замены.
Object _shown(GraphChangeSummary summary) => switch (summary) {
  GraphChangeCounts(:final added, :final changed, :final deleted) => (
    added: added,
    changed: changed,
    deleted: deleted,
  ),
  GraphDataReplaced() => _replaced,
};

List<DateTime> _moments(List<GraphBackupEntry> backups) => [
  for (final backup in backups) backup.madeAt,
];

/// Отказывает каждое удаление строк, пока задан [failsDelete].
final class _DeleteFailureProbe extends LocalDatabaseConnectionObserver {
  var failsDelete = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failsDelete &&
        statement.operation == LocalDatabaseSqlOperation.delete) {
      throw StateError('Внедрённый отказ удаления');
    }
  }
}
