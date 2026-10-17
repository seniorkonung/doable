part of 'drift_personal_graph_repository.dart';

/// Проверяет сохранённый путь независимо от текущей архивности и готовности.
/// Вызывается внутри транзакции чтения и доступен командам перед commit.
List<DailyChoicePathStepDetails> _validateStoredChoicePath({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, _StoredRelationGroupRow> relations,
  required Map<IntentionId, domain.Intention> intentions,
}) {
  final path = _validateStoredChoicePathLinks(
    choice: choice,
    steps: steps,
    relations: {
      for (final relation in relations.values)
        relation.id: (
          source: relation.sourceIntentionId,
          related: relation.relatedIntentionId,
        ),
    },
  );
  return List.unmodifiable([
    for (final step in path.steps)
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
StoredChoicePath _validateStoredChoicePathLinks({
  required DailyChoice choice,
  required List<ChoicePathStep> steps,
  required Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
}) =>
    verifyStoredChoicePath(
      choice: choice,
      steps: steps,
      relations: relations,
    ) ??
    (throw const _StoredIntentionCorruption());
