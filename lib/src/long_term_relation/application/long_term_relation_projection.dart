import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../../shared/domain/text_preview.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_description.dart';
import 'long_term_relation_permissions.dart';

final class RelationParticipantSummary {
  factory RelationParticipantSummary({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
  }) => RelationParticipantSummary._(
    id: id,
    title: IntentionText.normalizeTitle(title),
    archiveState: archiveState,
  );

  const RelationParticipantSummary._({
    required this.id,
    required this.title,
    required this.archiveState,
  });

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
}

/// Сосед в строке группы: участник связи, который не владеет группой.
final class RelationNeighbor {
  factory RelationNeighbor({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
    required IntentionReadiness readiness,
  }) => RelationNeighbor._(
    id: id,
    title: IntentionText.normalizeTitle(title),
    archiveState: archiveState,
    readiness: readiness,
  );

  const RelationNeighbor._({
    required this.id,
    required this.title,
    required this.archiveState,
    required this.readiness,
  });

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
  final IntentionReadiness readiness;
}

enum LongTermRelationProjectionValidationFailure { participantMismatch }

final class LongTermRelationProjectionValidationException implements Exception {
  const LongTermRelationProjectionValidationException(this.failure);

  final LongTermRelationProjectionValidationFailure failure;
}

final class LongTermRelationSummary {
  factory LongTermRelationSummary({
    required LongTermRelation relation,
    required RelationParticipantSummary source,
    required RelationParticipantSummary related,
    required bool hasDescription,
  }) {
    _ensureMatchingParticipants(relation, source, related);
    return LongTermRelationSummary._(
      relation: relation,
      source: source,
      related: related,
      hasDescription: hasDescription,
    );
  }

  const LongTermRelationSummary._({
    required this.relation,
    required this.source,
    required this.related,
    required this.hasDescription,
  });

  final LongTermRelation relation;
  final RelationParticipantSummary source;
  final RelationParticipantSummary related;
  final bool hasDescription;
}

/// Строка порции группы связей: связь, её сосед и начало описания.
///
/// Владельца группы в строке нет: его знает страница, которая читает группу.
final class RelationGroupEntry {
  factory RelationGroupEntry({
    required LongTermRelation relation,
    required RelationNeighbor neighbor,
    TextPreview? descriptionPreview,
  }) {
    if (neighbor.id != relation.sourceIntentionId &&
        neighbor.id != relation.relatedIntentionId) {
      throw const LongTermRelationProjectionValidationException(
        LongTermRelationProjectionValidationFailure.participantMismatch,
      );
    }
    return RelationGroupEntry._(
      relation: relation,
      neighbor: neighbor,
      descriptionPreview: descriptionPreview,
    );
  }

  const RelationGroupEntry._({
    required this.relation,
    required this.neighbor,
    required this.descriptionPreview,
  });

  final LongTermRelation relation;
  final RelationNeighbor neighbor;

  /// Начало описания; у связи без описания его нет.
  final TextPreview? descriptionPreview;
}

final class LongTermRelationDetails {
  factory LongTermRelationDetails({
    required LongTermRelation relation,
    required RelationParticipantSummary source,
    required RelationParticipantSummary related,
    required LongTermRelationDescription? description,
    LongTermRelationPermissions permissions =
        const LongTermRelationPermissions.unknown(),
  }) {
    _ensureMatchingParticipants(relation, source, related);
    return LongTermRelationDetails._(
      relation: relation,
      source: source,
      related: related,
      description: description,
      permissions: permissions,
    );
  }

  const LongTermRelationDetails._({
    required this.relation,
    required this.source,
    required this.related,
    required this.description,
    required this.permissions,
  });

  final LongTermRelation relation;
  final RelationParticipantSummary source;
  final RelationParticipantSummary related;
  final LongTermRelationDescription? description;
  final LongTermRelationPermissions permissions;

  bool get hasDescription => description != null;

  LongTermRelationDetails withPermissions(LongTermRelationPermissions value) =>
      LongTermRelationDetails(
        relation: relation,
        source: source,
        related: related,
        description: description,
        permissions: value,
      );
}

sealed class LongTermRelationReadFailure implements GraphCommandFailure {
  const LongTermRelationReadFailure();
}

final class LongTermRelationReadUnavailableFailure
    extends LongTermRelationReadFailure {
  const LongTermRelationReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class LongTermRelationReadCorruptionFailure
    extends LongTermRelationReadFailure {
  const LongTermRelationReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class LongTermRelationReadUnexpectedFailure
    extends LongTermRelationReadFailure {
  const LongTermRelationReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef LongTermRelationReadResult =
    GraphResult<
      GraphSnapshot<LongTermRelationDetails?>,
      LongTermRelationReadFailure
    >;
typedef LongTermRelationReadSuccess =
    GraphResultSuccess<
      GraphSnapshot<LongTermRelationDetails?>,
      LongTermRelationReadFailure
    >;
typedef LongTermRelationReadError =
    GraphResultFailure<
      GraphSnapshot<LongTermRelationDetails?>,
      LongTermRelationReadFailure
    >;

void _ensureMatchingParticipants(
  LongTermRelation relation,
  RelationParticipantSummary source,
  RelationParticipantSummary related,
) {
  if (source.id != relation.sourceIntentionId ||
      related.id != relation.relatedIntentionId) {
    throw const LongTermRelationProjectionValidationException(
      LongTermRelationProjectionValidationFailure.participantMismatch,
    );
  }
}
