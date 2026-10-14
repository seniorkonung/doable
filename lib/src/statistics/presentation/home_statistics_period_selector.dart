import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../daily_choice/domain/calendar_date.dart';
import '../application/statistics_period.dart';
import 'home_statistics_state.dart';

/// Показывает выбор модели; просмотр годов не меняет выбранный период.
final class HomeStatisticsPeriodSelector extends StatelessWidget {
  const HomeStatisticsPeriodSelector({
    required this.selection,
    required this.onTabSelected,
    required this.onPeriodSelected,
    required this.onPreviousPeriod,
    required this.onNextPeriod,
    required this.onExpandedChanged,
    required this.onBrowsePreviousYear,
    required this.onBrowseNextYear,
    super.key,
  });

  final HomeStatisticsSelection selection;
  final ValueChanged<HomeStatisticsTab> onTabSelected;
  final ValueChanged<StatisticsPeriod> onPeriodSelected;
  final VoidCallback onPreviousPeriod;
  final VoidCallback onNextPeriod;
  final ValueChanged<bool> onExpandedChanged;
  final VoidCallback onBrowsePreviousYear;
  final VoidCallback onBrowseNextYear;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final period = selection.period;
    final expanded = selection.isPeriodSelectorExpanded;
    final expansionLabel = expanded
        ? texts.statisticsCollapsePeriodSelector
        : texts.statisticsExpandPeriodSelector;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          role: SemanticsRole.tabBar,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tab in HomeStatisticsTab.values)
                _SelectionButton(
                  label: switch (tab) {
                    HomeStatisticsTab.month => texts.statisticsMonthTab,
                    HomeStatisticsTab.year => texts.statisticsYearTab,
                  },
                  role: SemanticsRole.tab,
                  selected: selection.tab == tab,
                  onPressed: () => onTabSelected(tab),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
              child: MergeSemantics(
                child: Semantics(
                  selected: true,
                  expanded: expanded,
                  child: Tooltip(
                    message: expansionLabel,
                    child: TextButton(
                      onPressed: () => onExpandedChanged(!expanded),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _periodLabel(texts, period),
                            textAlign: TextAlign.center,
                          ),
                          if (selection.isCurrentPeriod)
                            Text(
                              texts.statisticsCurrentPeriod,
                              textAlign: TextAlign.center,
                            ),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                          ),
                        ],
                      ),
                    ),
                  ),
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
        if (expanded) ...[
          Row(
            children: [
              IconButton(
                tooltip: texts.statisticsPreviousYear,
                onPressed: selection.browsedYear.previous == null
                    ? null
                    : onBrowsePreviousYear,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _periodLabel(texts, selection.browsedYear),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: texts.statisticsNextYear,
                onPressed: selection.browsedYear.next == null
                    ? null
                    : onBrowseNextYear,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in _choices())
                _SelectionButton(
                  label: switch (choice) {
                    StatisticsMonth(:final year, :final month) =>
                      texts.statisticsMonthName(DateTime.utc(year, month)),
                    StatisticsYear() => _periodLabel(texts, choice),
                  },
                  semanticLabel: _periodLabel(texts, choice),
                  selected: choice == period,
                  currentLabel: choice.contains(selection.localDate)
                      ? texts.statisticsCurrentPeriod
                      : null,
                  onPressed: () => onPeriodSelected(choice),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Iterable<StatisticsPeriod> _choices() sync* {
    final year = selection.browsedYear.year;
    switch (selection.tab) {
      case HomeStatisticsTab.month:
        for (var month = 1; month <= 12; ++month) {
          yield StatisticsMonth(year, month);
        }
      case HomeStatisticsTab.year:
        for (var candidate = year - 5; candidate <= year + 6; ++candidate) {
          if (candidate >= CalendarDate.earliest.year &&
              candidate <= CalendarDate.latest.year) {
            yield StatisticsYear(candidate);
          }
        }
    }
  }
}

String _periodLabel(AppLocalizations texts, StatisticsPeriod period) =>
    switch (period) {
      StatisticsMonth(:final year, :final month) => texts.statisticsMonthPeriod(
        DateTime.utc(year, month),
      ),
      StatisticsYear(:final year) => texts.statisticsYearPeriod(
        DateTime.utc(year),
      ),
    };

final class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.semanticLabel,
    this.currentLabel,
    this.role = SemanticsRole.none,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final String? currentLabel;
  final VoidCallback onPressed;
  final SemanticsRole role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        role: role,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
            backgroundColor: selected ? colors.secondaryContainer : null,
            foregroundColor: selected ? colors.onSecondaryContainer : null,
          ),
          child: Semantics(
            label: [semanticLabel ?? label, ?currentLabel].join('\n'),
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) const Icon(Icons.check, size: 18),
                Text(label, textAlign: TextAlign.center),
                if (currentLabel case final current?)
                  Text(current, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
