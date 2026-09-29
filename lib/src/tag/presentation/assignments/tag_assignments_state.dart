import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/tag_assignments.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';

sealed class TagAssignmentsState {
  const TagAssignmentsState();
}

final class TagAssignmentsInitialLoading extends TagAssignmentsState {
  const TagAssignmentsInitialLoading();
}

final class TagAssignmentsIntentionMissing extends TagAssignmentsState {
  const TagAssignmentsIntentionMissing();
}

final class TagAssignmentsInitialFailure extends TagAssignmentsState {
  const TagAssignmentsInitialFailure(this.failure);

  final TagAssignmentsReadFailure failure;
  bool get canRetry => failure is TagAssignmentsUnavailableFailure;
}

enum TagAssignmentsFreshness { current, refreshing, stale }

/// Строки относятся к одному полному снимку. Во время актуализации
/// известные изменения показаны сразу, но действия с ними недоступны.
final class TagAssignmentsLoaded extends TagAssignmentsState {
  TagAssignmentsLoaded({
    required this.intentionId,
    required List<Tag> items,
    required this.revision,
    this.freshness = TagAssignmentsFreshness.current,
    this.refreshFailure,
  }) : items = List.unmodifiable(items);

  final IntentionId intentionId;
  final List<Tag> items;
  final GraphRevision revision;
  final TagAssignmentsFreshness freshness;
  final TagAssignmentsReadFailure? refreshFailure;

  bool get isEmpty => items.isEmpty;
  bool get canUseCurrentItems => freshness == TagAssignmentsFreshness.current;

  bool contains(TagId id) => items.any((tag) => tag.id == id);

  TagAssignmentsLoaded withStatus({
    List<Tag>? items,
    TagAssignmentsFreshness? freshness,
    TagAssignmentsReadFailure? refreshFailure,
  }) => TagAssignmentsLoaded(
    intentionId: intentionId,
    items: items ?? this.items,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
  );
}
