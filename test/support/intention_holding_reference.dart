import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';

typedef HoldingReferenceIntention = ({
  IntentionKind kind,
  IntentionArchiveState archiveState,
});

typedef HoldingReferenceRelation = ({
  IntentionId source,
  IntentionId target,
  RelationScope scope,
});

/// Независимый эталон удержания: повторяет проход по всем связям, пока
/// множество удерживаемых растёт, без очереди обхода и компактной смежности.
/// Активное главное удерживает себя, а активная связь от удерживаемого
/// передаёт удержание активному вспомогательному.
Set<IntentionId> referenceHeldIntentions({
  required Map<IntentionId, HoldingReferenceIntention> intentions,
  required List<HoldingReferenceRelation> relations,
}) {
  bool isActive(IntentionId id) =>
      intentions[id]!.archiveState == IntentionArchiveState.active;
  final held = {
    for (final MapEntry(:key, :value) in intentions.entries)
      if (value.kind == IntentionKind.main && isActive(key)) key,
  };
  var grew = true;
  while (grew) {
    grew = false;
    for (final relation in relations) {
      if (relation.scope == RelationScope.active &&
          held.contains(relation.source) &&
          intentions[relation.target]!.kind == IntentionKind.supporting &&
          isActive(relation.target) &&
          held.add(relation.target)) {
        grew = true;
      }
    }
  }
  return held;
}
