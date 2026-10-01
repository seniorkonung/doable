import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/tagged_intentions_page.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';

sealed class TagNavigationState {
  const TagNavigationState({required this.tagId, required this.scope});

  final TagId tagId;
  final TaggedIntentionsScope scope;
}

final class TagNavigationInitialLoading extends TagNavigationState {
  const TagNavigationInitialLoading({
    required super.tagId,
    required super.scope,
  });
}

final class TagNavigationTagMissing extends TagNavigationState {
  const TagNavigationTagMissing({required super.tagId, required super.scope});
}

final class TagNavigationInitialFailure extends TagNavigationState {
  const TagNavigationInitialFailure({
    required super.tagId,
    required super.scope,
    required this.failure,
  });

  final TaggedIntentionsReadFailure failure;
  bool get canRetry => failure is TaggedIntentionsUnavailableFailure;
}

sealed class TagNavigationPageStatus {
  const TagNavigationPageStatus();
}

enum TagNavigationFreshness { current, refreshing, stale }

final class TagNavigationPageIdle extends TagNavigationPageStatus {
  const TagNavigationPageIdle();
}

final class TagNavigationPageLoading extends TagNavigationPageStatus {
  const TagNavigationPageLoading();
}

final class TagNavigationPageFailure extends TagNavigationPageStatus {
  const TagNavigationPageFailure(this.failure);

  final TaggedIntentionsReadFailure failure;
  bool get canRetry => failure is TaggedIntentionsUnavailableFailure;
}

/// Помеченные намерения и продолжение принадлежат одному тегу, охвату и снимку.
final class TagNavigationLoaded extends TagNavigationState {
  TagNavigationLoaded({
    required this.tag,
    required super.scope,
    required List<TaggedIntention> items,
    required this.nextCursor,
    required this.revision,
    this.freshness = TagNavigationFreshness.current,
    this.refreshFailure,
    this.pageStatus = const TagNavigationPageIdle(),
  }) : items = List.unmodifiable(items),
       super(tagId: tag.id);

  final Tag tag;
  final List<TaggedIntention> items;
  final TaggedIntentionsCursor? nextCursor;
  final GraphRevision revision;
  final TagNavigationFreshness freshness;
  final TaggedIntentionsReadFailure? refreshFailure;
  final TagNavigationPageStatus pageStatus;

  bool get isEmpty => items.isEmpty;
  bool get canUseCurrentItems => freshness == TagNavigationFreshness.current;
  bool get hasReachedEnd =>
      canUseCurrentItems &&
      nextCursor == null &&
      pageStatus is TagNavigationPageIdle;

  bool contains(IntentionId intentionId) =>
      items.any((item) => item.id == intentionId);

  TagNavigationLoaded withStatus({
    Tag? tag,
    bool clearCursor = false,
    TagNavigationFreshness? freshness,
    TaggedIntentionsReadFailure? refreshFailure,
    TagNavigationPageStatus? pageStatus,
  }) => TagNavigationLoaded(
    tag: tag ?? this.tag,
    scope: scope,
    items: items,
    nextCursor: clearCursor ? null : nextCursor,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
    pageStatus: pageStatus ?? this.pageStatus,
  );

  TagNavigationLoaded withPageStatus(
    TagNavigationPageStatus status, {
    bool clearCursor = false,
  }) => TagNavigationLoaded(
    tag: tag,
    scope: scope,
    items: items,
    nextCursor: clearCursor ? null : nextCursor,
    revision: revision,
    freshness: freshness,
    refreshFailure: refreshFailure,
    pageStatus: status,
  );
}
