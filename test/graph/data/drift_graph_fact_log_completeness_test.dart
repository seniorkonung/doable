import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_state_assembly.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show ComparableExpr, OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_log_completeness_reference.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Состояние графа по выгрузке базы на позиции последнего пакета лога.
typedef _GraphCheckpoint = ({int position, List<GraphEntityRecord> records});

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  /// Состояние, заполненное в обход лога; без него лог сверяется от
  /// позиции 0.
  _GraphCheckpoint? seeded;

  setUp(() async {
    seeded = null;
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    now = DateTime.utc(2026, 10, 17, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      // Каждое показание часов на секунду позже предыдущего, пока тест не
      // переведёт часы.
      () => now = now.add(const Duration(seconds: 1)),
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  Future<_GraphCheckpoint> checkpoint() async => (
    position: await _lastPosition(database),
    records: await referenceGraphRecords(database),
  );

  /// Сверяет выгрузку базы с состоянием, собранным из лога от позиции 0, а
  /// после заполнения в обход лога — от заполненного состояния, и от
  /// промежуточного состояния [base].
  Future<void> expectLogMatchesDatabase(_GraphCheckpoint base) async {
    final expected = await referenceGraphRecords(database);
    for (final (description, assemblyBase) in [
      switch (seeded) {
        null => ('от позиции 0', const GraphStateBase.empty()),
        final origin => ('от заполненного состояния', _baseOf(origin)),
      },
      ('от позиции ${base.position}', _baseOf(base)),
    ]) {
      final state = await GraphStateAssembly.assemble(
        assemblyBase,
        _packagesAfter(database, assemblyBase.position),
      );
      expect(
        _counts(state.counts),
        _countsOf(expected),
        reason: 'количества состояния, собранного $description',
      );
      expect(
        _lines(await state.records.toList()),
        _lines(expected),
        reason: 'записи состояния, собранного $description',
      );
    }
  }

  /// Подтверждает [command] и сверяет изменённую ею базу с состоянием,
  /// собранным из лога от позиции 0 и от состояния перед командой.
  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final before = await checkpoint();
    final result = await repository.execute(command);
    expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());
    expect(
      _lines(await referenceGraphRecords(database)),
      isNot(_lines(before.records)),
      reason: 'команда должна изменить граф',
    );
    await expectLogMatchesDatabase(before);
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
    IntentionReadiness readiness = IntentionReadiness.notReady,
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: readiness,
      tagIds: const {},
    ),
  )).intention;

  Future<LongTermRelation> relate(
    Intention source,
    Intention related, {
    IntentionRelationGroup group = IntentionRelationGroup.needs,
  }) async => (await confirm<LongTermRelationsAdded>(
    AddLongTermRelations(
      pageIntentionId: source.id,
      group: group,
      candidateIds: [related.id],
    ),
  )).relations.single;

  test('команды тегов: создание цветного и бесцветного тегов, '
      'переименование, правка только цвета, возврат к «Без цвета», '
      'назначение, снятие и удаление тега вместе с назначениями', () async {
    final home = await createTag('Дом', color: TagColor.blue);
    final sport = await createTag('Спорт');
    final running = await createIntention('Бегать');
    final swimming = await createIntention('Плавать');

    await confirm(
      UpdateTag(
        tagId: sport.id,
        name: TagName.fromInput('Физкультура'),
        color: sport.color,
      ),
    );
    await confirm(
      UpdateTag(
        tagId: sport.id,
        name: TagName.fromInput('Физкультура'),
        color: TagColor.green,
      ),
    );
    await confirm(UpdateTag(tagId: home.id, name: home.name, color: null));
    await confirm(AssignTag(tagId: home.id, intentionId: running.id));
    await confirm(AssignTag(tagId: sport.id, intentionId: running.id));
    await confirm(AssignTag(tagId: sport.id, intentionId: swimming.id));
    await confirm(RemoveTagAssignment(tagId: home.id, intentionId: running.id));
    await confirm(DeleteTag(sport.id));
  });

  test('тег, снятый с намерения и назначенный ему снова, собирается из лога '
      'в конце назначений, как и в базе', () async {
    final home = await createTag('Дом');
    final first = await createIntention('А');
    final second = await createIntention('Б');
    await confirm(AssignTag(tagId: home.id, intentionId: first.id));
    await confirm(AssignTag(tagId: home.id, intentionId: second.id));
    final beforeRemoval = await checkpoint();

    await confirm(RemoveTagAssignment(tagId: home.id, intentionId: first.id));
    await confirm(AssignTag(tagId: home.id, intentionId: first.id));

    expect(
      [
        for (final record in await referenceGraphRecords(database))
          if (record case TagAssignmentRecord(:final assignment))
            assignment.intentionId,
      ],
      [second.id, first.id],
    );
    await expectLogMatchesDatabase(beforeRemoval);
  });

  test('команды намерений: создание с тегами, изменение, готовность, '
      'архивирование вместе со связями, восстановление и удаление вместе с '
      'назначениями', () async {
    final home = await createTag('Дом');
    final sport = await createTag('Спорт');
    final health = (await confirm<IntentionSaved>(
      CreateIntention.withInitialState(
        title: 'Здоровье',
        description: 'Каждый день',
        readiness: IntentionReadiness.ready,
        tagIds: {home.id, sport.id},
      ),
    )).intention;
    final running = await createIntention('Бегать');
    final swimming = await createIntention('Плавать');
    await relate(health, running);
    await relate(swimming, health, group: IntentionRelationGroup.canUse);
    final reading = (await confirm<IntentionSaved>(
      CreateIntention.withInitialState(
        title: 'Читать',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: {home.id},
      ),
    )).intention;

    await confirm(
      UpdateIntention(
        id: running.id,
        title: 'Бегать по утрам',
        description: 'Пять километров\nв парке',
      ),
    );
    await confirm(EnableIntentionReadiness(running.id));
    await confirm(DisableIntentionReadiness(health.id));
    await confirm(ArchiveIntention(health.id));
    await confirm(RestoreIntention(health.id));
    await confirm(DeleteIntention(reading.id));
  });

  test('намерения, созданные после перевода часов назад, собираются из лога '
      'в порядке базы', () async {
    await createIntention('Здоровье');
    await createIntention('Бегать');

    now = now.subtract(const Duration(days: 1));
    await createIntention('Плавать');
    await createIntention('Читать');

    expect(
      [
        for (final record in await referenceGraphRecords(database))
          if (record case IntentionRecord(:final intention)) intention.title,
      ],
      ['Плавать', 'Читать', 'Здоровье', 'Бегать'],
    );
  });

  test('команды долговременных связей: создание, изменение, архивирование, '
      'восстановление и удаление', () async {
    final health = await createIntention('Здоровье');
    final running = await createIntention('Бегать');
    final swimming = await createIntention('Плавать');
    final relation = await relate(health, running);
    await confirm(
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: LongTermRelationPatch(
          priority: const LongTermRelationFieldSet(RelationPriority.p2),
          description: LongTermRelationDescriptionPatch.fromInput(
            'Сначала разминка',
          ),
        ),
      ),
    );
    await relate(health, swimming);

    await confirm(
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p1),
          description: LongTermRelationDescriptionCleared(),
        ),
      ),
    );
    await confirm(ArchiveLongTermRelation(relation.id));
    await confirm(RestoreLongTermRelation(relation.id));
    await confirm(DeleteLongTermRelation(relation.id));
  });

  test('команды действий и удаления в путях: изменение и удаление действий, '
      'появление и снятие надгробий намерения и пар', () async {
    final health = await createIntention('Здоровье');
    final running = await createIntention('Бегать');
    final morning = await createIntention('Пробежка утром');
    final healthRunning = await relate(health, running);
    final runningMorning = await relate(running, morning);
    final full = _actionId(1);
    final short = _actionId(2);
    await seedGraph(database, () async {
      await _insertAction(database, full, 'Пробежка в парке', [
        health,
        running,
        morning,
      ]);
      await _insertAction(database, short, 'Размяться', [health, running]);
      await _insertAction(database, _actionId(3), 'Выйти пораньше', [morning]);
    });
    seeded = await checkpoint();

    await confirm(
      UpdateActionFields(
        actionId: full,
        patch: ActionFieldsPatch(
          title: ActionFieldSet(ActionTitle('Пробежка у реки')),
          description: ActionFieldSet(ActionDescription.fromInput('Не спеша')),
          date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 19)),
          schedule: ActionFieldSet(ActionAtHour(7)),
          priority: const ActionFieldSet(ActionPriority.p1),
          isCompleted: const ActionFieldSet(true),
        ),
      ),
    );
    await confirm(DeleteLongTermRelation(healthRunning.id));
    final restored = await relate(health, running);
    // Удаление намерения со связями запрещено, поэтому связи удаляются
    // раньше.
    await confirm(DeleteLongTermRelation(restored.id));
    await confirm(DeleteLongTermRelation(runningMorning.id));
    await confirm(DeleteIntention(running.id));
    final deletion = _factKinds(await _lastPackageFacts(database));
    expect(
      deletion.where((kind) => kind == 'created DeletedIntentionRecord'),
      hasLength(1),
      reason: 'удаление намерения из двух путей даёт одно его надгробие',
    );
    expect(
      deletion,
      everyElement(isNot(contains('Action'))),
      reason: 'удаление намерения из путей не меняет действия',
    );
    await confirm(DeleteAction(short));
    await confirm(DeleteAction(full));
    expect(
      await referenceGraphRecords(database),
      everyElement(
        isNot(
          anyOf(
            isA<DeletedIntentionRecord>(),
            isA<DeletedRelationPairRecord>(),
          ),
        ),
      ),
      reason: 'удаление последнего пути снимает надгробия',
    );
  });
}

GraphStateBase _baseOf(_GraphCheckpoint checkpoint) => GraphStateBase(
  position: checkpoint.position,
  readRecords: () => Stream.fromIterable(checkpoint.records),
);

ActionId _actionId(int number) => (ActionId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as ActionIdDecodingSuccess).id;

/// Вставляет действие с путём [path]; вызывать внутри `seedGraph`.
Future<void> _insertAction(
  AppDatabase database,
  ActionId id,
  String title,
  List<Intention> path,
) async {
  await database.customStatement(
    'INSERT INTO actions (id, title, date, priority, is_completed, '
    "created_at, updated_at) VALUES (?, ?, '2026-10-17', 4, 0, 1, 1)",
    [id.toCanonicalString(), title],
  );
  for (final (position, intention) in path.indexed) {
    await database.customStatement(insertActionPathItem, [
      id.toCanonicalString(),
      position,
      intention.id.toCanonicalString(),
      position == 0 ? null : path[position - 1].id.toCanonicalString(),
      actionPathRole(position, path.length),
    ]);
  }
}

Future<List<GraphFact>> _lastPackageFacts(AppDatabase database) async {
  final package =
      await (database.select(database.graphLogPackages)
            ..orderBy([(package) => OrderingTerm.desc(package.position)])
            ..limit(1))
          .getSingle();
  return GraphFormatCodec.decodePackage(
    package.facts!,
    GraphFormatVersion.ofCarrier(package.formatVersion!),
  );
}

/// Вид факта и тип сущности, например `created DeletedIntentionRecord`.
List<String> _factKinds(List<GraphFact> facts) => [
  for (final fact in facts)
    switch (fact) {
      GraphEntityCreated(:final record) => 'created ${record.runtimeType}',
      GraphEntityChanged(:final record) => 'changed ${record.runtimeType}',
      GraphEntityDeleted(:final entity) => 'deleted ${entity.runtimeType}',
    },
];

Future<int> _lastPosition(AppDatabase database) async =>
    (await database
            .customSelect(
              'SELECT COALESCE(MAX(position), 0) AS position FROM graph_log_packages',
              readsFrom: {database.graphLogPackages},
            )
            .getSingle())
        .read<int>('position');

/// Пакеты лога после позиции [position] с фактами, прочитанными по
/// сохранённой версии формата.
Stream<GraphFactPackage> _packagesAfter(
  AppDatabase database,
  int position,
) async* {
  final packages =
      await (database.select(database.graphLogPackages)
            ..where((package) => package.position.isBiggerThanValue(position))
            ..orderBy([(package) => OrderingTerm.asc(package.position)]))
          .get();
  for (final package in packages) {
    yield GraphFactPackage(
      position: package.position,
      facts: GraphFormatCodec.decodePackage(
        package.facts!,
        GraphFormatVersion.ofCarrier(package.formatVersion!),
      ),
    );
  }
}

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

typedef _Counts = ({
  int tags,
  int intentions,
  int deletedIntentions,
  int tagAssignments,
  int longTermRelations,
  int deletedRelationPairs,
  int actions,
});

_Counts _counts(GraphRecordCounts counts) => (
  tags: counts.tags,
  intentions: counts.intentions,
  deletedIntentions: counts.deletedIntentions,
  tagAssignments: counts.tagAssignments,
  longTermRelations: counts.longTermRelations,
  deletedRelationPairs: counts.deletedRelationPairs,
  actions: counts.actions,
);

_Counts _countsOf(List<GraphEntityRecord> records) => (
  tags: records.whereType<TagRecord>().length,
  intentions: records.whereType<IntentionRecord>().length,
  deletedIntentions: records.whereType<DeletedIntentionRecord>().length,
  tagAssignments: records.whereType<TagAssignmentRecord>().length,
  longTermRelations: records.whereType<LongTermRelationRecord>().length,
  deletedRelationPairs: records.whereType<DeletedRelationPairRecord>().length,
  actions: records.whereType<ActionRecord>().length,
);
