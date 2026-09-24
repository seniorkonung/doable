import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

import 'in_memory_diagnostics_sink.dart';

String durabilityUuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId durabilityIntention(int number) => (IntentionId.decode(
  durabilityUuid(number),
) as IntentionIdDecodingSuccess).id;

LongTermRelationId durabilityRelation(int number) => (LongTermRelationId.decode(
  durabilityUuid(number),
) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId durabilityChoice(int number) => (DailyChoiceId.decode(
  durabilityUuid(number),
) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId durabilityStep(int number) => (ChoicePathStepId.decode(
  durabilityUuid(number),
) as ChoicePathStepIdDecodingSuccess).id;

final class FixedChoiceIds implements DailyChoiceIdGenerator {
  FixedChoiceIds(this._id);
  final DailyChoiceId _id;

  @override
  DailyChoiceId generate() => _id;
}

final class SequentialStepIds implements ChoicePathStepIdGenerator {
  SequentialStepIds(this._next);
  int _next;

  @override
  ChoicePathStepId generate() => durabilityStep(_next++);
}

DriftPersonalGraphRepository durabilityRepository(
  AppDatabase database, {
  int choiceNumber = 201,
  int firstStepNumber = 301,
}) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 23),
  InMemoryDiagnosticsSink(),
  dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(choiceNumber)),
  choicePathStepIdGenerator: SequentialStepIds(firstStepNumber),
);

Future<void> seedDurabilityGraph(AppDatabase database) async {
  for (var number = 1; number <= 5; number++) {
    await database.customStatement(
      '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, 0, 1, 1)''',
      [
        durabilityUuid(number),
        'Намерение $number',
        number == 3 || number == 4 ? 1 : 0,
      ],
    );
  }
  for (final (number, source, related, type) in [
    (101, 1, 2, 'need'),
    (102, 2, 3, 'can'),
    (103, 1, 4, 'need'),
    (104, 1, 5, 'can'),
  ]) {
    await database.customStatement(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id,
          type, priority, is_archived)
         VALUES (?, ?, ?, ?, 2, 0)''',
      [
        durabilityUuid(number),
        durabilityUuid(source),
        durabilityUuid(related),
        type,
      ],
    );
  }
}

ConfirmedChoicePath durabilityPath(List<int> relationNumbers) =>
    ConfirmedChoicePath([
      for (final number in relationNumbers)
        ConfirmedChoicePathStep(
          relationId: durabilityRelation(number),
          sourceIntentionId: durabilityIntention(switch (number) {
            101 || 103 || 104 => 1,
            102 => 2,
            _ => throw ArgumentError.value(number),
          }),
          type: switch (number) {
            102 || 104 => LongTermRelationType.can,
            101 || 103 => LongTermRelationType.need,
            _ => throw ArgumentError.value(number),
          },
          relatedIntentionId: durabilityIntention(switch (number) {
            101 => 2,
            102 => 3,
            103 => 4,
            104 => 5,
            _ => throw ArgumentError.value(number),
          }),
        ),
    ]);

CreateDailyChoice durabilityCreate({
  List<int> path = const [101, 102],
  CalendarDate? date,
  String? description = '  Выбор\nдня  ',
  bool completed = true,
}) => CreateDailyChoice(
  sourceIntentionId: durabilityIntention(1),
  selectedIntentionId: durabilityIntention(path.last == 103 ? 4 : 3),
  path: durabilityPath(path),
  date: date ?? CalendarDate.fromParts(2026, 9, 23),
  description: description == null
      ? null
      : DailyChoiceDescription.fromInput(description),
  isCompleted: completed,
);

CreateDailyChoice durabilityBottomCreate({List<int> path = const [101, 102]}) {
  final top = durabilityCreate(path: path);
  final draft = ChoicePathDraftBottomProgress(
    top.selectedIntentionId,
    top.path.steps.reversed,
  );
  return CreateDailyChoice(
    sourceIntentionId: draft.currentIntentionId,
    selectedIntentionId: draft.selectedActionId,
    path: draft.confirmedPath,
    date: top.date,
    description: top.description,
    isCompleted: top.isCompleted,
  );
}

UpdateDailyChoiceFields durabilityUpdate(int choiceNumber) =>
    UpdateDailyChoiceFields(
      choiceId: durabilityChoice(choiceNumber),
      patch: DailyChoiceFieldsPatch(
        date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 2)),
        description: DailyChoiceDescriptionSet(
          DailyChoiceDescription.fromInput('  Изменено  ')!,
        ),
        isCompleted: const DailyChoiceFieldSet(false),
      ),
    );

ReplaceDailyChoicePath durabilityReplace(int choiceNumber) =>
    ReplaceDailyChoicePath(
      choiceId: durabilityChoice(choiceNumber),
      sourceIntentionId: durabilityIntention(1),
      selectedIntentionId: durabilityIntention(4),
      path: durabilityPath([103]),
    );

DeleteBlockingRelations durabilityMixedDelete(int choiceNumber) =>
    DeleteBlockingRelations(
      intentionId: durabilityIntention(1),
      references: [
        DailyChoiceBlockingRelationReference(durabilityChoice(choiceNumber)),
        LongTermBlockingRelationReference(durabilityRelation(104)),
      ],
    );

Future<List<Map<String, Object?>>> durabilityRows(
  AppDatabase database,
  String table,
) async => [
  for (final row
      in await database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .get())
    Map<String, Object?>.from(row.data),
];

Future<List<Object>> durabilityState(AppDatabase database) async => [
  await durabilityRows(database, 'intentions'),
  await durabilityRows(database, 'long_term_relations'),
  await durabilityRows(database, 'daily_choices'),
  await durabilityRows(database, 'daily_choice_path_steps'),
];
