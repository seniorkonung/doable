import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design_system/components/count_tiles.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_icon.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../shared/domain/calendar_date.dart';
import '../application/intention_statistics_read_contract.dart';
import '../application/statistics_period.dart';
import '../application/statistics_read_contract.dart';
import 'intention_statistics_calendar.dart';
import 'intention_statistics_state.dart';

/// Представление готового состояния; периоды и чтения принадлежат модели.
final class IntentionStatisticsOverview extends StatelessWidget {
  const IntentionStatisticsOverview({
    required this.state,
    required this.onModeSelected,
    required this.onPreviousPeriod,
    required this.onNextPeriod,
    required this.onViewSelected,
    required this.onMonthSelected,
    required this.onDaySelected,
    super.key,
  });

  final IntentionStatisticsState state;
  final ValueChanged<IntentionStatisticsMode> onModeSelected;
  final VoidCallback onPreviousPeriod;
  final VoidCallback onNextPeriod;
  final ValueChanged<StatisticsView> onViewSelected;
  final ValueChanged<int> onMonthSelected;
  final ValueChanged<CalendarDate> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final selection = state.selection;
    final period = selection.period;
    final periodLabel = switch (period) {
      StatisticsMonth(:final year, :final month) => texts.statisticsMonthPeriod(
        DateTime.utc(year, month),
      ),
      StatisticsYear(:final year) => texts.statisticsYearPeriod(
        DateTime.utc(year),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            texts.statisticsSectionTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          role: SemanticsRole.tabBar,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in IntentionStatisticsMode.values)
                MergeSemantics(
                  child: Semantics(
                    role: SemanticsRole.tab,
                    selected: selection.mode == mode,
                    inMutuallyExclusiveGroup: true,
                    child: TextButton(
                      onPressed: () => onModeSelected(mode),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selection.mode == mode)
                            const Icon(Icons.check, size: 18),
                          Text(switch (mode) {
                            IntentionStatisticsMode.month =>
                              texts.statisticsMonthTab,
                            IntentionStatisticsMode.year =>
                              texts.statisticsYearTab,
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: switch (period) {
                StatisticsMonth() => texts.statisticsPreviousMonth,
                StatisticsYear() => texts.statisticsPreviousYear,
              },
              onPressed: period.previous == null ? null : onPreviousPeriod,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                selected: true,
                child: Column(
                  children: [
                    Text(periodLabel, textAlign: TextAlign.center),
                    if (selection.isCurrentPeriod)
                      Text(
                        texts.statisticsCurrentPeriod,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: switch (period) {
                StatisticsMonth() => texts.statisticsNextMonth,
                StatisticsYear() => texts.statisticsNextYear,
              },
              onPressed: period.next == null ? null : onNextPeriod,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (state.read case final IntentionStatisticsLoaded loaded) ...[
          const SizedBox(height: 4),
          _ViewTiles(
            section: loaded.section,
            periodLabel: periodLabel,
            onViewSelected: onViewSelected,
          ),
          _ViewHint(view: loaded.section.view),
          // Без действий вида сводку, календарь и столбики заменяет сообщение,
          // а плитки остаются; пустые разбивки не показываются.
          ...switch (loaded) {
            IntentionStatisticsData(:final section) => [
              const SizedBox(height: 16),
              _Summary(section: section),
              const SizedBox(height: 16),
              IntentionStatisticsCalendarView(
                calendar: section.calendar,
                localDate: selection.localDate,
                onMonthSelected: onMonthSelected,
                onDaySelected: onDaySelected,
              ),
            ],
            IntentionStatisticsEmpty(:final section) => [
              _EmptyView(view: section.view, periodLabel: periodLabel),
            ],
          },
        ],
      ],
    );
  }
}

/// Три плитки ролей в пути и широкая плитка «Через связи, как сейчас» с числом
/// действий вида за период; открыта ровно одна.
final class _ViewTiles extends StatelessWidget {
  const _ViewTiles({
    required this.section,
    required this.periodLabel,
    required this.onViewSelected,
  });

  final IntentionStatisticsSection section;
  final String periodLabel;
  final ValueChanged<StatisticsView> onViewSelected;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    String semanticLabel(StatisticsView view, String name) =>
        texts.statisticsTileSemantics(
          name,
          texts.statisticsPeriodActions(section.cards[view].planned),
          periodLabel,
        );
    CountTile<StatisticsView> tile(StatisticsView view, String name) =>
        CountTile(
          key: ValueKey(view),
          id: view,
          count: section.cards[view].planned,
          name: name,
          semanticLabel: semanticLabel(view, name),
        );
    final throughRelations = texts.statisticsTileThroughRelations;
    return CountTiles<StatisticsView>(
      columns: CountTileColumns.three,
      value: section.view,
      onPick: onViewSelected,
      label: texts.statisticsTilesLabel,
      tiles: [
        tile(StatisticsView.rootIntentions, texts.statisticsTileRoot),
        tile(
          StatisticsView.intermediateIntentions,
          texts.statisticsTileIntermediate,
        ),
        tile(StatisticsView.terminalIntentions, texts.statisticsTileTerminal),
      ],
      wide: CountTileWide(
        key: const ValueKey(StatisticsView.throughRelations),
        id: StatisticsView.throughRelations,
        count: section.cards[StatisticsView.throughRelations].planned,
        name: throughRelations,
        semanticLabel: semanticLabel(
          StatisticsView.throughRelations,
          throughRelations,
        ),
        icon: DoableIconData.graph,
      ),
    );
  }
}

/// Пояснение выбранного вида под плитками; для «Через связи» оно же говорит,
/// что число меняется вместе со связями.
final class _ViewHint extends StatelessWidget {
  const _ViewHint({required this.view});

  final StatisticsView view;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space1,
        10,
        DoableMetrics.space1,
        0,
      ),
      child: Text(switch (view) {
        StatisticsView.rootIntentions => texts.statisticsIntentionRootHint,
        StatisticsView.intermediateIntentions =>
          texts.statisticsIntentionIntermediateHint,
        StatisticsView.terminalIntentions =>
          texts.statisticsIntentionTerminalHint,
        StatisticsView.throughRelations =>
          texts.statisticsIntentionThroughRelationsHint,
      }, style: DoableType.caption.copyWith(color: colors.muted)),
    );
  }
}

/// Сообщение вместо сводки, календаря и разбивок: какие действия здесь будут
/// посчитаны.
final class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.view, required this.periodLabel});

  final StatisticsView view;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    return EmptyState(
      title: switch (view) {
        StatisticsView.rootIntentions =>
          texts.statisticsIntentionEmptyRootTitle(periodLabel),
        StatisticsView.intermediateIntentions =>
          texts.statisticsIntentionEmptyIntermediateTitle(periodLabel),
        StatisticsView.terminalIntentions =>
          texts.statisticsIntentionEmptyTerminalTitle(periodLabel),
        StatisticsView.throughRelations =>
          texts.statisticsIntentionEmptyThroughRelationsTitle(periodLabel),
      },
      text: switch (view) {
        StatisticsView.rootIntentions => texts.statisticsIntentionEmptyRootText,
        StatisticsView.intermediateIntentions =>
          texts.statisticsIntentionEmptyIntermediateText,
        StatisticsView.terminalIntentions =>
          texts.statisticsIntentionEmptyTerminalText,
        StatisticsView.throughRelations =>
          texts.statisticsIntentionEmptyThroughRelationsText,
      },
      textMaxWidth: 270,
      spaceAbove: DoableMetrics.space6,
      spaceBelow: DoableMetrics.space6,
      pretty: true,
    );
  }
}

final class _Summary extends StatelessWidget {
  const _Summary({required this.section});
  final IntentionStatisticsSection section;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final counts = section.selectedCounts;
    final share = _shareLabel(texts, section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          excludeSemantics: true,
          label: texts.statisticsContributionCountsSemantics(
            counts.contribution,
            counts.planned,
          ),
          child: Text(
            texts.statisticsPeriodCompleted(
              counts.contribution,
              counts.planned,
            ),
          ),
        ),
        if (share != null) Text(share),
        if (section.details case IntentionStatisticsThroughRelationsDetails(
          :final explicitPathActions,
        ))
          Text(
            texts.statisticsExplicitPathActions(
              explicitPathActions,
              counts.planned,
            ),
          ),
      ],
    );
  }
}

/// Доля действий вида среди всех действий периода; без действий периода
/// доли нет.
String? _shareLabel(
  AppLocalizations texts,
  IntentionStatisticsSection section,
) => section.periodCounts.planned == 0
    ? null
    : texts.statisticsPeriodActionsShare(
        section.selectedCounts.planned / section.periodCounts.planned,
      );
