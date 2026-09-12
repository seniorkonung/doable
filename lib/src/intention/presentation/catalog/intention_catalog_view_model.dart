import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../operation/intention_command_coordinator.dart';
import '../operation/intention_repository_provider.dart';
import 'catalog_paging_policy.dart';
import 'intention_catalog_state.dart';

part 'intention_catalog_view_model.g.dart';

@riverpod
final class IntentionCatalogViewModel extends _$IntentionCatalogViewModel {
  final _presentationListeners =
      <void Function(IntentionCatalogPresentationEvent)>{};
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
  final _mutationsBeforeFirstPage = <IntentionCatalogMutation>[];
  IntentionSummary? _cursorBoundary;
  _PendingCatalogContinuation? _pendingContinuation;

  IntentionCatalogSelection get selection => IntentionCatalogSelection(
    scope: _scope,
    titleFilterText: _titleFilterText,
    order: _order,
    filterValidationFailure: _filterValidationFailure,
  );

  void addPresentationListener(
    void Function(IntentionCatalogPresentationEvent) listener,
  ) {
    _presentationListeners.add(listener);
  }

  void removePresentationListener(
    void Function(IntentionCatalogPresentationEvent) listener,
  ) {
    _presentationListeners.remove(listener);
  }

  @override
  Future<IntentionCatalogState> build() {
    _invalidatePageRequest();
    _isLoadingFirstPage = false;
    _mutationsBeforeFirstPage.clear();
    _cursorBoundary = null;
    _pendingContinuation = null;
    final repository = ref.watch(intentionRepositoryProvider);
    _policy = ref.watch(catalogPagingPolicyProvider);
    final completionSubscription = ref
        .watch(intentionCommandCoordinatorProvider.notifier)
        .completions
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
    IntentionRepository repository,
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
        for (final mutation in _mutationsBeforeFirstPage) {
          final next = _applyMutation(reconciled, mutation);
          if (next == null) {
            _mutationsBeforeFirstPage.clear();
            scheduleMicrotask(_restartFromFirstPage);
            return confirmed;
          }
          reconciled = next;
        }
        _mutationsBeforeFirstPage.clear();
        return reconciled;
      }
      _mutationsBeforeFirstPage.clear();
      return mapped;
    } on Object {
      if (_queryGeneration == generation) {
        _isLoadingFirstPage = false;
        _mutationsBeforeFirstPage.clear();
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
      final repository = ref.read(intentionRepositoryProvider);
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
      final repository = ref.read(intentionRepositoryProvider);
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
                    IntentionCatalogRevisionOrder.older) {
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
      case IntentionCatalogRevisionOrder.older:
        return true;
      case IntentionCatalogRevisionOrder.same:
        state = AsyncData(_appendPage(confirmed, page));
        return false;
      case IntentionCatalogRevisionOrder.newer:
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
      case IntentionCatalogRevisionOrder.differentEpoch:
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
    IntentionConflictFailure() =>
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
    IntentionConflictFailure() => const IntentionCatalogRecoveryUnexpected(),
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
    final coordinator = ref.read(intentionCommandCoordinatorProvider.notifier);
    unawaited(
      _publishFallback(
        coordinator.claimCatalogFallback(completion.token),
        coordinator,
      ),
    );

    switch (completion.result) {
      case ResultSuccess(:final value):
        _reconcileMutation(value.catalogMutation);
      case ResultFailure():
        return;
    }
  }

  void _reconcileMutation(IntentionCatalogMutation mutation) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (_isLoadingFirstPage || current is! IntentionCatalogConfirmedState) {
      _mutationsBeforeFirstPage.add(mutation);
      return;
    }

    final reconciled = _applyMutation(current, mutation);
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
      case IntentionCatalogRevisionOrder.newer:
        return;
      case IntentionCatalogRevisionOrder.same:
        _pendingContinuation = null;
        state = AsyncData(_appendPage(confirmed, pending.page));
      case IntentionCatalogRevisionOrder.older:
        _pendingContinuation = null;
        scheduleMicrotask(_retryStalePendingContinuation);
      case IntentionCatalogRevisionOrder.differentEpoch:
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

  IntentionCatalogConfirmedState? _applyMutation(
    IntentionCatalogConfirmedState confirmed,
    IntentionCatalogMutation mutation,
  ) {
    switch (mutation.revision.compareTo(confirmed.revision)) {
      case IntentionCatalogRevisionOrder.older ||
          IntentionCatalogRevisionOrder.same:
        return confirmed;
      case IntentionCatalogRevisionOrder.differentEpoch:
        return null;
      case IntentionCatalogRevisionOrder.newer:
        break;
    }

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
    final changedId = mutation.after?.summary.id ?? mutation.before?.summary.id;
    if (changedId == null) {
      return null;
    }
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

  Future<void> _publishFallback(
    Future<IntentionCatalogFallbackPresentationClaim?> pendingClaim,
    IntentionCommandCoordinator coordinator,
  ) async {
    final claim = await pendingClaim;
    if (claim == null) {
      return;
    }
    if (!ref.mounted) {
      coordinator.confirmPresentation(claim);
      return;
    }

    final event = switch (claim.completion.kind) {
      IntentionCommandKind.create => IntentionCatalogCreatePresentationEvent(
        _createOutcome(claim.completion.result),
      ),
      IntentionCommandKind.update => IntentionCatalogUpdatePresentationEvent(
        _updateOutcome(claim.completion.result),
      ),
      IntentionCommandKind.enableReadiness ||
      IntentionCommandKind.disableReadiness ||
      IntentionCommandKind.archive ||
      IntentionCommandKind.restore => IntentionCatalogUpdatePresentationEvent(
        _updateOutcome(claim.completion.result),
      ),
      IntentionCommandKind.delete => IntentionCatalogDeletePresentationEvent(
        _deleteOutcome(claim.completion.result),
      ),
    };
    try {
      for (final listener in _presentationListeners.toList(growable: false)) {
        listener(event);
      }
    } finally {
      coordinator.confirmPresentation(claim);
    }
  }

  IntentionCatalogCreateOutcome _createOutcome(
    Result<IntentionCommandSuccess> result,
  ) => switch (result) {
    ResultSuccess(value: IntentionSaved()) =>
      IntentionCatalogCreateOutcome.succeeded,
    ResultSuccess(value: IntentionDeleted()) =>
      IntentionCatalogCreateOutcome.unexpected,
    ResultFailure(:final failure) => switch (failure) {
      IntentionValidationFailure() => IntentionCatalogCreateOutcome.validation,
      IntentionConflictFailure() => IntentionCatalogCreateOutcome.conflict,
      IntentionUnavailableFailure() =>
        IntentionCatalogCreateOutcome.unavailable,
      IntentionCorruptionFailure() => IntentionCatalogCreateOutcome.corruption,
      IntentionNotFoundFailure() ||
      IntentionUnexpectedFailure() => IntentionCatalogCreateOutcome.unexpected,
    },
  };

  IntentionCatalogUpdateOutcome _updateOutcome(
    Result<IntentionCommandSuccess> result,
  ) => switch (result) {
    ResultSuccess(value: IntentionSaved()) =>
      IntentionCatalogUpdateOutcome.succeeded,
    ResultSuccess(value: IntentionDeleted()) =>
      IntentionCatalogUpdateOutcome.unexpected,
    ResultFailure(:final failure) => switch (failure) {
      IntentionValidationFailure() => IntentionCatalogUpdateOutcome.validation,
      IntentionNotFoundFailure() => IntentionCatalogUpdateOutcome.notFound,
      IntentionConflictFailure() => IntentionCatalogUpdateOutcome.conflict,
      IntentionUnavailableFailure() =>
        IntentionCatalogUpdateOutcome.unavailable,
      IntentionCorruptionFailure() => IntentionCatalogUpdateOutcome.corruption,
      IntentionUnexpectedFailure() => IntentionCatalogUpdateOutcome.unexpected,
    },
  };

  IntentionCatalogDeleteOutcome _deleteOutcome(
    Result<IntentionCommandSuccess> result,
  ) => switch (result) {
    ResultSuccess(value: IntentionDeleted()) =>
      IntentionCatalogDeleteOutcome.succeeded,
    ResultSuccess(value: IntentionSaved()) =>
      IntentionCatalogDeleteOutcome.unexpected,
    ResultFailure(:final failure) => switch (failure) {
      IntentionValidationFailure() => IntentionCatalogDeleteOutcome.validation,
      IntentionNotFoundFailure() => IntentionCatalogDeleteOutcome.notFound,
      IntentionConflictFailure() => IntentionCatalogDeleteOutcome.conflict,
      IntentionUnavailableFailure() =>
        IntentionCatalogDeleteOutcome.unavailable,
      IntentionCorruptionFailure() => IntentionCatalogDeleteOutcome.corruption,
      IntentionUnexpectedFailure() => IntentionCatalogDeleteOutcome.unexpected,
    },
  };
}

final class _PendingCatalogContinuation {
  const _PendingCatalogContinuation({
    required this.generation,
    required this.page,
  });

  final int generation;
  final IntentionCatalogContinuationPage page;
}
