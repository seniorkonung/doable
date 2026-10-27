import 'dart:convert';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
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
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show ComparableExpr, OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_log_completeness_reference.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Состояние графа по выгрузке базы на позиции последнего пакета лога.
typedef _GraphCheckpoint = ({int position, List<GraphEntityRecord> records});

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
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

  /// Сверяет выгрузку базы с состоянием, собранным из лога от позиции 0 и
  /// от промежуточного состояния [base].
  Future<void> expectLogMatchesDatabase(_GraphCheckpoint base) async {
    final expected = await referenceGraphRecords(database);
    for (final (description, assemblyBase) in [
      ('от позиции 0', const GraphStateBase.empty()),
      (
        'от позиции ${base.position}',
        GraphStateBase(
          position: base.position,
          readRecords: () => Stream.fromIterable(base.records),
        ),
      ),
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
    await relate(swimming, health, type: LongTermRelationType.can);
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
    final relation = (await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: health.id,
        relatedIntentionId: running.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: LongTermRelationDescription.fromInput('Сначала разминка'),
      ),
    )).relation;
    await relate(health, swimming);

    await confirm(
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: LongTermRelationPatch(
          type: const LongTermRelationFieldSet(LongTermRelationType.can),
          priority: const LongTermRelationFieldSet(RelationPriority.p1),
          sourceIntentionId: LongTermRelationFieldSet(swimming.id),
          description: const LongTermRelationDescriptionCleared(),
        ),
      ),
    );
    await confirm(ArchiveLongTermRelation(relation.id));
    await confirm(RestoreLongTermRelation(relation.id));
    await confirm(DeleteLongTermRelation(relation.id));
  });

  test('команды дневных выборов: создание, изменение полей, замена пути и '
      'удаление вместе с шагами', () async {
    final health = await createIntention('Здоровье');
    final running = await createIntention(
      'Бегать',
      readiness: IntentionReadiness.ready,
    );
    final morning = await createIntention(
      'Пробежка утром',
      readiness: IntentionReadiness.ready,
    );
    final swimming = await createIntention(
      'Плавать',
      readiness: IntentionReadiness.ready,
    );
    final needRunning = await relate(health, running);
    final needMorning = await relate(running, morning);
    final canSwim = await relate(
      health,
      swimming,
      type: LongTermRelationType.can,
    );
    final choice = (await confirm<DailyChoiceCreated>(
      CreateDailyChoice(
        sourceIntentionId: health.id,
        selectedIntentionId: morning.id,
        path: _path([needRunning, needMorning]),
        date: CalendarDate.fromParts(2026, 10, 17),
        description: DailyChoiceDescription.fromInput('До работы'),
        isCompleted: false,
        schedule: DailyChoiceTime(hour: 7, minute: 30),
        priority: DailyChoicePriority.p2,
      ),
    )).choice;
    await confirm(
      CreateDailyChoice(
        sourceIntentionId: health.id,
        selectedIntentionId: running.id,
        path: _path([needRunning]),
        date: CalendarDate.fromParts(2026, 10, 18),
        description: null,
        isCompleted: false,
      ),
    );

    await confirm(
      UpdateDailyChoiceFields(
        choiceId: choice.id,
        patch: DailyChoiceFieldsPatch(
          date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 10, 19)),
          description: const DailyChoiceDescriptionCleared(),
          isCompleted: const DailyChoiceFieldSet(true),
          schedule: const DailyChoiceFieldSet(DailyChoiceAllDay()),
          priority: const DailyChoiceFieldSet(DailyChoicePriority.p1),
        ),
      ),
    );
    await confirm(
      ReplaceDailyChoicePath(
        choiceId: choice.id,
        sourceIntentionId: health.id,
        selectedIntentionId: swimming.id,
        path: _path([canSwim]),
      ),
    );
    await confirm(DeleteDailyChoice(choice.id));
  });
}

ConfirmedChoicePath _path(List<LongTermRelation> relations) =>
    ConfirmedChoicePath([
      for (final relation in relations)
        ConfirmedChoicePathStep(
          relationId: relation.id,
          sourceIntentionId: relation.sourceIntentionId,
          type: relation.type,
          relatedIntentionId: relation.relatedIntentionId,
        ),
    ]);

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
