import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';

enum SelectedRelationsQueryValidationFailure {
  emptySelection,
  duplicateRelation,
}

final class SelectedRelationsQueryValidationException implements Exception {
  const SelectedRelationsQueryValidationException(this.failure);

  final SelectedRelationsQueryValidationFailure failure;
}

/// Неизменяемая граница одного явно выбранного набора связей намерения.
final class SelectedRelationsQuery {
  factory SelectedRelationsQuery({
    required IntentionId intentionId,
    required Iterable<LongTermRelationId> relationIds,
  }) {
    final ids = <LongTermRelationId>{};
    for (final id in relationIds) {
      if (!ids.add(id)) {
        throw const SelectedRelationsQueryValidationException(
          SelectedRelationsQueryValidationFailure.duplicateRelation,
        );
      }
    }
    if (ids.isEmpty) {
      throw const SelectedRelationsQueryValidationException(
        SelectedRelationsQueryValidationFailure.emptySelection,
      );
    }
    return SelectedRelationsQuery._(
      intentionId: intentionId,
      relationIds: Set.unmodifiable(ids),
    );
  }

  const SelectedRelationsQuery._({
    required this.intentionId,
    required this.relationIds,
  });

  final IntentionId intentionId;
  final Set<LongTermRelationId> relationIds;
}

sealed class SelectedRelationEntry {
  const SelectedRelationEntry(this.id);

  final LongTermRelationId id;
}

final class SelectedRelationPresent extends SelectedRelationEntry {
  SelectedRelationPresent(this.details) : super(details.relation.id);

  final LongTermRelationDetails details;
}

final class SelectedRelationMissing extends SelectedRelationEntry {
  const SelectedRelationMissing(super.id);
}

final class SelectedRelationNoLongerBlocking extends SelectedRelationEntry {
  const SelectedRelationNoLongerBlocking(super.id);
}

enum SelectedRelationsSnapshotValidationFailure { entriesMismatch }

final class SelectedRelationsSnapshotValidationException implements Exception {
  const SelectedRelationsSnapshotValidationException(this.failure);

  final SelectedRelationsSnapshotValidationFailure failure;
}

final class SelectedRelationsSnapshot {
  factory SelectedRelationsSnapshot({
    required SelectedRelationsQuery query,
    required Map<LongTermRelationId, SelectedRelationEntry> entries,
  }) {
    if (entries.length != query.relationIds.length ||
        !entries.keys.toSet().containsAll(query.relationIds) ||
        entries.entries.any((entry) {
          if (entry.key != entry.value.id) return true;
          if (entry.value case SelectedRelationPresent(:final details)) {
            return details.relation.sourceIntentionId != query.intentionId &&
                details.relation.relatedIntentionId != query.intentionId;
          }
          return false;
        })) {
      throw const SelectedRelationsSnapshotValidationException(
        SelectedRelationsSnapshotValidationFailure.entriesMismatch,
      );
    }
    return SelectedRelationsSnapshot._(Map.unmodifiable(entries));
  }

  const SelectedRelationsSnapshot._(this.entries);

  final Map<LongTermRelationId, SelectedRelationEntry> entries;
}

sealed class SelectedRelationsReadFailure implements GraphCommandFailure {
  const SelectedRelationsReadFailure();
}

final class SelectedRelationsReadUnavailableFailure
    extends SelectedRelationsReadFailure {
  const SelectedRelationsReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class SelectedRelationsReadCorruptionFailure
    extends SelectedRelationsReadFailure {
  const SelectedRelationsReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class SelectedRelationsReadUnexpectedFailure
    extends SelectedRelationsReadFailure {
  const SelectedRelationsReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef SelectedRelationsReadResult =
    GraphResult<
      GraphSnapshot<SelectedRelationsSnapshot>,
      SelectedRelationsReadFailure
    >;
typedef SelectedRelationsReadSuccess =
    GraphResultSuccess<
      GraphSnapshot<SelectedRelationsSnapshot>,
      SelectedRelationsReadFailure
    >;
typedef SelectedRelationsReadError =
    GraphResultFailure<
      GraphSnapshot<SelectedRelationsSnapshot>,
      SelectedRelationsReadFailure
    >;
