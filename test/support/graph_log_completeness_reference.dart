import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/data/local/app_database.dart' as local;
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart';

import 'tag_positions.dart';

/// Эталонная выгрузка базы для проверки полноты лога фактов: записи формата
/// графа, прочитанные из таблиц графа собственными запросами, без механизма
/// фактов.
///
/// Записи идут в каноническом порядке файла формата: секции тегов,
/// намерений, надгробий намерений, назначений, долговременных связей,
/// надгробий пар, действий и дневных выборов, внутри секции — по
/// последовательности создания, намерения — по времени создания и
/// идентификатору, а надгробия — по ключу.
Future<List<GraphEntityRecord>> referenceGraphRecords(
  local.AppDatabase database,
) async {
  final tags = await (database.select(
    database.tags,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
  final intentions =
      await (database.select(database.intentions)..orderBy([
            (row) => OrderingTerm.asc(row.createdAt),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .get();
  final deletedIntentions = await (database.select(
    database.deletedIntentions,
  )..orderBy([(row) => OrderingTerm.asc(row.intentionId)])).get();
  final assignments = await (database.select(
    database.tagAssignments,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
  final relations = await (database.select(
    database.longTermRelations,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
  final deletedPairs =
      await (database.select(database.deletedRelationPairs)..orderBy([
            (row) => OrderingTerm.asc(row.sourceIntentionId),
            (row) => OrderingTerm.asc(row.relatedIntentionId),
          ]))
          .get();
  final actions = await (database.select(
    database.actions,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
  final pathItems = await (database.select(
    database.actionPathItems,
  )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
  final pathByAction = <String, List<IntentionId>>{};
  for (final item in pathItems) {
    pathByAction
        .putIfAbsent(item.actionId, () => [])
        .add(_intentionId(item.intentionId));
  }
  final choices = await (database.select(
    database.dailyChoices,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
  final stepsByChoice = <String, List<local.DailyChoicePathStep>>{};
  for (final step
      in await database.select(database.dailyChoicePathSteps).get()) {
    stepsByChoice.putIfAbsent(step.dailyChoiceId, () => []).add(step);
  }

  return [
    for (final row in tags)
      TagRecord(
        Tag(
          id: _tagId(row.id),
          name: TagName.fromStored(row.name),
          color: switch (row.color) {
            final code? => _tagColor(code),
            null => null,
          },
          position: tagPosition(row.position),
        ),
      ),
    for (final row in intentions) IntentionRecord(_intention(row)),
    for (final row in deletedIntentions)
      DeletedIntentionRecord(
        id: _intentionId(row.intentionId),
        title: row.title,
      ),
    for (final row in assignments)
      TagAssignmentRecord(
        TagAssignment(
          tagId: _tagId(row.tagId),
          intentionId: _intentionId(row.intentionId),
        ),
      ),
    for (final row in relations) _relation(row),
    for (final row in deletedPairs)
      DeletedRelationPairRecord(
        sourceIntentionId: _intentionId(row.sourceIntentionId),
        relatedIntentionId: _intentionId(row.relatedIntentionId),
        type: LongTermRelationType.values.byName(row.type),
      ),
    for (final row in actions)
      _action(row, ActionPath(pathByAction[row.id] ?? const [])),
    for (final row in choices)
      DailyChoiceRecord(
        choice: _dailyChoice(row),
        path: _path(stepsByChoice[row.id] ?? const []),
      ),
  ];
}

Intention _intention(local.Intention row) => Intention(
  id: _intentionId(row.id),
  title: row.title,
  description: row.description,
  readiness: row.isActionReady
      ? IntentionReadiness.ready
      : IntentionReadiness.notReady,
  archiveState: row.isArchived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
  createdAt: _timestamp(row.createdAt),
  updatedAt: _timestamp(row.updatedAt),
);

IntentionTimestamp _timestamp(int microseconds) =>
    IntentionTimestamp(_instant(microseconds));

DateTime _instant(int microseconds) =>
    DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);

LongTermRelationRecord _relation(local.LongTermRelation row) =>
    LongTermRelationRecord(
      id: _relationId(row.id),
      sourceIntentionId: _intentionId(row.sourceIntentionId),
      relatedIntentionId: _intentionId(row.relatedIntentionId),
      type: LongTermRelationType.values.byName(row.type),
      priority: RelationPriority.values.byName('p${row.priority}'),
      description: switch (row.description) {
        final description? => LongTermRelationDescription.fromInput(
          description,
        ),
        null => null,
      },
      scope: row.isArchived ? RelationScope.archived : RelationScope.active,
      createdAt: RelationTimestamp(_instant(row.createdAt)),
      updatedAt: RelationTimestamp(_instant(row.updatedAt)),
    );

ActionRecord _action(local.Action row, ActionPath path) => ActionRecord(
  id: (ActionId.decode(row.id) as ActionIdDecodingSuccess).id,
  title: ActionTitle(row.title),
  description: switch (row.description) {
    final description? => ActionDescription.fromInput(description),
    null => null,
  },
  path: path,
  date: CalendarDate.parseCanonical(row.date),
  schedule: switch (row.scheduledHour) {
    final hour? => ActionAtHour(hour),
    null => const ActionAllDay(),
  },
  priority: ActionPriority.values.byName('p${row.priority}'),
  isCompleted: row.isCompleted,
  createdAt: ActionTimestamp(_instant(row.createdAt)),
  updatedAt: ActionTimestamp(_instant(row.updatedAt)),
);

DailyChoice _dailyChoice(local.DailyChoice row) => DailyChoice(
  id: _dailyChoiceId(row.id),
  sourceIntentionId: _intentionId(row.sourceIntentionId),
  selectedIntentionId: _intentionId(row.selectedIntentionId),
  date: CalendarDate.parseCanonical(row.choiceDate),
  description: switch (row.description) {
    final description? => DailyChoiceDescription.fromStored(description),
    null => null,
  },
  isCompleted: row.isCompleted,
  schedule: switch (row.scheduledMinute) {
    final minute? => DailyChoiceTime(hour: minute ~/ 60, minute: minute % 60),
    null => const DailyChoiceAllDay(),
  },
  priority: DailyChoicePriority.values.byName('p${row.priority}'),
);

/// Шаги пути от корня по ссылкам на предыдущий шаг.
StoredChoicePath _path(List<local.DailyChoicePathStep> rows) {
  final byPrevious = {for (final row in rows) row.previousStepId: row};
  return StoredChoicePath([
    for (var row = byPrevious[null]; row != null; row = byPrevious[row.id])
      ChoicePathStep(
        id: _stepId(row.id),
        dailyChoiceId: _dailyChoiceId(row.dailyChoiceId),
        relationId: _relationId(row.longTermRelationId),
        previousStepId: switch (row.previousStepId) {
          final previous? => _stepId(previous),
          null => null,
        },
      ),
  ]);
}

TagId _tagId(String value) => (TagId.decode(value) as TagIdDecodingSuccess).id;

TagColor _tagColor(String code) =>
    (TagColor.decode(code) as TagColorDecodingSuccess).color;

IntentionId _intentionId(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String value) =>
    (LongTermRelationId.decode(value) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _dailyChoiceId(String value) =>
    (DailyChoiceId.decode(value) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId _stepId(String value) =>
    (ChoicePathStepId.decode(value) as ChoicePathStepIdDecodingSuccess).id;
