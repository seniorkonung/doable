import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/navigation/graph_generation.dart';
import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../graph/application/personal_graph_repository_provider.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';
import 'home_statistics_state.dart';

part 'home_statistics_view_model.g.dart';

@riverpod
final class HomeStatisticsViewModel extends _$HomeStatisticsViewModel {
  late StatisticsReadContract _reader;

  /// Поколение графа, для которого задан выбор Главной.
  GraphGeneration? _graphGeneration;
  late HomeStatisticsSelection _selection;
  var _generation = 0;
  var _isVisible = false;
  var _needsRead = true;
  int? _readingGeneration;
  GraphRevision? _requiredRevision;
  Object? _lifetime;

  @override
  HomeStatisticsState build() {
    // Новое поколение графа открывает Главную как при запуске приложения, а
    // другое перестроение сохраняет выбор.
    final graphGeneration = ref.watch(currentGraphGenerationProvider);
    if (graphGeneration != _graphGeneration) {
      _graphGeneration = graphGeneration;
      _selection = HomeStatisticsSelection.initial(
        ref.read(dailyChoiceLocalDateSourceProvider)().date,
      );
    }
    _reader = ref.watch(personalGraphRepositoryProvider);
    _requiredRevision = null;
    _needsRead = true;
    _readingGeneration = null;
    ++_generation;
    final lifetime = _lifetime = Object();
    final coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    final completions = coordinator.completions.listen(_onCompletion);
    ref.onDispose(() {
      _lifetime = null;
      ++_generation;
      unawaited(completions.cancel());
    });
    scheduleMicrotask(() {
      if (ref.mounted && identical(lifetime, _lifetime)) {
        unawaited(_readIfVisible());
      }
    });
    return HomeStatisticsState(
      selection: _selection,
      read: const HomeStatisticsInitialLoad(),
    );
  }

  /// Страница сообщает видимость маршрута; наличие слушателей её не заменяет.
  void setVisible(bool visible) {
    if (visible == _isVisible) return;
    _isVisible = visible;
    if (visible) {
      unawaited(_readIfVisible());
    } else if (_readingGeneration == _generation) {
      ++_generation;
      _readingGeneration = null;
      final current = state.read;
      if (current is HomeStatisticsData &&
          current.pageStatus is HomeStatisticsPageLoading) {
        state = state.copyWith(
          read: current.withPageStatus(const HomeStatisticsPageIdle()),
        );
      } else {
        _needsRead = true;
      }
    }
  }

  /// Сигнал часов меняет только границу невыполненного и отметку текущего периода.
  void setLocalDate(CalendarDate localDate) {
    if (localDate == _selection.localDate) return;
    _publishSelection(_selection.copyWith(localDate: localDate));
    unawaited(_markStale());
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
    if (!_isVisible) return Future.value();
    if (state.read case HomeStatisticsInitialFailure(canRetry: true)) {
      return _markStale();
    }
    return Future.value();
  }

  Future<void> retryRefresh() {
    if (!_isVisible) return Future.value();
    if (state.read case HomeStatisticsLoaded(
      refreshStatus: HomeStatisticsRefreshFailure(canRetry: true),
    )) {
      return _markStale();
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
    if (!_isVisible) return Future.value();
    if (state.read case final HomeStatisticsData current
        when current.nextCursor != null &&
            current.refreshStatus is HomeStatisticsRefreshIdle &&
            current.pageStatus is HomeStatisticsPageIdle) {
      return _loadMore(current);
    }
    return Future.value();
  }

  Future<void> retryLoadMore() {
    if (!_isVisible) return Future.value();
    final current = state.read;
    if (current is! HomeStatisticsData ||
        current.refreshStatus is! HomeStatisticsRefreshIdle) {
      return Future.value();
    }
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
    unawaited(_markStale());
  }

  void _onCompletion(GraphCommandCompletion completion) {
    final revision = completion.revision;
    if (revision == null) return;
    final known = _requiredRevision;
    if (known != null) {
      final order = revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = revision;
    ++_generation;
    _needsRead = true;
    final lifetime = _lifetime;
    scheduleMicrotask(() {
      if (ref.mounted && identical(lifetime, _lifetime)) {
        unawaited(_readIfVisible());
      }
    });
  }

  Future<void> _markStale() {
    ++_generation;
    _needsRead = true;
    return _readIfVisible();
  }

  Future<void> _readIfVisible() {
    if (!_isVisible || !_needsRead) return Future.value();
    _needsRead = false;
    final current = state.read;
    final confirmed = current is HomeStatisticsLoaded ? current : null;
    state = state.copyWith(
      read:
          confirmed?.withRefreshStatus(const HomeStatisticsRefreshing()) ??
          const HomeStatisticsInitialLoad(),
    );
    _readingGeneration = _generation;
    return _replaceLoaded(_generation, _selection, confirmed);
  }

  bool _isCurrent(int generation) =>
      ref.mounted && generation == _generation && _isVisible;

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  Future<void> _replaceLoaded(
    int generation,
    HomeStatisticsSelection selection,
    HomeStatisticsLoaded? confirmed,
  ) async {
    final result = await _readPage(selection);
    if (!_isCurrent(generation)) return;
    final StatisticsFirstPage first;
    switch (result) {
      case GraphResultSuccess(value: final StatisticsFirstPage page):
        first = page;
      case GraphResultSuccess():
        return _failReplacement(
          const StatisticsReadUnexpectedFailure(),
          confirmed,
        );
      case GraphResultFailure(:final failure):
        return _failReplacement(failure, confirmed);
    }
    if (_precedesRequired(first.revision)) return _markStale();
    final items = [...first.items];
    var cursor = first.nextCursor;
    while (cursor != null && items.length < (confirmed?.items.length ?? 0)) {
      final continuation = await _readPage(selection, cursor: cursor);
      if (!_isCurrent(generation)) return;
      switch (continuation) {
        case GraphResultSuccess(value: final StatisticsContinuationPage page):
          if (page.revision.compareTo(first.revision) !=
              GraphRevisionOrder.same) {
            return _markStale();
          }
          items.addAll(page.items);
          cursor = page.nextCursor;
        case GraphResultSuccess():
          return _failReplacement(
            const StatisticsReadUnexpectedFailure(),
            confirmed,
          );
        case GraphResultFailure(:final failure):
          return _failReplacement(failure, confirmed);
      }
    }
    _readingGeneration = null;
    _requiredRevision = first.revision;
    state = state.copyWith(
      read: first.totalItems == 0
          ? HomeStatisticsEmpty(
              summary: first.summary,
              revision: first.revision,
            )
          : HomeStatisticsData(
              summary: first.summary,
              totalItems: first.totalItems,
              items: items,
              revision: first.revision,
              nextCursor: cursor,
            ),
    );
  }

  Future<void> _failReplacement(
    StatisticsReadFailure failure,
    HomeStatisticsLoaded? confirmed,
  ) {
    if (failure is StatisticsSnapshotExpired) return _markStale();
    _readingGeneration = null;
    state = state.copyWith(
      read:
          confirmed?.withRefreshStatus(HomeStatisticsRefreshFailure(failure)) ??
          HomeStatisticsInitialFailure(failure),
    );
    return Future.value();
  }

  Future<void> _loadMore(HomeStatisticsData confirmed) async {
    final generation = _generation;
    _readingGeneration = generation;
    state = state.copyWith(
      read: confirmed.withPageStatus(const HomeStatisticsPageLoading()),
    );
    final result = await _readPage(_selection, cursor: confirmed.nextCursor);
    if (!_isCurrent(generation)) return;
    _readingGeneration = null;
    if (result case GraphResultFailure(failure: StatisticsSnapshotExpired())) {
      return _markStale();
    }
    if (result case GraphResultSuccess(:final value)
        when value.revision.compareTo(confirmed.revision) !=
            GraphRevisionOrder.same) {
      return _markStale();
    }
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

  Future<StatisticsPageResult> _readPage(
    HomeStatisticsSelection selection, {
    StatisticsCursor? cursor,
  }) async {
    try {
      return await _reader.getStatisticsPage(
        StatisticsQuery(
          period: selection.period,
          view: selection.view,
          localDate: selection.localDate,
          pageSize: 100,
          cursor: cursor,
        ),
      );
    } on Object {
      return const StatisticsPageError(StatisticsReadUnexpectedFailure());
    }
  }
}
