import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_revision.dart';
import '../application/contribution_counts.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';

enum HomeStatisticsTab { month, year }

/// Выбранные периоды не зависят от просмотра в раскрытом выборе.
final class HomeStatisticsSelection {
  const HomeStatisticsSelection({
    required this.localDate,
    required this.month,
    required this.year,
    required this.browsedYear,
    this.tab = HomeStatisticsTab.month,
    this.view = StatisticsView.sourceIntentions,
    this.isPeriodSelectorExpanded = false,
  });

  factory HomeStatisticsSelection.initial(CalendarDate localDate) =>
      HomeStatisticsSelection(
        localDate: localDate,
        month: StatisticsMonth(localDate.year, localDate.month),
        year: StatisticsYear(localDate.year),
        browsedYear: StatisticsYear(localDate.year),
      );

  final CalendarDate localDate;
  final HomeStatisticsTab tab;
  final StatisticsMonth month;
  final StatisticsYear year;
  final StatisticsView view;
  final bool isPeriodSelectorExpanded;
  final StatisticsYear browsedYear;

  StatisticsPeriod get period => switch (tab) {
    HomeStatisticsTab.month => month,
    HomeStatisticsTab.year => year,
  };

  bool get isCurrentPeriod => period.contains(localDate);

  HomeStatisticsSelection copyWith({
    CalendarDate? localDate,
    HomeStatisticsTab? tab,
    StatisticsMonth? month,
    StatisticsYear? year,
    StatisticsView? view,
    bool? isPeriodSelectorExpanded,
    StatisticsYear? browsedYear,
  }) => HomeStatisticsSelection(
    localDate: localDate ?? this.localDate,
    tab: tab ?? this.tab,
    month: month ?? this.month,
    year: year ?? this.year,
    view: view ?? this.view,
    isPeriodSelectorExpanded:
        isPeriodSelectorExpanded ?? this.isPeriodSelectorExpanded,
    browsedYear: browsedYear ?? this.browsedYear,
  );
}

final class HomeStatisticsState {
  const HomeStatisticsState({required this.selection, required this.read});

  final HomeStatisticsSelection selection;
  final HomeStatisticsReadState read;

  HomeStatisticsState copyWith({
    HomeStatisticsSelection? selection,
    HomeStatisticsReadState? read,
  }) => HomeStatisticsState(
    selection: selection ?? this.selection,
    read: read ?? this.read,
  );
}

sealed class HomeStatisticsReadState {
  const HomeStatisticsReadState();
}

final class HomeStatisticsInitialLoad extends HomeStatisticsReadState {
  const HomeStatisticsInitialLoad();
}

final class HomeStatisticsInitialFailure extends HomeStatisticsReadState {
  const HomeStatisticsInitialFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}

sealed class HomeStatisticsPageStatus {
  const HomeStatisticsPageStatus();
}

final class HomeStatisticsPageIdle extends HomeStatisticsPageStatus {
  const HomeStatisticsPageIdle();
}

final class HomeStatisticsPageLoading extends HomeStatisticsPageStatus {
  const HomeStatisticsPageLoading();
}

final class HomeStatisticsPageFailure extends HomeStatisticsPageStatus {
  const HomeStatisticsPageFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}

sealed class HomeStatisticsRefreshStatus {
  const HomeStatisticsRefreshStatus();
}

final class HomeStatisticsRefreshIdle extends HomeStatisticsRefreshStatus {
  const HomeStatisticsRefreshIdle();
}

final class HomeStatisticsRefreshing extends HomeStatisticsRefreshStatus {
  const HomeStatisticsRefreshing();
}

final class HomeStatisticsRefreshFailure extends HomeStatisticsRefreshStatus {
  const HomeStatisticsRefreshFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}

/// Сводка, число и элементы относятся к одному снимку выбранных условий.
sealed class HomeStatisticsLoaded extends HomeStatisticsReadState {
  HomeStatisticsLoaded({
    required this.summary,
    required this.totalItems,
    required List<StatisticsItem> items,
    required this.revision,
    required this.nextCursor,
    this.pageStatus = const HomeStatisticsPageIdle(),
    this.refreshStatus = const HomeStatisticsRefreshIdle(),
  }) : items = List.unmodifiable(items);

  final StatisticsPeriodSummary summary;
  final int totalItems;
  final List<StatisticsItem> items;
  final GraphRevision revision;
  final StatisticsCursor? nextCursor;
  final HomeStatisticsPageStatus pageStatus;
  final HomeStatisticsRefreshStatus refreshStatus;

  HomeStatisticsLoaded withRefreshStatus(
    HomeStatisticsRefreshStatus refreshStatus,
  ) => switch (this) {
    HomeStatisticsEmpty() => HomeStatisticsEmpty(
      summary: summary,
      revision: revision,
      refreshStatus: refreshStatus,
    ),
    HomeStatisticsData() => HomeStatisticsData(
      summary: summary,
      totalItems: totalItems,
      items: items,
      revision: revision,
      nextCursor: nextCursor,
      refreshStatus: refreshStatus,
    ),
  };
}

final class HomeStatisticsData extends HomeStatisticsLoaded {
  HomeStatisticsData({
    required super.summary,
    required super.totalItems,
    required super.items,
    required super.revision,
    required super.nextCursor,
    super.pageStatus,
    super.refreshStatus,
  });

  HomeStatisticsData withPageStatus(HomeStatisticsPageStatus pageStatus) =>
      HomeStatisticsData(
        summary: summary,
        totalItems: totalItems,
        items: items,
        revision: revision,
        nextCursor: nextCursor,
        pageStatus: pageStatus,
        refreshStatus: refreshStatus,
      );
}

final class HomeStatisticsEmpty extends HomeStatisticsLoaded {
  HomeStatisticsEmpty({
    required super.summary,
    required super.revision,
    super.refreshStatus,
  }) : super(totalItems: 0, items: const [], nextCursor: null);
}
