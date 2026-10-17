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
    );

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
