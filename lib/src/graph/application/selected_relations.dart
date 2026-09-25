import '../../daily_choice/application/daily_choice_catalog.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'blocking_relation_reference.dart';
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
/// Смешанный запрос сохраняет вид каждой ссылки, даже при совпадении UUID.
final class SelectedRelationsQuery {
  factory SelectedRelationsQuery({
    required IntentionId intentionId,
    required Iterable<LongTermRelationId> relationIds,
  }) => SelectedRelationsQuery.mixed(
    intentionId: intentionId,
    references: relationIds.map(LongTermBlockingRelationReference.new),
  );

  factory SelectedRelationsQuery.mixed({
    required IntentionId intentionId,
    required Iterable<BlockingRelationReference> references,
  }) {
    final selected = <BlockingRelationReference>{};
    for (final reference in references) {
      if (!selected.add(reference)) {
        throw const SelectedRelationsQueryValidationException(
          SelectedRelationsQueryValidationFailure.duplicateRelation,
        );
      }
    }
    if (selected.isEmpty) {
      throw const SelectedRelationsQueryValidationException(
        SelectedRelationsQueryValidationFailure.emptySelection,
      );
    }
    return SelectedRelationsQuery._(
      intentionId: intentionId,
      references: Set.unmodifiable(selected),
      relationIds: Set.unmodifiable(
        selected.whereType<LongTermBlockingRelationReference>().map(
          (reference) => reference.id,
        ),
      ),
      dailyChoiceIds: Set.unmodifiable(
        selected.whereType<DailyChoiceBlockingRelationReference>().map(
          (reference) => reference.id,
        ),
      ),
    );
  }

  const SelectedRelationsQuery._({
    required this.intentionId,
    required this.references,
    required this.relationIds,
    required this.dailyChoiceIds,
  });

  final IntentionId intentionId;
  final Set<BlockingRelationReference> references;
  final Set<LongTermRelationId> relationIds;
  final Set<DailyChoiceId> dailyChoiceIds;
}

sealed class SelectedRelationEntry {
  const SelectedRelationEntry();

  BlockingRelationReference get reference;
}

final class SelectedRelationPresent extends SelectedRelationEntry {
  SelectedRelationPresent(this.details);

  final LongTermRelationDetails details;
  LongTermRelationId get id => details.relation.id;
  bool get canDelete => details.permissions.canDelete;

  @override
  BlockingRelationReference get reference =>
      LongTermBlockingRelationReference(id);
}

final class SelectedRelationMissing extends SelectedRelationEntry {
  const SelectedRelationMissing(this.id);

  final LongTermRelationId id;

  @override
  BlockingRelationReference get reference =>
      LongTermBlockingRelationReference(id);
}

final class SelectedRelationNoLongerBlocking extends SelectedRelationEntry {
  const SelectedRelationNoLongerBlocking(this.id);

  final LongTermRelationId id;

  @override
  BlockingRelationReference get reference =>
      LongTermBlockingRelationReference(id);
}

final class SelectedDailyChoicePresent extends SelectedRelationEntry {
  SelectedDailyChoicePresent(this.item);

  final DailyChoiceCatalogItem item;
  DailyChoiceId get id => item.id;

  /// Прямую дневную связь можно удалить отдельной подтверждённой командой.
  bool get canDelete => true;

  @override
  BlockingRelationReference get reference =>
      DailyChoiceBlockingRelationReference(id);
}

final class SelectedDailyChoiceMissing extends SelectedRelationEntry {
  const SelectedDailyChoiceMissing(this.id);

  final DailyChoiceId id;

  @override
  BlockingRelationReference get reference =>
      DailyChoiceBlockingRelationReference(id);
}

final class SelectedDailyChoiceNoLongerBlocking extends SelectedRelationEntry {
  const SelectedDailyChoiceNoLongerBlocking(this.id);

  final DailyChoiceId id;

  @override
  BlockingRelationReference get reference =>
      DailyChoiceBlockingRelationReference(id);
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
  }) => SelectedRelationsSnapshot.mixed(
    query: query,
    entriesByReference: {
      for (final entry in entries.entries)
        LongTermBlockingRelationReference(entry.key): entry.value,
    },
  );

  factory SelectedRelationsSnapshot.mixed({
    required SelectedRelationsQuery query,
    required Map<BlockingRelationReference, SelectedRelationEntry>
    entriesByReference,
  }) {
    if (entriesByReference.length != query.references.length ||
        !entriesByReference.keys.toSet().containsAll(query.references) ||
        entriesByReference.entries.any((entry) {
          if (entry.key != entry.value.reference) return true;
          if (entry.value case SelectedRelationPresent(:final details)) {
            return details.relation.sourceIntentionId != query.intentionId &&
                details.relation.relatedIntentionId != query.intentionId;
          }
          if (entry.value case SelectedDailyChoicePresent(:final item)) {
            return item.source.id != query.intentionId &&
                item.selected.id != query.intentionId;
          }
          return false;
        })) {
      throw const SelectedRelationsSnapshotValidationException(
        SelectedRelationsSnapshotValidationFailure.entriesMismatch,
      );
    }
    return SelectedRelationsSnapshot._(Map.unmodifiable(entriesByReference));
  }

  const SelectedRelationsSnapshot._(this.entriesByReference);

  /// Каждая ссылка исходного запроса имеет ровно один результат.
  final Map<BlockingRelationReference, SelectedRelationEntry>
  entriesByReference;

  /// Совместимое представление долговременной части для существующего экрана.
  Map<LongTermRelationId, SelectedRelationEntry> get entries =>
      Map.unmodifiable({
        for (final entry in entriesByReference.entries)
          if (entry.key case LongTermBlockingRelationReference(:final id))
            id: entry.value,
      });
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
