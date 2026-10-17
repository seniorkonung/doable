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
import '../../tag/domain/tag_assignment.dart';
import '../../tag/domain/tag_id.dart';
import '../../tag/domain/tag_name.dart';
import 'stored_choice_path_verification.dart';

/// Превращает отметки, которые триггеры схемы ставят затронутым сущностям
/// графа, в пакет фактов текущей транзакции.
final class GraphFactCapture {
  const GraphFactCapture(this._database);

  final AppDatabase _database;

  /// Читает отметки и строки отмеченных сущностей, удаляет отметки и
  /// возвращает факты; пустой список — транзакция пакета не даёт.
  ///
  /// Факт — запись с полным состоянием сущности после транзакции или её
  /// удаление; созданная и удалённая в этой же транзакции сущность факта не
  /// даёт. Факты идут в порядке секций формата, внутри секции — в порядке
  /// создания сущностей, как их перечисляет база, а затем удаления.
  ///
  /// Вызывать внутри транзакции записи после изменений графа.
  Future<List<GraphFact>> takeFacts() async {
    final facts = [
      ...await _tagFacts(),
      ...await _intentionFacts(),
      ...await _tagAssignmentFacts(),
      ...await _relationFacts(),
      ...await _dailyChoiceFacts(),
    ];
    for (final marks in _markTables) {
      await _database.delete(marks).go();
    }
    return facts;
  }

  /// Остались ли отметки: перед подтверждением транзакции записи их быть не
  /// должно, иначе часть её изменений не попала бы в пакет.
  Future<bool> hasMarks() async {
    final markTables = _markTables;
    final exists = [
      for (final marks in markTables)
        'EXISTS (SELECT 1 FROM ${marks.actualTableName})',
    ];
    final row = await _database
        .customSelect(
          'SELECT ${exists.join(' OR ')} AS has_marks',
          readsFrom: markTables.toSet(),
        )
        .getSingle();
    return row.read<bool>('has_marks');
  }

  List<TableInfo<Table, Object?>> get _markTables => [
    _database.graphLogTagMarks,
    _database.graphLogIntentionMarks,
    _database.graphLogTagAssignmentMarks,
    _database.graphLogLongTermRelationMarks,
    _database.graphLogDailyChoiceMarks,
  ];

  Future<Iterable<GraphFact>> _tagFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.tag_id AS mark_id, mark.first_operation,
                tag.id IS NOT NULL AS present, tag.name
         FROM graph_log_tag_marks AS mark
         LEFT JOIN tags AS tag ON tag.id = mark.tag_id
         ORDER BY tag.creation_sequence IS NULL, tag.creation_sequence,
                  mark.tag_id''',
          readsFrom: {_database.graphLogTagMarks, _database.tags},
        )
        .get();
    return [
      for (final row in rows)
        ?_factOf(
          row,
          _decodeTagId(row.read<String>('mark_id')),
          TagKey.new,
          (id) => TagRecord(
            Tag(id: id, name: TagName.fromStored(row.read<String>('name'))),
          ),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _intentionFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.intention_id AS mark_id, mark.first_operation,
                intention.id IS NOT NULL AS present, intention.title,
                intention.description, intention.is_action_ready,
                intention.is_archived, intention.created_at,
                intention.updated_at
         FROM graph_log_intention_marks AS mark
         LEFT JOIN intentions AS intention ON intention.id = mark.intention_id
         ORDER BY intention.id IS NULL, intention.created_at, intention.id,
                  mark.intention_id''',
          readsFrom: {_database.graphLogIntentionMarks, _database.intentions},
        )
        .get();
    return [
      for (final row in rows)
        ?_factOf(
          row,
          _decodeIntentionId(row.read<String>('mark_id')),
          IntentionKey.new,
          (id) => IntentionRecord(_decodeIntention(id, row)),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _tagAssignmentFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.tag_id AS mark_tag_id,
                mark.intention_id AS mark_intention_id, mark.first_operation,
                assignment.creation_sequence IS NOT NULL AS present
         FROM graph_log_tag_assignment_marks AS mark
         LEFT JOIN tag_assignments AS assignment
           ON assignment.tag_id = mark.tag_id AND
              assignment.intention_id = mark.intention_id
         ORDER BY assignment.creation_sequence IS NULL,
                  assignment.creation_sequence, mark.tag_id,
                  mark.intention_id''',
          readsFrom: {
            _database.graphLogTagAssignmentMarks,
            _database.tagAssignments,
          },
        )
        .get();
    return [
      for (final row in rows)
        ?_factOf(
          row,
          TagAssignment(
            tagId: _decodeTagId(row.read<String>('mark_tag_id')),
            intentionId: _decodeIntentionId(
              row.read<String>('mark_intention_id'),
            ),
          ),
          TagAssignmentKey.new,
          TagAssignmentRecord.new,
        ),
    ];
  }

  Future<Iterable<GraphFact>> _relationFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.long_term_relation_id AS mark_id, mark.first_operation,
                relation.id IS NOT NULL AS present,
                relation.source_intention_id, relation.related_intention_id,
                relation.type, relation.priority, relation.description,
                relation.is_archived
         FROM graph_log_long_term_relation_marks AS mark
         LEFT JOIN long_term_relations AS relation
           ON relation.id = mark.long_term_relation_id
         ORDER BY relation.creation_sequence IS NULL,
                  relation.creation_sequence, mark.long_term_relation_id''',
          readsFrom: {
            _database.graphLogLongTermRelationMarks,
            _database.longTermRelations,
          },
        )
        .get();
    return [
      for (final row in rows)
        ?_factOf(
          row,
          _decodeRelationId(row.read<String>('mark_id')),
          LongTermRelationKey.new,
          (id) => _decodeRelation(id, row),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _dailyChoiceFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.daily_choice_id AS mark_id, mark.first_operation,
                choice.id IS NOT NULL AS present, choice.source_intention_id,
                choice.selected_intention_id, choice.choice_date,
                choice.description, choice.is_completed,
                choice.scheduled_minute, choice.priority
         FROM graph_log_daily_choice_marks AS mark
         LEFT JOIN daily_choices AS choice ON choice.id = mark.daily_choice_id
         ORDER BY choice.creation_sequence IS NULL, choice.creation_sequence,
                  mark.daily_choice_id''',
          readsFrom: {
            _database.graphLogDailyChoiceMarks,
            _database.dailyChoices,
          },
        )
        .get();
    if (rows.isEmpty) return const [];
    final paths = await _readMarkedChoicePaths();
    return [
      for (final row in rows)
        ?_factOf(
          row,
          _decodeDailyChoiceId(row.read<String>('mark_id')),
          DailyChoiceKey.new,
          (id) => _dailyChoiceRecord(_decodeDailyChoice(id, row), paths),
        ),
    ];
  }

  /// Шаги путей отмеченных выборов и концы связей этих шагов.
  Future<_ChoicePaths> _readMarkedChoicePaths() async {
    final stepRows = await _database
        .customSelect(
          '''SELECT step.id, step.daily_choice_id, step.long_term_relation_id,
                step.previous_step_id
         FROM graph_log_daily_choice_marks AS mark
         JOIN daily_choice_path_steps AS step
           ON step.daily_choice_id = mark.daily_choice_id''',
          readsFrom: {
            _database.graphLogDailyChoiceMarks,
            _database.dailyChoicePathSteps,
          },
        )
        .get();
    final steps = <DailyChoiceId, List<ChoicePathStep>>{};
    for (final row in stepRows) {
      final previous = row.readNullable<String>('previous_step_id');
      final step = ChoicePathStep(
        id: _decodeStepId(row.read<String>('id')),
        dailyChoiceId: _decodeDailyChoiceId(
          row.read<String>('daily_choice_id'),
        ),
        relationId: _decodeRelationId(
          row.read<String>('long_term_relation_id'),
        ),
        previousStepId: previous == null ? null : _decodeStepId(previous),
      );
      steps.putIfAbsent(step.dailyChoiceId, () => []).add(step);
    }

    final relationRows = await _database
        .customSelect(
          '''SELECT DISTINCT relation.id, relation.source_intention_id,
                relation.related_intention_id
         FROM graph_log_daily_choice_marks AS mark
         JOIN daily_choice_path_steps AS step
           ON step.daily_choice_id = mark.daily_choice_id
         JOIN long_term_relations AS relation
           ON relation.id = step.long_term_relation_id''',
          readsFrom: {
            _database.graphLogDailyChoiceMarks,
            _database.dailyChoicePathSteps,
            _database.longTermRelations,
          },
        )
        .get();
    return (
      steps: steps,
      relations: {
        for (final row in relationRows)
          _decodeRelationId(row.read<String>('id')): (
            source: _decodeIntentionId(row.read<String>('source_intention_id')),
            related: _decodeIntentionId(
              row.read<String>('related_intention_id'),
            ),
          ),
      },
    );
  }
}

/// Факт сущности с отметкой [row] и ключом [key]: запись, если сущность есть
/// после транзакции, иначе удаление, если сущность не создана в этой же
/// транзакции.
GraphFact? _factOf<K>(
  QueryRow row,
  K key,
  GraphEntityKey Function(K key) entityKey,
  GraphEntityRecord Function(K key) record,
) {
  if (row.read<bool>('present')) return record(key);
  return row.read<String>('first_operation') == 'insert'
      ? null
      : GraphEntityDeletion(entityKey(key));
}

/// Название и описание хранятся в той форме, к которой их приводит ввод.
Intention _decodeIntention(IntentionId id, QueryRow row) {
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
    createdAt: _decodeTimestamp(row.read<int>('created_at')),
    updatedAt: _decodeTimestamp(row.read<int>('updated_at')),
  );
  if (intention.title != title || intention.description != description) {
    throw StateError('Текст намерения хранится не в форме ввода.');
  }
  return intention;
}

IntentionTimestamp _decodeTimestamp(int microseconds) => IntentionTimestamp(
  DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true),
);

LongTermRelationRecord _decodeRelation(LongTermRelationId id, QueryRow row) {
  final description = row.readNullable<String>('description');
  return LongTermRelationRecord(
    id: id,
    sourceIntentionId: _decodeIntentionId(
      row.read<String>('source_intention_id'),
    ),
    relatedIntentionId: _decodeIntentionId(
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

DailyChoice _decodeDailyChoice(DailyChoiceId id, QueryRow row) {
  final description = row.readNullable<String>('description');
  final minute = row.readNullable<int>('scheduled_minute');
  return DailyChoice(
    id: id,
    sourceIntentionId: _decodeIntentionId(
      row.read<String>('source_intention_id'),
    ),
    selectedIntentionId: _decodeIntentionId(
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

typedef _ChoicePaths = ({
  Map<DailyChoiceId, List<ChoicePathStep>> steps,
  Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
});

DailyChoiceRecord _dailyChoiceRecord(DailyChoice choice, _ChoicePaths paths) =>
    DailyChoiceRecord(
      choice: choice,
      path:
          verifyStoredChoicePath(
            choice: choice,
            steps: paths.steps[choice.id] ?? const [],
            relations: paths.relations,
          ) ??
          (throw StateError('Шаги дневного выбора не образуют путь выбора.')),
    );

TagId _decodeTagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Идентификатор тега вне формы.'),
};

IntentionId _decodeIntentionId(String value) =>
    switch (IntentionId.decode(value)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError(
        'Идентификатор намерения вне формы.',
      ),
    };

LongTermRelationId _decodeRelationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Идентификатор связи вне формы.',
      ),
    };

DailyChoiceId _decodeDailyChoiceId(String value) =>
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
