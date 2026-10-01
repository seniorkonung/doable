import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';

/// Снимок одной пары тега и намерения без загрузки списка назначений.
typedef TagAssignmentStatusResult =
    GraphResult<GraphSnapshot<bool>, TagAssignmentStatusFailure>;
typedef TagAssignmentStatusSuccess =
    GraphResultSuccess<GraphSnapshot<bool>, TagAssignmentStatusFailure>;
typedef TagAssignmentStatusError =
    GraphResultFailure<GraphSnapshot<bool>, TagAssignmentStatusFailure>;

sealed class TagAssignmentStatusFailure implements GraphCommandFailure {
  const TagAssignmentStatusFailure();
}

final class TagAssignmentStatusTagNotFound extends TagAssignmentStatusFailure {
  const TagAssignmentStatusTagNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagAssignmentStatusIntentionNotFound
    extends TagAssignmentStatusFailure {
  const TagAssignmentStatusIntentionNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagAssignmentStatusUnavailable extends TagAssignmentStatusFailure {
  const TagAssignmentStatusUnavailable();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagAssignmentStatusCorruption extends TagAssignmentStatusFailure {
  const TagAssignmentStatusCorruption();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagAssignmentStatusUnexpected extends TagAssignmentStatusFailure {
  const TagAssignmentStatusUnexpected();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}
