import '../domain/intention.dart';
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';
import 'intention_command.dart';
import 'intention_result.dart';

abstract interface class IntentionRepository {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Stream<Intention?> watchById(IntentionId id);

  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command);
}

enum IntentionScope { active, archived, all }

enum IntentionCatalogSortField { createdAt, updatedAt }

enum IntentionCatalogSortDirection { ascending, descending }

final class IntentionCatalogOrder {
  const IntentionCatalogOrder({required this.field, required this.direction});

  static const createdAtDescending = IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.descending,
  );

  final IntentionCatalogSortField field;
  final IntentionCatalogSortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is IntentionCatalogOrder &&
      other.field == field &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);
}

enum IntentionCatalogQueryValidationFailure {
  pageSizeOutOfRange,
  titleFilterTooLong,
  cursorDoesNotMatchQuery,
}

final class IntentionCatalogQueryValidationException implements Exception {
  const IntentionCatalogQueryValidationException(this.failure);

  final IntentionCatalogQueryValidationFailure failure;
}

final class IntentionCatalogQuery {
  factory IntentionCatalogQuery({
    required IntentionScope scope,
    required String? titleFilter,
    required IntentionCatalogOrder order,
    required int pageSize,
    IntentionCatalogCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
      );
    }

    final normalizedFilter = _normalizeFilter(titleFilter);
    if (cursor != null && !cursor._matches(scope, normalizedFilter, order)) {
      throw const IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.cursorDoesNotMatchQuery,
      );
    }

    return IntentionCatalogQuery._(
      scope: scope,
      titleFilter: normalizedFilter,
      order: order,
      pageSize: pageSize,
      cursor: cursor,
    );
  }

  const IntentionCatalogQuery._({
    required this.scope,
    required this.titleFilter,
    required this.order,
    required this.pageSize,
    required this.cursor,
  });

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const maxTitleFilterLength = 255;

  final IntentionScope scope;
  final String? titleFilter;
  final IntentionCatalogOrder order;
  final int pageSize;
  final IntentionCatalogCursor? cursor;

  bool includes(IntentionSummary summary) {
    final matchesScope = switch (scope) {
      IntentionScope.active =>
        summary.archiveState == IntentionArchiveState.active,
      IntentionScope.archived =>
        summary.archiveState == IntentionArchiveState.archived,
      IntentionScope.all => true,
    };
    if (!matchesScope || titleFilter == null) {
      return matchesScope;
    }
    return summary.title.toLowerCase().contains(titleFilter!.toLowerCase());
  }

  int compare(IntentionSummary left, IntentionSummary right) {
    final timestampComparison = _timestampOf(left).value
        .compareTo(_timestampOf(right).value);
    final directionAdjusted = switch (order.direction) {
      IntentionCatalogSortDirection.ascending => timestampComparison,
      IntentionCatalogSortDirection.descending => -timestampComparison,
    };
    return directionAdjusted != 0
        ? directionAdjusted
        : left.id.value.compareTo(right.id.value);
  }

  IntentionTimestamp _timestampOf(IntentionSummary summary) =>
      switch (order.field) {
        IntentionCatalogSortField.createdAt => summary.createdAt,
        IntentionCatalogSortField.updatedAt => summary.updatedAt,
      };

  static String? _normalizeFilter(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (IntentionText.countGraphemeClusters(normalized) >
        maxTitleFilterLength) {
      throw const IntentionCatalogQueryValidationException(
        IntentionCatalogQueryValidationFailure.titleFilterTooLong,
      );
    }
    return normalized;
  }
}

final class IntentionCatalogCursor {
  const IntentionCatalogCursor._({
    required this.scope,
    required this.titleFilter,
    required this.order,
    required this.boundaryTimestamp,
    required this.boundaryId,
  });

  factory IntentionCatalogCursor.fromBoundary(
    IntentionCatalogQuery query,
    IntentionSummary boundary,
  ) => IntentionCatalogCursor._(
    scope: query.scope,
    titleFilter: query.titleFilter,
    order: query.order,
    boundaryTimestamp: switch (query.order.field) {
      IntentionCatalogSortField.createdAt => boundary.createdAt,
      IntentionCatalogSortField.updatedAt => boundary.updatedAt,
    },
    boundaryId: boundary.id,
  );

  final IntentionScope scope;
  final String? titleFilter;
  final IntentionCatalogOrder order;
  final IntentionTimestamp boundaryTimestamp;
  final IntentionId boundaryId;

  bool isFor(IntentionCatalogQuery query) =>
      _matches(query.scope, query.titleFilter, query.order);

  bool _matches(
    IntentionScope candidateScope,
    String? candidateFilter,
    IntentionCatalogOrder candidateOrder,
  ) =>
      scope == candidateScope &&
      titleFilter == candidateFilter &&
      order == candidateOrder;
}

final class IntentionSummary {
  IntentionSummary({
    required this.id,
    required String title,
    required this.hasDescription,
    required this.readiness,
    required this.archiveState,
    required this.createdAt,
    required this.updatedAt,
  }) : title = IntentionText.normalizeTitle(title);

  final IntentionId id;
  final String title;
  final bool hasDescription;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final IntentionTimestamp createdAt;
  final IntentionTimestamp updatedAt;
}

sealed class IntentionCatalogPage {
  IntentionCatalogPage({
    required List<IntentionSummary> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<IntentionSummary> items;
  final IntentionCatalogCursor? nextCursor;
}

final class IntentionCatalogFirstPage extends IntentionCatalogPage {
  IntentionCatalogFirstPage({
    required super.items,
    required this.totalCount,
    required super.nextCursor,
  }) : assert(totalCount >= items.length);

  final int totalCount;
}

final class IntentionCatalogContinuationPage extends IntentionCatalogPage {
  IntentionCatalogContinuationPage({
    required super.items,
    required super.nextCursor,
  });
}
