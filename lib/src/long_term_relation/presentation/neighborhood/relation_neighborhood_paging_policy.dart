import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/relation_group_page.dart';

part 'relation_neighborhood_paging_policy.g.dart';

enum RelationNeighborhoodPagingPolicyValidationFailure {
  pageSizeOutOfRange,
  prefetchRemainingOutOfRange,
}

final class RelationNeighborhoodPagingPolicyValidationException
    implements Exception {
  const RelationNeighborhoodPagingPolicyValidationException(this.failure);

  final RelationNeighborhoodPagingPolicyValidationFailure failure;
}

/// Политика порций одной выбранной группы связей намерения.
final class RelationNeighborhoodPagingPolicy {
  factory RelationNeighborhoodPagingPolicy({
    required int pageSize,
    required int prefetchRemaining,
  }) {
    if (pageSize < RelationGroupQuery.minPageSize ||
        pageSize > RelationGroupQuery.maxPageSize) {
      throw const RelationNeighborhoodPagingPolicyValidationException(
        RelationNeighborhoodPagingPolicyValidationFailure.pageSizeOutOfRange,
      );
    }
    if (prefetchRemaining < 0 || prefetchRemaining >= pageSize) {
      throw const RelationNeighborhoodPagingPolicyValidationException(
        RelationNeighborhoodPagingPolicyValidationFailure
            .prefetchRemainingOutOfRange,
      );
    }
    return RelationNeighborhoodPagingPolicy._(
      pageSize: pageSize,
      prefetchRemaining: prefetchRemaining,
    );
  }

  const RelationNeighborhoodPagingPolicy._({
    required this.pageSize,
    required this.prefetchRemaining,
  });

  /// Размер порции интерфейса одинаков для активных и архивных групп.
  ///
  /// Это политика чтения, а не предметный предел числа связей группы.
  static const production = RelationNeighborhoodPagingPolicy._(
    pageSize: 50,
    prefetchRemaining: 15,
  );

  final int pageSize;
  final int prefetchRemaining;
}

@Riverpod(keepAlive: true)
RelationNeighborhoodPagingPolicy relationNeighborhoodPagingPolicy(Ref ref) =>
    RelationNeighborhoodPagingPolicy.production;
