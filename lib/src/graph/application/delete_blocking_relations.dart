import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_change.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';

enum DeleteBlockingRelationsValidationFailure {
  emptySelection,
  duplicateRelation,
}

final class DeleteBlockingRelationsValidationException implements Exception {
  const DeleteBlockingRelationsValidationException(this.failure);

  final DeleteBlockingRelationsValidationFailure failure;
}

/// Фиксирует подтверждённый набор; репозиторий удаляет его целиком одной транзакцией.
final class DeleteBlockingRelations
    implements
        GraphCommand<BlockingRelationsDeleted, DeleteBlockingRelationsFailure> {
  factory DeleteBlockingRelations({
    required IntentionId intentionId,
    required Iterable<LongTermRelationId> relationIds,
  }) {
    final selectedIds = <LongTermRelationId>{};
    for (final id in relationIds) {
      if (!selectedIds.add(id)) {
        throw const DeleteBlockingRelationsValidationException(
          DeleteBlockingRelationsValidationFailure.duplicateRelation,
        );
      }
    }
    if (selectedIds.isEmpty) {
      throw const DeleteBlockingRelationsValidationException(
        DeleteBlockingRelationsValidationFailure.emptySelection,
      );
    }
    return DeleteBlockingRelations._(
      intentionId: intentionId,
      relationIds: Set<LongTermRelationId>.unmodifiable(selectedIds),
    );
  }

  const DeleteBlockingRelations._({
    required this.intentionId,
    required this.relationIds,
  });

  final IntentionId intentionId;
  final Set<LongTermRelationId> relationIds;
}

sealed class DeleteBlockingRelationsFailure implements GraphCommandFailure {
  const DeleteBlockingRelationsFailure();
}

final class DeleteBlockingRelationsIntentionNotFoundFailure
    extends DeleteBlockingRelationsFailure {
  const DeleteBlockingRelationsIntentionNotFoundFailure(this.intentionId);

  final IntentionId intentionId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

enum BlockingRelationConflictReason {
  relationMissing,
  noLongerBlocking,
  deletionProhibited,
}

final class DeleteBlockingRelationsSelectionConflictFailure
    extends DeleteBlockingRelationsFailure {
  const DeleteBlockingRelationsSelectionConflictFailure({
    required this.relationId,
    required this.reason,
  });

  final LongTermRelationId relationId;
  final BlockingRelationConflictReason reason;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class DeleteBlockingRelationsUnavailableFailure
    extends DeleteBlockingRelationsFailure {
  const DeleteBlockingRelationsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class DeleteBlockingRelationsCorruptionFailure
    extends DeleteBlockingRelationsFailure {
  const DeleteBlockingRelationsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class DeleteBlockingRelationsUnexpectedFailure
    extends DeleteBlockingRelationsFailure {
  const DeleteBlockingRelationsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

enum BlockingRelationsDeletedValidationFailure {
  relationsMismatch,
  notBlockingIntention,
  countsMismatch,
}

final class BlockingRelationsDeletedValidationException implements Exception {
  const BlockingRelationsDeletedValidationException(this.failure);

  final BlockingRelationsDeletedValidationFailure failure;
}

/// Подтверждается одной ревизией вместе со всеми удалениями и новыми счётчиками.
final class BlockingRelationsDeleted implements GraphCommandOutcome {
  factory BlockingRelationsDeleted({
    required DeleteBlockingRelations command,
    required GraphRevision revision,
    required Iterable<LongTermRelation> deletedRelations,
    required Map<IntentionId, RelationCounts> counts,
  }) {
    final deleted = List<LongTermRelation>.unmodifiable(deletedRelations);
    final deletedIds = {for (final relation in deleted) relation.id};
    if (deletedIds.length != deleted.length ||
        deletedIds.length != command.relationIds.length ||
        !deletedIds.containsAll(command.relationIds)) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.relationsMismatch,
      );
    }
    if (deleted.any(
      (relation) =>
          relation.sourceIntentionId != command.intentionId &&
          relation.relatedIntentionId != command.intentionId,
    )) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.notBlockingIntention,
      );
    }
    final affectedIds = <IntentionId>{
      command.intentionId,
      for (final relation in deleted) ...[
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      ],
    };
    if (counts.length != affectedIds.length ||
        !counts.keys.toSet().containsAll(affectedIds)) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.countsMismatch,
      );
    }
    return BlockingRelationsDeleted._(
      deletedRelations: deleted,
      changes: List<GraphChange>.unmodifiable([
        for (final relation in deleted)
          LongTermRelationDeletedChange(revision: revision, relation: relation),
        for (final entry in counts.entries)
          IntentionRelationCountsChanged(
            revision: revision,
            intentionId: entry.key,
            counts: entry.value,
          ),
      ]),
    );
  }

  const BlockingRelationsDeleted._({
    required this.deletedRelations,
    required this.changes,
  });

  final List<LongTermRelation> deletedRelations;

  @override
  final List<GraphChange> changes;
}

typedef DeleteBlockingRelationsResult =
    GraphCommandResult<
      BlockingRelationsDeleted,
      DeleteBlockingRelationsFailure
    >;
