import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../application/contribution_counts.dart';
import '../application/statistics_read_contract.dart';
import 'home_statistics_state.dart';
import 'statistics_read_notice.dart';
import 'statistics_view_sheet.dart';

/// Единая прокрутка выбора периода, сводки и ленивого каталога.
/// Чтениями и допустимостью повтора владеет модель страницы.
final class HomeStatisticsContent extends StatefulWidget {
  const HomeStatisticsContent({
    required this.state,
    required this.periodSelector,
    required this.onViewSelected,
    required this.onOpenIntention,
    required this.onLoadMoreIfNeeded,
    required this.onRetryFirstPage,
    required this.onRetryRefresh,
    required this.onRetryLoadMore,
    super.key,
  });

  final HomeStatisticsState state;
  final Widget periodSelector;
  final ValueChanged<StatisticsView> onViewSelected;
  final ValueChanged<IntentionId> onOpenIntention;
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
                    ..._slivers(texts, read),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _slivers(AppLocalizations texts, HomeStatisticsReadState read) =>
      switch (read) {
        HomeStatisticsPeriodEmpty() => [
          SliverToBoxAdapter(
            child: StatisticsReadNotice(message: texts.statisticsPeriodEmpty),
          ),
        ],
        HomeStatisticsData() => [
          SliverToBoxAdapter(child: _PeriodSummary(summary: read.summary)),
          _viewSelector(read.totalItems),
          SliverList.builder(
            // Ленивое построение: https://api.flutter.dev/flutter/widgets/SliverList/SliverList.builder.html
            itemCount: read.items.length,
            itemBuilder: (context, index) {
              _scheduleLoadMore(index, read);
              return _StatisticsRow(
                item: read.items[index],
                periodActions: read.summary.planned,
                onPressed: () => widget.onOpenIntention(read.items[index].id),
              );
            },
          ),
          SliverToBoxAdapter(child: _pageNotice(texts, read.pageStatus)),
        ],
        HomeStatisticsViewEmpty() => [
          SliverToBoxAdapter(child: _PeriodSummary(summary: read.summary)),
          _viewSelector(0),
          SliverToBoxAdapter(
            child: StatisticsReadNotice(
              message: texts.statisticsViewEmpty(
                widget.state.selection.view.title(texts),
              ),
            ),
          ),
        ],
        HomeStatisticsInitialLoad() => [
          _viewSelector(null),
          SliverToBoxAdapter(
            child: StatisticsReadNotice(message: texts.statisticsLoading),
          ),
        ],
        HomeStatisticsInitialFailure(:final failure, :final canRetry) => [
          _viewSelector(null),
          SliverToBoxAdapter(
            child: StatisticsReadNotice(
              message: statisticsReadFailureMessage(
                texts,
                failure,
                StatisticsReadStage.initial,
              ),
              onRetry: canRetry ? widget.onRetryFirstPage : null,
            ),
          ),
        ],
      };

  /// Выбор вида с числом его элементов; пока число не подтверждено, оно не
  /// показывается. Для вида «Через связи» над каталогом стоит пояснение.
  Widget _viewSelector(int? totalItems) {
    final view = widget.state.selection.view;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).statisticsViewLabel),
            const SizedBox(height: 8),
            _ViewSelector(
              view: view,
              totalItems: totalItems,
              onPressed: () => unawaited(
                showStatisticsViewSheet(
                  context,
                  selected: view,
                  onSelected: widget.onViewSelected,
                ),
              ),
            ),
            if (view == StatisticsView.throughRelations)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  AppLocalizations.of(context).statisticsThroughRelationsNote,
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
    HomeStatisticsRefreshing() => StatisticsReadNotice(
      message: texts.statisticsRefreshing,
      scrollMessage: true,
    ),
    HomeStatisticsRefreshFailure(:final failure, :final canRetry) =>
      StatisticsReadNotice(
        message: statisticsReadFailureMessage(
          texts,
          failure,
          StatisticsReadStage.refresh,
        ),
        scrollMessage: true,
        onRetry: canRetry ? widget.onRetryRefresh : null,
      ),
  };

  Widget _pageNotice(AppLocalizations texts, HomeStatisticsPageStatus status) =>
      switch (status) {
        HomeStatisticsPageIdle() => const SizedBox.shrink(),
        HomeStatisticsPageLoading() => StatisticsReadNotice(
          message: texts.statisticsLoadingMore,
        ),
        HomeStatisticsPageFailure(:final failure, :final canRetry) =>
          StatisticsReadNotice(
            message: statisticsReadFailureMessage(
              texts,
              failure,
              StatisticsReadStage.more,
            ),
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

final class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.summary});

  final ContributionCounts summary;

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
          Text(texts.statisticsPeriodActions(summary.planned)),
          Text(
            texts.statisticsPeriodCompleted(
              summary.contribution,
              summary.planned,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ViewSelector extends StatelessWidget {
  const _ViewSelector({
    required this.view,
    required this.totalItems,
    required this.onPressed,
  });

  final StatisticsView view;
  final int? totalItems;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    // Стандартная плитка обеспечивает фокус, клавиатуру и действие диктора.
    // https://api.flutter.dev/flutter/material/ListTile-class.html
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(view.title(texts)),
        subtitle: switch (totalItems) {
          final count? => Text(texts.statisticsTotalItems(count)),
          null => null,
        },
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: onPressed,
      ),
    );
  }
}

final class _StatisticsRow extends StatelessWidget {
  const _StatisticsRow({
    required this.item,
    required this.periodActions,
    required this.onPressed,
  });

  final StatisticsItem item;

  /// Элемент существует только при засчитанном действии периода, поэтому
  /// число действий периода положительно.
  final int periodActions;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final archived = item.archiveState == IntentionArchiveState.archived;
    final share = texts.statisticsPeriodActionsShare(
      item.counts.planned / periodActions,
    );
    // Стандартная кнопка обеспечивает фокус, клавиатуру и действие диктора.
    // https://api.flutter.dev/flutter/material/TextButton-class.html
    return Card(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(12),
        ),
        child: Semantics(
          excludeSemantics: true,
          label: [
            item.title,
            if (archived) texts.detailsArchived,
            texts.statisticsContributionCountsSemantics(
              item.counts.contribution,
              item.counts.planned,
            ),
            share,
          ].join('\n'),
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
              Text(share),
            ],
          ),
        ),
      ),
    );
  }
}
