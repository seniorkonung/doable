import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_target.dart';

/// Все назначенные получателю теги в порядке создания тегов.
/// Пустой успех означает существующего получателя без назначений.
final class TagAssignmentsSnapshot {
  TagAssignmentsSnapshot({
    required this.target,
    required List<Tag> items,
    required this.revision,
  }) : items = List.unmodifiable(items);
  final TagTarget target;
  final List<Tag> items;
  final GraphRevision revision;
}

sealed class TagAssignmentsReadFailure implements GraphCommandFailure {
  const TagAssignmentsReadFailure();
}

final class TagAssignmentsTargetNotFound extends TagAssignmentsReadFailure {
  const TagAssignmentsTargetNotFound();

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
