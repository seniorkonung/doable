import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_repository.dart';

part 'catalog_paging_policy.g.dart';

enum CatalogPagingPolicyValidationFailure {
  pageSizeOutOfRange,
  prefetchRemainingOutOfRange,
  negativeFilterDebounce,
}

final class CatalogPagingPolicyValidationException implements Exception {
  const CatalogPagingPolicyValidationException(this.failure);

  final CatalogPagingPolicyValidationFailure failure;
}

final class CatalogPagingPolicy {
  factory CatalogPagingPolicy({
    required int pageSize,
    required int prefetchRemaining,
    required Duration filterDebounce,
  }) {
    if (pageSize < IntentionCatalogQuery.minPageSize ||
        pageSize > IntentionCatalogQuery.maxPageSize) {
      throw const CatalogPagingPolicyValidationException(
        CatalogPagingPolicyValidationFailure.pageSizeOutOfRange,
      );
    }
    if (prefetchRemaining < 0 || prefetchRemaining >= pageSize) {
      throw const CatalogPagingPolicyValidationException(
        CatalogPagingPolicyValidationFailure.prefetchRemainingOutOfRange,
      );
    }
    if (filterDebounce.isNegative) {
      throw const CatalogPagingPolicyValidationException(
        CatalogPagingPolicyValidationFailure.negativeFilterDebounce,
      );
    }
    return CatalogPagingPolicy._(
      pageSize: pageSize,
      prefetchRemaining: prefetchRemaining,
      filterDebounce: filterDebounce,
    );
  }

  const CatalogPagingPolicy._({
    required this.pageSize,
    required this.prefetchRemaining,
    required this.filterDebounce,
  });

  static const production = CatalogPagingPolicy._(
    pageSize: 100,
    prefetchRemaining: 30,
    filterDebounce: Duration(milliseconds: 250),
  );

  final int pageSize;
  final int prefetchRemaining;
  final Duration filterDebounce;
}

@Riverpod(keepAlive: true)
CatalogPagingPolicy catalogPagingPolicy(Ref ref) =>
    CatalogPagingPolicy.production;
