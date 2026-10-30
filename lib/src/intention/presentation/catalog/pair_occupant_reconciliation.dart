import '../../../graph/application/graph_change.dart';
import '../../../long_term_relation/application/long_term_relation_command.dart';
import '../../../long_term_relation/application/relation_pair_probe.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../domain/intention_id.dart';

/// Занимающие связи строк [rowIds] после подтверждённых фактов [changes].
///
/// Прежнее состояние связи снимает отметку своего кандидата, только если она
/// указывает на эту связь, а новое ставит отметку, если строка кандидата
/// загружена.
Map<IntentionId, PairOccupant> reconcilePairOccupants({
  required RelationPairProbe probe,
  required Map<IntentionId, PairOccupant> occupants,
  required Set<IntentionId> rowIds,
  required Iterable<LongTermRelationChange> changes,
}) {
  final reconciled = {...occupants};
  for (final change in changes) {
    final previousCandidate = switch (change.before) {
      final relation? => _candidate(probe, relation),
      null => null,
    };
    if (reconciled[previousCandidate]?.relationId == change.id) {
      reconciled.remove(previousCandidate);
    }
    if (change.after case final relation?) {
      final candidate = _candidate(probe, relation);
      if (candidate != null && rowIds.contains(candidate)) {
        reconciled[candidate] = PairOccupant(
          relationId: relation.id,
          scope: relation.scope,
        );
      }
    }
  }
  return reconciled;
}

/// Намерение, выбор которого в роли пробы дал бы пару [relation]; `null` —
/// связь пару не занимает.
IntentionId? _candidate(RelationPairProbe probe, LongTermRelation relation) {
  if (relation.id == probe.ignoredRelationId) {
    return null;
  }
  return switch (probe.candidateRole) {
    RelationParticipantRole.related
        when relation.sourceIntentionId == probe.counterpartId =>
      relation.relatedIntentionId,
    RelationParticipantRole.source
        when relation.relatedIntentionId == probe.counterpartId =>
      relation.sourceIntentionId,
    _ => null,
  };
}
