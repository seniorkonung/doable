import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';

sealed class TagTarget {
  const TagTarget();
}

final class IntentionTagTarget extends TagTarget {
  const IntentionTagTarget(this.intentionId);

  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is IntentionTagTarget && other.intentionId == intentionId;

  @override
  int get hashCode => Object.hash(IntentionTagTarget, intentionId);
}

final class LongTermRelationTagTarget extends TagTarget {
  const LongTermRelationTagTarget(this.relationId);

  final LongTermRelationId relationId;

  @override
  bool operator ==(Object other) =>
      other is LongTermRelationTagTarget && other.relationId == relationId;

  @override
  int get hashCode => Object.hash(LongTermRelationTagTarget, relationId);
}
