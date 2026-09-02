import '../domain/intention.dart';
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';
import 'intention_command.dart';
import 'intention_result.dart';

abstract interface class IntentionRepository {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Stream<Result<Intention?>> watchById(IntentionId id);

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
  final IntentionTitleFilter? titleFilter;
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
    return titleFilter!.matchesTitle(summary.title);
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
        : left.id.compareTo(right.id);
  }

  IntentionTimestamp _timestampOf(IntentionSummary summary) =>
      switch (order.field) {
        IntentionCatalogSortField.createdAt => summary.createdAt,
        IntentionCatalogSortField.updatedAt => summary.updatedAt,
      };

  static IntentionTitleFilter? _normalizeFilter(String? value) {
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
    return IntentionTitleFilter._(normalized);
  }
}

final class IntentionTitleFilter {
  const IntentionTitleFilter._(this._normalizedValue);

  final String _normalizedValue;

  bool matchesTitle(String title) =>
      title.toLowerCase().contains(_normalizedValue.toLowerCase());

  T map<T>(T Function(String normalizedValue) transform) =>
      transform(_normalizedValue);
}

abstract interface class IntentionCatalogCursor {}

final class IntentionSummary {
  IntentionSummary({
    required this.id,
    required String title,
    required this.hasDescription,
    required this.readiness,
    required this.archiveState,
    required this.createdAt,
    required IntentionTimestamp updatedAt,
  }) : title = IntentionText.normalizeTitle(title),
       updatedAt = IntentionTimestamp.requireValidUpdate(
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

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
    required int totalCount,
    required super.nextCursor,
  }) : totalCount = _requireTotalCount(totalCount, items.length);

  final int totalCount;

  static int _requireTotalCount(int totalCount, int itemCount) {
    if (totalCount < itemCount) {
      throw const IntentionCatalogPageValidationException();
    }
    return totalCount;
  }
}

final class IntentionCatalogPageValidationException implements Exception {
  const IntentionCatalogPageValidationException();
}

final class IntentionCatalogContinuationPage extends IntentionCatalogPage {
  IntentionCatalogContinuationPage({
    required super.items,
    required super.nextCursor,
  });
}
