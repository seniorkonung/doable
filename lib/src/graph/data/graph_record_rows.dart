import 'package:drift/drift.dart';

import '../../data/local/app_database.dart' show AppDatabase;
import '../../graph_format/graph_format_records.dart';
import 'stored_graph_rows.dart';

// Записи формата графа из строк таблиц графа. Механизм фактов и чтение
// записей порциями разбирают строки общим разбором stored_graph_rows.dart и
// собирают из них записи формата.

/// Запись связи [relation].
LongTermRelationRecord storedRelationRecord(StoredLongTermRelation relation) =>
    LongTermRelationRecord(
      id: relation.id,
      sourceIntentionId: relation.sourceIntentionId,
      relatedIntentionId: relation.relatedIntentionId,
      type: relation.type,
      priority: relation.priority,
      description: relation.description,
      scope: relation.scope,
      createdAt: relation.createdAt,
      updatedAt: relation.updatedAt,
    );

/// Надгробие намерения из столбцов `intention_id` и `title` таблицы
/// `deleted_intentions`. Название хранится в форме названия намерения.
DeletedIntentionRecord storedDeletedIntentionRecord(
  Map<String, Object?> data,
) => DeletedIntentionRecord(
  id: decodeStoredIntentionId(requiredStoredString(data, 'intention_id')),
  title: decodeStoredIntentionTitle(data, 'title'),
);

/// Надгробие пары из столбцов таблицы `deleted_relation_pairs`.
DeletedRelationPairRecord storedDeletedRelationPairRecord(
  Map<String, Object?> data,
) {
  final ends = decodeStoredRelationEnds(data);
  try {
    return DeletedRelationPairRecord(
      sourceIntentionId: ends.source,
      relatedIntentionId: ends.related,
      type: decodeStoredRelationType(data),
    );
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

/// Строки путей действий по столбцу `action_id` в порядке позиций.
typedef StoredActionPathRows = Map<String, List<Map<String, Object?>>>;

/// Строки путей действий, идентификаторы которых выдаёт подзапрос
/// [actionIds] с переменными [variables].
Future<StoredActionPathRows> readStoredActionPathRows(
  AppDatabase database, {
  required String actionIds,
  List<Variable<Object>> variables = const [],
  required Set<ResultSetImplementation<dynamic, dynamic>> readsFrom,
}) async {
  final rows = await database
      .customSelect(
        '''SELECT action_id, position, intention_id, previous_intention_id
       FROM action_path_items
       WHERE action_id IN ($actionIds)
       ORDER BY action_id, position''',
        variables: variables,
        readsFrom: {...readsFrom, database.actionPathItems},
      )
      .get();
  final paths = <String, List<Map<String, Object?>>>{};
  for (final row in rows) {
    paths
        .putIfAbsent(requiredStoredString(row.data, 'action_id'), () => [])
        .add(row.data);
  }
  return paths;
}

/// Запись действия из столбцов таблицы `actions` в [data] с путём из
/// [paths]; действие без строк пути даёт [StoredGraphCorruption].
ActionRecord storedActionRecord(
  Map<String, Object?> data,
  StoredActionPathRows paths,
) {
  final action = decodeStoredAction(
    data,
    paths[requiredStoredString(data, 'id')] ?? const [],
  );
  return ActionRecord(
    id: action.id,
    title: action.title,
    description: action.description,
    path: action.path,
    date: action.date,
    schedule: action.schedule,
    priority: action.priority,
    isCompleted: action.isCompleted,
    createdAt: action.createdAt,
    updatedAt: action.updatedAt,
  );
}
