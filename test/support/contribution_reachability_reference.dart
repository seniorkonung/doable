import 'package:doable/src/intention/domain/intention_id.dart';

typedef ContributionReferenceRelation = ({
  IntentionId source,
  IntentionId target,
  bool archived,
});

typedef ContributionReferenceChoice = ({
  List<ContributionReferenceRelation> path,
  bool completed,
});

/// Независимый эталон: каждый самостоятельный выбор начинает обход
/// со всех намерений полного сохранённого пути, включая архивированные шаги.
/// Опорные группы, компоненты сильной связности и битовые маски не используются.
Map<IntentionId, ({int planned, int contribution})>
referenceContributionCounts({
  required List<ContributionReferenceRelation> relations,
  required List<ContributionReferenceChoice> choices,
}) {
  final parents = <IntentionId, List<IntentionId>>{};
  for (final relation in relations) {
    if (!relation.archived) {
      (parents[relation.target] ??= []).add(relation.source);
    }
  }
  final counts = <IntentionId, ({int planned, int contribution})>{};
  for (final choice in choices) {
    final visited = <IntentionId>{};
    final pending = [
      for (final step in choice.path) ...[step.source, step.target],
    ];
    while (pending.isNotEmpty) {
      final intention = pending.removeLast();
      if (!visited.add(intention)) continue;
      pending.addAll(parents[intention] ?? const []);
    }
    for (final intention in visited) {
      final previous = counts[intention] ?? (planned: 0, contribution: 0);
      counts[intention] = (
        planned: previous.planned + 1,
        contribution: previous.contribution + (choice.completed ? 1 : 0),
      );
    }
  }
  return counts;
}
