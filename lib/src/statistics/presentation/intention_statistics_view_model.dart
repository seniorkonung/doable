import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
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
    final generation = ++_generation;
    ref.onDispose(() => ++_generation);
    scheduleMicrotask(() {
      if (_isCurrent(generation)) {
        unawaited(_readSection(generation, selection));
      }
    });
    return IntentionStatisticsState(
      selection: selection,
      read: const IntentionStatisticsInitialLoad(),
    );
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
    if (state.read case IntentionStatisticsFailure(canRetry: true)) {
      return _restart(state.selection);
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
    final generation = ++_generation;
    state = IntentionStatisticsState(
      selection: selection,
      read: const IntentionStatisticsInitialLoad(),
    );
    return _readSection(generation, selection);
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> _readSection(
    int generation,
    IntentionStatisticsSelection selection,
  ) async {
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
        state = state.withRead(
          const IntentionStatisticsFailure(StatisticsReadUnexpectedFailure()),
        );
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        state = state.withRead(IntentionStatisticsLoaded.first(value));
      case GraphResultFailure(failure: StatisticsSnapshotExpired()):
        return _restart(selection);
      case GraphResultFailure(failure: StatisticsIntentionNotFoundFailure()):
        state = state.withRead(const IntentionStatisticsNotFound());
      case GraphResultFailure(:final failure):
        state = state.withRead(IntentionStatisticsFailure(failure));
    }
  }

  Future<void> _requestMore(
    StatisticsBreakdown breakdown, {
    int? lastVisibleIndex,
    bool retry = false,
  }) {
    final current = state.read;
    if (current is! IntentionStatisticsLoaded) return Future.value();
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
      current.withBreakdowns(
        replace(
          current.breakdowns,
          breakdown.withPageStatus(const IntentionStatisticsPageLoading()),
        ),
      ),
    );
    final IntentionStatisticsBreakdownResult<T> result;
    try {
      result = await _reader.getIntentionStatisticsBreakdown(cursor);
    } on Object {
      if (_isCurrent(generation)) {
        _publishBreakdown(
          replace,
          breakdown.withPageStatus(
            const IntentionStatisticsPageFailure(
              StatisticsReadUnexpectedFailure(),
            ),
          ),
        );
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (value.revision.compareTo(current.section.revision) !=
            GraphRevisionOrder.same) {
          return _restart(state.selection);
        }
        _publishBreakdown(replace, breakdown.append(value));
      case GraphResultFailure(failure: StatisticsSnapshotExpired()):
        return _restart(state.selection);
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
      current.withBreakdowns(replace(current.breakdowns, breakdown)),
    );
  }
}
