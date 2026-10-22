import 'package:drift/drift.dart';

import '../../data/local/app_database.dart' show AppDatabase;
import '../../graph_format/graph_format_records.dart';
import 'graph_record_rows.dart';
import 'stored_graph_rows.dart';

/// Превращает отметки, которые триггеры схемы ставят затронутым сущностям
/// графа, в пакет фактов текущей транзакции.
final class GraphFactCapture {
  const GraphFactCapture(this._database);

  final AppDatabase _database;

  /// Читает отметки и строки отмеченных сущностей, удаляет отметки и
  /// возвращает факты; пустой список — транзакция пакета не даёт.
  ///
  /// Факт несёт вид изменения сущности: «создана» и «изменена» — с полным
  /// состоянием сущности после транзакции, «удалена» — с её ключом;
  /// созданная и удалённая в этой же транзакции сущность факта не даёт.
  /// Факты идут в порядке секций формата, внутри секции — в порядке создания
  /// сущностей, как их перечисляет база, а затем удаления. Строка отмеченной
  /// сущности вне формы хранения даёт [StoredGraphCorruption].
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
                tag.id IS NOT NULL AS present, tag.id, tag.name,
                tag.color, tag.position
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
          record: () => TagRecord(decodeStoredTag(row.data)),
          key: () => TagKey(
            decodeStoredTagId(requiredStoredString(row.data, 'mark_id')),
          ),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _intentionFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.intention_id AS mark_id, mark.first_operation,
                intention.id IS NOT NULL AS present, intention.id,
                intention.title, intention.description,
                intention.is_action_ready, intention.is_archived,
                intention.created_at, intention.updated_at
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
          record: () => IntentionRecord(decodeStoredIntention(row.data)),
          key: () => IntentionKey(
            decodeStoredIntentionId(requiredStoredString(row.data, 'mark_id')),
          ),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _tagAssignmentFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.tag_id, mark.intention_id, mark.first_operation,
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
          record: () =>
              TagAssignmentRecord(decodeStoredTagAssignment(row.data)),
          key: () => TagAssignmentKey(decodeStoredTagAssignment(row.data)),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _relationFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.long_term_relation_id AS mark_id, mark.first_operation,
                relation.id IS NOT NULL AS present, relation.creation_sequence,
                relation.id, relation.source_intention_id,
                relation.related_intention_id, relation.type, relation.priority,
                relation.description, relation.is_archived
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
          record: () =>
              storedRelationRecord(StoredLongTermRelation.decode(row.data)),
          key: () => LongTermRelationKey(
            decodeStoredRelationId(requiredStoredString(row.data, 'mark_id')),
          ),
        ),
    ];
  }

  Future<Iterable<GraphFact>> _dailyChoiceFacts() async {
    final rows = await _database
        .customSelect(
          '''SELECT mark.daily_choice_id AS mark_id, mark.first_operation,
                choice.id IS NOT NULL AS present, choice.creation_sequence,
                choice.id, choice.source_intention_id,
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
          record: () =>
              storedDailyChoiceRecord(decodeStoredDailyChoice(row.data), paths),
          key: () => DailyChoiceKey(
            decodeStoredDailyChoiceId(
              requiredStoredString(row.data, 'mark_id'),
            ),
          ),
        ),
    ];
  }
}

/// Факт сущности с отметкой [row] по первой операции транзакции над ней и
/// её существованию после транзакции: с записью [record] сущности или с её
/// ключом [key].
GraphFact? _factOf(
  QueryRow row, {
  required GraphEntityRecord Function() record,
  required GraphEntityKey Function() key,
}) => switch ((
  inserted: row.read<String>('first_operation') == 'insert',
  present: row.read<bool>('present'),
)) {
  (inserted: true, present: true) => GraphEntityCreated(record()),
  (inserted: true, present: false) => null,
  (inserted: false, present: true) => GraphEntityChanged(record()),
  (inserted: false, present: false) => GraphEntityDeleted(key()),
};
