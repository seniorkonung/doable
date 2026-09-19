import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_result.dart';
import '../../domain/intention_id.dart';
import 'catalog_paging_policy.dart';
import 'intention_catalog_state.dart';

part 'intention_catalog_view_model.g.dart';

@riverpod
final class IntentionCatalogViewModel extends _$IntentionCatalogViewModel {
  IntentionScope _scope = IntentionCatalogSelection.initial.scope;
  String _titleFilterText = IntentionCatalogSelection.initial.titleFilterText;
  IntentionCatalogOrder _order = IntentionCatalogSelection.initial.order;
  IntentionCatalogFilterValidationFailure? _filterValidationFailure;
  CatalogPagingPolicy _policy = CatalogPagingPolicy.production;
  Timer? _filterTimer;
  bool _isDebouncingFilter = false;
  int _queryGeneration = 0;
  Object? _activePageRequest;
  bool _isLoadingFirstPage = false;
  final _mutationPackagesBeforeFirstPage = <List<IntentionCatalogMutation>>[];
  IntentionSummary? _cursorBoundary;
  _PendingCatalogContinuation? _pendingContinuation;

  IntentionCatalogSelection get selection => IntentionCatalogSelection(
    scope: _scope,
    titleFilterText: _titleFilterText,
    order: _order,
    filterValidationFailure: _filterValidationFailure,
  );

  @override
  Future<IntentionCatalogState> build() {
    _invalidatePageRequest();
    _isLoadingFirstPage = false;
    _mutationPackagesBeforeFirstPage.clear();
    _cursorBoundary = null;
    _pendingContinuation = null;
    final repository = ref.watch(personalGraphRepositoryProvider);
    _policy = ref.watch(catalogPagingPolicyProvider);
    final completionSubscription = ref
        .watch(graphCommandCoordinatorProvider.notifier)
        .intentionCompletions
        .listen(_handleCompletion);
    ref.onDispose(() => unawaited(completionSubscription.cancel()));
    ref.onCancel(() => _filterTimer?.cancel());

    if (_isDebouncingFilter) {
      return Future.value(IntentionCatalogDebouncing(selection: selection));
    }

    late final IntentionCatalogQuery query;
    try {
      query = IntentionCatalogQuery(
        scope: _scope,
        titleFilter: _titleFilterText,
        order: _order,
        pageSize: _policy.pageSize,
      );
    } on IntentionCatalogQueryValidationException catch (error) {
      _filterValidationFailure = switch (error.failure) {
        IntentionCatalogQueryValidationFailure.invalidUnicodeRepertoire =>
          IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
        IntentionCatalogQueryValidationFailure.titleFilterTooLong =>
          IntentionCatalogFilterValidationFailure.tooLong,
        IntentionCatalogQueryValidationFailure.pageSizeOutOfRange =>
          throw StateError('CatalogPagingPolicy пропустила неверный pageSize.'),
      };
      return Future.value(IntentionCatalogInvalidFilter(selection: selection));
    }

    _filterValidationFailure = null;
    final currentSelection = selection;
    _isLoadingFirstPage = true;
    return _loadFirstPage(
      repository,
      query,
      currentSelection,
      _queryGeneration,
    );
  }

  void changeScope(IntentionScope scope) {
    if (_scope == scope) {
      return;
    }
    _scope = scope;
    _applyParametersImmediately();
  }

  void changeOrder(IntentionCatalogOrder order) {
    if (_order == order) {
      return;
    }
    _order = order;
    _applyParametersImmediately();
  }

  void changeTitleFilter(String value) {
    if (_titleFilterText == value) {
      return;
    }
    _titleFilterText = value;
    _filterValidationFailure = null;
    _isDebouncingFilter = true;
    _invalidatePageRequest();
    _filterTimer?.cancel();
    ref.invalidateSelf();
    _filterTimer = Timer(_policy.filterDebounce, () {
      if (!ref.mounted) {
        return;
      }
      _isDebouncingFilter = false;
      ref.invalidateSelf();
    });
  }

  Future<void> retry() async {
    final current = state.value;
    if (current is! IntentionCatalogUnavailable) {
      return;
    }

    state = const AsyncLoading();
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  Future<void> loadNextPageIfNeeded({required int visibleIndex}) {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.nextCursor == null ||
        current.continuation is! IntentionCatalogContinuationIdle ||
        visibleIndex < 0 ||
        current.items.length - visibleIndex - 1 > _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadNextPage(current);
  }

  Future<void> retryNextPage() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogContinuationUnavailable) {
      return Future.value();
    }
    return _loadNextPage(current);
  }

  Future<void> recoverFromInvalidCursor() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogContinuationValidation) {
      return Future.value();
    }
    return _recoverFirstPage(current);
  }

  Future<void> retryRecovery() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogRecoveryUnavailable) {
      return Future.value();
    }
    return _recoverFirstPage(current);
  }

  Future<IntentionCatalogState> _loadFirstPage(
    PersonalGraphRepository repository,
    IntentionCatalogQuery query,
    IntentionCatalogSelection selection,
    int generation,
  ) async {
    try {
      final result = await repository.getCatalogPage(query);
      final mapped = switch (result) {
        ResultSuccess(:final value) => _mapPage(selection, query, value),
        ResultFailure(:final failure) => _mapFailure(selection, query, failure),
      };
      if (_queryGeneration != generation) {
        return mapped;
      }
      _isLoadingFirstPage = false;
      if (mapped case final IntentionCatalogConfirmedState confirmed) {
        _cursorBoundary = _boundaryFromFirstPage(confirmed);
        var reconciled = confirmed;
        for (final mutations in _mutationPackagesBeforeFirstPage) {
          final next = _applyMutationPackage(reconciled, mutations);
          if (next == null) {
            _mutationPackagesBeforeFirstPage.clear();
            scheduleMicrotask(_restartFromFirstPage);
            return confirmed;
          }
          reconciled = next;
        }
        _mutationPackagesBeforeFirstPage.clear();
        return reconciled;
      }
      _mutationPackagesBeforeFirstPage.clear();
      return mapped;
    } on Object {
      if (_queryGeneration == generation) {
        _isLoadingFirstPage = false;
        _mutationPackagesBeforeFirstPage.clear();
      }
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
  }

  IntentionSummary? _boundaryFromFirstPage(
    IntentionCatalogConfirmedState confirmed,
  ) {
    if (confirmed.nextCursor == null || confirmed is! IntentionCatalogLoaded) {
      return null;
    }
    return confirmed.items.isEmpty ? null : confirmed.items.last;
  }

  IntentionCatalogState _mapPage(
    IntentionCatalogSelection selection,
    IntentionCatalogQuery query,
    IntentionCatalogPage page,
  ) {
    if (page is! IntentionCatalogFirstPage ||
        page.items.length > query.pageSize) {
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
    if (page.items.isEmpty) {
      if (page.totalCount != 0 || page.nextCursor != null) {
        return IntentionCatalogUnexpected(selection: selection, query: query);
      }
      return IntentionCatalogEmpty(
        selection: selection,
        query: query,
        revision: page.revision,
      );
    }
    if (page.totalCount == page.items.length && page.nextCursor != null ||
        page.totalCount > page.items.length && page.nextCursor == null) {
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
    return IntentionCatalogLoaded(
      selection: selection,
      query: query,
      items: page.items,
      totalCount: page.totalCount,
      nextCursor: page.nextCursor,
      revision: page.revision,
    );
  }

  IntentionCatalogState _mapFailure(
    IntentionCatalogSelection selection,
    IntentionCatalogQuery query,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() => IntentionCatalogUnavailable(
      selection: selection,
      query: query,
    ),
    IntentionCorruptionFailure() => IntentionCatalogCorruption(
      selection: selection,
      query: query,
    ),
    IntentionUnexpectedFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionValidationFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionNotFoundFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionConflictFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionHasBlockingRelationsFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
  };

  Future<void> _loadNextPage(IntentionCatalogLoaded confirmed) async {
    if (_activePageRequest != null || confirmed.nextCursor == null) {
      return;
    }
    final request = Object();
    final generation = _queryGeneration;
    _activePageRequest = request;
    state = AsyncData(
      _withContinuation(confirmed, const IntentionCatalogContinuationLoading()),
    );

    try {
      final repository = ref.read(personalGraphRepositoryProvider);
      final query = _continuationQuery(confirmed);
      while (_ownsRequest(request, generation)) {
        final result = await repository.getCatalogPage(query);
        if (!_ownsRequest(request, generation)) {
          return;
        }
        final current = state.value;
        if (current is! IntentionCatalogLoaded) {
          return;
        }
        switch (result) {
          case ResultSuccess(:final value):
            if (_handleContinuationPage(current, value, generation)) {
              continue;
            }
          case ResultFailure(:final failure):
            state = AsyncData(
              _withContinuation(current, _continuationFailure(failure)),
            );
        }
        return;
      }
    } on Object {
      if (_ownsRequest(request, generation)) {
        final current = state.value;
        if (current is IntentionCatalogLoaded) {
          state = AsyncData(
            _withContinuation(
              current,
              const IntentionCatalogContinuationUnexpected(),
            ),
          );
        }
      }
    } finally {
      if (identical(_activePageRequest, request)) {
        _activePageRequest = null;
      }
    }
  }

  Future<void> _recoverFirstPage(IntentionCatalogLoaded confirmed) async {
    _invalidatePageRequest();
    final request = Object();
    final generation = _queryGeneration;
    _activePageRequest = request;
    state = AsyncData(
      _withContinuation(
        confirmed,
        const IntentionCatalogContinuationRecovering(),
      ),
    );

    try {
      final repository = ref.read(personalGraphRepositoryProvider);
      final query = _firstPageQuery(confirmed);
      while (_ownsRequest(request, generation)) {
        final result = await repository.getCatalogPage(query);
        if (!_ownsRequest(request, generation)) {
          return;
        }
        final current = state.value;
        switch (result) {
          case ResultSuccess(:final value):
            final mapped = _mapPage(confirmed.selection, query, value);
            if (mapped case final IntentionCatalogConfirmedState page) {
              if (current
                  case final IntentionCatalogConfirmedState currentConfirmed) {
                if (page.revision.compareTo(currentConfirmed.revision) ==
                    GraphRevisionOrder.older) {
                  continue;
                }
              }
              _cursorBoundary = _boundaryFromFirstPage(page);
            }
            state = AsyncData(mapped);
          case ResultFailure(:final failure):
            if (current is IntentionCatalogLoaded) {
              state = AsyncData(
                _withContinuation(current, _recoveryFailure(failure)),
              );
            }
        }
        return;
      }
    } on Object {
      if (_ownsRequest(request, generation)) {
        final current = state.value;
        if (current is IntentionCatalogLoaded) {
          state = AsyncData(
            _withContinuation(
              current,
              const IntentionCatalogRecoveryUnexpected(),
            ),
          );
        }
      }
    } finally {
      if (identical(_activePageRequest, request)) {
        _activePageRequest = null;
      }
    }
  }

  IntentionCatalogState _appendPage(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogPage page,
  ) {
    if (page is! IntentionCatalogContinuationPage ||
        page.items.length > confirmed.query.pageSize ||
        page.nextCursor != null && page.items.isEmpty) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }

    final knownIds = confirmed.items.map((item) => item.id).toSet();
    final combined = [...confirmed.items];
    for (final item in page.items) {
      if (knownIds.add(item.id)) {
        combined.add(item);
      }
    }
    if (combined.length > confirmed.totalCount) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }
    if (page.nextCursor == null && combined.length != confirmed.totalCount ||
        page.nextCursor != null && combined.length >= confirmed.totalCount) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }
    combined.sort(confirmed.query.compare);
    _cursorBoundary = page.nextCursor == null ? null : page.items.last;
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: combined,
      totalCount: confirmed.totalCount,
      nextCursor: page.nextCursor,
      revision: confirmed.revision,
    );
  }

  bool _handleContinuationPage(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogPage page,
    int generation,
  ) {
    if (page is! IntentionCatalogContinuationPage ||
        page.items.length > confirmed.query.pageSize) {
      state = AsyncData(
        _withContinuation(
          confirmed,
          const IntentionCatalogContinuationUnexpected(),
        ),
      );
      return false;
    }

    switch (page.revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.older:
        return true;
      case GraphRevisionOrder.same:
        state = AsyncData(_appendPage(confirmed, page));
        return false;
      case GraphRevisionOrder.newer:
        _pendingContinuation = _PendingCatalogContinuation(
          generation: generation,
          page: page,
        );
        state = AsyncData(
          _withContinuation(
            confirmed,
            const IntentionCatalogContinuationLoading(),
          ),
        );
        return false;
      case GraphRevisionOrder.differentEpoch:
        _restartFromFirstPage();
        return false;
    }
  }

  IntentionCatalogContinuationState _continuationFailure(
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() =>
      const IntentionCatalogContinuationUnavailable(),
    IntentionCorruptionFailure() =>
      const IntentionCatalogContinuationCorruption(),
    IntentionValidationFailure() =>
      const IntentionCatalogContinuationValidation(),
    IntentionUnexpectedFailure() ||
    IntentionNotFoundFailure() ||
    IntentionConflictFailure() ||
    IntentionHasBlockingRelationsFailure() =>
      const IntentionCatalogContinuationUnexpected(),
  };

  IntentionCatalogContinuationState _recoveryFailure(
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() =>
      const IntentionCatalogRecoveryUnavailable(),
    IntentionCorruptionFailure() => const IntentionCatalogRecoveryCorruption(),
    IntentionValidationFailure() ||
    IntentionUnexpectedFailure() ||
    IntentionNotFoundFailure() ||
    IntentionConflictFailure() ||
    IntentionHasBlockingRelationsFailure() =>
      const IntentionCatalogRecoveryUnexpected(),
  };

  IntentionCatalogQuery _continuationQuery(IntentionCatalogLoaded confirmed) =>
      IntentionCatalogQuery(
        scope: confirmed.query.scope,
        titleFilter: confirmed.query.titleFilter?.map((value) => value),
        order: confirmed.query.order,
        pageSize: confirmed.query.pageSize,
        cursor: confirmed.nextCursor,
      );

  IntentionCatalogQuery _firstPageQuery(IntentionCatalogLoaded confirmed) =>
      IntentionCatalogQuery(
        scope: confirmed.query.scope,
        titleFilter: confirmed.query.titleFilter?.map((value) => value),
        order: confirmed.query.order,
        pageSize: confirmed.query.pageSize,
      );

  IntentionCatalogLoaded _withContinuation(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogContinuationState continuation,
  ) => IntentionCatalogLoaded(
    selection: confirmed.selection,
    query: confirmed.query,
    items: confirmed.items,
    totalCount: confirmed.totalCount,
    nextCursor: confirmed.nextCursor,
    revision: confirmed.revision,
    continuation: continuation,
  );

  bool _ownsRequest(Object request, int generation) =>
      ref.mounted &&
      _queryGeneration == generation &&
      identical(_activePageRequest, request);

  void _invalidatePageRequest() {
    _queryGeneration += 1;
    _activePageRequest = null;
  }

  void _applyParametersImmediately() {
    _filterTimer?.cancel();
    _isDebouncingFilter = false;
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  void _handleCompletion(IntentionCommandCompletion completion) {
    switch (completion.confirmedResult) {
      case ResultSuccess(:final value):
        _reconcileMutations(
          value.changes.whereType<IntentionCatalogMutation>().toList(
            growable: false,
          ),
        );
      case ResultFailure():
        return;
    }
  }

  void _reconcileMutations(List<IntentionCatalogMutation> mutations) {
    if (!ref.mounted || mutations.isEmpty) {
      return;
    }
    final current = state.value;
    if (_isLoadingFirstPage || current is! IntentionCatalogConfirmedState) {
      _mutationPackagesBeforeFirstPage.add(mutations);
      return;
    }

    final reconciled = _applyMutationPackage(current, mutations);
    if (reconciled == null) {
      _restartFromFirstPage();
      return;
    }
    if (!identical(reconciled, current)) {
      state = AsyncData(reconciled);
    }
    _resolvePendingContinuation(reconciled);
  }

  void _resolvePendingContinuation(IntentionCatalogConfirmedState confirmed) {
    final pending = _pendingContinuation;
    if (pending == null || pending.generation != _queryGeneration) {
      return;
    }
    if (confirmed is! IntentionCatalogLoaded) {
      _pendingContinuation = null;
      return;
    }

    switch (pending.page.revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.newer:
        return;
      case GraphRevisionOrder.same:
        _pendingContinuation = null;
        state = AsyncData(_appendPage(confirmed, pending.page));
      case GraphRevisionOrder.older:
        _pendingContinuation = null;
        scheduleMicrotask(_retryStalePendingContinuation);
      case GraphRevisionOrder.differentEpoch:
        _pendingContinuation = null;
        _restartFromFirstPage();
    }
  }

  void _retryStalePendingContinuation() {
    if (!ref.mounted || _activePageRequest != null) {
      return;
    }
    final current = state.value;
    if (current is IntentionCatalogLoaded &&
        current.nextCursor != null &&
        current.continuation is IntentionCatalogContinuationLoading) {
      unawaited(_loadNextPage(current));
    }
  }

  void _restartFromFirstPage() {
    if (!ref.mounted) {
      return;
    }
    _pendingContinuation = null;
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  IntentionCatalogConfirmedState? _applyMutationPackage(
    IntentionCatalogConfirmedState confirmed,
    List<IntentionCatalogMutation> mutations,
  ) {
    final revision = mutations.first.revision;
    if (mutations.any(
      (mutation) =>
          mutation.revision.compareTo(revision) != GraphRevisionOrder.same,
    )) {
      return null;
    }

    switch (revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.older || GraphRevisionOrder.same:
        return confirmed;
      case GraphRevisionOrder.differentEpoch:
        return null;
      case GraphRevisionOrder.newer:
        break;
    }

    var reconciled = confirmed;
    final changedIds = <IntentionId>{};
    for (final mutation in mutations) {
      final changedId =
          mutation.after?.summary.id ?? mutation.before?.summary.id;
      if (changedId == null || !changedIds.add(changedId)) {
        return null;
      }
      final next = _applyMutationContent(reconciled, mutation);
      if (next == null) {
        return null;
      }
      reconciled = next;
    }
    return reconciled;
  }

  IntentionCatalogConfirmedState? _applyMutationContent(
    IntentionCatalogConfirmedState confirmed,
    IntentionCatalogMutation mutation,
  ) {
    final beforeMatches = mutation.before?.matches(confirmed.query) ?? false;
    final afterMatches = mutation.after?.matches(confirmed.query) ?? false;
    final totalCount =
        confirmed.totalCount + (afterMatches ? 1 : 0) - (beforeMatches ? 1 : 0);
    if (totalCount < 0) {
      return null;
    }

    final items = switch (confirmed) {
      IntentionCatalogLoaded(:final items) => [...items],
      IntentionCatalogEmpty() => <IntentionSummary>[],
    };
    final changedId = mutation.after?.summary.id ?? mutation.before!.summary.id;
    items.removeWhere((item) => item.id == changedId);

    final after = mutation.after;
    if (afterMatches &&
        after != null &&
        _belongsToLoadedPrefix(confirmed, after.summary)) {
      items.add(after.summary);
      items.sort(confirmed.query.compare);
    }

    if (totalCount == 0 && items.isEmpty && confirmed.nextCursor == null) {
      return IntentionCatalogEmpty(
        selection: confirmed.selection,
        query: confirmed.query,
        revision: mutation.revision,
      );
    }
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: items,
      totalCount: totalCount,
      nextCursor: confirmed.nextCursor,
      revision: mutation.revision,
      continuation: switch (confirmed) {
        IntentionCatalogLoaded(:final continuation) => continuation,
        IntentionCatalogEmpty() => const IntentionCatalogContinuationIdle(),
      },
    );
  }

  bool _belongsToLoadedPrefix(
    IntentionCatalogConfirmedState confirmed,
    IntentionSummary summary,
  ) {
    if (confirmed.nextCursor == null) {
      return true;
    }
    final boundary = _cursorBoundary;
    return boundary != null && confirmed.query.compare(summary, boundary) <= 0;
  }
}

final class _PendingCatalogContinuation {
  const _PendingCatalogContinuation({
    required this.generation,
    required this.page,
  });

  final int generation;
  final IntentionCatalogContinuationPage page;
}
