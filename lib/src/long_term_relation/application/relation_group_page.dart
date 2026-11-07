import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/long_term_relation.dart';
import 'long_term_relation_projection.dart';
import 'relation_counts.dart';

enum RelationGroupQueryValidationFailure { pageSizeOutOfRange }

final class RelationGroupQueryValidationException implements Exception {
  const RelationGroupQueryValidationException(this.failure);

  final RelationGroupQueryValidationFailure failure;
}

/// Непрозрачное продолжение одной согласованной группы связей.
abstract interface class RelationGroupCursor {}

final class RelationGroupQuery {
  factory RelationGroupQuery({
    required IntentionId intentionId,
    required LongTermRelationType type,
    required RelationDirection direction,
    required RelationScope scope,
    required int pageSize,
    RelationGroupCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const RelationGroupQueryValidationException(
        RelationGroupQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return RelationGroupQuery._(
      intentionId: intentionId,
      type: type,
      direction: direction,
      scope: scope,
      pageSize: pageSize,
      cursor: cursor,
    );
  }

  const RelationGroupQuery._({
    required this.intentionId,
    required this.type,
    required this.direction,
    required this.scope,
    required this.pageSize,
    required this.cursor,
  });

  static const minPageSize = 1;
  static const maxPageSize = 100;

  final IntentionId intentionId;
  final LongTermRelationType type;
  final RelationDirection direction;
  final RelationScope scope;
  final int pageSize;
  final RelationGroupCursor? cursor;
}

/// Первая порция содержит полную сводку восьми групп на своей ревизии.
/// Продолжение сохраняет привязку к ревизии через непрозрачный курсор.
sealed class RelationGroupPage {
  const RelationGroupPage({required this.nextCursor, required this.revision});

  final RelationGroupCursor? nextCursor;
  final GraphRevision revision;
}

final class RelationGroupFirstPage extends RelationGroupPage {
  RelationGroupFirstPage({
    required List<RelationGroupEntry> items,
    required this.counts,
    required super.nextCursor,
    required super.revision,
  }) : items = List.unmodifiable(items);

  final List<RelationGroupEntry> items;
  final RelationCounts counts;
}

final class RelationGroupContinuationPage extends RelationGroupPage {
  RelationGroupContinuationPage({
    required List<RelationGroupEntry> items,
    required super.nextCursor,
    required super.revision,
  }) : items = List.unmodifiable(items);

  final List<RelationGroupEntry> items;
}

sealed class RelationGroupReadFailure implements GraphCommandFailure {
  const RelationGroupReadFailure();
}

final class RelationGroupIntentionNotFoundFailure
    extends RelationGroupReadFailure {
  const RelationGroupIntentionNotFoundFailure(this.intentionId);

  final IntentionId intentionId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

/// Продолжение относится к уже недоступному снимку графа.
final class RelationGroupSnapshotExpired extends RelationGroupReadFailure {
  const RelationGroupSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class RelationGroupUnavailableFailure extends RelationGroupReadFailure {
  const RelationGroupUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class RelationGroupCorruptionFailure extends RelationGroupReadFailure {
  const RelationGroupCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class RelationGroupUnexpectedFailure extends RelationGroupReadFailure {
  const RelationGroupUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef RelationGroupPageResult =
    GraphResult<RelationGroupPage, RelationGroupReadFailure>;
typedef RelationGroupPageSuccess =
    GraphResultSuccess<RelationGroupPage, RelationGroupReadFailure>;
typedef RelationGroupPageFailure =
    GraphResultFailure<RelationGroupPage, RelationGroupReadFailure>;
