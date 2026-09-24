import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';

final class DailyChoiceCatalogSelection {
  const DailyChoiceCatalogSelection({this.date, this.isCompleted});

  final CalendarDate? date;
  final bool? isCompleted;

  DailyChoiceCatalogSelection withDate(CalendarDate? value) =>
      DailyChoiceCatalogSelection(date: value, isCompleted: isCompleted);

  DailyChoiceCatalogSelection withCompletion(bool? value) =>
      DailyChoiceCatalogSelection(date: date, isCompleted: value);
}

sealed class DailyChoiceCatalogState {
  const DailyChoiceCatalogState(this.selection);

  final DailyChoiceCatalogSelection selection;
}

final class DailyChoiceCatalogInitialLoad extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialLoad(super.selection);
}

final class DailyChoiceCatalogInitialFailure extends DailyChoiceCatalogState {
  const DailyChoiceCatalogInitialFailure(super.selection, this.failure);

  final DailyChoiceCatalogReadFailure failure;
  bool get canRetry => failure is DailyChoiceCatalogUnavailableFailure;
}

enum DailyChoiceCatalogFreshness { current, refreshing, stale }

sealed class DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageStatus();
}

final class DailyChoiceCatalogPageIdle extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageIdle();
}

final class DailyChoiceCatalogPageLoading extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageLoading();
}

final class DailyChoiceCatalogPageFailure extends DailyChoiceCatalogPageStatus {
  const DailyChoiceCatalogPageFailure(this.failure);

  final DailyChoiceCatalogReadFailure failure;
  bool get canRetry => failure is DailyChoiceCatalogUnavailableFailure;
}

/// Строки и полное количество относятся к одной опубликованной ревизии.
/// При обновлении прежний подтверждённый снимок остаётся доступным.
class DailyChoiceCatalogLoaded extends DailyChoiceCatalogState {
  DailyChoiceCatalogLoaded({
    required DailyChoiceCatalogSelection selection,
    required List<DailyChoiceCatalogItem> items,
    required this.totalCount,
    required this.nextCursor,
    required this.revision,
    this.freshness = DailyChoiceCatalogFreshness.current,
    this.refreshFailure,
    this.pageStatus = const DailyChoiceCatalogPageIdle(),
    this.needsRebase = false,
  }) : items = List.unmodifiable(items),
       super(selection);

  final List<DailyChoiceCatalogItem> items;
  final int totalCount;
  final DailyChoiceCatalogCursor? nextCursor;
  final GraphRevision revision;
  final DailyChoiceCatalogFreshness freshness;
  final DailyChoiceCatalogReadFailure? refreshFailure;
  final DailyChoiceCatalogPageStatus pageStatus;

  /// Даже посторонняя команда делает курсор прежней ревизии непригодным.
  final bool needsRebase;

  DailyChoiceCatalogLoaded withStatus({
    DailyChoiceCatalogFreshness? freshness,
    DailyChoiceCatalogReadFailure? refreshFailure,
    DailyChoiceCatalogPageStatus? pageStatus,
    bool? needsRebase,
  }) {
    final nextFreshness = freshness ?? this.freshness;
    final nextPageStatus = pageStatus ?? this.pageStatus;
    final nextNeedsRebase = needsRebase ?? this.needsRebase;
    if (this is DailyChoiceCatalogEmpty) {
      return DailyChoiceCatalogEmpty(
        selection: selection,
        revision: revision,
        freshness: nextFreshness,
        refreshFailure: refreshFailure,
        pageStatus: nextPageStatus,
        needsRebase: nextNeedsRebase,
      );
    }
    return DailyChoiceCatalogLoaded(
      selection: selection,
      items: items,
      totalCount: totalCount,
      nextCursor: nextCursor,
      revision: revision,
      freshness: nextFreshness,
      refreshFailure: refreshFailure,
      pageStatus: nextPageStatus,
      needsRebase: nextNeedsRebase,
    );
  }
}

final class DailyChoiceCatalogEmpty extends DailyChoiceCatalogLoaded {
  DailyChoiceCatalogEmpty({
    required super.selection,
    required super.revision,
    super.freshness,
    super.refreshFailure,
    super.pageStatus,
    super.needsRebase,
  }) : super(items: const [], totalCount: 0, nextCursor: null);
}
