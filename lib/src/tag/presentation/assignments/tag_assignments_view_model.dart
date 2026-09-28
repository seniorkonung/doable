import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_assignments_page.dart';
import '../../application/tag_change.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_target.dart';
import 'tag_assignments_state.dart';

part 'tag_assignments_view_model.g.dart';

/// Узкие зависимости позволяют проверять согласование без команд записи.
final tagAssignmentsReaderProvider = Provider<TagReadContract>(
  (ref) => ref.watch(personalGraphRepositoryProvider),
);

final tagAssignmentsChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

@riverpod
final class TagAssignmentsViewModel extends _$TagAssignmentsViewModel {
  static const _maxStaleReads = 8;

  late TagTarget _target;
  late TagReadContract _reads;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  GraphRevision? _requiredRevision;
  Future<void>? _activeRequest;
  bool _refreshNeeded = false;
  int _generation = 0;
  int _staleReadAttempts = 0;

  @override
  TagAssignmentsState build(TagTarget target) {
    unawaited(_changes?.cancel());
    final active = _activeRequest;
    _target = target;
    _reads = ref.watch(tagAssignmentsReaderProvider);
    _requiredRevision = null;
    _refreshNeeded = false;
    _staleReadAttempts = 0;
    _generation++;
    final generation = _generation;
    _changes = ref.watch(tagAssignmentsChangesProvider).listen((package) {
      if (generation == _generation) _onChange(package);
    });
    ref.onDispose(() => unawaited(_changes?.cancel()));
    if (active == null) {
      unawaited(_startFirst());
    } else {
      _refreshNeeded = true;
    }
    return const TagAssignmentsInitialLoading();
  }

  /// При повторном использовании той же модели прежнее чтение теряет право
  /// публикации. Пока оно выполняется, новый запрос ждёт его завершения.
  void setTarget(TagTarget target) {
    if (_target == target) return;
    _target = target;
    _generation++;
    _staleReadAttempts = 0;
    state = const TagAssignmentsInitialLoading();
    if (_activeRequest == null) {
      unawaited(_startFirst());
    } else {
      _refreshNeeded = true;
    }
  }

  bool canActOn(TagId id) {
    final current = state;
    return current is TagAssignmentsLoaded &&
        current.target == _target &&
        current.canUseCurrentItems &&
        current.contains(id);
  }

  Future<void> retryFirstPage() {
    final current = state;
    if (current is! TagAssignmentsInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = const TagAssignmentsInitialLoading();
    _staleReadAttempts = 0;
    return _startFirst();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! TagAssignmentsLoaded ||
        current.freshness != TagAssignmentsFreshness.stale ||
        current.refreshFailure is! TagAssignmentsUnavailableFailure) {
      return Future.value();
    }
    state = current.withStatus(freshness: TagAssignmentsFreshness.refreshing);
    _staleReadAttempts = 0;
    return _startFirst();
  }

  Future<void> loadMore() {
    final current = state;
    if (current is! TagAssignmentsLoaded ||
        !current.canUseCurrentItems ||
        current.nextCursor == null ||
        current.pageStatus is! TagAssignmentsPageIdle) {
      return _activeRequest ?? Future.value();
    }
    return _start(() => _loadMore(current, _generation));
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! TagAssignmentsLoaded ||
        current.pageStatus is! TagAssignmentsPageFailure ||
        !(current.pageStatus as TagAssignmentsPageFailure).canRetry ||
        !current.canUseCurrentItems) {
      return Future.value();
    }
    state = current.withStatus(pageStatus: const TagAssignmentsPageIdle());
    return loadMore();
  }

  Future<void> _startFirst() => _start(() => _loadFirst(_target, _generation));

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

  Future<void> _loadFirst(TagTarget target, int generation) async {
    final result = await _readPage(target);
    if (!ref.mounted || generation != _generation || target != _target) return;
    if (result is GraphResultFailure && _refreshNeeded) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        final current = state;
        final precedesDisplayed =
            current is TagAssignmentsLoaded &&
            value.revision.compareTo(current.revision) ==
                GraphRevisionOrder.older;
        if (value.target != target || !_unique(value.items)) {
          _firstFailure(const TagAssignmentsUnexpectedFailure());
          return;
        }
        if (_precedesRequired(value.revision) || precedesDisplayed) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _firstFailure(const TagAssignmentsUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        state = TagAssignmentsLoaded(
          target: target,
          items: value.items,
          nextCursor: value.nextCursor,
          revision: value.revision,
        );
      case GraphResultFailure(failure: TagAssignmentsTargetNotFound()):
        _refreshNeeded = false;
        state = const TagAssignmentsTargetMissing();
      case GraphResultFailure(:final failure):
        _refreshNeeded = false;
        _firstFailure(failure);
    }
  }

  Future<void> _loadMore(TagAssignmentsLoaded base, int generation) async {
    state = base.withStatus(pageStatus: const TagAssignmentsPageLoading());
    final result = await _readPage(base.target, cursor: base.nextCursor);
    if (!ref.mounted || generation != _generation || base.target != _target) {
      return;
    }
    final current = state;
    if (current is! TagAssignmentsLoaded) return;
    if (current.freshness != TagAssignmentsFreshness.current ||
        _precedesRequired(base.revision)) {
      _refreshNeeded = true;
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (value.target != base.target) {
          state = current.withStatus(
            pageStatus: const TagAssignmentsPageFailure(
              TagAssignmentsUnexpectedFailure(),
            ),
          );
          return;
        }
        if (value.revision.compareTo(base.revision) !=
            GraphRevisionOrder.same) {
          _beginRefresh(current);
          _refreshNeeded = true;
          return;
        }
        final ids = <TagId>{for (final tag in base.items) tag.id};
        if (value.items.any((tag) => !ids.add(tag.id)) ||
            (value.items.isEmpty && value.nextCursor != null)) {
          state = current.withStatus(
            pageStatus: const TagAssignmentsPageFailure(
              TagAssignmentsUnexpectedFailure(),
            ),
          );
          return;
        }
        state = TagAssignmentsLoaded(
          target: base.target,
          items: [...base.items, ...value.items],
          nextCursor: value.nextCursor,
          revision: base.revision,
        );
      case GraphResultFailure(
        failure: TagAssignmentsSnapshotExpired() ||
            TagAssignmentsInvalidCursor(),
      ):
        _beginRefresh(current);
        _refreshNeeded = true;
      case GraphResultFailure(failure: TagAssignmentsTargetNotFound()):
        state = const TagAssignmentsTargetMissing();
      case GraphResultFailure(:final failure):
        state = current.withStatus(
          pageStatus: TagAssignmentsPageFailure(failure),
        );
    }
  }

  void _onChange(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    final required = _requiredRevision;
    if (required != null) {
      final order = package.revision.compareTo(required);
      if (order == GraphRevisionOrder.same ||
          order == GraphRevisionOrder.older) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _staleReadAttempts = 0;
    final current = state;
    final pageAlreadyIncludes =
        current is TagAssignmentsLoaded &&
        switch (package.revision.compareTo(current.revision)) {
          GraphRevisionOrder.older || GraphRevisionOrder.same => true,
          GraphRevisionOrder.newer ||
          GraphRevisionOrder.differentEpoch => false,
        };
    if (pageAlreadyIncludes) return;
    if (current is TagAssignmentsLoaded) {
      var items = current.items;
      for (final change in package.changes) {
        switch (change) {
          case TagRenamedChange(:final after):
            items = [
              for (final tag in items)
                if (tag.id == after.id) after else tag,
            ];
          case TagDeletedChange(:final tagId):
            items = [
              for (final tag in items)
                if (tag.id != tagId) tag,
            ];
          case TagAssignmentChangedChange(:final assignment, :final state)
              when assignment.target == _target &&
                  state == TagAssignmentState.absent:
            items = [
              for (final tag in items)
                if (tag.id != assignment.tagId) tag,
            ];
          case TagChange():
            break;
          case GraphChange():
            break;
        }
      }
      state = current.withStatus(
        items: items,
        clearCursor: true,
        freshness: TagAssignmentsFreshness.refreshing,
        pageStatus: const TagAssignmentsPageIdle(),
      );
    } else {
      state = const TagAssignmentsInitialLoading();
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _beginRefresh(TagAssignmentsLoaded current) {
    state = current.withStatus(
      clearCursor: true,
      freshness: TagAssignmentsFreshness.refreshing,
      pageStatus: const TagAssignmentsPageIdle(),
    );
  }

  void _firstFailure(TagAssignmentsReadFailure failure) {
    final current = state;
    if (current is TagAssignmentsLoaded) {
      state = current.withStatus(
        freshness: TagAssignmentsFreshness.stale,
        refreshFailure: failure,
        pageStatus: const TagAssignmentsPageIdle(),
      );
    } else {
      state = TagAssignmentsInitialFailure(failure);
    }
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  Future<TagAssignmentsPageResult> _readPage(
    TagTarget target, {
    TagAssignmentsCursor? cursor,
  }) async {
    try {
      return await _reads.getTagAssignmentsPage(
        TagAssignmentsQuery(target: target, cursor: cursor),
      );
    } on Object {
      return const TagAssignmentsPageError(TagAssignmentsUnexpectedFailure());
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
