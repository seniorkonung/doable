import 'dart:typed_data';

import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';

/// Компактный граф удержания без пользовательского текста: вид и архивное
/// состояние каждого намерения и все связи с признаком архива.
///
/// Индекс намерения — его позиция при сборке. Признаки намерения i лежат в
/// [intentionFlags][i] битами [supportingFlag] и [archivedFlag]. Исходящие
/// связи i занимают диапазон [childOffsets][i]..[childOffsets][i+1] массива
/// [children], а [childArchived] того же диапазона хранит 1 у архивной связи.
///
/// Массивы передаются в фоновый изолят без объектов предметной области;
/// согласованность индексов обеспечивает [IntentionHoldingGraphBuilder].
final class IntentionHoldingGraph {
  IntentionHoldingGraph._({
    required Uint8List intentionFlags,
    required Uint32List childOffsets,
    required Uint32List children,
    required Uint8List childArchived,
  }) : intentionFlags = intentionFlags.asUnmodifiableView(),
       childOffsets = childOffsets.asUnmodifiableView(),
       children = children.asUnmodifiableView(),
       childArchived = childArchived.asUnmodifiableView();

  static const supportingFlag = 1;
  static const archivedFlag = 2;

  final Uint8List intentionFlags;
  final Uint32List childOffsets;
  final Uint32List children;
  final Uint8List childArchived;
}

/// Собирает [IntentionHoldingGraph]: сначала все намерения, затем связи между
/// ними. Связь с несобранным намерением отклоняется
/// [IntentionHoldingGraphIncomplete].
final class IntentionHoldingGraphBuilder {
  final _indexes = <IntentionId, int>{};
  final _flags = <int>[];
  final _sources = <int>[];
  final _targets = <int>[];
  final _archived = <int>[];
  var _built = false;

  void addIntention(
    IntentionId id,
    IntentionKind kind,
    IntentionArchiveState archiveState,
  ) {
    assert(!_built && !_indexes.containsKey(id));
    _indexes[id] = _flags.length;
    _flags.add(
      (kind == IntentionKind.supporting
              ? IntentionHoldingGraph.supportingFlag
              : 0) |
          (archiveState == IntentionArchiveState.archived
              ? IntentionHoldingGraph.archivedFlag
              : 0),
    );
  }

  void addRelation(
    IntentionId source,
    IntentionId target,
    RelationScope scope,
  ) {
    assert(!_built);
    final sourceIndex = _indexes[source];
    final targetIndex = _indexes[target];
    if (sourceIndex == null || targetIndex == null) {
      throw const IntentionHoldingGraphIncomplete();
    }
    _sources.add(sourceIndex);
    _targets.add(targetIndex);
    _archived.add(scope == RelationScope.archived ? 1 : 0);
  }

  /// Граф и индексы намерений в нём. Строитель после этого не используется.
  ({IntentionHoldingGraph graph, Map<IntentionId, int> indexes}) build() {
    _built = true;
    final offsets = Uint32List(_flags.length + 1);
    for (final source in _sources) {
      offsets[source + 1]++;
    }
    for (var i = 1; i < offsets.length; i++) {
      offsets[i] += offsets[i - 1];
    }
    final positions = Uint32List.fromList(offsets);
    final children = Uint32List(_targets.length);
    final childArchived = Uint8List(_targets.length);
    for (var edge = 0; edge < _sources.length; edge++) {
      final position = positions[_sources[edge]]++;
      children[position] = _targets[edge];
      childArchived[position] = _archived[edge];
    }
    return (
      graph: IntentionHoldingGraph._(
        intentionFlags: Uint8List.fromList(_flags),
        childOffsets: offsets,
        children: children,
        childArchived: childArchived,
      ),
      indexes: Map.unmodifiable(_indexes),
    );
  }
}

/// Связь указывает на намерение, которого нет среди собранных.
final class IntentionHoldingGraphIncomplete implements Exception {
  const IntentionHoldingGraphIncomplete();
}

/// Удерживаемые намерения [graph]: 1 по индексу намерения у удерживаемого,
/// 0 у остальных. Обход в ширину начинается со всех активных главных и идёт
/// по активным связям в активные вспомогательные, поэтому вспомогательные,
/// ведущие только друг к другу, архивные главные и архивные связи ничего не
/// удерживают.
///
/// Чистый синхронный подсчёт для вызова адаптером в фоновом изоляте: не
/// читает SQLite, не меняет входы и не хранит состояние между вызовами.
Uint8List computeIntentionHolding(IntentionHoldingGraph graph) {
  final flags = graph.intentionFlags;
  final held = Uint8List(flags.length);
  final queue = Uint32List(flags.length);
  var tail = 0;
  for (var intention = 0; intention < flags.length; intention++) {
    if (flags[intention] == 0) {
      held[intention] = 1;
      queue[tail++] = intention;
    }
  }
  final offsets = graph.childOffsets;
  final children = graph.children;
  final childArchived = graph.childArchived;
  for (var head = 0; head < tail; head++) {
    final holder = queue[head];
    for (var edge = offsets[holder]; edge < offsets[holder + 1]; edge++) {
      final child = children[edge];
      if (childArchived[edge] == 0 &&
          held[child] == 0 &&
          flags[child] == IntentionHoldingGraph.supportingFlag) {
        held[child] = 1;
        queue[tail++] = child;
      }
    }
  }
  return held;
}
