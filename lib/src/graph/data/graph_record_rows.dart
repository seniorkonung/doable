import 'package:drift/drift.dart';

import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../data/local/app_database.dart' show AppDatabase;
import '../../graph_format/graph_format_records.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'stored_choice_path_verification.dart';
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
    final step = decodeStoredChoicePathStep(row.data);
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
        decodeStoredRelationId(requiredStoredString(row.data, 'id')):
            decodeStoredRelationEnds(row.data),
    },
  );
}

/// Запись выбора [choice] с его путём из [paths].
DailyChoiceRecord storedDailyChoiceRecord(
  DailyChoice choice,
  StoredChoicePaths paths,
) => DailyChoiceRecord(
  choice: choice,
  path: verifyStoredChoicePath(
    choice: choice,
    steps: paths.steps[choice.id] ?? const [],
    relations: paths.relations,
  ),
);
