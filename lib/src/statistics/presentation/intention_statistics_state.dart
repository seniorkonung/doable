import '../../shared/domain/calendar_date.dart';
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
    this.view,
  });

  factory IntentionStatisticsSelection.initial(
    CalendarDate localDate,
    IntentionStatisticsTarget? target,
  ) {
    final selection = IntentionStatisticsSelection(
      localDate: localDate,
      month: StatisticsMonth(localDate.year, localDate.month),
      year: StatisticsYear(localDate.year),
      view: target?.view,
    );
    return target == null ? selection : selection.withPeriod(target.period);
  }

  final CalendarDate localDate;
  final IntentionStatisticsMode mode;
  final StatisticsMonth month;
  final StatisticsYear year;

  /// null до первого раздела, если цель открытия не задала вид: его выбирает
  /// чтение, и дальше раздел остаётся на выбранном виде.
  final StatisticsView? view;

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
    CalendarDate? localDate,
    IntentionStatisticsMode? mode,
    StatisticsMonth? month,
    StatisticsYear? year,
    StatisticsView? view,
  }) => IntentionStatisticsSelection(
    localDate: localDate ?? this.localDate,
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

  /// Разбивка без элементов в разделе не показывается.
  bool get hasItems => totalItems > 0;

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
    IntentionStatisticsRootDetails(:final terminalIntentions) =>
      IntentionStatisticsRootBreakdowns(
        IntentionStatisticsBreakdownState.first(terminalIntentions),
      ),
    IntentionStatisticsIntermediateDetails(
      :final rootIntentions,
      :final terminalIntentions,
    ) =>
      IntentionStatisticsIntermediateBreakdowns(
        IntentionStatisticsBreakdownState.first(rootIntentions),
        IntentionStatisticsBreakdownState.first(terminalIntentions),
      ),
    IntentionStatisticsTerminalDetails(:final rootIntentions) =>
      IntentionStatisticsTerminalBreakdowns(
        IntentionStatisticsBreakdownState.first(rootIntentions),
      ),
    IntentionStatisticsThroughRelationsDetails(
      :final relations,
      :final terminalIntentions,
    ) =>
      IntentionStatisticsThroughRelationsBreakdowns(
        IntentionStatisticsBreakdownState.first(relations),
        IntentionStatisticsBreakdownState.first(terminalIntentions),
      ),
  };

  IntentionStatisticsBreakdownState<StatisticsItem>? get rootIntentions => null;
  IntentionStatisticsBreakdownState<StatisticsItem>? get terminalIntentions =>
      null;
  IntentionStatisticsBreakdownState<StatisticsRelationItem>? get relations =>
      null;

  IntentionStatisticsBreakdowns copyWith({
    IntentionStatisticsBreakdownState<StatisticsItem>? rootIntentions,
    IntentionStatisticsBreakdownState<StatisticsItem>? terminalIntentions,
    IntentionStatisticsBreakdownState<StatisticsRelationItem>? relations,
  }) => switch (this) {
    IntentionStatisticsRootBreakdowns(terminalIntentions: final terminals) =>
      IntentionStatisticsRootBreakdowns(terminalIntentions ?? terminals),
    IntentionStatisticsIntermediateBreakdowns(
      rootIntentions: final roots,
      terminalIntentions: final terminals,
    ) =>
      IntentionStatisticsIntermediateBreakdowns(
        rootIntentions ?? roots,
        terminalIntentions ?? terminals,
      ),
    IntentionStatisticsTerminalBreakdowns(rootIntentions: final roots) =>
      IntentionStatisticsTerminalBreakdowns(rootIntentions ?? roots),
    IntentionStatisticsThroughRelationsBreakdowns(
      relations: final links,
      terminalIntentions: final terminals,
    ) =>
      IntentionStatisticsThroughRelationsBreakdowns(
        relations ?? links,
        terminalIntentions ?? terminals,
      ),
  };
}

final class IntentionStatisticsRootBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsRootBreakdowns(this.terminalIntentions);
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> terminalIntentions;
}

final class IntentionStatisticsIntermediateBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsIntermediateBreakdowns(
    this.rootIntentions,
    this.terminalIntentions,
  );
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> rootIntentions;
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> terminalIntentions;
}

final class IntentionStatisticsTerminalBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsTerminalBreakdowns(this.rootIntentions);
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> rootIntentions;
}

final class IntentionStatisticsThroughRelationsBreakdowns
    extends IntentionStatisticsBreakdowns {
  const IntentionStatisticsThroughRelationsBreakdowns(
    this.relations,
    this.terminalIntentions,
  );
  @override
  final IntentionStatisticsBreakdownState<StatisticsRelationItem> relations;
  @override
  final IntentionStatisticsBreakdownState<StatisticsItem> terminalIntentions;
}

sealed class IntentionStatisticsLoaded extends IntentionStatisticsReadState {
  const IntentionStatisticsLoaded({
    required this.section,
    required this.breakdowns,
    this.refreshStatus = const IntentionStatisticsRefreshIdle(),
  });

  factory IntentionStatisticsLoaded.first(IntentionStatisticsSection section) {
    final breakdowns = IntentionStatisticsBreakdowns.first(section.details);
    return section.selectedCounts.planned == 0
        ? IntentionStatisticsEmpty(section: section, breakdowns: breakdowns)
        : IntentionStatisticsData(section: section, breakdowns: breakdowns);
  }

  final IntentionStatisticsSection section;
  final IntentionStatisticsBreakdowns breakdowns;
  final IntentionStatisticsRefreshStatus refreshStatus;

  IntentionStatisticsLoaded copyWith({
    IntentionStatisticsBreakdowns? breakdowns,
    IntentionStatisticsRefreshStatus? refreshStatus,
  }) => switch (this) {
    IntentionStatisticsData() => IntentionStatisticsData(
      section: section,
      breakdowns: breakdowns ?? this.breakdowns,
      refreshStatus: refreshStatus ?? this.refreshStatus,
    ),
    IntentionStatisticsEmpty() => IntentionStatisticsEmpty(
      section: section,
      breakdowns: breakdowns ?? this.breakdowns,
      refreshStatus: refreshStatus ?? this.refreshStatus,
    ),
  };
}

final class IntentionStatisticsData extends IntentionStatisticsLoaded {
  const IntentionStatisticsData({
    required super.section,
    required super.breakdowns,
    super.refreshStatus,
  });
}

final class IntentionStatisticsEmpty extends IntentionStatisticsLoaded {
  const IntentionStatisticsEmpty({
    required super.section,
    required super.breakdowns,
    super.refreshStatus,
  });
}

sealed class IntentionStatisticsRefreshStatus {
  const IntentionStatisticsRefreshStatus();
}

final class IntentionStatisticsRefreshIdle
    extends IntentionStatisticsRefreshStatus {
  const IntentionStatisticsRefreshIdle();
}

final class IntentionStatisticsRefreshing
    extends IntentionStatisticsRefreshStatus {
  const IntentionStatisticsRefreshing();
}

final class IntentionStatisticsRefreshFailure
    extends IntentionStatisticsRefreshStatus {
  const IntentionStatisticsRefreshFailure(this.failure);

  final StatisticsReadFailure failure;
  bool get canRetry => failure is StatisticsReadUnavailableFailure;
}
