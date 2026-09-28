import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_read_result.dart';
import '../../application/tagged_entities_page.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_target.dart';
import 'tag_navigation_state.dart';

part 'tag_navigation_view_model.g.dart';

final tagNavigationReaderProvider = Provider<TagReadContract>(
  (ref) => ref.watch(personalGraphRepositoryProvider),
);

@riverpod
final class TagNavigationViewModel extends _$TagNavigationViewModel {
  late TagId _tagId;
  late TagReadContract _reads;
  TaggedEntitiesScope _scope = TaggedEntitiesScope.active;
  Future<void>? _activeRequest;
  bool _firstPagePending = false;
  int _generation = 0;

  @override
  TagNavigationState build(TagId tagId) {
    _tagId = tagId;
    _scope = TaggedEntitiesScope.active;
    _reads = ref.watch(tagNavigationReaderProvider);
    _generation++;
    ref.onDispose(() {
      _generation++;
      _firstPagePending = false;
    });
    _requestFirstPage();
    return _loading();
  }

  void setTagId(TagId tagId) {
    if (!ref.mounted || _tagId == tagId) return;
    _tagId = tagId;
    _changeSelection();
  }

  void setScope(TaggedEntitiesScope scope) {
    if (!ref.mounted || _scope == scope) return;
    _scope = scope;
    _changeSelection();
  }

  void _changeSelection() {
    _generation++;
    state = _loading();
    _requestFirstPage();
  }

  /// Прежний запрос теряет право публикации, но завершается до нового чтения.
  /// Несколько смен выбора объединяются в одну первую порцию последнего выбора.
  void _requestFirstPage() {
    _firstPagePending = _activeRequest != null;
    if (!_firstPagePending) unawaited(_startFirst());
  }

  Future<void> retryFirstPage() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current is! TagNavigationInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = _loading();
    return _startFirst();
  }

  Future<void> loadMore() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current is! TagNavigationLoaded ||
        current.nextCursor == null ||
        current.pageStatus is! TagNavigationPageIdle) {
      return Future.value();
    }
    return _start(() => _loadMore(current, _generation));
  }

  Future<void> retryLoadMore() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current case TagNavigationLoaded(
      pageStatus: TagNavigationPageFailure(canRetry: true),
    )) {
      state = current.withPageStatus(const TagNavigationPageIdle());
      return loadMore();
    }
    return Future.value();
  }

  Future<void> _startFirst() =>
      _start(() => _loadFirst(_tagId, _scope, _generation));

  Future<void> _start(Future<void> Function() read) {
    if (_activeRequest case final active?) return active;
    final completion = Completer<void>();
    final future = completion.future;
    _activeRequest = future;
    unawaited(
      read().whenComplete(() {
        _activeRequest = null;
        if (_firstPagePending && ref.mounted) {
          _firstPagePending = false;
          unawaited(_startFirst());
        }
        completion.complete();
      }),
    );
    return future;
  }

  Future<void> _loadFirst(
    TagId tagId,
    TaggedEntitiesScope scope,
    int generation,
  ) async {
    final query = TaggedEntitiesQuery(tagId: tagId, scope: scope);
    final result = await _readPage(query);
    if (!_canPublish(generation)) return;
    _firstPagePending = false;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matches(value, query) || !_unique(value.items)) {
          _firstFailure(const TaggedEntitiesUnexpectedFailure());
          return;
        }
        state = TagNavigationLoaded(
          tag: value.tag,
          scope: scope,
          items: value.items,
          nextCursor: value.nextCursor,
          revision: value.revision,
        );
      case GraphResultFailure(failure: TaggedEntitiesTagNotFound()):
        _tagMissing();
      case GraphResultFailure(:final failure):
        _firstFailure(failure);
    }
  }

  Future<void> _loadMore(TagNavigationLoaded base, int generation) async {
    state = base.withPageStatus(const TagNavigationPageLoading());
    final query = TaggedEntitiesQuery(
      tagId: base.tagId,
      scope: base.scope,
      cursor: base.nextCursor,
    );
    final result = await _readPage(query);
    if (!_canPublish(generation)) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matches(value, query)) {
          _pageFailure(base, const TaggedEntitiesUnexpectedFailure());
          return;
        }
        if (value.revision.compareTo(base.revision) !=
            GraphRevisionOrder.same) {
          _pageFailure(base, const TaggedEntitiesSnapshotExpired());
          return;
        }
        if (value.tag.name != base.tag.name ||
            identical(value.nextCursor, base.nextCursor) ||
            !_unique([...base.items, ...value.items])) {
          _pageFailure(base, const TaggedEntitiesUnexpectedFailure());
          return;
        }
        state = TagNavigationLoaded(
          tag: value.tag,
          scope: base.scope,
          items: [...base.items, ...value.items],
          nextCursor: value.nextCursor,
          revision: base.revision,
        );
      case GraphResultFailure(failure: TaggedEntitiesTagNotFound()):
        _tagMissing();
      case GraphResultFailure(:final failure):
        _pageFailure(base, failure);
    }
  }

  bool _canPublish(int generation) => ref.mounted && generation == _generation;

  bool _matches(TaggedEntitiesPage page, TaggedEntitiesQuery query) =>
      page.tag.id == query.tagId &&
      page.scope == query.scope &&
      page.pageSize == query.pageSize;

  bool _unique(List<TaggedEntity> items) {
    final targets = <TagTarget>{};
    return items.every((item) => targets.add(item.target));
  }

  TagNavigationInitialLoading _loading() =>
      TagNavigationInitialLoading(tagId: _tagId, scope: _scope);

  void _tagMissing() {
    state = TagNavigationTagMissing(tagId: _tagId, scope: _scope);
  }

  void _firstFailure(TaggedEntitiesReadFailure failure) {
    state = TagNavigationInitialFailure(
      tagId: _tagId,
      scope: _scope,
      failure: failure,
    );
  }

  void _pageFailure(
    TagNavigationLoaded base,
    TaggedEntitiesReadFailure failure,
  ) {
    state = base.withPageStatus(
      TagNavigationPageFailure(failure),
      clearCursor: failure is! TaggedEntitiesUnavailableFailure,
    );
  }

  Future<TaggedEntitiesPageResult> _readPage(TaggedEntitiesQuery query) async {
    try {
      return await _reads.getTaggedEntitiesPage(query);
    } on Object {
      return const TaggedEntitiesPageError(TaggedEntitiesUnexpectedFailure());
    }
  }
}
