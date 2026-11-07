import 'package:doable/src/intention/domain/intention_id.dart';

typedef ContributionReferenceRelation = ({
  IntentionId source,
  IntentionId target,
  bool archived,
});

typedef ContributionReferenceAction = ({
  List<IntentionId> path,
  bool completed,
});

/// Независимый эталон Главной: каждое самостоятельное действие начинает обход
/// со всех существующих намерений сохранённого пути, включая архивированные,
/// и идёт по активным связям. Удалённые намерения [deleted] не засчитываются
/// и обход не начинают. Опорные группы, сокращение опорных намерений,
/// компоненты сильной связности и битовые маски не используются.
Map<IntentionId, ({int planned, int contribution})>
referenceActionContributionCounts({
  required List<ContributionReferenceRelation> relations,
  required List<ContributionReferenceAction> actions,
  Set<IntentionId> deleted = const {},
}) {
  final parents = <IntentionId, List<IntentionId>>{};
  for (final relation in relations) {
    if (!relation.archived) {
      (parents[relation.target] ??= []).add(relation.source);
    }
  }
  final counts = <IntentionId, ({int planned, int contribution})>{};
  for (final action in actions) {
    final visited = <IntentionId>{};
    final pending = [
      for (final intention in action.path)
        if (!deleted.contains(intention)) intention,
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
        contribution: previous.contribution + (action.completed ? 1 : 0),
      );
    }
  }
  return counts;
}

typedef ContributionReferenceCounts = ({int planned, int contribution});

typedef ContributionReferenceIntentionStatistics = ({
  ContributionReferenceCounts throughRelations,
  int explicitPathActions,
  Map<IntentionId, ContributionReferenceCounts> terminalIntentions,
  Map<ContributionReferenceRelation, ContributionReferenceCounts> relations,
});

/// Независимый эталон вида «Через связи» раздела одного намерения: каждое
/// самостоятельное действие проверяется отдельно по полному пути без опорных
/// групп, сокращения опорных намерений и битовых масок. Удалённые намерения
/// [deleted] не засчитываются, обход не начинают и элементами не бывают;
/// их связей в [relations] нет.
ContributionReferenceIntentionStatistics referenceIntentionActionStatistics({
  required IntentionId intentionId,
  required List<ContributionReferenceRelation> relations,
  required List<ContributionReferenceAction> actions,
  Set<IntentionId> deleted = const {},
}) {
  final children = <IntentionId, List<IntentionId>>{};
  for (final relation in relations) {
    if (!relation.archived) {
      (children[relation.source] ??= []).add(relation.target);
    }
  }
  // Связанное намерение связи засчитывает действие в обход самого намерения.
  bool reachesAvoiding(IntentionId start, Set<IntentionId> targets) {
    final visited = <IntentionId>{};
    final pending = [start];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node == intentionId || !visited.add(node)) continue;
      if (targets.contains(node)) return true;
      pending.addAll(children[node] ?? const []);
    }
    return false;
  }

  ContributionReferenceCounts add(
    ContributionReferenceCounts? previous,
    bool completed,
  ) => (
    planned: (previous?.planned ?? 0) + 1,
    contribution: (previous?.contribution ?? 0) + (completed ? 1 : 0),
  );

  ContributionReferenceCounts? through;
  var explicit = 0;
  final terminals = <IntentionId, ContributionReferenceCounts>{};
  final relationCounts =
      <ContributionReferenceRelation, ContributionReferenceCounts>{};
  for (final action in actions) {
    final existing = {
      for (final intention in action.path)
        if (!deleted.contains(intention)) intention,
    };
    if (existing.isEmpty) continue;
    final position = action.path.indexOf(intentionId);
    final counted =
        position >= 0 || _reachesAny(children, intentionId, existing);
    if (!counted) continue;
    through = add(through, action.completed);
    if (position >= 0) explicit++;
    final terminal = action.path.last;
    if (terminal == intentionId) continue;
    if (!deleted.contains(terminal)) {
      terminals[terminal] = add(terminals[terminal], action.completed);
    }
    final others = existing..remove(intentionId);
    for (final relation in relations) {
      if (relation.source != intentionId) continue;
      final following =
          position >= 0 && action.path[position + 1] == relation.target;
      if (following ||
          (!relation.archived && reachesAvoiding(relation.target, others))) {
        relationCounts[relation] = add(
          relationCounts[relation],
          action.completed,
        );
      }
    }
  }
  return (
    throughRelations: through ?? (planned: 0, contribution: 0),
    explicitPathActions: explicit,
    terminalIntentions: terminals,
    relations: relationCounts,
  );
}

bool _reachesAny(
  Map<IntentionId, List<IntentionId>> children,
  IntentionId start,
  Set<IntentionId> targets,
) {
  final visited = <IntentionId>{};
  final pending = [start];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (!visited.add(node)) continue;
    if (targets.contains(node)) return true;
    pending.addAll(children[node] ?? const []);
  }
  return false;
}
