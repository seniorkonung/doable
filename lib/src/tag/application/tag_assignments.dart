import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/tag.dart';

/// Все назначенные намерению теги в порядке создания тегов на одной ревизии.
/// Пустой успех означает существующее намерение без назначений.
final class TagAssignmentsSnapshot {
  TagAssignmentsSnapshot({
    required this.intentionId,
    required List<Tag> items,
    required this.revision,
  }) : items = List.unmodifiable(items);
  final IntentionId intentionId;
  final List<Tag> items;
  final GraphRevision revision;
}

sealed class TagAssignmentsReadFailure implements GraphCommandFailure {
  const TagAssignmentsReadFailure();
}

final class TagAssignmentsIntentionNotFound extends TagAssignmentsReadFailure {
  const TagAssignmentsIntentionNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagAssignmentsUnavailableFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagAssignmentsCorruptionFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagAssignmentsUnexpectedFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TagAssignmentsResult =
    GraphResult<TagAssignmentsSnapshot, TagAssignmentsReadFailure>;
typedef TagAssignmentsSuccess =
    GraphResultSuccess<TagAssignmentsSnapshot, TagAssignmentsReadFailure>;
typedef TagAssignmentsError =
    GraphResultFailure<TagAssignmentsSnapshot, TagAssignmentsReadFailure>;
