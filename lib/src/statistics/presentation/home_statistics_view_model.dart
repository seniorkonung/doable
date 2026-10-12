import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/personal_graph_repository_provider.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';
import 'home_statistics_state.dart';

part 'home_statistics_view_model.g.dart';

@riverpod
final class HomeStatisticsViewModel extends _$HomeStatisticsViewModel {
  late StatisticsReadContract _reader;
  late var _selection = HomeStatisticsSelection.initial(
    ref.read(dailyChoiceLocalDateSourceProvider)().date,
  );
  var _generation = 0;

  @override
  HomeStatisticsState build() {
    _reader = ref.watch(personalGraphRepositoryProvider);
    unawaited(_loadFirst(++_generation));
    return HomeStatisticsState(
      selection: _selection,
      read: const HomeStatisticsInitialLoad(),
    );
  }

  void selectTab(HomeStatisticsTab tab) {
    if (tab == _selection.tab) return;
    final selection = _selection.copyWith(tab: tab);
    _restart(
      selection.copyWith(browsedYear: StatisticsYear(selection.period.year)),
    );
  }

  /// Выбор периода также выбирает его вкладку; другая вкладка сохраняется.
  void selectPeriod(StatisticsPeriod period) {
    if (period == _selection.period) return;
    final selection = switch (period) {
      StatisticsMonth() => _selection.copyWith(
        tab: HomeStatisticsTab.month,
        month: period,
      ),
      StatisticsYear() => _selection.copyWith(
        tab: HomeStatisticsTab.year,
        year: period,
      ),
    };
    _restart(selection.copyWith(browsedYear: StatisticsYear(period.year)));
  }

  void selectPreviousPeriod() {
    final previous = _selection.period.previous;
    if (previous != null) selectPeriod(previous);
  }

  void selectNextPeriod() {
    final next = _selection.period.next;
    if (next != null) selectPeriod(next);
  }

  void selectView(StatisticsView view) {
    if (view == _selection.view) return;
    _restart(_selection.copyWith(view: view));
  }

  void setPeriodSelectorExpanded(bool expanded) {
    if (expanded == _selection.isPeriodSelectorExpanded) return;
    _publishSelection(
      _selection.copyWith(
        isPeriodSelectorExpanded: expanded,
        browsedYear: StatisticsYear(_selection.period.year),
      ),
    );
  }

  void browsePreviousYear() => _browseYear(_selection.browsedYear.previous);

  void browseNextYear() => _browseYear(_selection.browsedYear.next);

  Future<void> retryFirstPage() {
    if (state.read case HomeStatisticsInitialFailure(canRetry: true)) {
      state = state.copyWith(read: const HomeStatisticsInitialLoad());
      return _loadFirst(++_generation);
    }
    return Future.value();
  }

  /// Индекс последнего видимого элемента; следующие 100 запрашиваются,
  /// когда после него остаётся не больше 30 загруженных элементов.
  Future<void> loadMoreIfNeeded(int lastVisibleIndex) {
    final current = state.read;
    if (current is HomeStatisticsData &&
        current.items.length - lastVisibleIndex - 1 <= 30) {
      return loadMore();
    }
    return Future.value();
  }

  Future<void> loadMore() {
    if (state.read case final HomeStatisticsData current
        when current.nextCursor != null &&
            current.pageStatus is HomeStatisticsPageIdle) {
      return _loadMore(current);
    }
    return Future.value();
  }

  Future<void> retryLoadMore() {
    final current = state.read;
    if (current is! HomeStatisticsData) return Future.value();
    if (current.pageStatus case HomeStatisticsPageFailure(canRetry: true)) {
      return _loadMore(current);
    }
    return Future.value();
  }

  void _browseYear(StatisticsYear? year) {
    if (!_selection.isPeriodSelectorExpanded || year == null) return;
    _publishSelection(_selection.copyWith(browsedYear: year));
  }

  void _publishSelection(HomeStatisticsSelection selection) {
    _selection = selection;
    state = state.copyWith(selection: selection);
  }

  void _restart(HomeStatisticsSelection selection) {
    _selection = selection;
    state = HomeStatisticsState(
      selection: selection,
      read: const HomeStatisticsInitialLoad(),
    );
    unawaited(_loadFirst(++_generation));
  }

  Future<void> _loadFirst(int generation) async {
    final result = await _readPage();
    if (!ref.mounted || generation != _generation) return;
    final read = switch (result) {
      GraphResultSuccess(value: final StatisticsFirstPage page) =>
        page.totalItems == 0
            ? HomeStatisticsEmpty(
                summary: page.summary,
                revision: page.revision,
              )
            : HomeStatisticsData(
                summary: page.summary,
                totalItems: page.totalItems,
                items: page.items,
                revision: page.revision,
                nextCursor: page.nextCursor,
              ),
      GraphResultSuccess() => const HomeStatisticsInitialFailure(
        StatisticsReadUnexpectedFailure(),
      ),
      GraphResultFailure(:final failure) => HomeStatisticsInitialFailure(
        failure,
      ),
    };
    state = state.copyWith(read: read);
  }

  Future<void> _loadMore(HomeStatisticsData confirmed) async {
    final generation = _generation;
    state = state.copyWith(
      read: confirmed.withPageStatus(const HomeStatisticsPageLoading()),
    );
    final result = await _readPage(cursor: confirmed.nextCursor);
    if (!ref.mounted || generation != _generation) return;
    final read = switch (result) {
      GraphResultSuccess(value: final StatisticsContinuationPage page) =>
        HomeStatisticsData(
          summary: confirmed.summary,
          totalItems: confirmed.totalItems,
          items: [...confirmed.items, ...page.items],
          revision: confirmed.revision,
          nextCursor: page.nextCursor,
        ),
      GraphResultSuccess() => confirmed.withPageStatus(
        const HomeStatisticsPageFailure(StatisticsReadUnexpectedFailure()),
      ),
      GraphResultFailure(:final failure) => confirmed.withPageStatus(
        HomeStatisticsPageFailure(failure),
      ),
    };
    state = state.copyWith(read: read);
  }

  Future<StatisticsPageResult> _readPage({StatisticsCursor? cursor}) async {
    try {
      return await _reader.getStatisticsPage(
        StatisticsQuery(
          period: _selection.period,
          view: _selection.view,
          localDate: _selection.localDate,
          pageSize: 100,
          cursor: cursor,
        ),
      );
    } on Object {
      return const StatisticsPageError(StatisticsReadUnexpectedFailure());
    }
  }
}
