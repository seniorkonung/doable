import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_catalog_state.dart';

part 'daily_choice_catalog_view_model.g.dart';

/// Согласовывает ограниченную загруженную часть с подтверждённым графом.
@riverpod
final class DailyChoiceCatalogViewModel extends _$DailyChoiceCatalogViewModel {
  static const _maxAssemblyAttempts = 8;

  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  StreamSubscription<GraphCommandCompletion>? _completions;
  var _selection = const DailyChoiceCatalogSelection();
  var _generation = 0;
  var _invalidation = 0;
  GraphRevision? _requiredRevision;
  Object? _activeRequest;

  @override
  DailyChoiceCatalogState build() {
    unawaited(_completions?.cancel());
    _activeRequest = null;
    _requiredRevision = null;
    _invalidation++;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completions = _coordinator.completions.listen((completion) {
      scheduleMicrotask(() => _onCompletion(completion));
    });
    ref.onDispose(() => unawaited(_completions?.cancel()));
    unawaited(_loadFirst(++_generation));
    return DailyChoiceCatalogInitialLoad(_selection);
  }

  void selectDate(CalendarDate? date) {
    if (_selection.date == date) return;
    _restart(_selection.withDate(date));
  }

  void selectCompletion(bool? isCompleted) {
    if (_selection.isCompleted == isCompleted) return;
    _restart(_selection.withCompletion(isCompleted));
  }

  void clearFilters() {
    if (_selection.date == null && _selection.isCompleted == null) return;
    _restart(const DailyChoiceCatalogSelection());
  }

  Future<void> retryFirstPage() {
    final current = state;
    if (current is! DailyChoiceCatalogInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = DailyChoiceCatalogInitialLoad(_selection);
    return _loadFirst(++_generation);
  }

  Future<void> loadMore() {
    final current = state;
    if (current is! DailyChoiceCatalogLoaded || current.nextCursor == null) {
      return Future.value();
    }
    if (current.freshness != DailyChoiceCatalogFreshness.current ||
        _activeRequest != null) {
      return Future.value();
    }
    if (current.needsRebase) {
      return _refresh(current, includeNextPage: true);
    }
    if (current.pageStatus is! DailyChoiceCatalogPageIdle) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! DailyChoiceCatalogLoaded ||
        current.pageStatus is! DailyChoiceCatalogPageFailure ||
        !(current.pageStatus as DailyChoiceCatalogPageFailure).canRetry) {
      return Future.value();
    }
    state = current.withStatus(pageStatus: const DailyChoiceCatalogPageIdle());
    return loadMore();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! DailyChoiceCatalogLoaded ||
        current.freshness != DailyChoiceCatalogFreshness.stale ||
        current.refreshFailure is! DailyChoiceCatalogUnavailableFailure) {
      return Future.value();
    }
    return _refresh(current, includeNextPage: false);
  }

  void _restart(DailyChoiceCatalogSelection selection) {
    _selection = selection;
    _requiredRevision = null;
    _activeRequest = null;
    final generation = ++_generation;
    state = DailyChoiceCatalogInitialLoad(selection);
    unawaited(_loadFirst(generation));
  }

  Future<void> _loadFirst(int generation) async {
    final request = Object();
    _activeRequest = request;
    for (var attempt = 0; attempt < _maxAssemblyAttempts; attempt++) {
      final result = await _readPage();
      if (!_owns(request, generation)) return;
      switch (result) {
        case GraphResultSuccess(value: final DailyChoiceCatalogFirstPage page):
          if (_precedesRequired(page.revision)) continue;
          final items = _combine(
            const [],
            page.items,
            page.nextCursor,
            page.totalCount,
          );
          if (items == null) {
            state = DailyChoiceCatalogInitialFailure(
              _selection,
              const DailyChoiceCatalogUnexpectedFailure(),
            );
          } else {
            state = _confirmed(
              items,
              page.totalCount,
              page.nextCursor,
              page.revision,
            );
          }
        case GraphResultSuccess():
          state = DailyChoiceCatalogInitialFailure(
            _selection,
            const DailyChoiceCatalogUnexpectedFailure(),
          );
        case GraphResultFailure(:final failure):
          state = DailyChoiceCatalogInitialFailure(_selection, failure);
      }
      _activeRequest = null;
      return;
    }
    _activeRequest = null;
    state = DailyChoiceCatalogInitialFailure(
      _selection,
      const DailyChoiceCatalogUnavailableFailure(),
    );
  }

  Future<void> _loadMore(DailyChoiceCatalogLoaded confirmed) async {
    final cursor = confirmed.nextCursor;
    if (cursor == null) return;
    final request = Object();
    final generation = _generation;
    final invalidation = _invalidation;
    _activeRequest = request;
    state = confirmed.withStatus(
      pageStatus: const DailyChoiceCatalogPageLoading(),
    );
    final result = await _readPage(cursor: cursor);
    if (!_owns(request, generation)) return;
    _activeRequest = null;
    if (invalidation != _invalidation) {
      await _refresh(confirmed, includeNextPage: true);
      return;
    }
    switch (result) {
      case GraphResultSuccess(
        value: final DailyChoiceCatalogContinuationPage page,
      ):
        if (page.revision.compareTo(confirmed.revision) !=
            GraphRevisionOrder.same) {
          await _refresh(confirmed, includeNextPage: true);
          return;
        }
        final combined = _combine(
          confirmed.items,
          page.items,
          page.nextCursor,
          confirmed.totalCount,
        );
        if (combined == null) {
          state = confirmed.withStatus(
            pageStatus: const DailyChoiceCatalogPageFailure(
              DailyChoiceCatalogUnexpectedFailure(),
            ),
          );
          return;
        }
        state = _confirmed(
          combined,
          confirmed.totalCount,
          page.nextCursor,
          confirmed.revision,
        );
      case GraphResultSuccess():
        state = confirmed.withStatus(
          pageStatus: const DailyChoiceCatalogPageFailure(
            DailyChoiceCatalogUnexpectedFailure(),
          ),
        );
      case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
        await _refresh(confirmed, includeNextPage: true);
      case GraphResultFailure(:final failure):
        state = confirmed.withStatus(
          pageStatus: DailyChoiceCatalogPageFailure(failure),
        );
    }
  }

  Future<void> _refresh(
    DailyChoiceCatalogLoaded base, {
    required bool includeNextPage,
  }) async {
    final request = Object();
    final generation = _generation;
    _activeRequest = request;
    state = base.withStatus(
      freshness: DailyChoiceCatalogFreshness.refreshing,
      pageStatus: const DailyChoiceCatalogPageIdle(),
      needsRebase: true,
    );
    try {
      for (var attempt = 0; attempt < _maxAssemblyAttempts; attempt++) {
        final invalidation = _invalidation;
        final assembled = await _assemble(
          base.items.length +
              (includeNextPage ? DailyChoiceCatalogQuery.defaultPageSize : 0),
          request,
          generation,
          invalidation,
        );
        if (!_owns(request, generation)) return;
        switch (assembled) {
          case _AssemblyReady(:final snapshot):
            if (invalidation != _invalidation) continue;
            state = snapshot;
            return;
          case _AssemblyInterrupted():
            continue;
          case _AssemblyFailed(:final failure):
            state = base.withStatus(
              freshness: DailyChoiceCatalogFreshness.stale,
              refreshFailure: failure,
              pageStatus: const DailyChoiceCatalogPageIdle(),
              needsRebase: true,
            );
            return;
        }
      }
      state = base.withStatus(
        freshness: DailyChoiceCatalogFreshness.stale,
        refreshFailure: const DailyChoiceCatalogUnavailableFailure(),
        pageStatus: const DailyChoiceCatalogPageIdle(),
        needsRebase: true,
      );
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  Future<_Assembly> _assemble(
    int limit,
    Object request,
    int generation,
    int invalidation,
  ) async {
    final firstResult = await _readPage();
    if (!_assemblyCurrent(request, generation, invalidation)) {
      return const _AssemblyInterrupted();
    }
    final DailyChoiceCatalogFirstPage first;
    switch (firstResult) {
      case GraphResultSuccess(value: final DailyChoiceCatalogFirstPage page):
        first = page;
      case GraphResultSuccess():
        return const _AssemblyFailed(DailyChoiceCatalogUnexpectedFailure());
      case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
        return const _AssemblyInterrupted();
      case GraphResultFailure(:final failure):
        return _AssemblyFailed(failure);
    }
    if (_precedesRequired(first.revision)) return const _AssemblyInterrupted();
    var cursor = first.nextCursor;
    final firstItems = _combine(
      const [],
      first.items,
      cursor,
      first.totalCount,
    );
    if (firstItems == null) {
      return const _AssemblyFailed(DailyChoiceCatalogUnexpectedFailure());
    }
    var items = firstItems;
    while (cursor != null && items.length < limit) {
      final result = await _readPage(cursor: cursor);
      if (!_assemblyCurrent(request, generation, invalidation)) {
        return const _AssemblyInterrupted();
      }
      switch (result) {
        case GraphResultSuccess(
          value: final DailyChoiceCatalogContinuationPage page,
        ):
          if (page.revision.compareTo(first.revision) !=
              GraphRevisionOrder.same) {
            return const _AssemblyInterrupted();
          }
          final combined = _combine(
            items,
            page.items,
            page.nextCursor,
            first.totalCount,
          );
          if (combined == null) {
            return const _AssemblyFailed(DailyChoiceCatalogUnexpectedFailure());
          }
          items = combined;
          cursor = page.nextCursor;
        case GraphResultSuccess():
          return const _AssemblyFailed(DailyChoiceCatalogUnexpectedFailure());
        case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
          return const _AssemblyInterrupted();
        case GraphResultFailure(:final failure):
          return _AssemblyFailed(failure);
      }
    }
    return _AssemblyReady(
      _confirmed(items, first.totalCount, cursor, first.revision),
    );
  }

  Future<DailyChoiceCatalogPageResult> _readPage({
    DailyChoiceCatalogCursor? cursor,
  }) async {
    try {
      return await _repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(
          date: _selection.date,
          isCompleted: _selection.isCompleted,
          cursor: cursor,
        ),
      );
    } on Object {
      return const DailyChoiceCatalogPageError(
        DailyChoiceCatalogUnexpectedFailure(),
      );
    }
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final package = completion.confirmedChange;
    if (package == null) return;
    final current = state;
    final confirmedRevision = current is DailyChoiceCatalogLoaded
        ? current.revision
        : null;
    for (final known in [?confirmedRevision, ?_requiredRevision]) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _invalidation++;
    if (current is! DailyChoiceCatalogLoaded) return;
    final affects = _affectsVisibleData(package.changes, current);
    if (affects ||
        current.freshness != DailyChoiceCatalogFreshness.current ||
        current.pageStatus is DailyChoiceCatalogPageLoading) {
      if (_activeRequest == null ||
          current.pageStatus is DailyChoiceCatalogPageLoading) {
        _activeRequest = null;
        unawaited(
          _refresh(
            current,
            includeNextPage:
                current.pageStatus is DailyChoiceCatalogPageLoading,
          ),
        );
      }
    } else {
      state = current.withStatus(needsRebase: true);
    }
  }

  bool _affectsVisibleData(
    List<GraphChange> changes,
    DailyChoiceCatalogLoaded current,
  ) {
    final ids = {for (final item in current.items) item.id};
    final participants = {
      for (final item in current.items) ...[item.source.id, item.selected.id],
    };
    for (final change in changes) {
      switch (change) {
        case DailyChoiceChange(:final before, :final after):
          if (ids.contains(before?.id) ||
              ids.contains(after?.id) ||
              _matches(before) ||
              _matches(after)) {
            return true;
          }
        case IntentionCatalogMutation(:final before, :final after):
          if (participants.contains(before?.summary.id) ||
              participants.contains(after?.summary.id)) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _matches(DailyChoice? choice) =>
      choice != null &&
      (_selection.date == null || choice.date == _selection.date) &&
      (_selection.isCompleted == null ||
          choice.isCompleted == _selection.isCompleted);

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  bool _owns(Object request, int generation) =>
      ref.mounted &&
      generation == _generation &&
      identical(request, _activeRequest);

  bool _assemblyCurrent(Object request, int generation, int invalidation) =>
      _owns(request, generation) && invalidation == _invalidation;

  List<DailyChoiceCatalogItem>? _combine(
    List<DailyChoiceCatalogItem> loaded,
    List<DailyChoiceCatalogItem> page,
    DailyChoiceCatalogCursor? cursor,
    int totalCount,
  ) {
    if (page.length > DailyChoiceCatalogQuery.defaultPageSize ||
        (page.isEmpty && cursor != null)) {
      return null;
    }
    final ids = <DailyChoiceId>{for (final item in loaded) item.id};
    final combined = [...loaded];
    for (final item in page) {
      if (!ids.add(item.id) ||
          (_selection.date != null && item.date != _selection.date) ||
          (_selection.isCompleted != null &&
              item.isCompleted != _selection.isCompleted)) {
        return null;
      }
      combined.add(item);
    }
    if (cursor == null
        ? combined.length != totalCount
        : combined.length >= totalCount) {
      return null;
    }
    return combined;
  }

  DailyChoiceCatalogLoaded _confirmed(
    List<DailyChoiceCatalogItem> items,
    int total,
    DailyChoiceCatalogCursor? cursor,
    GraphRevision revision,
  ) => items.isEmpty && total == 0
      ? DailyChoiceCatalogEmpty(selection: _selection, revision: revision)
      : DailyChoiceCatalogLoaded(
          selection: _selection,
          items: items,
          totalCount: total,
          nextCursor: cursor,
          revision: revision,
        );
}

sealed class _Assembly {
  const _Assembly();
}

final class _AssemblyReady extends _Assembly {
  const _AssemblyReady(this.snapshot);
  final DailyChoiceCatalogLoaded snapshot;
}

final class _AssemblyInterrupted extends _Assembly {
  const _AssemblyInterrupted();
}

final class _AssemblyFailed extends _Assembly {
  const _AssemblyFailed(this.failure);
  final DailyChoiceCatalogReadFailure failure;
}
