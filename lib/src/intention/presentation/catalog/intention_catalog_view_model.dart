import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../operation/intention_repository_provider.dart';
import 'catalog_paging_policy.dart';
import 'intention_catalog_state.dart';

part 'intention_catalog_view_model.g.dart';

@riverpod
final class IntentionCatalogViewModel extends _$IntentionCatalogViewModel {
  @override
  Future<IntentionCatalogState> build() {
    final repository = ref.watch(intentionRepositoryProvider);
    final policy = ref.watch(catalogPagingPolicyProvider);
    final query = IntentionCatalogQuery(
      scope: IntentionScope.active,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: policy.pageSize,
    );
    return _loadFirstPage(repository, query);
  }

  Future<void> retry() async {
    final current = state.value;
    if (current is! IntentionCatalogUnavailable) {
      return;
    }

    state = const AsyncLoading();
    final nextState = await _loadFirstPage(
      ref.read(intentionRepositoryProvider),
      current.query,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(nextState);
  }

  Future<IntentionCatalogState> _loadFirstPage(
    IntentionRepository repository,
    IntentionCatalogQuery query,
  ) async {
    try {
      final result = await repository.getCatalogPage(query);
      return switch (result) {
        ResultSuccess(:final value) => _mapPage(query, value),
        ResultFailure(:final failure) => _mapFailure(query, failure),
      };
    } on Object {
      return IntentionCatalogUnexpected(query: query);
    }
  }

  IntentionCatalogState _mapPage(
    IntentionCatalogQuery query,
    IntentionCatalogPage page,
  ) {
    if (page is! IntentionCatalogFirstPage ||
        page.items.length > query.pageSize) {
      return IntentionCatalogUnexpected(query: query);
    }
    if (page.items.isEmpty) {
      if (page.totalCount != 0 || page.nextCursor != null) {
        return IntentionCatalogUnexpected(query: query);
      }
      return IntentionCatalogEmpty(query: query, revision: page.revision);
    }
    if (page.totalCount == page.items.length && page.nextCursor != null ||
        page.totalCount > page.items.length && page.nextCursor == null) {
      return IntentionCatalogUnexpected(query: query);
    }
    return IntentionCatalogLoaded(
      query: query,
      items: page.items,
      totalCount: page.totalCount,
      nextCursor: page.nextCursor,
      revision: page.revision,
    );
  }

  IntentionCatalogState _mapFailure(
    IntentionCatalogQuery query,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() => IntentionCatalogUnavailable(query: query),
    IntentionCorruptionFailure() => IntentionCatalogCorruption(query: query),
    IntentionUnexpectedFailure() => IntentionCatalogUnexpected(query: query),
    IntentionValidationFailure() => IntentionCatalogUnexpected(query: query),
    IntentionNotFoundFailure() => IntentionCatalogUnexpected(query: query),
    IntentionConflictFailure() => IntentionCatalogUnexpected(query: query),
  };
}
