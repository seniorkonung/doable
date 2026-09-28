import '../../../graph/application/graph_revision.dart';
import '../../application/tagged_entities_page.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';

sealed class TagNavigationState {
  const TagNavigationState({required this.tagId, required this.scope});

  final TagId tagId;
  final TaggedEntitiesScope scope;
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

  final TaggedEntitiesReadFailure failure;
  bool get canRetry => failure is TaggedEntitiesUnavailableFailure;
}

sealed class TagNavigationPageStatus {
  const TagNavigationPageStatus();
}

final class TagNavigationPageIdle extends TagNavigationPageStatus {
  const TagNavigationPageIdle();
}

final class TagNavigationPageLoading extends TagNavigationPageStatus {
  const TagNavigationPageLoading();
}

final class TagNavigationPageFailure extends TagNavigationPageStatus {
  const TagNavigationPageFailure(this.failure);

  final TaggedEntitiesReadFailure failure;
  bool get canRetry => failure is TaggedEntitiesUnavailableFailure;
}

/// Смешанные строки и продолжение принадлежат одному тегу, охвату и снимку.
final class TagNavigationLoaded extends TagNavigationState {
  TagNavigationLoaded({
    required this.tag,
    required super.scope,
    required List<TaggedEntity> items,
    required this.nextCursor,
    required this.revision,
    this.pageStatus = const TagNavigationPageIdle(),
  }) : items = List.unmodifiable(items),
       super(tagId: tag.id);

  final Tag tag;
  final List<TaggedEntity> items;
  final TaggedEntitiesCursor? nextCursor;
  final GraphRevision revision;
  final TagNavigationPageStatus pageStatus;

  bool get isEmpty => items.isEmpty;
  bool get hasReachedEnd =>
      nextCursor == null && pageStatus is TagNavigationPageIdle;

  TagNavigationLoaded withPageStatus(
    TagNavigationPageStatus status, {
    bool clearCursor = false,
  }) => TagNavigationLoaded(
    tag: tag,
    scope: scope,
    items: items,
    nextCursor: clearCursor ? null : nextCursor,
    revision: revision,
    pageStatus: status,
  );
}
