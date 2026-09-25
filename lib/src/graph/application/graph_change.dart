import '../../daily_choice/domain/daily_choice.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/application/long_term_relation_permissions.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_revision.dart';

enum DailyChoiceChangeValidationFailure {
  missingChoice,
  identityMismatch,
  invalidPathDelta,
  missingCounts,
  missingPermissions,
  unconfirmedPermissions,
}

final class DailyChoiceChangeValidationException implements Exception {
  const DailyChoiceChangeValidationException(this.failure);

  final DailyChoiceChangeValidationFailure failure;
}

/// Изменение выбора и подтверждённые зависимости одной ревизии графа.
final class DailyChoiceChange implements GraphChange {
  factory DailyChoiceChange({
    required GraphRevision revision,
    required DailyChoice? before,
    required DailyChoice? after,
    required Iterable<LongTermRelationId> releasedRelationIds,
    required Iterable<LongTermRelationId> occupiedRelationIds,
    required Map<IntentionId, RelationCounts> intentionCounts,
    required Map<LongTermRelationId, LongTermRelationPermissions>
    relationPermissions,
  }) {
    if (before == null && after == null) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.missingChoice,
      );
    }
    if (before != null && after != null && before.id != after.id) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.identityMismatch,
      );
    }
    final released = Set<LongTermRelationId>.unmodifiable(releasedRelationIds);
    final occupied = Set<LongTermRelationId>.unmodifiable(occupiedRelationIds);
    if ((before == null && released.isNotEmpty) ||
        (after == null && occupied.isNotEmpty) ||
        (before == null && occupied.isEmpty) ||
        (after == null && released.isEmpty) ||
        released.intersection(occupied).isNotEmpty) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.invalidPathDelta,
      );
    }
    final previousParticipants = _participants(before);
    final currentParticipants = _participants(after);
    final counts = Map<IntentionId, RelationCounts>.unmodifiable(
      intentionCounts,
    );
    if (!counts.keys.toSet().containsAll({
      ...previousParticipants,
      ...currentParticipants,
    })) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.missingCounts,
      );
    }
    final permissions =
        Map<LongTermRelationId, LongTermRelationPermissions>.unmodifiable(
          relationPermissions,
        );
    if (!permissions.keys.toSet().containsAll({...released, ...occupied})) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.missingPermissions,
      );
    }
    if (permissions.values.any((permission) => !permission.isConfirmed)) {
      throw const DailyChoiceChangeValidationException(
        DailyChoiceChangeValidationFailure.unconfirmedPermissions,
      );
    }
    return DailyChoiceChange._(
      revision: revision,
      before: before,
      after: after,
      previousParticipants: previousParticipants,
      currentParticipants: currentParticipants,
      releasedRelationIds: released,
      occupiedRelationIds: occupied,
      intentionCounts: counts,
      relationPermissions: permissions,
    );
  }

  const DailyChoiceChange._({
    required this.revision,
    required this.before,
    required this.after,
    required this.previousParticipants,
    required this.currentParticipants,
    required this.releasedRelationIds,
    required this.occupiedRelationIds,
    required this.intentionCounts,
    required this.relationPermissions,
  });

  @override
  final GraphRevision revision;
  final DailyChoice? before;
  final DailyChoice? after;
  final Set<IntentionId> previousParticipants;
  final Set<IntentionId> currentParticipants;
  final Set<LongTermRelationId> releasedRelationIds;
  final Set<LongTermRelationId> occupiedRelationIds;
  final Map<IntentionId, RelationCounts> intentionCounts;
  final Map<LongTermRelationId, LongTermRelationPermissions>
  relationPermissions;

  static Set<IntentionId> _participants(DailyChoice? choice) =>
      Set<IntentionId>.unmodifiable(
        choice == null
            ? <IntentionId>{}
            : {choice.sourceIntentionId, choice.selectedIntentionId},
      );
}

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
  LongTermRelationPermissions? get permissions;
}

final class LongTermRelationCreatedChange extends LongTermRelationChange {
  const LongTermRelationCreatedChange({
    required this.revision,
    required this.relation,
    this.permissions = const LongTermRelationPermissions.unknown(),
  });

  @override
  final GraphRevision revision;
  final LongTermRelation relation;
  @override
  final LongTermRelationPermissions permissions;

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
    LongTermRelationPermissions permissions =
        const LongTermRelationPermissions.unknown(),
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
      permissions: permissions,
    );
  }

  const LongTermRelationUpdatedChange._({
    required this.revision,
    required this.before,
    required this.after,
    required this.permissions,
  });

  @override
  final GraphRevision revision;

  @override
  final LongTermRelation before;

  @override
  final LongTermRelation after;
  @override
  final LongTermRelationPermissions permissions;

  @override
  LongTermRelationId get id => after.id;
}

final class LongTermRelationUnchangedChange extends LongTermRelationChange {
  const LongTermRelationUnchangedChange({
    required this.revision,
    required this.relation,
    this.permissions = const LongTermRelationPermissions.unknown(),
  });

  @override
  final GraphRevision revision;

  final LongTermRelation relation;
  @override
  final LongTermRelationPermissions permissions;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation get before => relation;

  @override
  LongTermRelation get after => relation;
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
  @override
  LongTermRelationPermissions? get permissions => null;
}
