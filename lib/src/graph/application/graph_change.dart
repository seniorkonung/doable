import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_revision.dart';

final class IntentionRelationCountsChanged implements GraphChange {
  const IntentionRelationCountsChanged({
    required this.revision,
    required this.intentionId,
    required this.counts,
  });

  @override
  final GraphRevision revision;
  final IntentionId intentionId;
  final RelationCounts counts;
}

sealed class LongTermRelationChange implements GraphChange {
  const LongTermRelationChange();

  LongTermRelationId get id;
  LongTermRelation? get before;
  LongTermRelation? get after;
}

final class LongTermRelationCreatedChange extends LongTermRelationChange {
  const LongTermRelationCreatedChange({
    required this.revision,
    required this.relation,
  });

  @override
  final GraphRevision revision;
  final LongTermRelation relation;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation? get before => null;

  @override
  LongTermRelation get after => relation;
}

enum LongTermRelationChangeValidationFailure { identityMismatch }

final class LongTermRelationChangeValidationException implements Exception {
  const LongTermRelationChangeValidationException(this.failure);

  final LongTermRelationChangeValidationFailure failure;
}

final class LongTermRelationUpdatedChange extends LongTermRelationChange {
  factory LongTermRelationUpdatedChange({
    required GraphRevision revision,
    required LongTermRelation before,
    required LongTermRelation after,
  }) {
    if (before.id != after.id) {
      throw const LongTermRelationChangeValidationException(
        LongTermRelationChangeValidationFailure.identityMismatch,
      );
    }
    return LongTermRelationUpdatedChange._(
      revision: revision,
      before: before,
      after: after,
    );
  }

  const LongTermRelationUpdatedChange._({
    required this.revision,
    required this.before,
    required this.after,
  });

  @override
  final GraphRevision revision;

  @override
  final LongTermRelation before;

  @override
  final LongTermRelation after;

  @override
  LongTermRelationId get id => after.id;
}

final class LongTermRelationDeletedChange extends LongTermRelationChange {
  const LongTermRelationDeletedChange({
    required this.revision,
    required this.relation,
  });

  @override
  final GraphRevision revision;
  final LongTermRelation relation;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation get before => relation;

  @override
  LongTermRelation? get after => null;
}
