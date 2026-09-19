import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_description.dart';

enum RelationParticipantSummaryValidationFailure { negativeActiveRelationCount }

final class RelationParticipantSummaryValidationException implements Exception {
  const RelationParticipantSummaryValidationException(this.failure);

  final RelationParticipantSummaryValidationFailure failure;
}

final class RelationParticipantSummary {
  factory RelationParticipantSummary({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
    required int activeRelationCount,
  }) {
    if (activeRelationCount < 0) {
      throw const RelationParticipantSummaryValidationException(
        RelationParticipantSummaryValidationFailure.negativeActiveRelationCount,
      );
    }
    return RelationParticipantSummary._(
      id: id,
      title: IntentionText.normalizeTitle(title),
      archiveState: archiveState,
      activeRelationCount: activeRelationCount,
    );
  }

  const RelationParticipantSummary._({
    required this.id,
    required this.title,
    required this.archiveState,
    required this.activeRelationCount,
  });

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
  final int activeRelationCount;
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

final class LongTermRelationDetails {
  factory LongTermRelationDetails({
    required LongTermRelation relation,
    required RelationParticipantSummary source,
    required RelationParticipantSummary related,
    required LongTermRelationDescription? description,
  }) {
    _ensureMatchingParticipants(relation, source, related);
    return LongTermRelationDetails._(
      relation: relation,
      source: source,
      related: related,
      description: description,
    );
  }

  const LongTermRelationDetails._({
    required this.relation,
    required this.source,
    required this.related,
    required this.description,
  });

  final LongTermRelation relation;
  final RelationParticipantSummary source;
  final RelationParticipantSummary related;
  final LongTermRelationDescription? description;

  bool get hasDescription => description != null;
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
