import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../graph/application/personal_graph_repository_provider.dart';
import '../../intention/domain/intention_id.dart';
import '../application/intention_statistics_breakdown.dart';
import '../application/intention_statistics_read_contract.dart';
import '../application/intention_statistics_target.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';
import 'intention_statistics_state.dart';

part 'intention_statistics_view_model.g.dart';

// Семейство и автоматическое освобождение задают жизнь состояния страницы:
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionStatisticsViewModel
    extends _$IntentionStatisticsViewModel {
  late StatisticsReadContract _reader;
  var _generation = 0;
  var _isVisible = false;
  var _needsRead = true;
  GraphRevision? _requiredRevision;
  Object? _lifetime;

  /// Ключ создаётся один раз на страницу и сохраняется до её закрытия.
  @override
  IntentionStatisticsState build(
    IntentionId intentionId,
    Object pageKey, {
    IntentionStatisticsTarget? target,
  }) {
    _reader = ref.watch(personalGraphRepositoryProvider);
    final selection = IntentionStatisticsSelection.initial(
      ref.read(dailyChoiceLocalDateSourceProvider)().date,
      target,
    );
    ++_generation;
    _requiredRevision = null;
    _needsRead = true;
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
    return IntentionStatisticsState(
      selection: selection,
      read: const IntentionStatisticsInitialLoad(),
    );
  }

  /// Видимость задаёт верхний маршрут страницы, а не наличие слушателей.
  void setVisible(bool visible) {
    if (visible == _isVisible) return;
    _isVisible = visible;
    if (visible) {
      unawaited(_readIfVisible());
      return;
    }
    ++_generation;
    final current = state.read;
    if (current is IntentionStatisticsInitialLoad ||
        current is IntentionStatisticsLoaded &&
            current.refreshStatus is IntentionStatisticsRefreshing) {
      _needsRead = true;
    }
    if (current is IntentionStatisticsLoaded) {
      state = state.withRead(
        current.copyWith(breakdowns: _stopPageLoads(current.breakdowns)),
      );
    }
  }

  IntentionStatisticsBreakdowns _stopPageLoads(
    IntentionStatisticsBreakdowns parts,
  ) {
    IntentionStatisticsBreakdownState<T>? reset<T>(
      IntentionStatisticsBreakdownState<T>? page,
    ) => page != null && page.pageStatus is IntentionStatisticsPageLoading
        ? page.withPageStatus(const IntentionStatisticsPageIdle())
        : page;
    return parts.copyWith(
      sourceIntentions: reset(parts.sourceIntentions),
      selectedActions: reset(parts.selectedActions),
      relations: reset(parts.relations),
    );
  }

  void setLocalDate(CalendarDate localDate) {
    if (localDate == state.selection.localDate) return;
    state = IntentionStatisticsState(
      selection: state.selection.copyWith(localDate: localDate),
      read: state.read,
    );
    unawaited(_markStale());
  }

  void selectMode(IntentionStatisticsMode mode) {
    if (mode == state.selection.mode) return;
    _restart(state.selection.copyWith(mode: mode));
  }

  void selectPeriod(StatisticsPeriod period) {
    if (period == state.selection.period) return;
    _restart(state.selection.withPeriod(period));
  }

  void selectPreviousPeriod() {
    final previous = state.selection.period.previous;
    if (previous != null) selectPeriod(previous);
  }

  void selectNextPeriod() {
    final next = state.selection.period.next;
    if (next != null) selectPeriod(next);
  }

  void selectMonth(int month) =>
      selectPeriod(StatisticsMonth(state.selection.year.year, month));

  void selectView(StatisticsView view) {
    if (view == state.selection.view) return;
    _restart(state.selection.copyWith(view: view));
  }

  Future<void> retry() {
    if (!_isVisible) return Future.value();
    if (state.read case IntentionStatisticsFailure(canRetry: true)) {
      return _markStale();
    }
    return Future.value();
  }

  Future<void> retryRefresh() {
    if (!_isVisible) return Future.value();
    if (state.read case IntentionStatisticsLoaded(
      refreshStatus: IntentionStatisticsRefreshFailure(canRetry: true),
    )) {
      return _markStale();
    }
    return Future.value();
  }

  /// Индекс относится к одной разбивке, а не ко всей странице.
  Future<void> loadMoreIfNeeded(
    StatisticsBreakdown breakdown,
    int lastVisibleIndex,
  ) => _requestMore(breakdown, lastVisibleIndex: lastVisibleIndex);

  Future<void> loadMore(StatisticsBreakdown breakdown) =>
      _requestMore(breakdown);

  Future<void> retryLoadMore(StatisticsBreakdown breakdown) =>
      _requestMore(breakdown, retry: true);

  Future<void> _restart(IntentionStatisticsSelection selection) {
    state = IntentionStatisticsState(
      selection: selection,
      read: const IntentionStatisticsInitialLoad(),
    );
    return _markStale();
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
    final generation = _generation;
    final selection = state.selection;
    final current = state.read;
    final confirmed = current is IntentionStatisticsLoaded
        ? current.copyWith(breakdowns: _stopPageLoads(current.breakdowns))
        : null;
    state = state.withRead(
      confirmed?.copyWith(
            refreshStatus: const IntentionStatisticsRefreshing(),
          ) ??
          const IntentionStatisticsInitialLoad(),
    );
    return _replaceLoaded(generation, selection, confirmed);
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
    IntentionStatisticsSelection selection,
    IntentionStatisticsLoaded? confirmed,
  ) async {
    if (!_isCurrent(generation)) return;
    final IntentionStatisticsSectionResult result;
    try {
      result = await _reader.getIntentionStatisticsSection(
        IntentionStatisticsQuery(
          intentionId: intentionId,
          period: selection.period,
          view: selection.view,
          localDate: selection.localDate,
          pageSize: 100,
        ),
      );
    } on Object {
      if (_isCurrent(generation)) {
        await _failReplacement(
          const StatisticsReadUnexpectedFailure(),
          confirmed,
        );
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    final IntentionStatisticsSection section;
    switch (result) {
      case GraphResultSuccess(:final value):
        section = value;
      case GraphResultFailure(:final failure):
        return _failReplacement(failure, confirmed);
    }
    if (_precedesRequired(section.revision)) return _markStale();
    var replacement = IntentionStatisticsLoaded.first(section);

    Future<StatisticsReadFailure?> restore<T>(
      IntentionStatisticsBreakdownState<T>? first,
      IntentionStatisticsBreakdownState<T>? previous,
      IntentionStatisticsBreakdowns Function(
        IntentionStatisticsBreakdowns,
        IntentionStatisticsBreakdownState<T>,
      )
      replace,
    ) async {
      if (first == null) return null;
      var page = first;
      while (page.nextCursor != null &&
          page.items.length < (previous?.items.length ?? 0)) {
        final continuation = await _readBreakdown(page.nextCursor!);
        if (!_isCurrent(generation)) return null;
        switch (continuation) {
          case GraphResultSuccess(:final value):
            if (value.revision.compareTo(section.revision) !=
                GraphRevisionOrder.same) {
              return const StatisticsSnapshotExpired();
            }
            page = page.append(value);
          case GraphResultFailure(:final failure):
            return failure;
        }
      }
      replacement = replacement.copyWith(
        breakdowns: replace(replacement.breakdowns, page),
      );
      return null;
    }

    var failure = await restore(
      replacement.breakdowns.sourceIntentions,
      confirmed?.breakdowns.sourceIntentions,
      (parts, page) => parts.copyWith(sourceIntentions: page),
    );
    if (!_isCurrent(generation)) return;
    if (failure != null) return _failReplacement(failure, confirmed);
    failure = await restore(
      replacement.breakdowns.relations,
      confirmed?.breakdowns.relations,
      (parts, page) => parts.copyWith(relations: page),
    );
    if (!_isCurrent(generation)) return;
    if (failure != null) return _failReplacement(failure, confirmed);
    failure = await restore(
      replacement.breakdowns.selectedActions,
      confirmed?.breakdowns.selectedActions,
      (parts, page) => parts.copyWith(selectedActions: page),
    );
    if (!_isCurrent(generation)) return;
    if (failure != null) return _failReplacement(failure, confirmed);
    _requiredRevision = section.revision;
    state = state.withRead(replacement);
  }

  Future<void> _failReplacement(
    StatisticsReadFailure failure,
    IntentionStatisticsLoaded? confirmed,
  ) {
    if (failure is StatisticsSnapshotExpired) return _markStale();
    state = state.withRead(
      failure is StatisticsIntentionNotFoundFailure
          ? const IntentionStatisticsNotFound()
          : confirmed?.copyWith(
                  refreshStatus: IntentionStatisticsRefreshFailure(failure),
                ) ??
                IntentionStatisticsFailure(failure),
    );
    return Future.value();
  }

  Future<IntentionStatisticsBreakdownResult<T>> _readBreakdown<T>(
    StatisticsBreakdownCursor<T> cursor,
  ) async {
    try {
      return await _reader.getIntentionStatisticsBreakdown(cursor);
    } on Object {
      return const IntentionStatisticsBreakdownError(
        StatisticsReadUnexpectedFailure(),
      );
    }
  }

  Future<void> _requestMore(
    StatisticsBreakdown breakdown, {
    int? lastVisibleIndex,
    bool retry = false,
  }) {
    final current = state.read;
    if (!_isVisible ||
        _needsRead ||
        current is! IntentionStatisticsLoaded ||
        current.refreshStatus is! IntentionStatisticsRefreshIdle) {
      return Future.value();
    }
    return switch (breakdown) {
      StatisticsBreakdown.sourceIntentions => _loadMore(
        current.breakdowns.sourceIntentions,
        (parts, page) => parts.copyWith(sourceIntentions: page),
        lastVisibleIndex: lastVisibleIndex,
        retry: retry,
      ),
      StatisticsBreakdown.selectedActions => _loadMore(
        current.breakdowns.selectedActions,
        (parts, page) => parts.copyWith(selectedActions: page),
        lastVisibleIndex: lastVisibleIndex,
        retry: retry,
      ),
      StatisticsBreakdown.relations => _loadMore(
        current.breakdowns.relations,
        (parts, page) => parts.copyWith(relations: page),
        lastVisibleIndex: lastVisibleIndex,
        retry: retry,
      ),
    };
  }

  Future<void> _loadMore<T>(
    IntentionStatisticsBreakdownState<T>? breakdown,
    IntentionStatisticsBreakdowns Function(
      IntentionStatisticsBreakdowns,
      IntentionStatisticsBreakdownState<T>,
    )
    replace, {
    int? lastVisibleIndex,
    required bool retry,
  }) async {
    final cursor = breakdown?.nextCursor;
    if (breakdown == null || cursor == null) return;
    final canLoad = switch (breakdown.pageStatus) {
      IntentionStatisticsPageIdle() => !retry,
      IntentionStatisticsPageFailure(canRetry: true) => retry,
      _ => false,
    };
    if (!canLoad ||
        (lastVisibleIndex != null &&
            breakdown.items.length - lastVisibleIndex - 1 > 30)) {
      return;
    }
    final current = state.read;
    if (current is! IntentionStatisticsLoaded) return;
    final generation = _generation;
    state = state.withRead(
      current.copyWith(
        breakdowns: replace(
          current.breakdowns,
          breakdown.withPageStatus(const IntentionStatisticsPageLoading()),
        ),
      ),
    );
    if (!_isCurrent(generation)) return;
    final result = await _readBreakdown(cursor);
    if (!_isCurrent(generation)) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (value.revision.compareTo(current.section.revision) !=
            GraphRevisionOrder.same) {
          return _markStale();
        }
        _publishBreakdown(replace, breakdown.append(value));
      case GraphResultFailure(failure: StatisticsSnapshotExpired()):
        return _markStale();
      case GraphResultFailure(:final failure):
        _publishBreakdown(
          replace,
          breakdown.withPageStatus(IntentionStatisticsPageFailure(failure)),
        );
    }
  }

  void _publishBreakdown<T>(
    IntentionStatisticsBreakdowns Function(
      IntentionStatisticsBreakdowns,
      IntentionStatisticsBreakdownState<T>,
    )
    replace,
    IntentionStatisticsBreakdownState<T> breakdown,
  ) {
    final current = state.read;
    if (current is! IntentionStatisticsLoaded) return;
    state = state.withRead(
      current.copyWith(breakdowns: replace(current.breakdowns, breakdown)),
    );
  }
}
