import 'package:drift/drift.dart';

import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/domain/choice_path_step_id.dart';
import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_description.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../daily_choice/domain/daily_choice_priority.dart';
import '../../daily_choice/domain/daily_choice_schedule.dart';
import '../../data/local/app_database.dart' show AppDatabase;
import '../../graph_format/graph_format_records.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../tag/domain/tag.dart';
import '../../tag/domain/tag_id.dart';
import '../../tag/domain/tag_name.dart';
import 'stored_choice_path_verification.dart';

// Записи формата графа из строк таблиц графа. Механизм фактов и чтение
// записей порциями читают строки своими запросами со столбцами под именами
// таблиц и получают из одной строки одну запись. Строка вне формы записи
// нарушает схему или единый путь записи и даёт StateError.

TagRecord storedTagRecord(TagId id, QueryRow row) =>
    TagRecord(Tag(id: id, name: TagName.fromStored(row.read<String>('name'))));

/// Название и описание хранятся в той форме, к которой их приводит ввод.
IntentionRecord storedIntentionRecord(IntentionId id, QueryRow row) {
  final title = row.read<String>('title');
  final description = row.readNullable<String>('description');
  final intention = Intention(
    id: id,
    title: title,
    description: description,
    readiness: row.read<bool>('is_action_ready')
        ? IntentionReadiness.ready
        : IntentionReadiness.notReady,
    archiveState: row.read<bool>('is_archived')
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: _storedTimestamp(row.read<int>('created_at')),
    updatedAt: _storedTimestamp(row.read<int>('updated_at')),
  );
  if (intention.title != title || intention.description != description) {
    throw StateError('Текст намерения хранится не в форме ввода.');
  }
  return IntentionRecord(intention);
}

IntentionTimestamp _storedTimestamp(int microseconds) => IntentionTimestamp(
  DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true),
);

LongTermRelationRecord storedRelationRecord(
  LongTermRelationId id,
  QueryRow row,
) {
  final description = row.readNullable<String>('description');
  return LongTermRelationRecord(
    id: id,
    sourceIntentionId: decodeStoredIntentionId(
      row.read<String>('source_intention_id'),
    ),
    relatedIntentionId: decodeStoredIntentionId(
      row.read<String>('related_intention_id'),
    ),
    type: switch (row.read<String>('type')) {
      'need' => LongTermRelationType.need,
      'can' => LongTermRelationType.can,
      _ => throw StateError('Тип связи вне схемы.'),
    },
    priority: switch (row.read<int>('priority')) {
      1 => RelationPriority.p1,
      2 => RelationPriority.p2,
      3 => RelationPriority.p3,
      4 => RelationPriority.p4,
      _ => throw StateError('Приоритет связи вне схемы.'),
    },
    description: description == null
        ? null
        : LongTermRelationDescription.fromInput(description) ??
              (throw StateError('Описание связи хранится пустым.')),
    scope: row.read<bool>('is_archived')
        ? RelationScope.archived
        : RelationScope.active,
  );
}

DailyChoice storedDailyChoice(DailyChoiceId id, QueryRow row) {
  final description = row.readNullable<String>('description');
  final minute = row.readNullable<int>('scheduled_minute');
  return DailyChoice(
    id: id,
    sourceIntentionId: decodeStoredIntentionId(
      row.read<String>('source_intention_id'),
    ),
    selectedIntentionId: decodeStoredIntentionId(
      row.read<String>('selected_intention_id'),
    ),
    date: CalendarDate.parseCanonical(row.read<String>('choice_date')),
    description: description == null
        ? null
        : DailyChoiceDescription.fromStored(description),
    isCompleted: row.read<bool>('is_completed'),
    schedule: minute == null
        ? const DailyChoiceAllDay()
        : DailyChoiceTime(hour: minute ~/ 60, minute: minute % 60),
    priority: switch (row.read<int>('priority')) {
      1 => DailyChoicePriority.p1,
      2 => DailyChoicePriority.p2,
      3 => DailyChoicePriority.p3,
      4 => DailyChoicePriority.p4,
      _ => throw StateError('Приоритет дневного выбора вне схемы.'),
    },
  );
}

/// Шаги путей дневных выборов и концы связей этих шагов.
typedef StoredChoicePaths = ({
  Map<DailyChoiceId, List<ChoicePathStep>> steps,
  Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
});

/// Шаги путей выборов, идентификаторы которых выдаёт подзапрос [choiceIds]
/// с переменными [variables], и концы связей этих шагов.
Future<StoredChoicePaths> readStoredChoicePaths(
  AppDatabase database, {
  required String choiceIds,
  List<Variable<Object>> variables = const [],
  required Set<ResultSetImplementation<dynamic, dynamic>> readsFrom,
}) async {
  final stepRows = await database
      .customSelect(
        '''SELECT step.id, step.daily_choice_id, step.long_term_relation_id,
              step.previous_step_id
       FROM daily_choice_path_steps AS step
       WHERE step.daily_choice_id IN ($choiceIds)''',
        variables: variables,
        readsFrom: {...readsFrom, database.dailyChoicePathSteps},
      )
      .get();
  final steps = <DailyChoiceId, List<ChoicePathStep>>{};
  for (final row in stepRows) {
    final previous = row.readNullable<String>('previous_step_id');
    final step = ChoicePathStep(
      id: _decodeStepId(row.read<String>('id')),
      dailyChoiceId: decodeStoredDailyChoiceId(
        row.read<String>('daily_choice_id'),
      ),
      relationId: decodeStoredRelationId(
        row.read<String>('long_term_relation_id'),
      ),
      previousStepId: previous == null ? null : _decodeStepId(previous),
    );
    steps.putIfAbsent(step.dailyChoiceId, () => []).add(step);
  }

  final relationRows = await database
      .customSelect(
        '''SELECT DISTINCT relation.id, relation.source_intention_id,
              relation.related_intention_id
       FROM daily_choice_path_steps AS step
       JOIN long_term_relations AS relation
         ON relation.id = step.long_term_relation_id
       WHERE step.daily_choice_id IN ($choiceIds)''',
        variables: variables,
        readsFrom: {
          ...readsFrom,
          database.dailyChoicePathSteps,
          database.longTermRelations,
        },
      )
      .get();
  return (
    steps: steps,
    relations: {
      for (final row in relationRows)
        decodeStoredRelationId(row.read<String>('id')): (
          source: decodeStoredIntentionId(
            row.read<String>('source_intention_id'),
          ),
          related: decodeStoredIntentionId(
            row.read<String>('related_intention_id'),
          ),
        ),
    },
  );
}

/// Запись выбора [choice] с его путём из [paths].
DailyChoiceRecord storedDailyChoiceRecord(
  DailyChoice choice,
  StoredChoicePaths paths,
) => DailyChoiceRecord(
  choice: choice,
  path:
      verifyStoredChoicePath(
        choice: choice,
        steps: paths.steps[choice.id] ?? const [],
        relations: paths.relations,
      ) ??
      (throw StateError('Шаги дневного выбора не образуют путь выбора.')),
);

TagId decodeStoredTagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Идентификатор тега вне формы.'),
};

IntentionId decodeStoredIntentionId(String value) =>
    switch (IntentionId.decode(value)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError(
        'Идентификатор намерения вне формы.',
      ),
    };

LongTermRelationId decodeStoredRelationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Идентификатор связи вне формы.',
      ),
    };

DailyChoiceId decodeStoredDailyChoiceId(String value) =>
    switch (DailyChoiceId.decode(value)) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw StateError(
        'Идентификатор дневного выбора вне формы.',
      ),
    };

ChoicePathStepId _decodeStepId(String value) =>
    switch (ChoicePathStepId.decode(value)) {
      ChoicePathStepIdDecodingSuccess(:final id) => id,
      InvalidChoicePathStepIdDecoding() => throw StateError(
        'Идентификатор шага пути вне формы.',
      ),
    };
