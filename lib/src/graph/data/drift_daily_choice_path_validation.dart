part of 'drift_personal_graph_repository.dart';

/// Проверяет сохранённый путь независимо от текущей архивности и готовности.
/// Вызывается внутри транзакции чтения и доступен командам перед commit.
List<DailyChoicePathStepDetails> _validateStoredChoicePath({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, _StoredRelationGroupRow> relations,
  required Map<IntentionId, domain.Intention> intentions,
}) {
  final orderedSteps = _validateStoredChoicePathLinks(
    choice: choice,
    steps: steps,
    relations: {
      for (final relation in relations.values)
        relation.id: (
          source: relation.sourceIntentionId,
          related: relation.relatedIntentionId,
        ),
    },
    intentionIds: intentions.keys.toSet(),
  );
  return List.unmodifiable([
    for (final step in orderedSteps)
      DailyChoicePathStepDetails(
        step: step,
        relation: relations[step.relationId]!.toDomain(),
        description: relations[step.relationId]!.description,
        source: intentions[relations[step.relationId]!.sourceIntentionId]!,
        related: intentions[relations[step.relationId]!.relatedIntentionId]!,
      ),
  ]);
}

/// Общая проверка цепочки; для каталога достаточно только ссылок её порции.
List<ChoicePathStep> _validateStoredChoicePathLinks({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
  required Set<IntentionId> intentionIds,
}) {
  if (steps.isEmpty ||
      !intentionIds.contains(choice.sourceIntentionId) ||
      !intentionIds.contains(choice.selectedIntentionId)) {
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

  final ordered = <ChoicePathStep>[];
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
        storedRelation.source != currentIntentionId ||
        !seenIntentions.add(storedRelation.related)) {
      throw const _StoredIntentionCorruption();
    }
    if (!intentionIds.contains(currentIntentionId) ||
        !intentionIds.contains(storedRelation.related)) {
      throw const _StoredIntentionCorruption();
    }
    ordered.add(currentStep);
    currentIntentionId = storedRelation.related;
    currentStep = successors[currentStep.id];
  }
  if (seenSteps.length != steps.length ||
      currentIntentionId != choice.selectedIntentionId) {
    throw const _StoredIntentionCorruption();
  }
  return List.unmodifiable(ordered);
}
