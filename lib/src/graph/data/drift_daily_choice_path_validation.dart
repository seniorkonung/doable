part of 'drift_personal_graph_repository.dart';

/// Проверяет сохранённый путь независимо от текущей архивности и готовности.
/// Вызывается внутри транзакции чтения и доступен командам перед commit.
List<DailyChoicePathStepDetails> _validateStoredChoicePath({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, _StoredRelationGroupRow> relations,
  required Map<IntentionId, domain.Intention> intentions,
}) {
  if (steps.isEmpty ||
      !intentions.containsKey(choice.sourceIntentionId) ||
      !intentions.containsKey(choice.selectedIntentionId)) {
    throw const _StoredIntentionCorruption();
  }

  final byId = <ChoicePathStepId, ChoicePathStep>{};
  final successors = <ChoicePathStepId, ChoicePathStep>{};
  ChoicePathStep? root;
  for (final step in steps) {
    if (step.dailyChoiceId != choice.id || byId.containsKey(step.id)) {
      throw const _StoredIntentionCorruption();
    }
    byId[step.id] = step;
    final previous = step.previousStepId;
    if (previous == null) {
      if (root != null) throw const _StoredIntentionCorruption();
      root = step;
    } else if (successors.containsKey(previous)) {
      throw const _StoredIntentionCorruption();
    } else {
      successors[previous] = step;
    }
  }
  if (root == null) throw const _StoredIntentionCorruption();

  final ordered = <DailyChoicePathStepDetails>[];
  final seenSteps = <ChoicePathStepId>{};
  final seenIntentions = <IntentionId>{choice.sourceIntentionId};
  var currentIntentionId = choice.sourceIntentionId;
  ChoicePathStep? currentStep = root;
  while (currentStep != null) {
    if (!seenSteps.add(currentStep.id)) {
      throw const _StoredIntentionCorruption();
    }
    final storedRelation = relations[currentStep.relationId];
    if (storedRelation == null ||
        storedRelation.sourceIntentionId != currentIntentionId ||
        !seenIntentions.add(storedRelation.relatedIntentionId)) {
      throw const _StoredIntentionCorruption();
    }
    final source = intentions[currentIntentionId];
    final related = intentions[storedRelation.relatedIntentionId];
    if (source == null || related == null) {
      throw const _StoredIntentionCorruption();
    }
    ordered.add(
      DailyChoicePathStepDetails(
        step: currentStep,
        relation: storedRelation.toDomain(),
        description: storedRelation.description,
        source: source,
        related: related,
      ),
    );
    currentIntentionId = storedRelation.relatedIntentionId;
    currentStep = successors[currentStep.id];
  }
  if (seenSteps.length != steps.length ||
      currentIntentionId != choice.selectedIntentionId) {
    throw const _StoredIntentionCorruption();
  }
  return List.unmodifiable(ordered);
}
