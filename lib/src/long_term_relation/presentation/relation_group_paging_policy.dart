import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../application/relation_group_page.dart';

part 'relation_group_paging_policy.g.dart';

enum RelationGroupPagingPolicyValidationFailure {
  pageSizeOutOfRange,
  prefetchRemainingOutOfRange,
}

final class RelationGroupPagingPolicyValidationException implements Exception {
  const RelationGroupPagingPolicyValidationException(this.failure);

  final RelationGroupPagingPolicyValidationFailure failure;
}

/// Политика порций одной выбранной группы связей намерения.
final class RelationGroupPagingPolicy {
  factory RelationGroupPagingPolicy({
    required int pageSize,
    required int prefetchRemaining,
  }) {
    if (pageSize < RelationGroupQuery.minPageSize ||
        pageSize > RelationGroupQuery.maxPageSize) {
      throw const RelationGroupPagingPolicyValidationException(
        RelationGroupPagingPolicyValidationFailure.pageSizeOutOfRange,
      );
    }
    if (prefetchRemaining < 0 || prefetchRemaining >= pageSize) {
      throw const RelationGroupPagingPolicyValidationException(
        RelationGroupPagingPolicyValidationFailure.prefetchRemainingOutOfRange,
      );
    }
    return RelationGroupPagingPolicy._(
      pageSize: pageSize,
      prefetchRemaining: prefetchRemaining,
    );
  }

  const RelationGroupPagingPolicy._({
    required this.pageSize,
    required this.prefetchRemaining,
  });

  /// Размер порции интерфейса одинаков для активных и архивных групп.
  ///
  /// Это политика чтения, а не предметный предел числа связей группы.
  static const production = RelationGroupPagingPolicy._(
    pageSize: 50,
    prefetchRemaining: 15,
  );

  final int pageSize;
  final int prefetchRemaining;
}

@Riverpod(keepAlive: true)
RelationGroupPagingPolicy relationGroupPagingPolicy(Ref ref) =>
    RelationGroupPagingPolicy.production;
