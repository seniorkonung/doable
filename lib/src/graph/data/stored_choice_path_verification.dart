import '../../daily_choice/domain/choice_path_step_id.dart';
import '../../daily_choice/domain/daily_choice.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'stored_graph_rows.dart';

/// Упорядочивает сохранённые шаги пути [choice] от корня и проверяет его
/// связи [relations]; шаги, которые не образуют путь выбора, дают
/// [StoredGraphCorruption].
///
/// Единственность шага, корня и преемника каждого шага гарантируют первичный
/// ключ и уникальные индексы схемы, предшественника из того же выбора —
/// составной внешний ключ, а шаги читаются по идентификатору выбора.
/// Существование намерений обеспечивает вызывающий код проверкой или
/// внешними ключами схемы. Проверяется то, чего схема не выражает: путь не
/// пуст, непрерывен от источника до выбранного намерения, не повторяет
/// намерения и не содержит шагов вне цепочки от корня.
StoredChoicePath verifyStoredChoicePath({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
}) {
  final successors = <ChoicePathStepId, ChoicePathStep>{};
  ChoicePathStep? root;
  for (final step in steps) {
    final previous = step.previousStepId;
    if (previous == null) {
      root = step;
    } else {
      successors[previous] = step;
    }
  }
  if (root == null) throw const StoredGraphCorruption();

  final ordered = <ChoicePathStep>[];
  final seenSteps = <ChoicePathStepId>{};
  final seenIntentions = <IntentionId>{choice.sourceIntentionId};
  var currentIntentionId = choice.sourceIntentionId;
  ChoicePathStep? currentStep = root;
  while (currentStep != null) {
    if (!seenSteps.add(currentStep.id)) throw const StoredGraphCorruption();
    final storedRelation = relations[currentStep.relationId];
    if (storedRelation == null ||
        storedRelation.source != currentIntentionId ||
        !seenIntentions.add(storedRelation.related)) {
      throw const StoredGraphCorruption();
    }
    ordered.add(currentStep);
    currentIntentionId = storedRelation.related;
    currentStep = successors[currentStep.id];
  }
  if (seenSteps.length != steps.length ||
      currentIntentionId != choice.selectedIntentionId) {
    throw const StoredGraphCorruption();
  }
  return StoredChoicePath(ordered);
}
