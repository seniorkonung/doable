import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';

import 'intention_holding_reference.dart';

/// Предмет эталона: намерение или связь из [CascadeReferenceGraph.relations].
typedef CascadeReferenceSubject = ({
  IntentionId? intention,
  HoldingReferenceRelation? relation,
});

typedef CascadeReferenceGraph = ({
  Map<IntentionId, HoldingReferenceIntention> intentions,
  List<HoldingReferenceRelation> relations,
});

/// Множества и числа варианта архивирования или удаления. Множества не
/// содержат намерение-предмет.
typedef CascadeReferenceRemoval = ({
  Set<IntentionId> departing,
  Set<IntentionId> promoted,
  Set<IntentionId> archivedByInvariant,
  Set<IntentionId> mainsLosingRelation,
  int removedRelationCount,
  int archivedByInvariantRelationCount,
});

typedef CascadeReferenceRestore = ({
  Set<IntentionId> restored,
  Set<IntentionId> returnedAsMain,
  int restoredRelationCount,
});

/// Независимый эталон каскада: применяет правила `intention-cascade`
/// напрямую повторными проходами по всем связям, пока множество растёт, без
/// компактной смежности, обхода в глубину и удержания внутри D. Удержание
/// после операции считается заново по всему графу без предмета.
({
  CascadeReferenceRemoval withSupporting,
  CascadeReferenceRemoval onlyThis,
  bool asksQuestion,
})
referenceCascadeRemoval(
  CascadeReferenceGraph graph,
  CascadeReferenceSubject subject, {
  required bool delete,
}) {
  final intentions = graph.intentions;
  bool active(IntentionId id) =>
      intentions[id]!.archiveState == IntentionArchiveState.active;
  bool supporting(IntentionId id) =>
      intentions[id]!.kind == IntentionKind.supporting;
  bool inScope(IntentionId id) => delete || active(id);
  bool relationInScope(HoldingReferenceRelation relation) =>
      delete || relation.scope == RelationScope.active;
  final relations = [
    for (final relation in graph.relations)
      if (relationInScope(relation)) relation,
  ];
  final x = subject.intention;
  final r = subject.relation;

  // Ниже элемента: вспомогательные, до которых можно дойти вниз от элемента
  // через вспомогательные.
  final below = <IntentionId>{};
  _grow(() {
    var grew = false;
    for (final relation in relations) {
      final fromElement =
          relation.source == x ||
          below.contains(relation.source) ||
          identical(relation, r);
      if (fromElement &&
          relation.target != x &&
          supporting(relation.target) &&
          inScope(relation.target) &&
          below.add(relation.target)) {
        grew = true;
      }
    }
    return grew;
  });

  // Удержание после операции: главные держат себя и передают удержание по
  // связям через вспомогательные; предмет ничего не держит.
  final heldAfter = {
    for (final id in intentions.keys)
      if (id != x && !supporting(id) && inScope(id)) id,
  };
  _grow(() {
    var grew = false;
    for (final relation in relations) {
      if (!identical(relation, r) &&
          heldAfter.contains(relation.source) &&
          relation.target != x &&
          supporting(relation.target) &&
          inScope(relation.target) &&
          heldAfter.add(relation.target)) {
        grew = true;
      }
    }
    return grew;
  });
  final departing = below.difference(heldAfter);
  final directlyBelow = {
    for (final relation in relations)
      if (relation.source == x || identical(relation, r)) relation.target,
  };

  CascadeReferenceRemoval variant({required bool onlyThis}) {
    final gone = {?x, if (!onlyThis) ...departing};
    final promoted = onlyThis
        ? departing.intersection(directlyBelow)
        : <IntentionId>{};
    bool removed(HoldingReferenceRelation relation) =>
        identical(relation, r) ||
        gone.contains(relation.source) ||
        gone.contains(relation.target);
    final removedRelations = [
      for (final relation in relations)
        if (removed(relation)) relation,
    ];
    final mains = <IntentionId>{
      for (final relation in removedRelations)
        for (final end in [relation.source, relation.target])
          if (!gone.contains(end) && !supporting(end)) end,
    };

    final archived = <IntentionId>{};
    var archivedRelationCount = 0;
    if (delete) {
      bool mainAfter(IntentionId id) =>
          !supporting(id) || promoted.contains(id);
      final activeAfter = [
        for (final relation in graph.relations)
          if (relation.scope == RelationScope.active && !removed(relation))
            relation,
      ];
      bool activeSupportingAfter(IntentionId id) =>
          !gone.contains(id) && active(id) && !mainAfter(id);
      archived.addAll([
        for (final id in intentions.keys)
          if (activeSupportingAfter(id) &&
              !activeAfter.any((relation) => relation.target == id))
            id,
      ]);
      final heldByActiveMain = {
        for (final id in intentions.keys)
          if (!gone.contains(id) && active(id) && mainAfter(id)) id,
      };
      _grow(() {
        var grew = false;
        for (final relation in activeAfter) {
          if (heldByActiveMain.contains(relation.source) &&
              activeSupportingAfter(relation.target) &&
              heldByActiveMain.add(relation.target)) {
            grew = true;
          }
        }
        return grew;
      });
      _grow(() {
        var grew = false;
        for (final relation in activeAfter) {
          if (archived.contains(relation.source) &&
              activeSupportingAfter(relation.target) &&
              !heldByActiveMain.contains(relation.target) &&
              archived.add(relation.target)) {
            grew = true;
          }
        }
        return grew;
      });
      archivedRelationCount = activeAfter
          .where(
            (relation) =>
                archived.contains(relation.source) ||
                archived.contains(relation.target),
          )
          .length;
    }
    return (
      departing: gone.difference({?x}),
      promoted: promoted,
      archivedByInvariant: archived,
      mainsLosingRelation: mains,
      removedRelationCount: removedRelations.length,
      archivedByInvariantRelationCount: archivedRelationCount,
    );
  }

  return (
    withSupporting: variant(onlyThis: false),
    onlyThis: variant(onlyThis: true),
    asksQuestion: departing.isNotEmpty,
  );
}

/// Эталон восстановления: архивные участники элемента и каскадом —
/// архивные вспомогательные, до которых можно дойти вниз от них через
/// архивные вспомогательные.
({
  CascadeReferenceRestore withSupporting,
  CascadeReferenceRestore onlyThis,
  bool asksQuestion,
})
referenceCascadeRestore(
  CascadeReferenceGraph graph,
  CascadeReferenceSubject subject,
) {
  final intentions = graph.intentions;
  bool archivedIntention(IntentionId id) =>
      intentions[id]!.archiveState == IntentionArchiveState.archived;
  final x = subject.intention;
  final r = subject.relation;
  final participants = {
    ?x,
    if (r != null)
      for (final end in [r.source, r.target])
        if (archivedIntention(end)) end,
  };
  final cascade = {...participants};
  _grow(() {
    var grew = false;
    for (final relation in graph.relations) {
      if (cascade.contains(relation.source) &&
          archivedIntention(relation.target) &&
          intentions[relation.target]!.kind == IntentionKind.supporting &&
          cascade.add(relation.target)) {
        grew = true;
      }
    }
    return grew;
  });

  CascadeReferenceRestore variant(Set<IntentionId> restored) {
    bool activeAfter(IntentionId id) =>
        !archivedIntention(id) || restored.contains(id);
    final restoredRelations = [
      for (final relation in graph.relations)
        if (relation.scope == RelationScope.archived &&
            (identical(relation, r) ||
                restored.contains(relation.source) ||
                restored.contains(relation.target)) &&
            activeAfter(relation.source) &&
            activeAfter(relation.target))
          relation,
    ];
    return (
      restored: restored.difference({?x}),
      returnedAsMain: {
        for (final id in restored)
          if (intentions[id]!.kind == IntentionKind.supporting &&
              !graph.relations.any(
                (relation) =>
                    relation.target == id && activeAfter(relation.source),
              ))
            id,
      },
      restoredRelationCount: restoredRelations.length,
    );
  }

  return (
    withSupporting: variant(cascade),
    onlyThis: variant(participants),
    asksQuestion: cascade.length > participants.length,
  );
}

void _grow(bool Function() pass) {
  while (pass()) {}
}
