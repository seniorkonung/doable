import 'dart:typed_data';

import '../../intention/application/cascade/intention_cascade.dart';
import '../../intention/domain/intention_id.dart';
import 'intention_holding_computation.dart';

/// Предмет, существование которого вызывающий подтвердил строкой хранилища.
/// Связь задаётся неизменной парой участников (ADR-0051): граф удержания не
/// хранит идентификаторов связей.
sealed class CascadePlanningSubject {
  const CascadePlanningSubject();
}

final class PlannedIntention extends CascadePlanningSubject {
  const PlannedIntention(this.intentionId);

  final IntentionId intentionId;
}

final class PlannedRelation extends CascadePlanningSubject {
  const PlannedRelation({required this.source, required this.related});

  final IntentionId source;
  final IntentionId related;
}

/// Планировщик каскада (D6, ADR-0057): вычисляет составы обоих вариантов
/// архивирования, удаления и восстановления по графу и удержанию индекса
/// одной ревизии. Общий для предпросмотра и исполнения; не читает SQLite и
/// не меняет входы.
///
/// Намерения, которого нет в годном индексе, создано после построения:
/// создание индекс не сбрасывает. Оно планируется как активное главное без
/// связей, поэтому состав каждого его варианта — только оно само. Связь и её
/// участники в годном индексе есть всегда: создание связи индекс сбрасывает.
final class IntentionCascadePlanner {
  IntentionCascadePlanner({
    required this.graph,
    required this.indexes,
    required this.ids,
    required this.held,
  });

  final IntentionHoldingGraph graph;
  final Map<IntentionId, int> indexes;
  final List<IntentionId> ids;

  /// Удержание индекса по [computeIntentionHolding].
  final Uint8List held;

  /// Архивирование учитывает только активные намерения и связи.
  CascadePlan<ArchiveCascadeComposition> planArchive(
    CascadePlanningSubject subject,
  ) {
    final resolved = _resolve(subject);
    if (resolved == null) {
      final nothing = ArchiveCascadeComposition(
        departing: const [],
        promoted: const [],
        archivedRelationCount: 0,
      );
      return CascadePlan(
        withSupporting: nothing,
        onlyThis: nothing,
        asksQuestion: false,
      );
    }
    final removal = _Removal(this, resolved, archiveScope: true);
    ArchiveCascadeComposition variant(CascadeChoice choice) =>
        ArchiveCascadeComposition(
          departing: removal.departing(choice),
          promoted: removal.promoted(choice),
          archivedRelationCount: removal.relationCount(choice),
        );
    return CascadePlan(
      withSupporting: variant(CascadeChoice.withSupporting),
      onlyThis: variant(CascadeChoice.onlyThis),
      asksQuestion: removal.cascadeTakesOthers,
    );
  }

  /// Удаление учитывает и архивные намерения и связи, а затем архивирует
  /// активные вспомогательные, оставшиеся без активной входящей связи.
  CascadePlan<DeleteCascadeComposition> planDelete(
    CascadePlanningSubject subject,
  ) {
    final resolved = _resolve(subject);
    if (resolved == null) {
      final nothing = DeleteCascadeComposition(
        departing: const [],
        promoted: const [],
        archivedByInvariant: const [],
        mainsLosingRelation: const [],
        deletedRelationCount: 0,
      );
      return CascadePlan(
        withSupporting: nothing,
        onlyThis: nothing,
        asksQuestion: false,
      );
    }
    final removal = _Removal(this, resolved, archiveScope: false);
    DeleteCascadeComposition variant(CascadeChoice choice) {
      return DeleteCascadeComposition(
        departing: removal.departing(choice),
        promoted: removal.promoted(choice),
        archivedByInvariant: removal.archivedByInvariant(choice),
        mainsLosingRelation: removal.mainsLosingRelation(choice),
        deletedRelationCount: removal.relationCount(choice),
      );
    }

    return CascadePlan(
      withSupporting: variant(CascadeChoice.withSupporting),
      onlyThis: variant(CascadeChoice.onlyThis),
      asksQuestion: removal.cascadeTakesOthers,
    );
  }

  /// Каскад восстановления идёт вниз через архивные вспомогательные
  /// намерения и останавливается на главных и активных.
  CascadePlan<RestoreCascadeComposition> planRestore(
    CascadePlanningSubject subject,
  ) {
    final resolved = _resolve(subject);
    if (resolved == null) {
      final nothing = RestoreCascadeComposition(
        restored: const [],
        returnedAsMain: null,
        restoredRelationCount: 0,
      );
      return CascadePlan(
        withSupporting: nothing,
        onlyThis: nothing,
        asksQuestion: false,
      );
    }
    final roots = switch (resolved) {
      _IntentionSubject(:final intention) => [intention],
      _RelationSubject(:final source, :final target) => [
        for (final end in [source, target])
          if (_archived(end)) end,
      ],
    };
    final cascade = Uint8List(_count);
    final cascadeOrder = _preorder(
      roots,
      cascade,
      (edge, child) => _archived(child) && _supporting(child),
    );
    final single = Uint8List(_count);
    for (final root in roots) {
      single[root] = 1;
    }
    final subjectIntention = switch (resolved) {
      _IntentionSubject(:final intention) => intention,
      _RelationSubject() => null,
    };
    RestoreCascadeComposition variant(Uint8List restored, List<int> order) =>
        RestoreCascadeComposition(
          restored: [
            for (final intention in order)
              if (intention != subjectIntention) ids[intention],
          ],
          returnedAsMain: _returnedAsMain(resolved, restored),
          restoredRelationCount: _restoredRelations(resolved, restored, order),
        );
    return CascadePlan(
      withSupporting: variant(cascade, cascadeOrder),
      onlyThis: variant(single, roots),
      asksQuestion: cascadeOrder.length > roots.length,
    );
  }

  int get _count => graph.intentionFlags.length;

  bool _supporting(int intention) =>
      graph.intentionFlags[intention] & IntentionHoldingGraph.supportingFlag !=
      0;

  bool _archived(int intention) =>
      graph.intentionFlags[intention] & IntentionHoldingGraph.archivedFlag != 0;

  _Subject? _resolve(CascadePlanningSubject subject) {
    switch (subject) {
      case PlannedIntention(:final intentionId):
        final intention = indexes[intentionId];
        return intention == null ? null : _IntentionSubject(intention);
      case PlannedRelation(:final source, :final related):
        final sourceIndex = indexes[source];
        final targetIndex = indexes[related];
        if (sourceIndex == null || targetIndex == null) {
          throw const IntentionHoldingGraphIncomplete();
        }
        final offsets = graph.childOffsets;
        for (
          var edge = offsets[sourceIndex];
          edge < offsets[sourceIndex + 1];
          edge++
        ) {
          if (graph.children[edge] == targetIndex) {
            return _RelationSubject(
              source: sourceIndex,
              target: targetIndex,
              archived: graph.childArchived[edge] == 1,
            );
          }
        }
        throw const IntentionHoldingGraphIncomplete();
    }
  }

  /// Прямой порядок обхода в глубину от [roots] по исходящим связям в
  /// порядке связей; обход входит в непосещённое намерение, если [descends]
  /// допускает связь [edge] к нему. Отмечает посещённые в [visited].
  List<int> _preorder(
    List<int> roots,
    Uint8List visited,
    bool Function(int edge, int child) descends,
  ) {
    final offsets = graph.childOffsets;
    final order = <int>[];
    final nodes = <int>[];
    final positions = <int>[];
    for (final root in roots) {
      if (visited[root] == 1) continue;
      visited[root] = 1;
      order.add(root);
      nodes.add(root);
      positions.add(offsets[root]);
      while (nodes.isNotEmpty) {
        final top = nodes.length - 1;
        final node = nodes[top];
        final edge = positions[top];
        if (edge == offsets[node + 1]) {
          nodes.removeLast();
          positions.removeLast();
          continue;
        }
        positions[top] = edge + 1;
        final child = graph.children[edge];
        if (visited[child] == 0 && descends(edge, child)) {
          visited[child] = 1;
          order.add(child);
          nodes.add(child);
          positions.add(offsets[child]);
        }
      }
    }
    return order;
  }

  /// Вспомогательное возвращается главным, если над ним не останется
  /// активного намерения. Концы каскада всегда имеют входящую связь от
  /// вернувшегося намерения, а связанный участник — от связи-предмета.
  IntentionId? _returnedAsMain(_Subject subject, Uint8List restored) {
    final candidate = switch (subject) {
      _IntentionSubject(:final intention) => intention,
      _RelationSubject(:final source) => source,
    };
    if (restored[candidate] == 0 || !_supporting(candidate)) return null;
    final offsets = graph.parentOffsets;
    for (var edge = offsets[candidate]; edge < offsets[candidate + 1]; edge++) {
      final parent = graph.parents[edge];
      if (!_archived(parent) || restored[parent] == 1) return null;
    }
    return ids[candidate];
  }

  /// Архивные связи возвращаемых намерений, оба конца которых после
  /// восстановления активны, и сама связь-предмет.
  int _restoredRelations(
    _Subject subject,
    Uint8List restored,
    List<int> order,
  ) {
    bool activeAfter(int intention) =>
        !_archived(intention) || restored[intention] == 1;
    var count = 0;
    for (final intention in order) {
      for (
        var edge = graph.childOffsets[intention];
        edge < graph.childOffsets[intention + 1];
        edge++
      ) {
        if (graph.childArchived[edge] == 1 &&
            activeAfter(graph.children[edge])) {
          count++;
        }
      }
      for (
        var edge = graph.parentOffsets[intention];
        edge < graph.parentOffsets[intention + 1];
        edge++
      ) {
        final parent = graph.parents[edge];
        if (graph.parentArchived[edge] == 1 &&
            restored[parent] == 0 &&
            activeAfter(parent)) {
          count++;
        }
      }
    }
    if (subject case _RelationSubject(:final source, :final target)
        when restored[source] == 0 && restored[target] == 0) {
      count++;
    }
    return count;
  }
}

sealed class _Subject {
  const _Subject();
}

final class _IntentionSubject extends _Subject {
  const _IntentionSubject(this.intention);

  final int intention;
}

final class _RelationSubject extends _Subject {
  const _RelationSubject({
    required this.source,
    required this.target,
    required this.archived,
  });

  final int source;
  final int target;
  final bool archived;
}

/// Архивирование или удаление одного предмета. Ниже предмета — множество D
/// вспомогательных намерений, до которых можно дойти вниз от предмета через
/// вспомогательные. Удержание вне D операция не меняет, поэтому удерживаемые
/// внутри D находятся обходом внутри D от связей, входящих в D от главного
/// или удерживаемого намерения вне D, кроме предмета.
final class _Removal {
  _Removal(this.planner, this.subject, {required this.archiveScope})
    : graph = planner.graph,
      below = Uint8List(planner._count),
      cascade = Uint8List(planner._count),
      single = Uint8List(planner._count) {
    final roots = switch (subject) {
      _IntentionSubject(:final intention) => [intention],
      _RelationSubject(:final target, :final archived) =>
        _includesRelation(archived) && _belowCandidate(target)
            ? [target]
            : const <int>[],
    };
    belowOrder = planner._preorder(
      roots,
      below,
      (edge, child) =>
          _includesRelation(graph.childArchived[edge] == 1) &&
          _belowCandidate(child),
    );
    if (subject case _IntentionSubject(:final intention)) {
      belowOrder.removeAt(0);
      below[intention] = 0;
      cascade[intention] = 1;
      single[intention] = 1;
    }
    final heldBelow = _heldBelow();
    var takesOthers = false;
    for (final intention in belowOrder) {
      if (heldBelow[intention] == 0) {
        cascade[intention] = 1;
        takesOthers = true;
      }
    }
    cascadeTakesOthers = takesOthers;
  }

  final IntentionCascadePlanner planner;
  final IntentionHoldingGraph graph;
  final _Subject subject;

  /// Архивирование учитывает только активное, удаление — всё.
  final bool archiveScope;

  /// Отметки и прямой порядок обхода D.
  final Uint8List below;
  late final List<int> belowOrder;

  /// Уходящие намерения варианта «со вспомогательными», включая
  /// намерение-предмет.
  final Uint8List cascade;

  /// Уходящие намерения варианта «только это».
  final Uint8List single;

  /// Каскад уносит хотя бы одно намерение, кроме намерения-предмета.
  late final bool cascadeTakesOthers;

  bool _includesIntention(int intention) =>
      !archiveScope || !planner._archived(intention);

  bool _includesRelation(bool archived) => !archiveScope || !archived;

  bool _belowCandidate(int intention) =>
      planner._supporting(intention) && _includesIntention(intention);

  bool _isSubjectRelation(int source, int target) => switch (subject) {
    _RelationSubject(source: final s, target: final t) =>
      s == source && t == target,
    _IntentionSubject() => false,
  };

  bool _isSubjectIntention(int intention) => switch (subject) {
    _IntentionSubject(intention: final subject) => subject == intention,
    _RelationSubject() => false,
  };

  Uint8List _heldBelow() {
    final heldBelow = Uint8List(planner._count);
    if (belowOrder.isEmpty) return heldBelow;
    final holders = archiveScope ? planner.held : _heldByAnyMain();
    final queue = <int>[];
    for (final intention in belowOrder) {
      for (
        var edge = graph.parentOffsets[intention];
        edge < graph.parentOffsets[intention + 1];
        edge++
      ) {
        final parent = graph.parents[edge];
        if (below[parent] == 0 &&
            holders[parent] == 1 &&
            _includesRelation(graph.parentArchived[edge] == 1) &&
            !_isSubjectIntention(parent) &&
            !_isSubjectRelation(parent, intention)) {
          heldBelow[intention] = 1;
          queue.add(intention);
          break;
        }
      }
    }
    for (var head = 0; head < queue.length; head++) {
      final holder = queue[head];
      for (
        var edge = graph.childOffsets[holder];
        edge < graph.childOffsets[holder + 1];
        edge++
      ) {
        final child = graph.children[edge];
        if (below[child] == 1 &&
            heldBelow[child] == 0 &&
            _includesRelation(graph.childArchived[edge] == 1) &&
            !_isSubjectRelation(holder, child)) {
          heldBelow[child] = 1;
          queue.add(child);
        }
      }
    }
    return heldBelow;
  }

  /// Удержание для удаления: держат и архивные главные, и архивные связи.
  Uint8List _heldByAnyMain() {
    final flags = graph.intentionFlags;
    final heldByAny = Uint8List(flags.length);
    final queue = <int>[];
    for (var intention = 0; intention < flags.length; intention++) {
      if (!planner._supporting(intention)) {
        heldByAny[intention] = 1;
        queue.add(intention);
      }
    }
    for (var head = 0; head < queue.length; head++) {
      final holder = queue[head];
      for (
        var edge = graph.childOffsets[holder];
        edge < graph.childOffsets[holder + 1];
        edge++
      ) {
        final child = graph.children[edge];
        if (heldByAny[child] == 0) {
          heldByAny[child] = 1;
          queue.add(child);
        }
      }
    }
    return heldByAny;
  }

  Uint8List _leaving(CascadeChoice choice) => switch (choice) {
    CascadeChoice.withSupporting => cascade,
    CascadeChoice.onlyThis => single,
  };

  /// Уходящие намерения варианта без намерения-предмета.
  List<IntentionId> departing(CascadeChoice choice) {
    final leaving = _leaving(choice);
    return [
      for (final intention in belowOrder)
        if (leaving[intention] == 1) planner.ids[intention],
    ];
  }

  /// При «только это» главными становятся непосредственно нижние намерения,
  /// которые ушли бы каскадом.
  Uint8List _promoted(CascadeChoice choice) {
    final promoted = Uint8List(planner._count);
    if (choice == CascadeChoice.withSupporting) return promoted;
    switch (subject) {
      case _IntentionSubject(:final intention):
        for (
          var edge = graph.childOffsets[intention];
          edge < graph.childOffsets[intention + 1];
          edge++
        ) {
          final child = graph.children[edge];
          if (cascade[child] == 1 &&
              _includesRelation(graph.childArchived[edge] == 1)) {
            promoted[child] = 1;
          }
        }
      case _RelationSubject(:final target):
        if (cascade[target] == 1) promoted[target] = 1;
    }
    return promoted;
  }

  List<IntentionId> promoted(CascadeChoice choice) {
    final promoted = _promoted(choice);
    return [
      for (final intention in belowOrder)
        if (promoted[intention] == 1) planner.ids[intention],
    ];
  }

  /// Главные на другом конце уходящих связей в порядке, в котором обход в
  /// глубину от предмета по уходящим намерениям встречает эти связи;
  /// входящие связи каждого намерения раньше исходящих.
  List<IntentionId> mainsLosingRelation(CascadeChoice choice) {
    final leaving = _leaving(choice);
    final recorded = Uint8List(planner._count);
    final mains = <IntentionId>[];
    void record(int intention) {
      if (leaving[intention] == 0 &&
          !planner._supporting(intention) &&
          recorded[intention] == 0) {
        recorded[intention] = 1;
        mains.add(planner.ids[intention]);
      }
    }

    final List<int> roots;
    switch (subject) {
      case _IntentionSubject(:final intention):
        roots = [intention];
      case _RelationSubject(:final source, :final target, :final archived):
        if (_includesRelation(archived)) {
          record(source);
          record(target);
        }
        roots = leaving[target] == 1 ? [target] : const [];
    }
    final offsets = graph.childOffsets;
    final visited = Uint8List(planner._count);
    final nodes = <int>[];
    final positions = <int>[];
    void enter(int intention) {
      visited[intention] = 1;
      nodes.add(intention);
      positions.add(offsets[intention]);
      for (
        var edge = graph.parentOffsets[intention];
        edge < graph.parentOffsets[intention + 1];
        edge++
      ) {
        if (_includesRelation(graph.parentArchived[edge] == 1)) {
          record(graph.parents[edge]);
        }
      }
    }

    for (final root in roots) {
      enter(root);
      while (nodes.isNotEmpty) {
        final top = nodes.length - 1;
        final edge = positions[top];
        if (edge == offsets[nodes[top] + 1]) {
          nodes.removeLast();
          positions.removeLast();
          continue;
        }
        positions[top] = edge + 1;
        if (!_includesRelation(graph.childArchived[edge] == 1)) continue;
        final child = graph.children[edge];
        if (leaving[child] == 1) {
          if (visited[child] == 0) enter(child);
        } else {
          record(child);
        }
      }
    }
    return mains;
  }

  /// Связи, уходящие вместе с намерениями варианта, и связь-предмет.
  int relationCount(CascadeChoice choice) {
    final leaving = _leaving(choice);
    var count = 0;
    final intentions = [
      if (subject case _IntentionSubject(:final intention)) intention,
      for (final intention in belowOrder)
        if (leaving[intention] == 1) intention,
    ];
    for (final intention in intentions) {
      for (
        var edge = graph.childOffsets[intention];
        edge < graph.childOffsets[intention + 1];
        edge++
      ) {
        if (_includesRelation(graph.childArchived[edge] == 1)) count++;
      }
      for (
        var edge = graph.parentOffsets[intention];
        edge < graph.parentOffsets[intention + 1];
        edge++
      ) {
        if (leaving[graph.parents[edge]] == 0 &&
            _includesRelation(graph.parentArchived[edge] == 1)) {
          count++;
        }
      }
    }
    if (subject
        case _RelationSubject(:final source, :final target, :final archived)
        when leaving[source] == 0 &&
            leaving[target] == 0 &&
            _includesRelation(archived)) {
      count++;
    }
    return count;
  }

  /// Второй проход удаления: активные вспомогательные, которые после
  /// удаления намерений варианта остались без активной входящей связи,
  /// архивируются вместе со всем ниже них, что не удерживают активные
  /// главные. Такие намерения лежат в D: связи теряют только нижние
  /// намерения удаляемых.
  List<IntentionId> archivedByInvariant(CascadeChoice choice) {
    final leaving = _leaving(choice);
    final promoted = _promoted(choice);
    bool remainsActiveSupporting(int intention) =>
        leaving[intention] == 0 &&
        promoted[intention] == 0 &&
        planner._supporting(intention) &&
        !planner._archived(intention);
    bool remainsActiveRelation(int source, int target, int archived) =>
        archived == 0 &&
        leaving[source] == 0 &&
        leaving[target] == 0 &&
        !_isSubjectRelation(source, target);

    final orphans = <int>[];
    final checked = Uint8List(planner._count);
    void check(int intention) {
      if (checked[intention] == 1 || !remainsActiveSupporting(intention)) {
        return;
      }
      checked[intention] = 1;
      for (
        var edge = graph.parentOffsets[intention];
        edge < graph.parentOffsets[intention + 1];
        edge++
      ) {
        if (remainsActiveRelation(
          graph.parents[edge],
          intention,
          graph.parentArchived[edge],
        )) {
          return;
        }
      }
      orphans.add(intention);
    }

    for (final intention in belowOrder) {
      check(intention);
    }
    if (orphans.isEmpty) return const [];

    final heldAfter = Uint8List(planner._count);
    final queue = <int>[];
    for (var intention = 0; intention < planner._count; intention++) {
      if (leaving[intention] == 0 &&
          !planner._archived(intention) &&
          (!planner._supporting(intention) || promoted[intention] == 1)) {
        heldAfter[intention] = 1;
        queue.add(intention);
      }
    }
    _spread(queue, heldAfter, remainsActiveSupporting, remainsActiveRelation);

    final archived = Uint8List(planner._count);
    final archiving = <int>[];
    for (final orphan in orphans) {
      archived[orphan] = 1;
      archiving.add(orphan);
    }
    _spread(
      archiving,
      archived,
      (intention) =>
          remainsActiveSupporting(intention) && heldAfter[intention] == 0,
      remainsActiveRelation,
    );

    return [
      for (final intention in belowOrder)
        if (archived[intention] == 1) planner.ids[intention],
    ];
  }

  /// Обход в ширину от [queue] по связям, которые допускает [relation], в
  /// намерения, которые допускает [admits]; дополняет [queue] и [marks].
  void _spread(
    List<int> queue,
    Uint8List marks,
    bool Function(int intention) admits,
    bool Function(int source, int target, int archived) relation,
  ) {
    for (var head = 0; head < queue.length; head++) {
      final source = queue[head];
      for (
        var edge = graph.childOffsets[source];
        edge < graph.childOffsets[source + 1];
        edge++
      ) {
        final child = graph.children[edge];
        if (marks[child] == 0 &&
            admits(child) &&
            relation(source, child, graph.childArchived[edge])) {
          marks[child] = 1;
          queue.add(child);
        }
      }
    }
  }
}
