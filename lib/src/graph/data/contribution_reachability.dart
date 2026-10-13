import 'dart:typed_data';

import '../../intention/domain/intention_id.dart';
import '../../statistics/application/contribution_counts.dart';

/// Внутренний снимок только активных связей, без отображаемых данных.
///
/// Индекс намерения — его позиция в уникальном [intentionIds]. Смежность
/// хранится диапазонами: дети i занимают [childOffsets[i], childOffsets[i+1]),
/// родители — аналогичный диапазон [parents]. Оба направления описывают одни
/// связи; смещения начинаются с нуля и заканчиваются длиной массива смежности.
/// При N намерениях массивы смещений имеют N+1 элементов, а каждый индекс
/// смежности лежит в диапазоне от 0 включительно до N исключительно.
/// Намерения без активных связей могут отсутствовать в таблице идентификаторов.
///
/// Загрузчик передаёт владение массивами конструктору и больше не изменяет их,
/// включая другие представления их буферов. Здесь создаются представления
/// только для чтения без копирования; список идентификаторов копируется.
/// Корректность индексов и согласованность направлений обеспечивает загрузчик.
final class ContributionRelationGraph {
  ContributionRelationGraph({
    required List<IntentionId> intentionIds,
    required Uint32List childOffsets,
    required Uint32List children,
    required Uint32List parentOffsets,
    required Uint32List parents,
  }) : intentionIds = List.unmodifiable(intentionIds),
       childOffsets = childOffsets.asUnmodifiableView(),
       children = children.asUnmodifiableView(),
       parentOffsets = parentOffsets.asUnmodifiableView(),
       parents = parents.asUnmodifiableView();

  final List<IntentionId> intentionIds;
  final Uint32List childOffsets;
  final Uint32List children;
  final Uint32List parentOffsets;
  final Uint32List parents;
}

/// Непустой опорный набор и суммарный вес самостоятельных дневных выборов.
///
/// Подготовка групп сохраняет выбранное действие и исходные намерения
/// архивированных шагов. Равные наборы объединяются до подсчёта, а каждый
/// дубликат выбора увеличивает вес. [seeds] копируется; [counts] неизменяем.
/// Подготовка передаёт только группы с положительным запланированным вкладом.
final class ContributionSeedGroup {
  ContributionSeedGroup({
    required List<IntentionId> seeds,
    required this.counts,
  }) : assert(seeds.isNotEmpty),
       assert(counts.planned > 0),
       seeds = List.unmodifiable(seeds);

  final List<IntentionId> seeds;
  final ContributionCounts counts;
}

typedef ContributionReachabilityEntry = ({
  IntentionId intentionId,
  ContributionCounts counts,
});

/// Точные количества Главной в порядке убывания вклада, запланированного
/// вклада и идентификатора. Возвращает только элементы с запланированным вкладом.
///
/// Чистый синхронный подсчёт для вызова адаптером в фоновом изоляте. Не читает
/// SQLite, не меняет входы и не хранит состояние между вызовами. Рабочие массивы
/// принадлежат вызову; возвращаемый список и его значения неизменяемы.
List<ContributionReachabilityEntry> computeContributionReachability(
  ContributionRelationGraph graph,
  List<ContributionSeedGroup> groups,
) {
  if (groups.isEmpty) return const [];

  final components = _condense(graph, groups);
  final componentCount = components.childOffsets.length - 1;
  final planned = Int64List(componentCount);
  final contribution = Int64List(componentCount);
  final masks = Int64List(componentCount);

  for (var first = 0; first < groups.length; first += 64) {
    masks.fillRange(0, componentCount, 0);
    final end = first + 64 < groups.length ? first + 64 : groups.length;
    for (var group = first; group < end; group++) {
      final bit = 1 << (group - first);
      for (final seed in groups[group].seeds) {
        masks[components.byNode[components.indexById[seed]!]] |= bit;
      }
    }

    final plannedSums = _byteSums(groups, first, contribution: false);
    final contributionSums = _byteSums(groups, first, contribution: true);
    // Тарьян выдаёт потомков раньше предков; повторные рёбра безопасны для OR.
    for (var component = 0; component < componentCount; component++) {
      var mask = masks[component];
      for (
        var edge = components.childOffsets[component];
        edge < components.childOffsets[component + 1];
        edge++
      ) {
        mask |= masks[components.children[edge]];
      }
      masks[component] = mask;
      for (var byte = 0; byte < 8; byte++) {
        // Логический сдвиг сохраняет старший бит знакового 64-битного слова.
        // https://api.dart.dev/dart-core/int/operator_triple_shift.html
        final tableIndex = byte * 256 + ((mask >>> (byte * 8)) & 255);
        planned[component] += plannedSums[tableIndex];
        contribution[component] += contributionSums[tableIndex];
      }
    }
  }

  final entries = <ContributionReachabilityEntry>[
    for (final node in components.affectedNodes)
      (
        intentionId: components.intentionIds[node],
        counts: ContributionCounts(
          planned: planned[components.byNode[node]],
          contribution: contribution[components.byNode[node]],
        ),
      ),
  ];
  entries.sort((a, b) {
    final byContribution = b.counts.contribution.compareTo(
      a.counts.contribution,
    );
    if (byContribution != 0) return byContribution;
    final byPlanned = b.counts.planned.compareTo(a.counts.planned);
    return byPlanned != 0 ? byPlanned : b.intentionId.compareTo(a.intentionId);
  });
  return List.unmodifiable(entries);
}

Int64List _byteSums(
  List<ContributionSeedGroup> groups,
  int first, {
  required bool contribution,
}) {
  final sums = Int64List(8 * 256);
  for (var byte = 0; byte < 8; byte++) {
    for (var subset = 1; subset < 256; subset++) {
      final lowestBit = subset & -subset;
      final group = first + byte * 8 + lowestBit.bitLength - 1;
      final weight = group < groups.length
          ? (contribution
                ? groups[group].counts.contribution
                : groups[group].counts.planned)
          : 0;
      final offset = byte * 256;
      sums[offset + subset] = sums[offset + (subset ^ lowestBit)] + weight;
    }
  }
  return sums;
}

final class _Components {
  _Components(
    this.intentionIds,
    this.indexById,
    this.affectedNodes,
    this.byNode,
    this.childOffsets,
    this.children,
  );

  final List<IntentionId> intentionIds;
  final Map<IntentionId, int> indexById;
  final List<int> affectedNodes;
  final Int32List byNode;
  final Uint32List childOffsets;
  final Uint32List children;
}

_Components _condense(
  ContributionRelationGraph graph,
  List<ContributionSeedGroup> groups,
) {
  final ids = [...graph.intentionIds];
  final indexes = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final seedNodes = <int>[];
  for (final group in groups) {
    for (final seed in group.seeds) {
      final node = indexes.putIfAbsent(seed, () {
        ids.add(seed);
        return ids.length - 1;
      });
      seedNodes.add(node);
    }
  }

  final affected = Uint8List(ids.length);
  final affectedNodes = <int>[];
  void include(int node) {
    if (affected[node] != 0) return;
    affected[node] = 1;
    affectedNodes.add(node);
  }

  for (final node in seedNodes) {
    include(node);
  }
  for (var i = 0; i < affectedNodes.length; i++) {
    final node = affectedNodes[i];
    if (node >= graph.intentionIds.length) continue;
    for (
      var edge = graph.parentOffsets[node];
      edge < graph.parentOffsets[node + 1];
      edge++
    ) {
      include(graph.parents[edge]);
    }
  }

  final discovery = Int32List(ids.length)..fillRange(0, ids.length, -1);
  final low = Int32List(ids.length);
  final byNode = Int32List(ids.length)..fillRange(0, ids.length, -1);
  final nextEdge = Uint32List(ids.length);
  final onStack = Uint8List(ids.length);
  final unresolved = <int>[];
  final frames = <int>[];
  final childOffsets = <int>[0];
  final children = <int>[];
  var nextDiscovery = 0;

  void enter(int node) {
    discovery[node] = low[node] = nextDiscovery++;
    if (node < graph.intentionIds.length) {
      nextEdge[node] = graph.childOffsets[node];
    }
    onStack[node] = 1;
    unresolved.add(node);
    frames.add(node);
  }

  for (final root in affectedNodes) {
    if (discovery[root] >= 0) continue;
    enter(root);
    while (frames.isNotEmpty) {
      final node = frames.last;
      final end = node < graph.intentionIds.length
          ? graph.childOffsets[node + 1]
          : 0;
      if (nextEdge[node] < end) {
        final child = graph.children[nextEdge[node]++];
        if (affected[child] == 0) continue;
        if (discovery[child] < 0) {
          enter(child);
        } else if (onStack[child] != 0 && discovery[child] < low[node]) {
          low[node] = discovery[child];
        }
        continue;
      }

      frames.removeLast();
      if (frames.isNotEmpty && low[node] < low[frames.last]) {
        low[frames.last] = low[node];
      }
      if (low[node] != discovery[node]) continue;

      final component = childOffsets.length - 1;
      final members = <int>[];
      int member;
      do {
        member = unresolved.removeLast();
        onStack[member] = 0;
        byNode[member] = component;
        members.add(member);
      } while (member != node);
      for (final member in members) {
        if (member >= graph.intentionIds.length) continue;
        for (
          var edge = graph.childOffsets[member];
          edge < graph.childOffsets[member + 1];
          edge++
        ) {
          final child = graph.children[edge];
          if (affected[child] != 0 && byNode[child] != component) {
            assert(byNode[child] >= 0 && byNode[child] < component);
            children.add(byNode[child]);
          }
        }
      }
      childOffsets.add(children.length);
    }
  }
  return _Components(
    ids,
    indexes,
    affectedNodes,
    byNode,
    Uint32List.fromList(childOffsets),
    Uint32List.fromList(children),
  );
}
