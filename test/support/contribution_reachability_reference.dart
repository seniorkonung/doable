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

/// Эталон разбивки одного намерения: обходит полные пути каждого выбора
/// без опорных групп, а неявное основание ищет отдельно от каждой связи.
Map<ContributionReferenceRelation, ({int planned, int contribution})>
referenceIntentionRelationCounts({
  required IntentionId intentionId,
  required List<ContributionReferenceRelation> relations,
  required List<ContributionReferenceChoice> choices,
}) {
  final children = <IntentionId, List<IntentionId>>{};
  for (final relation in relations) {
    if (!relation.archived &&
        relation.source != intentionId &&
        relation.target != intentionId) {
      (children[relation.source] ??= []).add(relation.target);
    }
  }
  final counts =
      <ContributionReferenceRelation, ({int planned, int contribution})>{};
  for (final choice in choices) {
    if (choice.path.last.target == intentionId ||
        !referenceContributionCounts(
          relations: relations,
          choices: [choice],
        ).containsKey(intentionId)) {
      continue;
    }
    final pathIntentions = {
      for (final step in choice.path) ...[step.source, step.target],
    }..remove(intentionId);
    for (final relation in relations) {
      if (relation.source != intentionId) continue;
      var included = choice.path.contains(relation);
      if (!included && !relation.archived) {
        final visited = <IntentionId>{};
        final pending = [relation.target];
        while (pending.isNotEmpty) {
          final node = pending.removeLast();
          if (node == intentionId || !visited.add(node)) continue;
          if (pathIntentions.contains(node)) {
            included = true;
            break;
          }
          pending.addAll(children[node] ?? const []);
        }
      }
      if (!included) continue;
      final previous = counts[relation] ?? (planned: 0, contribution: 0);
      counts[relation] = (
        planned: previous.planned + 1,
        contribution: previous.contribution + (choice.completed ? 1 : 0),
      );
    }
  }
  return counts;
}
