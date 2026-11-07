import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_description.dart';
import '../domain/long_term_relation_id.dart';
import 'intention_relation_group.dart';

sealed class LongTermRelationCommand
    implements
        GraphCommand<
          LongTermRelationCommandSuccess,
          LongTermRelationCommandFailure
        > {
  const LongTermRelationCommand();
}

enum AddLongTermRelationsValidationFailure {
  noCandidates,
  duplicateCandidates,
  pageIntentionAmongCandidates,
}

final class AddLongTermRelationsValidationException implements Exception {
  const AddLongTermRelationsValidationException(this.failure);

  final AddLongTermRelationsValidationFailure failure;
}

/// Добавляет в группу страницы намерения связи с упорядоченным набором
/// намерений.
///
/// Группа задаёт тип и направление, поэтому приоритет и описание команда не
/// принимает: каждая связь получает P4 и не имеет описания. Порядок набора
/// становится порядком последовательности создания.
final class AddLongTermRelations extends LongTermRelationCommand {
  factory AddLongTermRelations({
    required IntentionId pageIntentionId,
    required IntentionRelationGroup group,
    required Iterable<IntentionId> candidateIds,
  }) {
    final candidates = List<IntentionId>.unmodifiable(candidateIds);
    if (candidates.isEmpty) {
      throw const AddLongTermRelationsValidationException(
        AddLongTermRelationsValidationFailure.noCandidates,
      );
    }
    if (candidates.toSet().length != candidates.length) {
      throw const AddLongTermRelationsValidationException(
        AddLongTermRelationsValidationFailure.duplicateCandidates,
      );
    }
    if (candidates.contains(pageIntentionId)) {
      throw const AddLongTermRelationsValidationException(
        AddLongTermRelationsValidationFailure.pageIntentionAmongCandidates,
      );
    }
    return AddLongTermRelations._(
      pageIntentionId: pageIntentionId,
      group: group,
      candidateIds: candidates,
    );
  }

  const AddLongTermRelations._({
    required this.pageIntentionId,
    required this.group,
    required this.candidateIds,
  });

  final IntentionId pageIntentionId;
  final IntentionRelationGroup group;
  final List<IntentionId> candidateIds;
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
    this.description = const LongTermRelationDescriptionUnchanged(),
  });

  final LongTermRelationFieldPatch<LongTermRelationType> type;
  final LongTermRelationFieldPatch<RelationPriority> priority;
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

final class LongTermRelationPairOccupiedFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationPairOccupiedFailure(this.existingRelationId);

  final LongTermRelationId existingRelationId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

/// Набор правок архивированной связи меняет её тип.
///
/// Архивированная связь сохраняет тип до восстановления, поэтому отклоняется
/// весь набор, а не только изменение типа.
final class LongTermRelationArchivedTypeChangeFailure
    extends LongTermRelationCommandFailure {
  const LongTermRelationArchivedTypeChangeFailure(this.relationId);

  final LongTermRelationId relationId;

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

/// Связи пачки в порядке набора команды.
final class LongTermRelationsAdded extends LongTermRelationCommandSuccess {
  LongTermRelationsAdded({
    required Iterable<LongTermRelation> relations,
    required super.changes,
  }) : relations = List.unmodifiable(relations);

  final List<LongTermRelation> relations;
}

final class LongTermRelationUpdated extends LongTermRelationCommandSuccess {
  LongTermRelationUpdated({
    required this.before,
    required this.relation,
    required this.description,
    required super.changes,
  });

  final LongTermRelation before;
  final LongTermRelation relation;
  final LongTermRelationDescription? description;
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
