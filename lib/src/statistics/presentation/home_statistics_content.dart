import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../intention/domain/intention.dart';
import '../application/contribution_counts.dart';
import '../application/statistics_read_contract.dart';
import 'home_statistics_state.dart';

/// Единая прокрутка выбора периода, сводки и ленивого каталога.
/// Чтениями и допустимостью повтора владеет модель страницы.
final class HomeStatisticsContent extends StatefulWidget {
  const HomeStatisticsContent({
    required this.state,
    required this.periodSelector,
    required this.onViewSelected,
    required this.onLoadMoreIfNeeded,
    required this.onRetryFirstPage,
    required this.onRetryRefresh,
    required this.onRetryLoadMore,
    super.key,
  });

  final HomeStatisticsState state;
  final Widget periodSelector;
  final ValueChanged<StatisticsView> onViewSelected;
  final ValueChanged<int> onLoadMoreIfNeeded;
  final VoidCallback onRetryFirstPage;
  final VoidCallback onRetryRefresh;
  final VoidCallback onRetryLoadMore;

  @override
  State<HomeStatisticsContent> createState() => _HomeStatisticsContentState();
}

final class _HomeStatisticsContentState extends State<HomeStatisticsContent> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(HomeStatisticsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state.selection;
    final after = widget.state.selection;
    if ((before.period != after.period || before.view != after.view) &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final read = widget.state.read;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: widget.periodSelector),
              if (read case HomeStatisticsLoaded(:final summary))
                SliverToBoxAdapter(child: _PeriodSummary(summary: summary)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(texts.statisticsViewLabel),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final view in StatisticsView.values)
                            _ViewButton(
                              view: view,
                              selected: widget.state.selection.view == view,
                              onPressed: () => widget.onViewSelected(view),
                            ),
                        ],
                      ),
                      if (read case HomeStatisticsLoaded(:final totalItems))
                        Text(texts.statisticsTotalItems(totalItems)),
                    ],
                  ),
                ),
              ),
              if (read case HomeStatisticsData())
                SliverList.builder(
                  itemCount: read.items.length,
                  itemBuilder: (context, index) => _StatisticsRow(
                    item: read.items[index],
                    periodContribution: read.summary.counts.contribution,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Text(
                    read is HomeStatisticsEmpty
                        ? texts.statisticsEmpty
                        : texts.statisticsLoading,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.summary});

  final StatisticsPeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              texts.statisticsPeriodSummary,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Text(texts.statisticsPlannedContribution(summary.counts.planned)),
          Text(texts.statisticsContribution(summary.counts.contribution)),
          Text(texts.statisticsMissed(summary.uncompleted.missed)),
          Text(texts.statisticsUpcoming(summary.uncompleted.upcoming)),
        ],
      ),
    );
  }
}

final class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.view,
    required this.selected,
    required this.onPressed,
  });

  final StatisticsView view;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final label = switch (view) {
      StatisticsView.sourceIntentions => texts.statisticsSourceIntentions,
      StatisticsView.intermediateIntentions =>
        texts.statisticsIntermediateIntentions,
      StatisticsView.selectedActions => texts.statisticsSelectedActions,
    };
    final colors = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
            backgroundColor: selected ? colors.secondaryContainer : null,
            foregroundColor: selected ? colors.onSecondaryContainer : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) const Icon(Icons.check, size: 18),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

final class _StatisticsRow extends StatelessWidget {
  const _StatisticsRow({required this.item, required this.periodContribution});

  final StatisticsItem item;
  final int periodContribution;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final archived = item.archiveState == IntentionArchiveState.archived;
    final share = periodContribution == 0
        ? null
        : texts.statisticsContributionShare(
            item.counts.contribution / periodContribution,
          );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        item.title,
        if (archived) texts.detailsArchived,
        texts.statisticsContributionCountsSemantics(
          item.counts.contribution,
          item.counts.planned,
        ),
        share ?? texts.statisticsNoContributionShare,
      ].join('\n'),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              if (archived) Text(texts.detailsArchived),
              Text(
                texts.statisticsContributionCounts(
                  item.counts.contribution,
                  item.counts.planned,
                ),
              ),
              if (share != null) Text(share),
            ],
          ),
        ),
      ),
    );
  }
}
