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
/// Входящие связи i так же лежат в [parentOffsets], [parents] и
/// [parentArchived]. Оба диапазона упорядочены порядком связей: «нужно»
/// раньше «можно», затем приоритет, затем последовательность создания.
///
/// Массивы передаются в фоновый изолят без объектов предметной области;
/// согласованность индексов обеспечивает [IntentionHoldingGraphBuilder].
final class IntentionHoldingGraph {
  IntentionHoldingGraph._({
    required Uint8List intentionFlags,
    required Uint32List childOffsets,
    required Uint32List children,
    required Uint8List childArchived,
    required Uint32List parentOffsets,
    required Uint32List parents,
    required Uint8List parentArchived,
  }) : intentionFlags = intentionFlags.asUnmodifiableView(),
       childOffsets = childOffsets.asUnmodifiableView(),
       children = children.asUnmodifiableView(),
       childArchived = childArchived.asUnmodifiableView(),
       parentOffsets = parentOffsets.asUnmodifiableView(),
       parents = parents.asUnmodifiableView(),
       parentArchived = parentArchived.asUnmodifiableView();

  static const supportingFlag = 1;
  static const archivedFlag = 2;

  final Uint8List intentionFlags;
  final Uint32List childOffsets;
  final Uint32List children;
  final Uint8List childArchived;
  final Uint32List parentOffsets;
  final Uint32List parents;
  final Uint8List parentArchived;
}

/// Собирает [IntentionHoldingGraph]: сначала все намерения, затем связи между
/// ними. Связь с несобранным намерением отклоняется
/// [IntentionHoldingGraphIncomplete].
final class IntentionHoldingGraphBuilder {
  final _indexes = <IntentionId, int>{};
  final _ids = <IntentionId>[];
  final _flags = <int>[];
  final _relations = <_HoldingRelation>[];
  var _built = false;

  void addIntention(
    IntentionId id,
    IntentionKind kind,
    IntentionArchiveState archiveState,
  ) {
    assert(!_built && !_indexes.containsKey(id));
    _indexes[id] = _flags.length;
    _ids.add(id);
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
    RelationScope scope, {
    required LongTermRelationType type,
    required RelationPriority priority,
    required int creationSequence,
  }) {
    assert(!_built);
    final sourceIndex = _indexes[source];
    final targetIndex = _indexes[target];
    if (sourceIndex == null || targetIndex == null) {
      throw const IntentionHoldingGraphIncomplete();
    }
    _relations.add((
      source: sourceIndex,
      target: targetIndex,
      archived: scope == RelationScope.archived ? 1 : 0,
      rank: type.index * RelationPriority.values.length + priority.index,
      creationSequence: creationSequence,
    ));
  }

  /// Граф, индексы намерений в нём и намерения по индексам. Строитель после
  /// этого не используется.
  ({
    IntentionHoldingGraph graph,
    Map<IntentionId, int> indexes,
    List<IntentionId> ids,
  })
  build() {
    _built = true;
    // Связи раскладываются по диапазонам в порядке связей, поэтому каждый
    // диапазон исходящих и входящих связей получается упорядоченным.
    _relations.sort(
      (a, b) => a.rank != b.rank
          ? a.rank - b.rank
          : a.creationSequence.compareTo(b.creationSequence),
    );
    final childOffsets = _offsets((relation) => relation.source);
    final parentOffsets = _offsets((relation) => relation.target);
    final childPositions = Uint32List.fromList(childOffsets);
    final parentPositions = Uint32List.fromList(parentOffsets);
    final children = Uint32List(_relations.length);
    final childArchived = Uint8List(_relations.length);
    final parents = Uint32List(_relations.length);
    final parentArchived = Uint8List(_relations.length);
    for (final relation in _relations) {
      final child = childPositions[relation.source]++;
      children[child] = relation.target;
      childArchived[child] = relation.archived;
      final parent = parentPositions[relation.target]++;
      parents[parent] = relation.source;
      parentArchived[parent] = relation.archived;
    }
    return (
      graph: IntentionHoldingGraph._(
        intentionFlags: Uint8List.fromList(_flags),
        childOffsets: childOffsets,
        children: children,
        childArchived: childArchived,
        parentOffsets: parentOffsets,
        parents: parents,
        parentArchived: parentArchived,
      ),
      indexes: Map.unmodifiable(_indexes),
      ids: List.unmodifiable(_ids),
    );
  }

  Uint32List _offsets(int Function(_HoldingRelation relation) intention) {
    final offsets = Uint32List(_flags.length + 1);
    for (final relation in _relations) {
      offsets[intention(relation) + 1]++;
    }
    for (var i = 1; i < offsets.length; i++) {
      offsets[i] += offsets[i - 1];
    }
    return offsets;
  }
}

typedef _HoldingRelation = ({
  int source,
  int target,
  int archived,
  int rank,
  int creationSequence,
});

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
