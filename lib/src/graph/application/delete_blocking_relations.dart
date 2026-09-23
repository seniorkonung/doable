import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'blocking_relation_reference.dart';
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
    required Iterable<BlockingRelationReference> references,
  }) {
    final selected = <BlockingRelationReference>{};
    for (final reference in references) {
      if (!selected.add(reference)) {
        throw const DeleteBlockingRelationsValidationException(
          DeleteBlockingRelationsValidationFailure.duplicateRelation,
        );
      }
    }
    if (selected.isEmpty) {
      throw const DeleteBlockingRelationsValidationException(
        DeleteBlockingRelationsValidationFailure.emptySelection,
      );
    }
    return DeleteBlockingRelations._(
      intentionId: intentionId,
      references: Set<BlockingRelationReference>.unmodifiable(selected),
    );
  }

  factory DeleteBlockingRelations.longTerm({
    required IntentionId intentionId,
    required Iterable<LongTermRelationId> relationIds,
  }) => DeleteBlockingRelations(
    intentionId: intentionId,
    references: relationIds.map(LongTermBlockingRelationReference.new),
  );

  const DeleteBlockingRelations._({
    required this.intentionId,
    required this.references,
  });

  final IntentionId intentionId;
  final Set<BlockingRelationReference> references;

  Set<LongTermRelationId> get relationIds => Set.unmodifiable(
    references.whereType<LongTermBlockingRelationReference>().map(
      (ref) => ref.id,
    ),
  );

  Set<DailyChoiceId> get dailyChoiceIds => Set.unmodifiable(
    references.whereType<DailyChoiceBlockingRelationReference>().map(
      (ref) => ref.id,
    ),
  );
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
  DeleteBlockingRelationsSelectionConflictFailure.longTerm({
    required LongTermRelationId relationId,
    required BlockingRelationConflictReason reason,
  }) : this(
         reference: LongTermBlockingRelationReference(relationId),
         reason: reason,
       );

  const DeleteBlockingRelationsSelectionConflictFailure({
    required this.reference,
    required this.reason,
  });

  final BlockingRelationReference reference;
  final BlockingRelationConflictReason reason;

  LongTermRelationId? get relationId => switch (reference) {
    LongTermBlockingRelationReference(:final id) => id,
    DailyChoiceBlockingRelationReference() => null,
  };

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
  choicesMismatch,
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
    Iterable<DailyChoiceChange> deletedChoiceChanges = const [],
    required Map<IntentionId, RelationCounts> counts,
  }) {
    final deleted = List<LongTermRelation>.unmodifiable(deletedRelations);
    final choiceChanges = List<DailyChoiceChange>.unmodifiable(
      deletedChoiceChanges,
    );
    final deletedIds = {for (final relation in deleted) relation.id};
    if (deletedIds.length != deleted.length ||
        deletedIds.length != command.relationIds.length ||
        !deletedIds.containsAll(command.relationIds)) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.relationsMismatch,
      );
    }
    final choiceIds = {
      for (final change in choiceChanges)
        if (change.before case final choice?) choice.id,
    };
    if (choiceIds.length != choiceChanges.length ||
        choiceIds.length != command.dailyChoiceIds.length ||
        !choiceIds.containsAll(command.dailyChoiceIds) ||
        choiceChanges.any(
          (change) =>
              change.after != null ||
              change.before == null ||
              (change.before!.sourceIntentionId != command.intentionId &&
                  change.before!.selectedIntentionId != command.intentionId),
        )) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.choicesMismatch,
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
      for (final change in choiceChanges) ...change.previousParticipants,
    };
    if (counts.length != affectedIds.length ||
        !counts.keys.toSet().containsAll(affectedIds)) {
      throw const BlockingRelationsDeletedValidationException(
        BlockingRelationsDeletedValidationFailure.countsMismatch,
      );
    }
    return BlockingRelationsDeleted._(
      deletedRelations: deleted,
      deletedDailyChoices: List<DailyChoice>.unmodifiable(
        choiceChanges.map((change) => change.before!),
      ),
      changes: List<GraphChange>.unmodifiable([
        for (final relation in deleted)
          LongTermRelationDeletedChange(revision: revision, relation: relation),
        ...choiceChanges,
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
    required this.deletedDailyChoices,
    required this.changes,
  });

  final List<LongTermRelation> deletedRelations;
  final List<DailyChoice> deletedDailyChoices;

  @override
  final List<GraphChange> changes;
}

typedef DeleteBlockingRelationsResult =
    GraphCommandResult<
      BlockingRelationsDeleted,
      DeleteBlockingRelationsFailure
    >;
