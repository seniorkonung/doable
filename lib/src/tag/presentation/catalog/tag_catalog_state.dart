import '../../../graph/application/graph_revision.dart';
import '../../application/tag_catalog.dart';
import '../../domain/tag.dart';

sealed class TagCatalogState {
  const TagCatalogState();
}

final class TagCatalogInitialLoading extends TagCatalogState {
  const TagCatalogInitialLoading();
}

final class TagCatalogInitialFailure extends TagCatalogState {
  const TagCatalogInitialFailure(this.failure);

  final TagCatalogReadFailure failure;
  bool get canRetry => failure is TagCatalogUnavailableFailure;
}

enum TagCatalogFreshness { current, refreshing, stale }

sealed class TagCatalogPageStatus {
  const TagCatalogPageStatus();
}

final class TagCatalogPageIdle extends TagCatalogPageStatus {
  const TagCatalogPageIdle();
}

final class TagCatalogPageLoading extends TagCatalogPageStatus {
  const TagCatalogPageLoading();
}

final class TagCatalogPageFailure extends TagCatalogPageStatus {
  const TagCatalogPageFailure(this.failure);

  final TagCatalogReadFailure failure;
  bool get canRetry => failure is TagCatalogUnavailableFailure;
}

/// Строки и курсор принадлежат одной отображаемой основе. При актуализации
/// известные имена и удаления учитываются сразу, но список остаётся неактуальным.
final class TagCatalogLoaded extends TagCatalogState {
  TagCatalogLoaded({
    required List<Tag> items,
    required this.nextCursor,
    required this.revision,
    this.freshness = TagCatalogFreshness.current,
    this.refreshFailure,
    this.pageStatus = const TagCatalogPageIdle(),
  }) : items = List.unmodifiable(items);

  final List<Tag> items;
  final TagCatalogCursor? nextCursor;
  final GraphRevision revision;
  final TagCatalogFreshness freshness;
  final TagCatalogReadFailure? refreshFailure;
  final TagCatalogPageStatus pageStatus;

  bool get isEmpty => items.isEmpty;
  bool get canUseCurrentItems => freshness == TagCatalogFreshness.current;

  TagCatalogLoaded withStatus({
    List<Tag>? items,
    TagCatalogFreshness? freshness,
    TagCatalogReadFailure? refreshFailure,
    TagCatalogPageStatus? pageStatus,
  }) => TagCatalogLoaded(
    items: items ?? this.items,
    nextCursor: nextCursor,
    revision: revision,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure,
    pageStatus: pageStatus ?? this.pageStatus,
  );
}
