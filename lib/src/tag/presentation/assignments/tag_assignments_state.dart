import '../../../graph/application/graph_revision.dart';
import '../../application/tag_assignments_page.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_target.dart';

sealed class TagAssignmentsState {
  const TagAssignmentsState();
}

final class TagAssignmentsInitialLoading extends TagAssignmentsState {
  const TagAssignmentsInitialLoading();
}

final class TagAssignmentsTargetMissing extends TagAssignmentsState {
  const TagAssignmentsTargetMissing();
}

final class TagAssignmentsInitialFailure extends TagAssignmentsState {
  const TagAssignmentsInitialFailure(this.failure);

  final TagAssignmentsReadFailure failure;
  bool get canRetry => failure is TagAssignmentsUnavailableFailure;
}

enum TagAssignmentsFreshness { current, refreshing, stale }

sealed class TagAssignmentsPageStatus {
  const TagAssignmentsPageStatus();
}

final class TagAssignmentsPageIdle extends TagAssignmentsPageStatus {
  const TagAssignmentsPageIdle();
}

final class TagAssignmentsPageLoading extends TagAssignmentsPageStatus {
  const TagAssignmentsPageLoading();
}

final class TagAssignmentsPageFailure extends TagAssignmentsPageStatus {
  const TagAssignmentsPageFailure(this.failure);

  final TagAssignmentsReadFailure failure;
  bool get canRetry => failure is TagAssignmentsUnavailableFailure;
}

/// Строки и продолжение относятся к одной основе. Во время актуализации
/// известные изменения показаны сразу, но действия с ними недоступны.
final class TagAssignmentsLoaded extends TagAssignmentsState {
  TagAssignmentsLoaded({
    required this.target,
    required List<Tag> items,
    required this.nextCursor,
    required this.revision,
    this.freshness = TagAssignmentsFreshness.current,
    this.refreshFailure,
    this.pageStatus = const TagAssignmentsPageIdle(),
  }) : items = List.unmodifiable(items);

  final TagTarget target;
  final List<Tag> items;
  final TagAssignmentsCursor? nextCursor;
  final GraphRevision revision;
  final TagAssignmentsFreshness freshness;
  final TagAssignmentsReadFailure? refreshFailure;
  final TagAssignmentsPageStatus pageStatus;

  bool get isEmpty => items.isEmpty;
  bool get canUseCurrentItems => freshness == TagAssignmentsFreshness.current;

  bool contains(TagId id) => items.any((tag) => tag.id == id);

  TagAssignmentsLoaded withStatus({
    List<Tag>? items,
    bool clearCursor = false,
    TagAssignmentsFreshness? freshness,
    TagAssignmentsReadFailure? refreshFailure,
    TagAssignmentsPageStatus? pageStatus,
  }) => TagAssignmentsLoaded(
    target: target,
    items: items ?? this.items,
    nextCursor: clearCursor ? null : nextCursor,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
    pageStatus: pageStatus ?? this.pageStatus,
  );
}
