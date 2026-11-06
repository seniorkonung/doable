part of 'contribution_reachability.dart';

/// Положение рассматриваемого намерения в сохранённом пути действия.
sealed class IntentionContributionPathPosition {
  const IntentionContributionPathPosition();
}

final class ContributionOutsidePath extends IntentionContributionPathPosition {
  const ContributionOutsidePath();
}

/// Намерение — последнее звено пути; [isRoot] означает путь из него одного.
/// Такое действие засчитано намерению без связи.
final class ContributionTerminalOnPath
    extends IntentionContributionPathPosition {
  const ContributionTerminalOnPath({required this.isRoot});

  final bool isRoot;
}

/// Намерение — корневое при [isRoot], иначе промежуточное звено пути.
/// [followingRelationId] — его связь со следующим намерением пути, в том
/// числе архивированная; null, если такой связи больше нет.
final class ContributionBeforeTerminal
    extends IntentionContributionPathPosition {
  const ContributionBeforeTerminal({
    required this.isRoot,
    this.followingRelationId,
  });

  final bool isRoot;
  final LongTermRelationId? followingRelationId;
}

/// Группа для одного намерения и периода без пользовательского содержимого.
///
/// Подготовка объединяет только действия с одинаковыми опорным набором,
/// положением намерения, конечным намерением и календарной частью. Опорные —
/// существующие намерения пути; намерение, за которым в пути идёт другое,
/// не рассматриваемое, по активной связи их пары, может быть опущено.
/// Вес включает каждое самостоятельное действие. Группа непустая, а
/// положение согласовано с рассматриваемым намерением.
///
/// [terminalIntentionId] — существующее конечное намерение пути, если оно не
/// рассматриваемое намерение; иначе null.
/// [CalendarPart] — ключ дня месяца либо месяца года: вычисление сохраняет
/// тип ключа потребителя, не преобразует даты и не определяет период заново.
/// Списки копируются; остальные значения неизменяемы и принадлежат снимку.
final class IntentionContributionGroup<CalendarPart extends Object> {
  IntentionContributionGroup({
    required List<IntentionId> seeds,
    required this.terminalIntentionId,
    required this.calendarPart,
    required this.pathPosition,
    required this.counts,
  }) : assert(seeds.isNotEmpty),
       assert(counts.planned > 0),
       seeds = List.unmodifiable(seeds);

  final List<IntentionId> seeds;
  final IntentionId? terminalIntentionId;
  final CalendarPart calendarPart;
  final IntentionContributionPathPosition pathPosition;
  final ContributionCounts counts;
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
/// по убыванию запланированного вклада, вклада и собственного идентификатора.
/// Отсутствующая календарная часть имеет нулевые количества.
final class IntentionContributionResult<CalendarPart extends Object> {
  IntentionContributionResult._({
    required this.counts,
    required this.explicitPathActions,
    required Map<CalendarPart, ContributionCounts> calendarCounts,
    required List<ContributionReachabilityEntry> terminalIntentions,
    required List<ContributionRelationEntry> relations,
  }) : calendarCounts = Map.unmodifiable(calendarCounts),
       terminalIntentions = List.unmodifiable(terminalIntentions),
       relations = List.unmodifiable(relations);

  final ContributionCounts counts;
  final int explicitPathActions;
  final Map<CalendarPart, ContributionCounts> calendarCounts;
  final List<ContributionReachabilityEntry> terminalIntentions;
  final List<ContributionRelationEntry> relations;
}

/// Чистый синхронный подсчёт вида «Через связи» для фонового изолята адаптера.
/// [activeOutgoingRelations] содержит все активные исходящие связи намерения
/// из того же снимка, что [graph]. Связи, следующие за намерением в путях,
/// приходят в группах. SQLite, названия, ревизии и порционирование остаются
/// у вызывающего адаптера.
IntentionContributionResult<CalendarPart>
computeIntentionContribution<CalendarPart extends Object>({
  required ContributionRelationGraph graph,
  required IntentionId intentionId,
  required List<IntentionContributionGroup<CalendarPart>> groups,
  required List<ContributionOutgoingRelation> activeOutgoingRelations,
}) {
  final reachable = _descendants(graph, intentionId);
  final calendar = <CalendarPart, _ContributionTotal>{};
  final terminals = <IntentionId, _ContributionTotal>{};
  final included = <IntentionContributionGroup<CalendarPart>>[];
  final total = _ContributionTotal();
  var explicit = 0;
  for (final group in groups) {
    if (!group.seeds.any(reachable.contains)) continue;
    final counts = group.counts;
    total.add(counts);
    (calendar[group.calendarPart] ??= _ContributionTotal()).add(counts);
    if (group.terminalIntentionId case final terminal?) {
      (terminals[terminal] ??= _ContributionTotal()).add(counts);
    }
    if (group.pathPosition is! ContributionOutsidePath) {
      explicit += counts.planned;
    }
    if (group.pathPosition is! ContributionTerminalOnPath) included.add(group);
  }

  final terminalIntentions =
      <ContributionReachabilityEntry>[
        for (final entry in terminals.entries)
          (intentionId: entry.key, counts: entry.value.counts),
      ]..sort((a, b) {
        final byCounts = _compareContributionCounts(a.counts, b.counts);
        return byCounts != 0
            ? byCounts
            : b.intentionId.compareTo(a.intentionId);
      });
  return IntentionContributionResult._(
    counts: total.counts,
    explicitPathActions: explicit,
    calendarCounts: {
      for (final entry in calendar.entries) entry.key: entry.value.counts,
    },
    terminalIntentions: terminalIntentions,
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

/// Действие относится к связи, следующей за намерением в его пути, и к
/// активной исходящей связи, связанное намерение которой достигает опорного
/// намерения без прохода через рассматриваемое.
List<ContributionRelationEntry> _relationContributions<T extends Object>(
  ContributionRelationGraph graph,
  IntentionId intentionId,
  List<IntentionContributionGroup<T>> groups,
  List<ContributionOutgoingRelation> outgoing,
) {
  if (groups.isEmpty) return const [];
  // Опорные намерения без рассматриваемого. Пропуск звена перед ним при
  // подготовке не допускается, поэтому оставшиеся опорные сохраняют
  // достижимость в обход рассматриваемого намерения.
  final seeds = [
    for (final group in groups)
      [
        for (final seed in group.seeds)
          if (seed != intentionId) seed,
      ],
  ];
  final weights = [for (final group in groups) group.counts];
  // Исключение происходит до сжатия: прежние компоненты могут распасться.
  final components = _condense(
    graph,
    seeds.expand((group) => group),
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
      for (final seed in seeds[group]) {
        masks[components.byNode[components.indexById[seed]!]] |= bit;
      }
      if (groups[group].pathPosition case ContributionBeforeTerminal(
        followingRelationId: final following?,
      )) {
        relationMasks.update(
          following,
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
    final plannedSums = _byteSums(weights, first, contribution: false);
    final contributionSums = _byteSums(weights, first, contribution: true);
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
  final byPlanned = b.planned.compareTo(a.planned);
  return byPlanned != 0 ? byPlanned : b.contribution.compareTo(a.contribution);
}
