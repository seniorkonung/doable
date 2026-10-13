import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/app_localizations.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../application/intention_statistics_breakdown.dart';
import '../application/statistics_read_contract.dart';
import 'intention_statistics_state.dart';
import 'statistics_read_notice.dart';

/// Ленивые разбивки в общей прокрутке страницы; чтения и переходы — события.
final class IntentionStatisticsBreakdownsSliver extends StatelessWidget {
  const IntentionStatisticsBreakdownsSliver({
    required this.state,
    required this.onOpenIntention,
    required this.onLoadMoreIfNeeded,
    required this.onRetry,
    required this.onRetryRefresh,
    required this.onRetryLoadMore,
    super.key,
  });

  final IntentionStatisticsState state;
  final void Function(IntentionId, StatisticsBreakdown) onOpenIntention;
  final void Function(StatisticsBreakdown, int) onLoadMoreIfNeeded;
  final VoidCallback onRetry;
  final VoidCallback onRetryRefresh;
  final ValueChanged<StatisticsBreakdown> onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final read = state.read;
    return switch (read) {
      IntentionStatisticsLoaded() => _loaded(context, read),
      IntentionStatisticsInitialLoad() => SliverToBoxAdapter(
        child: StatisticsReadNotice(message: texts.statisticsLoading),
      ),
      IntentionStatisticsNotFound() => SliverToBoxAdapter(
        child: StatisticsReadNotice(message: texts.detailsNotFound),
      ),
      IntentionStatisticsFailure(:final failure, :final canRetry) =>
        SliverToBoxAdapter(
          child: StatisticsReadNotice(
            message: statisticsReadFailureMessage(
              texts,
              failure,
              StatisticsReadStage.initial,
            ),
            onRetry: canRetry ? onRetry : null,
          ),
        ),
    };
  }

  Widget _loaded(BuildContext context, IntentionStatisticsLoaded read) {
    final texts = AppLocalizations.of(context);
    final breakdowns = read.breakdowns;
    final contribution = read.section.selectedCounts.contribution;
    Widget intentions(
      StatisticsBreakdown kind,
      IntentionStatisticsBreakdownState<StatisticsItem> breakdown,
    ) => _BreakdownSliver<StatisticsItem>(
      key: ValueKey(kind),
      title: switch (kind) {
        StatisticsBreakdown.sourceIntentions =>
          texts.statisticsBreakdownSourceIntentions,
        StatisticsBreakdown.selectedActions =>
          texts.statisticsBreakdownSelectedActions,
        StatisticsBreakdown.relations => texts.statisticsBreakdownRelations,
      },
      state: breakdown,
      canLoadMore: read.refreshStatus is IntentionStatisticsRefreshIdle,
      onLoadMoreIfNeeded: (index) => onLoadMoreIfNeeded(kind, index),
      onRetry: () => onRetryLoadMore(kind),
      itemBuilder: (item) => _BreakdownRow(
        item: item,
        contribution: contribution,
        onPressed: () => onOpenIntention(item.id, kind),
      ),
    );
    final rows = SliverMainAxisGroup(
      slivers: [
        if (breakdowns.sourceIntentions case final sources?)
          intentions(StatisticsBreakdown.sourceIntentions, sources),
        if (breakdowns.relations case final relations?)
          _BreakdownSliver<StatisticsRelationItem>(
            key: const ValueKey(StatisticsBreakdown.relations),
            title: texts.statisticsBreakdownRelations,
            state: relations,
            canLoadMore: read.refreshStatus is IntentionStatisticsRefreshIdle,
            onLoadMoreIfNeeded: (index) =>
                onLoadMoreIfNeeded(StatisticsBreakdown.relations, index),
            onRetry: () => onRetryLoadMore(StatisticsBreakdown.relations),
            itemBuilder: (relation) => _BreakdownRow(
              item: relation.relatedIntention,
              contribution: contribution,
              relationArchived: relation.scope == RelationScope.archived,
              onPressed: () => onOpenIntention(
                relation.relatedIntention.id,
                StatisticsBreakdown.relations,
              ),
            ),
          ),
        if (breakdowns.selectedActions case final actions?)
          intentions(StatisticsBreakdown.selectedActions, actions),
      ],
    );
    // Размер закреплённого сообщения следует тексту; группа ограничивает его
    // разбивками, чтобы оно не оставалось поверх групп связей страницы.
    // https://api.flutter.dev/flutter/widgets/PinnedHeaderSliver-class.html
    // https://api.flutter.dev/flutter/widgets/SliverMainAxisGroup-class.html
    return FocusTraversalGroup(
      // Повтор доступен раньше прокрученных строк, без возврата к началу.
      // https://api.flutter.dev/flutter/widgets/OrderedTraversalPolicy-class.html
      policy: OrderedTraversalPolicy(),
      child: SliverMainAxisGroup(
        slivers: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: FocusTraversalGroup(
              child: PinnedHeaderSliver(
                child: Material(
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall,
                    child: switch (read.refreshStatus) {
                      IntentionStatisticsRefreshIdle() =>
                        const SizedBox.shrink(),
                      IntentionStatisticsRefreshing() => StatisticsReadNotice(
                        message: texts.statisticsRefreshing,
                      ),
                      IntentionStatisticsRefreshFailure(
                        :final failure,
                        :final canRetry,
                      ) =>
                        StatisticsReadNotice(
                          message: switch (failure) {
                            StatisticsReadUnavailableFailure() =>
                              texts.statisticsRefreshUnavailableShort,
                            StatisticsReadCorruptionFailure() =>
                              texts.statisticsRefreshCorruptionShort,
                            StatisticsReadUnexpectedFailure() ||
                            StatisticsSnapshotExpired() ||
                            StatisticsIntentionNotFoundFailure() =>
                              texts.statisticsRefreshUnexpectedShort,
                          },
                          onRetry: canRetry ? onRetryRefresh : null,
                        ),
                    },
                  ),
                ),
              ),
            ),
          ),
          if (read is IntentionStatisticsEmpty)
            SliverToBoxAdapter(
              child: StatisticsReadNotice(message: texts.statisticsEmpty),
            ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: FocusTraversalGroup(child: rows),
          ),
        ],
      ),
    );
  }
}

final class _BreakdownSliver<T> extends StatefulWidget {
  const _BreakdownSliver({
    required this.title,
    required this.state,
    required this.itemBuilder,
    required this.onLoadMoreIfNeeded,
    required this.canLoadMore,
    required this.onRetry,
    super.key,
  });

  final String title;
  final IntentionStatisticsBreakdownState<T> state;
  final Widget Function(T) itemBuilder;
  final ValueChanged<int> onLoadMoreIfNeeded;
  final bool canLoadMore;
  final VoidCallback onRetry;

  @override
  State<_BreakdownSliver<T>> createState() => _BreakdownSliverState<T>();
}

final class _BreakdownSliverState<T> extends State<_BreakdownSliver<T>> {
  final _listKey = GlobalKey();
  bool _loadMoreScheduled = false;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                AppLocalizations.of(context)
                    .statisticsTotalItems(widget.state.totalItems),
              ),
            ],
          ),
        ),
      ),
      SliverLayoutBuilder(
        builder: (context, constraints) {
          _scheduleLoadMore();
          return SliverList.builder(
            key: _listKey,
            itemCount: widget.state.items.length,
            itemBuilder: (context, index) =>
                widget.itemBuilder(widget.state.items[index]),
          );
        },
      ),
      SliverToBoxAdapter(
        child: switch (widget.state.pageStatus) {
          IntentionStatisticsPageIdle() => const SizedBox.shrink(),
          IntentionStatisticsPageLoading() => StatisticsReadNotice(
            message: AppLocalizations.of(context).statisticsLoadingMore,
          ),
          IntentionStatisticsPageFailure(:final failure, :final canRetry) =>
            StatisticsReadNotice(
              message: statisticsReadFailureMessage(
                AppLocalizations.of(context),
                failure,
                StatisticsReadStage.more,
              ),
              onRetry: canRetry && widget.canLoadMore ? widget.onRetry : null,
            ),
        },
      ),
    ],
  );

  void _scheduleLoadMore() {
    final state = widget.state;
    if (_loadMoreScheduled ||
        !widget.canLoadMore ||
        state.nextCursor == null ||
        state.pageStatus is! IntentionStatisticsPageIdle) {
      return;
    }
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreScheduled = false;
      if (!mounted || !widget.canLoadMore || !identical(widget.state, state)) {
        return;
      }
      final list = _listKey.currentContext?.findRenderObject();
      if (list is! RenderSliverList || list.geometry?.visible != true) return;
      // Построение включает кэш и оценку скрытых списков. Подгрузке нужен
      // последний видимый индекс после компоновки, а не последний построенный.
      // https://api.flutter.dev/flutter/rendering/RenderSliverMultiBoxAdaptor/childScrollOffset.html
      int? lastVisibleIndex;
      final firstVisibleOffset = list.constraints.scrollOffset;
      final endVisibleOffset =
          firstVisibleOffset + list.constraints.remainingPaintExtent;
      for (
        var child = list.firstChild;
        child != null;
        child = list.childAfter(child)
      ) {
        final offset = list.childScrollOffset(child);
        if (offset != null &&
            offset < endVisibleOffset &&
            offset + child.size.height > firstVisibleOffset) {
          lastVisibleIndex = list.indexOf(child);
        }
      }
      if (lastVisibleIndex != null) {
        widget.onLoadMoreIfNeeded(lastVisibleIndex);
      }
    });
  }
}

final class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.item,
    required this.contribution,
    required this.onPressed,
    this.relationArchived = false,
  });

  final StatisticsItem item;
  final int contribution;
  final bool relationArchived;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final archived = item.archiveState == IntentionArchiveState.archived;
    final share = contribution == 0
        ? null
        : texts.statisticsBreakdownContributionShare(
            item.counts.contribution / contribution,
          );
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
            if (relationArchived) texts.relationNeighborhoodRelationArchived,
            texts.statisticsContributionCountsSemantics(
              item.counts.contribution,
              item.counts.planned,
            ),
            share ?? texts.statisticsBreakdownNoContributionShare,
          ].join('\n'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              if (archived) Text(texts.detailsArchived),
              if (relationArchived)
                Text(texts.relationNeighborhoodRelationArchived),
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
