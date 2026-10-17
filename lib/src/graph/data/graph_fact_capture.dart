import 'package:drift/drift.dart';

import '../../data/local/app_database.dart' show AppDatabase;
import '../../graph_format/graph_format_records.dart';
import '../../tag/domain/tag_assignment.dart';
import 'graph_record_rows.dart';

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
          decodeStoredTagId(row.read<String>('mark_id')),
          TagKey.new,
          (id) => storedTagRecord(id, row),
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
          decodeStoredIntentionId(row.read<String>('mark_id')),
          IntentionKey.new,
          (id) => storedIntentionRecord(id, row),
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
            tagId: decodeStoredTagId(row.read<String>('mark_tag_id')),
            intentionId: decodeStoredIntentionId(
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
          decodeStoredRelationId(row.read<String>('mark_id')),
          LongTermRelationKey.new,
          (id) => storedRelationRecord(id, row),
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
    final paths = await readStoredChoicePaths(
      _database,
      choiceIds: 'SELECT daily_choice_id FROM graph_log_daily_choice_marks',
      readsFrom: {_database.graphLogDailyChoiceMarks},
    );
    return [
      for (final row in rows)
        ?_factOf(
          row,
          decodeStoredDailyChoiceId(row.read<String>('mark_id')),
          DailyChoiceKey.new,
          (id) => storedDailyChoiceRecord(storedDailyChoice(id, row), paths),
        ),
    ];
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
