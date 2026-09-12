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
  IntentionScope _scope = IntentionCatalogSelection.initial.scope;
  String _titleFilterText = IntentionCatalogSelection.initial.titleFilterText;
  IntentionCatalogOrder _order = IntentionCatalogSelection.initial.order;
  IntentionCatalogFilterValidationFailure? _filterValidationFailure;
  CatalogPagingPolicy _policy = CatalogPagingPolicy.production;
  Timer? _filterTimer;
  bool _isDebouncingFilter = false;

  IntentionCatalogSelection get selection => IntentionCatalogSelection(
    scope: _scope,
    titleFilterText: _titleFilterText,
    order: _order,
    filterValidationFailure: _filterValidationFailure,
  );

  @override
  Future<IntentionCatalogState> build() {
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
    ref.invalidateSelf();
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

  void _applyParametersImmediately() {
    _filterTimer?.cancel();
    _isDebouncingFilter = false;
    ref.invalidateSelf();
  }

  void _handleCompletion(IntentionCommandCompletion completion) {
    switch (completion.result) {
      case ResultSuccess():
        if (_isDebouncingFilter ||
            _filterValidationFailure != null ||
            !ref.mounted) {
          return;
        }
        ref.invalidateSelf();
      case ResultFailure():
        return;
    }
  }
}
