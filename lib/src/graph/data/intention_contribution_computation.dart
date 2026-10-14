part of 'contribution_reachability.dart';

/// Положение рассматриваемого намерения в простом сохранённом пути.
sealed class IntentionContributionPathPosition {
  const IntentionContributionPathPosition();
}

final class ContributionOutsidePath extends IntentionContributionPathPosition {
  const ContributionOutsidePath();
}

final class ContributionSelectedOnPath
    extends IntentionContributionPathPosition {
  const ContributionSelectedOnPath();
}

/// Намерение исходное при отсутствии предшественника, иначе промежуточное.
/// Следующая связь сохраняет явное основание независимо от архивирования.
final class ContributionBeforeSelectedAction
    extends IntentionContributionPathPosition {
  const ContributionBeforeSelectedAction({
    this.predecessorId,
    required this.followingRelationId,
  });

  final IntentionId? predecessorId;
  final LongTermRelationId followingRelationId;
}

/// Группа для одного намерения и периода без пользовательского содержимого.
///
/// Подготовка объединяет только выборы с одинаковыми опорным набором,
/// положением намерения, выбранным действием и календарной частью. Опорные —
/// выбранное действие и исходные намерения архивированных шагов. Вес включает
/// каждый самостоятельный выбор; деление невыполненного уже учитывает местную
/// дату. Группа непустая, а положение согласовано с рассматриваемым намерением.
///
/// [CalendarPart] — ключ дня месяца либо месяца года: вычисление сохраняет
/// тип ключа потребителя, не преобразует даты и не определяет период заново.
/// Списки копируются; остальные значения неизменяемы и принадлежат снимку.
final class IntentionContributionGroup<CalendarPart extends Object> {
  IntentionContributionGroup({
    required List<IntentionId> seeds,
    required this.selectedActionId,
    required this.calendarPart,
    required this.pathPosition,
    required this.summary,
  }) : assert(seeds.isNotEmpty),
       assert(summary.counts.planned > 0),
       seeds = List.unmodifiable(seeds);

  final List<IntentionId> seeds;
  final IntentionId selectedActionId;
  final CalendarPart calendarPart;
  final IntentionContributionPathPosition pathPosition;
  final StatisticsPeriodSummary summary;
}

typedef ContributionOutgoingRelation = ({
  LongTermRelationId relationId,
  IntentionId targetId,
});

typedef ContributionRelationEntry = ({
  LongTermRelationId relationId,
  ContributionCounts counts,
});

/// Неизменяемые количества для сборки раздела и порций адаптером.
/// Разбивки содержат только положительный запланированный вклад и упорядочены
/// по убыванию вклада, запланированного вклада и собственного идентификатора.
/// Отсутствующая календарная часть имеет нулевые количества.
final class IntentionContributionResult<CalendarPart extends Object> {
  IntentionContributionResult._({
    required this.summary,
    required this.explicitPathChoices,
    required Map<CalendarPart, ContributionCounts> calendarCounts,
    required List<ContributionReachabilityEntry> selectedActions,
    required List<ContributionRelationEntry> relations,
  }) : calendarCounts = Map.unmodifiable(calendarCounts),
       selectedActions = List.unmodifiable(selectedActions),
       relations = List.unmodifiable(relations);

  final StatisticsPeriodSummary summary;
  final int explicitPathChoices;
  final Map<CalendarPart, ContributionCounts> calendarCounts;
  final List<ContributionReachabilityEntry> selectedActions;
  final List<ContributionRelationEntry> relations;
}

/// Чистый синхронный подсчёт вида «Через связи» для фонового изолята адаптера.
/// [activeOutgoingRelations] содержит все активные исходящие связи намерения
/// из того же снимка, что [graph]. Архивированные явные связи приходят в группах.
/// SQLite, названия, ревизии и порционирование остаются у вызывающего адаптера.
IntentionContributionResult<CalendarPart>
computeIntentionContribution<CalendarPart extends Object>({
  required ContributionRelationGraph graph,
  required IntentionId intentionId,
  required List<IntentionContributionGroup<CalendarPart>> groups,
  required List<ContributionOutgoingRelation> activeOutgoingRelations,
}) {
  final reachable = _descendants(graph, intentionId);
  final calendar = <CalendarPart, _ContributionTotal>{};
  final actions = <IntentionId, _ContributionTotal>{};
  final included = <IntentionContributionGroup<CalendarPart>>[];
  final total = _ContributionTotal();
  var missed = 0;
  var upcoming = 0;
  var explicit = 0;
  for (final group in groups) {
    if (!group.seeds.any(reachable.contains)) continue;
    final counts = group.summary.counts;
    total.add(counts);
    missed += group.summary.uncompleted.missed;
    upcoming += group.summary.uncompleted.upcoming;
    (calendar[group.calendarPart] ??= _ContributionTotal()).add(counts);
    (actions[group.selectedActionId] ??= _ContributionTotal()).add(counts);
    if (group.pathPosition is! ContributionOutsidePath) {
      explicit += counts.planned;
    }
    if (group.selectedActionId != intentionId) included.add(group);
  }

  final selectedActions =
      <ContributionReachabilityEntry>[
        for (final entry in actions.entries)
          (intentionId: entry.key, counts: entry.value.counts),
      ]..sort((a, b) {
        final byCounts = _compareContributionCounts(a.counts, b.counts);
        return byCounts != 0
            ? byCounts
            : b.intentionId.compareTo(a.intentionId);
      });
  return IntentionContributionResult._(
    summary: StatisticsPeriodSummary(
      counts: total.counts,
      uncompleted: UncompletedSplit(missed: missed, upcoming: upcoming),
    ),
    explicitPathChoices: explicit,
    calendarCounts: {
      for (final entry in calendar.entries) entry.key: entry.value.counts,
    },
    selectedActions: selectedActions,
    relations: _relationContributions(
      graph,
      intentionId,
      included,
      activeOutgoingRelations,
    ),
  );
}

Set<IntentionId> _descendants(
  ContributionRelationGraph graph,
  IntentionId intentionId,
) {
  final root = graph.intentionIds.indexOf(intentionId);
  final reachable = {intentionId};
  if (root < 0) return reachable;
  final pending = <int>[root];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    for (
      var edge = graph.childOffsets[node];
      edge < graph.childOffsets[node + 1];
      edge++
    ) {
      final child = graph.children[edge];
      if (reachable.add(graph.intentionIds[child])) pending.add(child);
    }
  }
  return reachable;
}

List<ContributionRelationEntry> _relationContributions<T extends Object>(
  ContributionRelationGraph graph,
  IntentionId intentionId,
  List<IntentionContributionGroup<T>> groups,
  List<ContributionOutgoingRelation> outgoing,
) {
  if (groups.isEmpty) return const [];
  final refined = [
    for (final group in groups)
      ContributionSeedGroup(
        seeds: {
          for (final seed in group.seeds)
            if (seed != intentionId) seed,
          if (group.pathPosition case ContributionBeforeSelectedAction(
            predecessorId: final predecessor?,
          ))
            predecessor,
        }.toList(),
        counts: group.summary.counts,
      ),
  ];
  // Исключение происходит до сжатия: прежние компоненты могут распасться.
  final components = _condense(
    graph,
    refined,
    excludedIntentionId: intentionId,
  );
  final componentCount = components.childOffsets.length - 1;
  final masks = Int64List(componentCount);
  final totals = <LongTermRelationId, _ContributionTotal>{};
  for (var first = 0; first < groups.length; first += 64) {
    masks.fillRange(0, componentCount, 0);
    final end = first + 64 < groups.length ? first + 64 : groups.length;
    final relationMasks = <LongTermRelationId, int>{};
    for (var group = first; group < end; group++) {
      final bit = 1 << (group - first);
      for (final seed in refined[group].seeds) {
        masks[components.byNode[components.indexById[seed]!]] |= bit;
      }
      if (groups[group].pathPosition case ContributionBeforeSelectedAction(
        :final followingRelationId,
      )) {
        relationMasks.update(
          followingRelationId,
          (mask) => mask | bit,
          ifAbsent: () => bit,
        );
      }
    }
    for (var component = 0; component < componentCount; component++) {
      for (
        var edge = components.childOffsets[component];
        edge < components.childOffsets[component + 1];
        edge++
      ) {
        masks[component] |= masks[components.children[edge]];
      }
    }
    for (final relation in outgoing) {
      final node = components.indexById[relation.targetId];
      if (node == null || components.byNode[node] < 0) continue;
      final mask = masks[components.byNode[node]];
      if (mask == 0) continue;
      relationMasks.update(
        relation.relationId,
        (explicit) => explicit | mask,
        ifAbsent: () => mask,
      );
    }
    final plannedSums = _byteSums(refined, first, contribution: false);
    final contributionSums = _byteSums(refined, first, contribution: true);
    for (final entry in relationMasks.entries) {
      final total = totals[entry.key] ??= _ContributionTotal();
      for (var byte = 0; byte < 8; byte++) {
        final index = byte * 256 + ((entry.value >>> (byte * 8)) & 255);
        total.planned += plannedSums[index];
        total.contribution += contributionSums[index];
      }
    }
  }
  return [
    for (final entry in totals.entries)
      (relationId: entry.key, counts: entry.value.counts),
  ]..sort((a, b) {
    final byCounts = _compareContributionCounts(a.counts, b.counts);
    return byCounts != 0 ? byCounts : b.relationId.compareTo(a.relationId);
  });
}

final class _ContributionTotal {
  var planned = 0;
  var contribution = 0;

  void add(ContributionCounts counts) {
    planned += counts.planned;
    contribution += counts.contribution;
  }

  ContributionCounts get counts =>
      ContributionCounts(planned: planned, contribution: contribution);
}

int _compareContributionCounts(ContributionCounts a, ContributionCounts b) {
  final byContribution = b.contribution.compareTo(a.contribution);
  return byContribution != 0 ? byContribution : b.planned.compareTo(a.planned);
}
