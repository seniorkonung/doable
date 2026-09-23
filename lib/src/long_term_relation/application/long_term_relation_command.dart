import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_description.dart';
import '../domain/long_term_relation_id.dart';
import 'long_term_relation_permissions.dart';

sealed class LongTermRelationCommand
    implements
        GraphCommand<
          LongTermRelationCommandSuccess,
          LongTermRelationCommandFailure
        > {
  const LongTermRelationCommand();
}

enum CreateLongTermRelationValidationFailure { sameIntention }

final class CreateLongTermRelationValidationException implements Exception {
  const CreateLongTermRelationValidationException(this.failure);

  final CreateLongTermRelationValidationFailure failure;
}

final class CreateLongTermRelation extends LongTermRelationCommand {
  factory CreateLongTermRelation({
    required IntentionId sourceIntentionId,
    required IntentionId relatedIntentionId,
    required LongTermRelationType type,
    required RelationPriority priority,
    required LongTermRelationDescription? description,
  }) {
    if (sourceIntentionId == relatedIntentionId) {
      throw const CreateLongTermRelationValidationException(
        CreateLongTermRelationValidationFailure.sameIntention,
      );
    }
    return CreateLongTermRelation._(
      sourceIntentionId: sourceIntentionId,
      relatedIntentionId: relatedIntentionId,
      type: type,
      priority: priority,
      description: description,
    );
  }

  const CreateLongTermRelation._({
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    required this.description,
  });

  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final LongTermRelationDescription? description;
}

sealed class LongTermRelationFieldPatch<T extends Object> {
  const LongTermRelationFieldPatch();
}

final class LongTermRelationFieldUnchanged<T extends Object>
    extends LongTermRelationFieldPatch<T> {
  const LongTermRelationFieldUnchanged();
}

final class LongTermRelationFieldSet<T extends Object>
    extends LongTermRelationFieldPatch<T> {
  const LongTermRelationFieldSet(this.value);

  final T value;
}

sealed class LongTermRelationDescriptionPatch {
  const LongTermRelationDescriptionPatch();

  static LongTermRelationDescriptionPatch fromInput(String input) {
    final description = LongTermRelationDescription.fromInput(input);
    return description == null
        ? const LongTermRelationDescriptionCleared()
        : LongTermRelationDescriptionReplaced(description);
  }
}

final class LongTermRelationDescriptionUnchanged
    extends LongTermRelationDescriptionPatch {
  const LongTermRelationDescriptionUnchanged();
}

final class LongTermRelationDescriptionCleared
    extends LongTermRelationDescriptionPatch {
  const LongTermRelationDescriptionCleared();
}

final class LongTermRelationDescriptionReplaced
    extends LongTermRelationDescriptionPatch {
  const LongTermRelationDescriptionReplaced(this.value);

  final LongTermRelationDescription value;
}

final class LongTermRelationPatch {
  const LongTermRelationPatch({
    this.type = const LongTermRelationFieldUnchanged<LongTermRelationType>(),
    this.priority = const LongTermRelationFieldUnchanged<RelationPriority>(),
    this.sourceIntentionId =
        const LongTermRelationFieldUnchanged<IntentionId>(),
    this.relatedIntentionId =
        const LongTermRelationFieldUnchanged<IntentionId>(),
    this.description = const LongTermRelationDescriptionUnchanged(),
  });

  final LongTermRelationFieldPatch<LongTermRelationType> type;
  final LongTermRelationFieldPatch<RelationPriority> priority;
  final LongTermRelationFieldPatch<IntentionId> sourceIntentionId;
  final LongTermRelationFieldPatch<IntentionId> relatedIntentionId;
  final LongTermRelationDescriptionPatch description;
}

final class UpdateLongTermRelation extends LongTermRelationCommand {
  const UpdateLongTermRelation({required this.relationId, required this.patch});

  final LongTermRelationId relationId;
  final LongTermRelationPatch patch;
}

final class ArchiveLongTermRelation extends LongTermRelationCommand {
  const ArchiveLongTermRelation(this.relationId);

  final LongTermRelationId relationId;
}

final class RestoreLongTermRelation extends LongTermRelationCommand {
  const RestoreLongTermRelation(this.relationId);

  final LongTermRelationId relationId;
}

final class DeleteLongTermRelation extends LongTermRelationCommand {
  const DeleteLongTermRelation(this.relationId);

  final LongTermRelationId relationId;
}

enum RelationParticipantRole { source, related }

sealed class LongTermRelationCommandFailure implements GraphCommandFailure {
  const LongTermRelationCommandFailure();
}

final class LongTermRelationCommandValidationFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationCommandValidationFailure(this.reason);

  final CreateLongTermRelationValidationFailure reason;

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

final class LongTermRelationPairOccupiedFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationPairOccupiedFailure(this.existingRelationId);

  final LongTermRelationId existingRelationId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class LongTermRelationNotFoundFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationNotFoundFailure(this.relationId);

  final LongTermRelationId relationId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class LongTermRelationParticipantNotFoundFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationParticipantNotFoundFailure({
    required this.role,
    required this.intentionId,
  });

  final RelationParticipantRole role;
  final IntentionId intentionId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class LongTermRelationParticipantArchivedFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationParticipantArchivedFailure({
    required this.role,
    required this.intentionId,
  });

  final RelationParticipantRole role;
  final IntentionId intentionId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class LongTermRelationUnavailableFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class LongTermRelationCorruptionFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class LongTermRelationUnexpectedFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

sealed class LongTermRelationCommandSuccess implements GraphCommandOutcome {
  LongTermRelationCommandSuccess({required Iterable<GraphChange> changes})
    : changes = List.unmodifiable(changes);

  @override
  final List<GraphChange> changes;
}

final class LongTermRelationCreated extends LongTermRelationCommandSuccess {
  LongTermRelationCreated({
    required this.relation,
    required this.description,
    this.permissions = const LongTermRelationPermissions.unknown(),
    required super.changes,
  });

  final LongTermRelation relation;
  final LongTermRelationDescription? description;
  final LongTermRelationPermissions permissions;
}

final class LongTermRelationUpdated extends LongTermRelationCommandSuccess {
  LongTermRelationUpdated({
    required this.before,
    required this.relation,
    required this.description,
    this.permissions = const LongTermRelationPermissions.unknown(),
    required super.changes,
  });

  final LongTermRelation before;
  final LongTermRelation relation;
  final LongTermRelationDescription? description;
  final LongTermRelationPermissions permissions;
}

final class LongTermRelationDeleted extends LongTermRelationCommandSuccess {
  LongTermRelationDeleted({required this.relation, required super.changes});

  final LongTermRelation relation;
}

typedef LongTermRelationCommandResult =
    GraphCommandResult<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >;
