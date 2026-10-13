import '../../daily_choice/domain/calendar_date.dart';
import '../application/intention_statistics_breakdown.dart';
import '../application/intention_statistics_read_contract.dart';
import '../application/intention_statistics_target.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';

enum IntentionStatisticsMode { month, year }

final class IntentionStatisticsSelection {
  const IntentionStatisticsSelection({
    required this.localDate,
    required this.month,
    required this.year,
    this.mode = IntentionStatisticsMode.month,
    this.view = StatisticsView.throughRelations,
  });

  factory IntentionStatisticsSelection.initial(
    CalendarDate localDate,
    IntentionStatisticsTarget? target,
  ) {
    final selection = IntentionStatisticsSelection(
      localDate: localDate,
      month: StatisticsMonth(localDate.year, localDate.month),
      year: StatisticsYear(localDate.year),
      view: target?.view ?? StatisticsView.throughRelations,
    );
    return target == null ? selection : selection.withPeriod(target.period);
  }

  final CalendarDate localDate;
  final IntentionStatisticsMode mode;
  final StatisticsMonth month;
  final StatisticsYear year;
  final StatisticsView view;

  StatisticsPeriod get period => switch (mode) {
    IntentionStatisticsMode.month => month,
    IntentionStatisticsMode.year => year,
  };

  bool get isCurrentPeriod => period.contains(localDate);

  IntentionStatisticsSelection withPeriod(StatisticsPeriod period) =>
      switch (period) {
        StatisticsMonth() => copyWith(
          mode: IntentionStatisticsMode.month,
          month: period,
        ),
        StatisticsYear() => copyWith(
          mode: IntentionStatisticsMode.year,
          year: period,
        ),
      };

  IntentionStatisticsSelection copyWith({
    IntentionStatisticsMode? mode,
    StatisticsMonth? month,
    StatisticsYear? year,
    StatisticsView? view,
  }) => IntentionStatisticsSelection(
    localDate: localDate,
    mode: mode ?? this.mode,
    month: month ?? this.month,
    year: year ?? this.year,
    view: view ?? this.view,
  );
}

final class IntentionStatisticsState {
  const IntentionStatisticsState({required this.selection, required this.read});

  final IntentionStatisticsSelection selection;
  final IntentionStatisticsReadState read;

  IntentionStatisticsState withRead(IntentionStatisticsReadState read) =>
      IntentionStatisticsState(selection: selection, read: read);
}

sealed class IntentionStatisticsReadState {
  const IntentionStatisticsReadState();
}

final class IntentionStatisticsInitialLoad
    extends IntentionStatisticsReadState {
  const IntentionStatisticsInitialLoad();
}

final class IntentionStatisticsNotFound extends IntentionStatisticsReadState {
  const IntentionStatisticsNotFound();
}

final class IntentionStatisticsFailure extends IntentionStatisticsReadState {
  const IntentionStatisticsFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}

sealed class IntentionStatisticsPageStatus {
  const IntentionStatisticsPageStatus();
}

final class IntentionStatisticsPageIdle extends IntentionStatisticsPageStatus {
  const IntentionStatisticsPageIdle();
}

final class IntentionStatisticsPageLoading
    extends IntentionStatisticsPageStatus {
  const IntentionStatisticsPageLoading();
}

final class IntentionStatisticsPageFailure
    extends IntentionStatisticsPageStatus {
  const IntentionStatisticsPageFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}

/// Каждая разбивка сохраняет тип строк и собственное состояние продолжения.
final class IntentionStatisticsBreakdownState<T> {
  IntentionStatisticsBreakdownState({
    required List<T> items,
    required this.totalItems,
    required this.nextCursor,
    this.pageStatus = const IntentionStatisticsPageIdle(),
  }) : items = List.unmodifiable(items);

  factory IntentionStatisticsBreakdownState.first(
    StatisticsBreakdownFirstPage<T> page,
  ) => IntentionStatisticsBreakdownState(
    items: page.items,
    totalItems: page.totalItems,
    nextCursor: page.nextCursor,
  );

  final List<T> items;
  final int totalItems;
  final StatisticsBreakdownCursor<T>? nextCursor;
  final IntentionStatisticsPageStatus pageStatus;

  IntentionStatisticsBreakdownState<T> withPageStatus(
    IntentionStatisticsPageStatus pageStatus,
  ) => IntentionStatisticsBreakdownState(
    items: items,
    totalItems: totalItems,
    nextCursor: nextCursor,
    pageStatus: pageStatus,
  );

  IntentionStatisticsBreakdownState<T> append(
    StatisticsBreakdownContinuationPage<T> page,
  ) => IntentionStatisticsBreakdownState(
    items: [...items, ...page.items],
    totalItems: totalItems,
    nextCursor: page.nextCursor,
  );
}

/// Вариант вида задаёт только допустимые разбивки, включая тип их курсоров.
sealed class IntentionStatisticsBreakdowns {
  const IntentionStatisticsBreakdowns();

  factory IntentionStatisticsBreakdowns.first(
    IntentionStatisticsViewDetails details,
  ) => switch (details) {
    IntentionStatisticsSourceDetails(:final selectedActions) =>
      IntentionStatisticsSourceBreakdowns(
        IntentionStatisticsBreakdownState.first(selectedActions),
      ),
    IntentionStatisticsIntermediateDetails(
      :final sourceIntentions,
      :final selectedActions,
    ) =>
      IntentionStatisticsIntermediateBreakdowns(
        IntentionStatisticsBreakdownState.first(sourceIntentions),
        IntentionStatisticsBreakdownState.first(selectedActions),
      ),
    IntentionStatisticsSelectedDetails(:final sourceIntentions) =>
      IntentionStatisticsSelectedBreakdowns(
        IntentionStatisticsBreakdownState.first(sourceIntentions),
      ),
    IntentionStatisticsThroughRelationsDetails(
      :final relations,
      :final selectedActions,
    ) =>
      IntentionStatisticsThroughRelationsBreakdowns(
        IntentionStatisticsBreakdownState.first(relations),
        IntentionStatisticsBreakdownState.first(selectedActions),
      ),
  };

  IntentionStatisticsBreakdownState<StatisticsItem>? get sourceIntentions =>
      null;
  IntentionStatisticsBreakdownState<StatisticsItem>? get selectedActions =>
      null;
  IntentionStatisticsBreakdownState<StatisticsRelationItem>? get relations =>
      null;

  IntentionStatisticsBreakdowns copyWith({
    IntentionStatisticsBreakdownState<StatisticsItem>? sourceIntentions,
    IntentionStatisticsBreakdownState<StatisticsItem>? selectedActions,
    IntentionStatisticsBreakdownState<StatisticsRelationItem>? relations,
  }) => switch (this) {
    IntentionStatisticsSourceBreakdowns(selectedActions: final actions) =>
      IntentionStatisticsSourceBreakdowns(selectedActions ?? actions),
    IntentionStatisticsIntermediateBreakdowns(
      sourceIntentions: final sources,
      selectedActions: final actions,
    ) =>
      IntentionStatisticsIntermediateBreakdowns(
        sourceIntentions ?? sources,
        selectedActions ?? actions,
      ),
    IntentionStatisticsSelectedBreakdowns(sourceIntentions: final sources) =>
      IntentionStatisticsSelectedBreakdowns(sourceIntentions ?? sources),
    IntentionStatisticsThroughRelationsBreakdowns(
      relations: final links,
      selectedActions: final actions,
    ) =>
      IntentionStatisticsThroughRelationsBreakdowns(
        relations ?? links,
        selectedActions ?? actions,
      ),
  };
}

final class IntentionStatisticsSourceBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsSourceBreakdowns(this.selectedActions);
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> selectedActions;
}

final class IntentionStatisticsIntermediateBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsIntermediateBreakdowns(
    this.sourceIntentions,
    this.selectedActions,
  );
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> sourceIntentions;
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> selectedActions;
}

final class IntentionStatisticsSelectedBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsSelectedBreakdowns(this.sourceIntentions);
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> sourceIntentions;
}

final class IntentionStatisticsThroughRelationsBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsThroughRelationsBreakdowns(
    this.relations,
    this.selectedActions,
  );
  @override
  final IntentionStatisticsBreakdownState<StatisticsRelationItem> relations;
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> selectedActions;
}

sealed class IntentionStatisticsLoaded extends IntentionStatisticsReadState {
  const IntentionStatisticsLoaded({
    required this.section,
    required this.breakdowns,
  });

  factory IntentionStatisticsLoaded.first(IntentionStatisticsSection section) {
    final breakdowns = IntentionStatisticsBreakdowns.first(section.details);
    return section.selectedCounts.planned == 0
        ? IntentionStatisticsEmpty(section: section, breakdowns: breakdowns)
        : IntentionStatisticsData(section: section, breakdowns: breakdowns);
  }

  final IntentionStatisticsSection section;
  final IntentionStatisticsBreakdowns breakdowns;

  IntentionStatisticsLoaded withBreakdowns(
    IntentionStatisticsBreakdowns breakdowns,
  ) => switch (this) {
    IntentionStatisticsData() => IntentionStatisticsData(
      section: section,
      breakdowns: breakdowns,
    ),
    IntentionStatisticsEmpty() => IntentionStatisticsEmpty(
      section: section,
      breakdowns: breakdowns,
    ),
  };
}

final class IntentionStatisticsData extends IntentionStatisticsLoaded {
  const IntentionStatisticsData({
    required super.section,
    required super.breakdowns,
  });
}

final class IntentionStatisticsEmpty extends IntentionStatisticsLoaded {
  const IntentionStatisticsEmpty({
    required super.section,
    required super.breakdowns,
  });
}
