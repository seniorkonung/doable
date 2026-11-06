import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
        if (state.read case IntentionStatisticsLoaded(:final section)) ...[
          const SizedBox(height: 8),
          _Cards(
            section: section,
            periodLabel: periodLabel,
            onViewSelected: onViewSelected,
          ),
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
      ],
    );
  }
}

final class _Cards extends StatelessWidget {
  const _Cards({
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
    final colors = Theme.of(context).colorScheme;
    // Wrap переносит карточки, а их высота следует содержимому и масштабу текста:
    // https://api.flutter.dev/flutter/widgets/Wrap-class.html
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final view in StatisticsView.values)
            SizedBox(
              width: constraints.maxWidth >= 600
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth,
              child: MergeSemantics(
                child: Semantics(
                  selected: section.view == view,
                  inMutuallyExclusiveGroup: true,
                  child: OutlinedButton(
                    onPressed: () => onViewSelected(view),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: section.view == view
                          ? colors.secondaryContainer
                          : null,
                      foregroundColor: section.view == view
                          ? colors.onSecondaryContainer
                          : null,
                      padding: const EdgeInsets.all(12),
                    ),
                    child: Semantics(
                      excludeSemantics: true,
                      label: [
                        texts.statisticsViewCardSemantics(
                          _viewLabel(texts, view),
                          periodLabel,
                          texts.statisticsContributionCountsSemantics(
                            section.cards[view].contribution,
                            section.cards[view].planned,
                          ),
                        ),
                        if (section.view == view) ?_shareLabel(texts, section),
                      ].join('. '),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (section.view == view)
                            const Icon(Icons.check, size: 18),
                          Text(
                            _viewLabel(texts, view),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            texts.statisticsContributionCounts(
                              section.cards[view].contribution,
                              section.cards[view].planned,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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

String _viewLabel(AppLocalizations texts, StatisticsView view) =>
    switch (view) {
      StatisticsView.rootIntentions => texts.statisticsRootIntentions,
      StatisticsView.intermediateIntentions =>
        texts.statisticsIntermediateIntentions,
      StatisticsView.terminalIntentions => texts.statisticsTerminalIntentions,
      StatisticsView.throughRelations => texts.statisticsThroughRelations,
    };
