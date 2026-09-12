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
    return _loadFirstPage(repository, query, currentSelection);
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
  ) async {
    try {
      final result = await repository.getCatalogPage(query);
      return switch (result) {
        ResultSuccess(:final value) => _mapPage(selection, query, value),
        ResultFailure(:final failure) => _mapFailure(selection, query, failure),
      };
    } on Object {
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
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
      final result = await repository.getCatalogPage(query);
      if (!_ownsRequest(request, generation)) {
        return;
      }
      state = AsyncData(switch (result) {
        ResultSuccess(:final value) => _appendPage(confirmed, value),
        ResultFailure(:final failure) => _withContinuation(
          confirmed,
          _continuationFailure(failure),
        ),
      });
    } on Object {
      if (_ownsRequest(request, generation)) {
        state = AsyncData(
          _withContinuation(
            confirmed,
            const IntentionCatalogContinuationUnexpected(),
          ),
        );
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
      final result = await repository.getCatalogPage(query);
      if (!_ownsRequest(request, generation)) {
        return;
      }
      state = AsyncData(switch (result) {
        ResultSuccess(:final value) => _mapPage(
          confirmed.selection,
          query,
          value,
        ),
        ResultFailure(:final failure) => _withContinuation(
          confirmed,
          _recoveryFailure(failure),
        ),
      });
    } on Object {
      if (_ownsRequest(request, generation)) {
        state = AsyncData(
          _withContinuation(
            confirmed,
            const IntentionCatalogRecoveryUnexpected(),
          ),
        );
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
        page.revision.compareTo(confirmed.revision) !=
            IntentionCatalogRevisionOrder.same) {
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
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: combined,
      totalCount: confirmed.totalCount,
      nextCursor: page.nextCursor,
      revision: confirmed.revision,
    );
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
    if (completion.kind == IntentionCommandKind.create) {
      final coordinator = ref.read(
        intentionCommandCoordinatorProvider.notifier,
      );
      unawaited(
        _publishCreateFallback(
          coordinator.claimCatalogFallback(completion.token),
          coordinator,
        ),
      );
    }

    switch (completion.result) {
      case ResultSuccess():
        if (_isDebouncingFilter ||
            _filterValidationFailure != null ||
            !ref.mounted) {
          return;
        }
        _invalidatePageRequest();
        ref.invalidateSelf();
      case ResultFailure():
        return;
    }
  }

  Future<void> _publishCreateFallback(
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

    final event = IntentionCatalogPresentationEvent.create(
      _createOutcome(claim.completion.result),
    );
    for (final listener in _presentationListeners.toList(growable: false)) {
      listener(event);
    }
    coordinator.confirmPresentation(claim);
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
}
