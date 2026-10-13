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
  int? _loadMoreIndex;

  @override
  void didUpdateWidget(HomeStatisticsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state.selection;
    final after = widget.state.selection;
    if (before.period != after.period || before.view != after.view) {
      // AppBar слушает прокрутку: уведомлять его во время build нельзя.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
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
    return Padding(
      padding: const EdgeInsets.all(16),
      // Сообщение занимает место над каталогом и не перекрывает его строки.
      // https://api.flutter.dev/flutter/widgets/Expanded-class.html
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (read case HomeStatisticsLoaded(:final refreshStatus))
              // Даже при крупном тексте остаётся место для прежних строк.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight / 2,
                ),
                child: _refreshNotice(texts, refreshStatus),
              ),
            Expanded(
              // Обход каталога не ставит его невидимые кнопки перед повтором.
              // https://api.flutter.dev/flutter/widgets/FocusTraversalGroup-class.html
              child: FocusTraversalGroup(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: widget.periodSelector),
                    if (read case HomeStatisticsLoaded(:final summary))
                      SliverToBoxAdapter(
                        child: _PeriodSummary(summary: summary),
                      ),
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
                                    selected:
                                        widget.state.selection.view == view,
                                    onPressed: () =>
                                        widget.onViewSelected(view),
                                  ),
                              ],
                            ),
                            if (read case HomeStatisticsLoaded(
                              :final totalItems,
                            ))
                              Text(texts.statisticsTotalItems(totalItems)),
                          ],
                        ),
                      ),
                    ),
                    switch (read) {
                      HomeStatisticsData() => SliverList.builder(
                        // Ленивое построение: https://api.flutter.dev/flutter/widgets/SliverList/SliverList.builder.html
                        itemCount: read.items.length,
                        itemBuilder: (context, index) {
                          _scheduleLoadMore(index, read);
                          return _StatisticsRow(
                            item: read.items[index],
                            periodContribution:
                                read.summary.counts.contribution,
                          );
                        },
                      ),
                      HomeStatisticsInitialLoad() => SliverToBoxAdapter(
                        child: _ReadNotice(message: texts.statisticsLoading),
                      ),
                      HomeStatisticsInitialFailure(
                        :final failure,
                        :final canRetry,
                      ) =>
                        SliverToBoxAdapter(
                          child: _ReadNotice(
                            message: _failureMessage(
                              texts,
                              failure,
                              _ReadStage.initial,
                            ),
                            onRetry: canRetry ? widget.onRetryFirstPage : null,
                          ),
                        ),
                      HomeStatisticsEmpty() => SliverToBoxAdapter(
                        child: _ReadNotice(message: texts.statisticsEmpty),
                      ),
                    },
                    if (read case HomeStatisticsData(:final pageStatus))
                      SliverToBoxAdapter(child: _pageNotice(texts, pageStatus)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshNotice(
    AppLocalizations texts,
    HomeStatisticsRefreshStatus status,
  ) => switch (status) {
    HomeStatisticsRefreshIdle() => const SizedBox.shrink(),
    HomeStatisticsRefreshing() => _ReadNotice(
      message: texts.statisticsRefreshing,
      scrollMessage: true,
    ),
    HomeStatisticsRefreshFailure(:final failure, :final canRetry) =>
      _ReadNotice(
        message: _failureMessage(texts, failure, _ReadStage.refresh),
        scrollMessage: true,
        onRetry: canRetry ? widget.onRetryRefresh : null,
      ),
  };

  Widget _pageNotice(AppLocalizations texts, HomeStatisticsPageStatus status) =>
      switch (status) {
        HomeStatisticsPageIdle() => const SizedBox.shrink(),
        HomeStatisticsPageLoading() => _ReadNotice(
          message: texts.statisticsLoadingMore,
        ),
        HomeStatisticsPageFailure(:final failure, :final canRetry) =>
          _ReadNotice(
            message: _failureMessage(texts, failure, _ReadStage.more),
            onRetry: canRetry ? widget.onRetryLoadMore : null,
          ),
      };

  void _scheduleLoadMore(int index, HomeStatisticsData read) {
    if (read.nextCursor == null) return;
    final scheduled = _loadMoreIndex != null;
    _loadMoreIndex = index;
    if (scheduled) return;
    // Модель уведомляется после компоновки, чтобы не менять её во время build.
    // https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lastIndex = _loadMoreIndex;
      _loadMoreIndex = null;
      if (mounted && identical(widget.state.read, read) && lastIndex != null) {
        widget.onLoadMoreIfNeeded(lastIndex);
      }
    });
  }
}

enum _ReadStage { initial, refresh, more }

String _failureMessage(
  AppLocalizations texts,
  StatisticsReadFailure failure,
  _ReadStage stage,
) => switch ((stage, failure)) {
  (_ReadStage.initial, StatisticsReadUnavailableFailure()) =>
    texts.statisticsUnavailable,
  (_ReadStage.initial, StatisticsReadCorruptionFailure()) =>
    texts.statisticsCorruption,
  (
    _ReadStage.initial,
    StatisticsReadUnexpectedFailure() || StatisticsSnapshotExpired(),
  ) =>
    texts.statisticsUnexpectedFailure,
  (_ReadStage.refresh, StatisticsReadUnavailableFailure()) =>
    texts.statisticsRefreshUnavailable,
  (_ReadStage.refresh, StatisticsReadCorruptionFailure()) =>
    texts.statisticsRefreshCorruption,
  (
    _ReadStage.refresh,
    StatisticsReadUnexpectedFailure() || StatisticsSnapshotExpired(),
  ) =>
    texts.statisticsRefreshUnexpectedFailure,
  (_ReadStage.more, StatisticsReadUnavailableFailure()) =>
    texts.statisticsLoadMoreUnavailable,
  (_ReadStage.more, StatisticsReadCorruptionFailure()) =>
    texts.statisticsLoadMoreCorruption,
  (
    _ReadStage.more,
    StatisticsReadUnexpectedFailure() || StatisticsSnapshotExpired(),
  ) =>
    texts.statisticsLoadMoreUnexpectedFailure,
};

final class _ReadNotice extends StatelessWidget {
  const _ReadNotice({
    required this.message,
    this.onRetry,
    this.scrollMessage = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool scrollMessage;

  @override
  Widget build(BuildContext context) {
    final notice = Semantics(
      // Сообщает об обновлении без переноса доступного фокуса.
      // https://api.flutter.dev/flutter/semantics/SemanticsProperties/liveRegion.html
      liveRegion: true,
      child: Text(message),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scrollMessage)
            Flexible(
              // Крупный текст прокручивается отдельно; повтор остаётся видимым.
              // https://api.flutter.dev/flutter/widgets/SingleChildScrollView-class.html
              child: SingleChildScrollView(primary: false, child: notice),
            )
          else
            notice,
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
        ],
      ),
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
      StatisticsView.throughRelations => texts.statisticsThroughRelations,
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
