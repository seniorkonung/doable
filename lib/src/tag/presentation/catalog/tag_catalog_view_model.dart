import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_catalog.dart';
import '../../application/tag_change.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import 'tag_catalog_state.dart';

part 'tag_catalog_view_model.g.dart';

@riverpod
final class TagCatalogViewModel extends _$TagCatalogViewModel {
  static const _maxStaleReads = 8;

  late PersonalGraphRepository _repository;
  StreamSubscription<GraphCommandCompletion>? _completions;
  StreamSubscription<TagReadResult>? _selectedReads;
  TagCatalogSelection _selection = const TagCatalogNoSelection();
  GraphRevision? _selectedRevision;
  int _selectionGeneration = 0;
  GraphRevision? _requiredRevision;
  Future<void>? _activeRequest;
  bool _refreshNeeded = false;
  int _generation = 0;
  int _staleReadAttempts = 0;

  @override
  TagCatalogState build() {
    unawaited(_completions?.cancel());
    unawaited(_selectedReads?.cancel());
    _repository = ref.watch(personalGraphRepositoryProvider);
    final coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _requiredRevision = null;
    _selection = const TagCatalogNoSelection();
    _selectedRevision = null;
    _selectionGeneration++;
    _activeRequest = null;
    _refreshNeeded = false;
    _generation++;
    _staleReadAttempts = 0;
    _completions = coordinator.completions.listen(_onCompletion);
    ref.onDispose(() {
      unawaited(_completions?.cancel());
      unawaited(_selectedReads?.cancel());
    });
    unawaited(_startFirst());
    return const TagCatalogInitialLoading();
  }

  Future<void> retryFirstPage() {
    final current = state;
    if (current is! TagCatalogInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = const TagCatalogInitialLoading();
    _staleReadAttempts = 0;
    return _startFirst();
  }

  void selectTag(TagId id) {
    _selectionGeneration++;
    final generation = _selectionGeneration;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selectedRevision = null;
    _publishSelection(TagCatalogSelectionLoading(id));
    try {
      _selectedReads = _repository
          .watchTag(id)
          .listen(
            (result) => _onSelectedRead(id, generation, result),
            onError: (Object _) => _selectedReadFailed(
              id,
              generation,
              const TagReadUnexpectedFailure(),
            ),
            onDone: () {
              if (_selection is TagCatalogSelectionLoading) {
                _selectedReadFailed(
                  id,
                  generation,
                  const TagReadUnexpectedFailure(),
                );
              }
            },
          );
    } on Object {
      _selectedReadFailed(id, generation, const TagReadUnexpectedFailure());
    }
  }

  void retrySelectedTag() {
    final selection = _selection;
    if (selection is TagCatalogSelectionFailure && selection.canRetry) {
      selectTag(selection.id);
    }
  }

  bool canActOn(TagId id) {
    final current = state;
    if (current is! TagCatalogLoaded || !current.canUseCurrentItems) {
      return false;
    }
    final selection = _selection;
    if (selection.id == id) {
      return selection is TagCatalogSelectionReady;
    }
    return current.items.any((tag) => tag.id == id);
  }

  void _onSelectedRead(TagId id, int generation, TagReadResult result) {
    if (!ref.mounted || generation != _selectionGeneration) return;
    switch (result) {
      case TagReadSuccess(:final value):
        final required = _selectedRevision;
        if (required != null &&
            value.revision.compareTo(required) != GraphRevisionOrder.same &&
            value.revision.compareTo(required) != GraphRevisionOrder.newer) {
          return;
        }
        final tag = value.value;
        if (tag == null) {
          _confirmedMissing(id, value.revision);
        } else if (tag.id != id) {
          _selectedReadFailed(id, generation, const TagReadCorruptionFailure());
        } else {
          _selectedRevision = value.revision;
          _publishSelection(TagCatalogSelectionReady(tag));
        }
      case TagReadError(:final failure):
        _selectedReadFailed(id, generation, failure);
    }
  }

  void _selectedReadFailed(TagId id, int generation, TagReadFailure failure) {
    if (!ref.mounted || generation != _selectionGeneration) return;
    _publishSelection(TagCatalogSelectionFailure(id, failure));
  }

  void _confirmedMissing(TagId id, GraphRevision revision) {
    final current = state;
    final pageOrder = current is TagCatalogLoaded
        ? current.revision.compareTo(revision)
        : null;
    if (current is TagCatalogLoaded &&
        pageOrder == GraphRevisionOrder.newer &&
        current.items.any((tag) => tag.id == id)) {
      return;
    }
    final required = _requiredRevision;
    if (required == null ||
        revision.compareTo(required) == GraphRevisionOrder.newer ||
        revision.compareTo(required) == GraphRevisionOrder.differentEpoch) {
      _requiredRevision = revision;
    }
    _staleReadAttempts = 0;
    _selectionGeneration++;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selectedRevision = null;
    _selection = const TagCatalogNoSelection();
    if (current is TagCatalogLoaded) {
      final items = [
        for (final tag in current.items)
          if (tag.id != id) tag,
      ];
      final pageIsCurrent =
          (pageOrder == GraphRevisionOrder.same ||
              pageOrder == GraphRevisionOrder.newer) &&
          items.length == current.items.length;
      state = current.withStatus(
        items: items,
        selection: _selection,
        freshness: pageIsCurrent
            ? current.freshness
            : TagCatalogFreshness.refreshing,
        pageStatus: pageIsCurrent
            ? current.pageStatus
            : const TagCatalogPageIdle(),
      );
      if (pageIsCurrent) return;
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _publishSelection(TagCatalogSelection selection) {
    _selection = selection;
    if (state case TagCatalogLoaded loaded) {
      state = loaded.withSelection(selection);
    }
  }

  Future<void> loadMore() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        !current.canUseCurrentItems ||
        current.nextCursor == null ||
        current.pageStatus is! TagCatalogPageIdle) {
      return _activeRequest ?? Future.value();
    }
    return _start(() => _loadMore(current, _generation));
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        current.pageStatus is! TagCatalogPageFailure ||
        !(current.pageStatus as TagCatalogPageFailure).canRetry ||
        !current.canUseCurrentItems) {
      return Future.value();
    }
    state = current.withStatus(pageStatus: const TagCatalogPageIdle());
    return loadMore();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        current.freshness != TagCatalogFreshness.stale ||
        current.refreshFailure is! TagCatalogUnavailableFailure) {
      return Future.value();
    }
    state = current.withStatus(freshness: TagCatalogFreshness.refreshing);
    _staleReadAttempts = 0;
    return _startFirst();
  }

  Future<void> _startFirst() => _start(() => _loadFirst(_generation));

  Future<void> _start(Future<void> Function() read) {
    final active = _activeRequest;
    if (active != null) return active;
    final future = read();
    _activeRequest = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_activeRequest, future)) return;
        _activeRequest = null;
        if (_refreshNeeded && ref.mounted) {
          _refreshNeeded = false;
          unawaited(_startFirst());
        }
      }),
    );
    return future;
  }

  Future<void> _loadFirst(int generation) async {
    final result = await _readPage();
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        final current = state;
        final precedesDisplayed =
            current is TagCatalogLoaded &&
            value.revision.compareTo(current.revision) ==
                GraphRevisionOrder.older;
        if (_precedesRequired(value.revision) || precedesDisplayed) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _firstFailure(const TagCatalogUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        if (!_unique(value.items)) {
          _firstFailure(const TagCatalogUnexpectedFailure());
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        state = TagCatalogLoaded(
          items: value.items,
          nextCursor: value.nextCursor,
          revision: value.revision,
          selection: _selection,
        );
      case GraphResultFailure(:final failure):
        _refreshNeeded = false;
        _firstFailure(failure);
    }
  }

  Future<void> _loadMore(TagCatalogLoaded base, int generation) async {
    state = base.withStatus(pageStatus: const TagCatalogPageLoading());
    final result = await _readPage(cursor: base.nextCursor);
    if (!ref.mounted || generation != _generation) return;
    final current = state;
    if (current is! TagCatalogLoaded) return;
    if (current.freshness != TagCatalogFreshness.current ||
        _precedesRequired(base.revision)) {
      _refreshNeeded = true;
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (value.revision.compareTo(base.revision) !=
            GraphRevisionOrder.same) {
          _beginRefresh(current);
          _refreshNeeded = true;
          return;
        }
        final ids = <TagId>{for (final item in base.items) item.id};
        if (!ids.addAllChecked(value.items) ||
            (value.items.isEmpty && value.nextCursor != null)) {
          state = current.withStatus(
            pageStatus: const TagCatalogPageFailure(
              TagCatalogUnexpectedFailure(),
            ),
          );
          return;
        }
        state = TagCatalogLoaded(
          items: [...base.items, ...value.items],
          nextCursor: value.nextCursor,
          revision: base.revision,
          selection: _selection,
        );
      case GraphResultFailure(failure: TagCatalogSnapshotExpired()):
        _beginRefresh(current);
        _refreshNeeded = true;
      case GraphResultFailure(failure: TagCatalogInvalidCursor()):
        _beginRefresh(current);
        _refreshNeeded = true;
      case GraphResultFailure(:final failure):
        state = current.withStatus(pageStatus: TagCatalogPageFailure(failure));
    }
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final package = completion.confirmedChange;
    if (package == null) return;
    if (_requiredRevision case final required?) {
      final order = package.revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _staleReadAttempts = 0;
    final current = state;
    final pageAlreadyIncludes =
        current is TagCatalogLoaded &&
        switch (package.revision.compareTo(current.revision)) {
          GraphRevisionOrder.older || GraphRevisionOrder.same => true,
          GraphRevisionOrder.newer ||
          GraphRevisionOrder.differentEpoch => false,
        };
    final canUpdateSelection =
        _selectedRevision == null ||
        switch (package.revision.compareTo(_selectedRevision!)) {
          GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => true,
          GraphRevisionOrder.older || GraphRevisionOrder.same => false,
        };
    var items = current is TagCatalogLoaded ? current.items : <Tag>[];
    for (final change in package.changes) {
      switch (change) {
        case TagRenamedChange(:final after):
          if (!pageAlreadyIncludes) {
            items = [
              for (final tag in items)
                if (tag.id == after.id) after else tag,
            ];
          }
          if (canUpdateSelection && _selection.id == after.id) {
            var selected = after;
            GraphRevision revision = package.revision;
            if (pageAlreadyIncludes) {
              for (final tag in current.items) {
                if (tag.id == after.id) {
                  selected = tag;
                  revision = current.revision;
                  break;
                }
              }
            }
            _selection = TagCatalogSelectionReady(selected);
            _selectedRevision = revision;
          }
        case TagDeletedChange(:final tagId):
          if (!pageAlreadyIncludes) {
            items = [
              for (final tag in items)
                if (tag.id != tagId) tag,
            ];
          }
          if (canUpdateSelection && _selection.id == tagId) {
            _selectionGeneration++;
            unawaited(_selectedReads?.cancel());
            _selectedReads = null;
            _selectedRevision = null;
            _selection = const TagCatalogNoSelection();
          }
        case TagChange():
          break;
        case GraphChange():
          break;
      }
    }
    if (current is TagCatalogLoaded) {
      if (pageAlreadyIncludes) {
        if (!identical(current.selection, _selection)) {
          state = current.withSelection(_selection);
        }
        return;
      }
      state = current.withStatus(
        items: items,
        selection: _selection,
        freshness: TagCatalogFreshness.refreshing,
        pageStatus: const TagCatalogPageIdle(),
      );
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _beginRefresh(TagCatalogLoaded current) {
    state = current.withStatus(
      freshness: TagCatalogFreshness.refreshing,
      pageStatus: const TagCatalogPageIdle(),
    );
  }

  void _firstFailure(TagCatalogReadFailure failure) {
    final current = state;
    if (current is TagCatalogLoaded) {
      state = current.withStatus(
        freshness: TagCatalogFreshness.stale,
        refreshFailure: failure,
        pageStatus: const TagCatalogPageIdle(),
      );
    } else {
      state = TagCatalogInitialFailure(failure);
    }
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  Future<TagCatalogPageResult> _readPage({TagCatalogCursor? cursor}) async {
    try {
      return await _repository.getTagCatalogPage(
        TagCatalogQuery(cursor: cursor),
      );
    } on Object {
      return const TagCatalogPageError(TagCatalogUnexpectedFailure());
    }
  }

  bool _unique(List<Tag> tags) {
    final ids = <TagId>{};
    for (final tag in tags) {
      if (!ids.add(tag.id)) return false;
    }
    return true;
  }
}

extension on Set<TagId> {
  bool addAllChecked(List<Tag> tags) {
    for (final tag in tags) {
      if (!add(tag.id)) return false;
    }
    return true;
  }
}
