import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routing/app_router.gr.dart';
import '../application/intention_statistics_target.dart';
import 'intention_statistics_breakdowns.dart';
import 'intention_statistics_overview.dart';
import 'intention_statistics_view_model.dart';

/// Композиция раздела в общей прокрутке; состояние принадлежит странице.
final class IntentionStatisticsSectionSliver extends ConsumerWidget {
  const IntentionStatisticsSectionSliver({required this.provider, super.key});

  final IntentionStatisticsViewModelProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    // Обзор и ленивые разбивки остаются частью одной прокрутки страницы.
    // https://api.flutter.dev/flutter/widgets/SliverMainAxisGroup-class.html
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: IntentionStatisticsOverview(
              state: state,
              onModeSelected: model.selectMode,
              onPreviousPeriod: model.selectPreviousPeriod,
              onNextPeriod: model.selectNextPeriod,
              onViewSelected: model.selectView,
              onMonthSelected: model.selectMonth,
            ),
          ),
          IntentionStatisticsBreakdownsSliver(
            state: state,
            onOpenIntention: (id, breakdown) => context.router.push(
              IntentionDetailsRoute(
                intentionId: id,
                statisticsTarget: IntentionStatisticsTarget.forBreakdown(
                  breakdown: breakdown,
                  period: state.selection.period,
                ),
              ),
            ),
            onLoadMoreIfNeeded: model.loadMoreIfNeeded,
            onRetry: model.retry,
            onRetryRefresh: model.retryRefresh,
            onRetryLoadMore: model.retryLoadMore,
          ),
        ],
      ),
    );
  }
}
