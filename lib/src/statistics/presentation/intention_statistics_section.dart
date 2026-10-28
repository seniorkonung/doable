import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/routing/app_router.gr.dart';
import '../../intention/presentation/details/intention_page_target.dart';
import '../application/intention_statistics_target.dart';
import '../application/statistics_read_contract.dart';
import 'intention_statistics_breakdowns.dart';
import 'intention_statistics_overview.dart';
import 'intention_statistics_state.dart';
import 'intention_statistics_view_model.dart';
import 'statistics_read_notice.dart';

/// Композиция раздела в общей прокрутке; состояние принадлежит странице.
final class IntentionStatisticsSectionSliver extends ConsumerWidget {
  const IntentionStatisticsSectionSliver({required this.provider, super.key});

  final IntentionStatisticsViewModelProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final texts = AppLocalizations.of(context);
    final refreshStatus = switch (state.read) {
      IntentionStatisticsLoaded(:final refreshStatus) => refreshStatus,
      _ => const IntentionStatisticsRefreshIdle(),
    };
    return FocusTraversalGroup(
      // Повтор доступен раньше обзора и прокрученных строк.
      // https://api.flutter.dev/flutter/widgets/OrderedTraversalPolicy-class.html
      policy: OrderedTraversalPolicy(),
      child: SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        // Группа ограничивает закреплённое сообщение всем разделом статистики.
        // https://api.flutter.dev/flutter/widgets/SliverMainAxisGroup-class.html
        sliver: SliverMainAxisGroup(
          slivers: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: FocusTraversalGroup(
                // Высота следует локализованному тексту и доступной команде.
                // https://api.flutter.dev/flutter/widgets/PinnedHeaderSliver-class.html
                child: PinnedHeaderSliver(
                  child: Material(
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.bodySmall,
                      child: switch (refreshStatus) {
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
                            onRetry: canRetry ? model.retryRefresh : null,
                          ),
                      },
                    ),
                  ),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: FocusTraversalGroup(
                child: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: IntentionStatisticsOverview(
                        state: state,
                        onModeSelected: model.selectMode,
                        onPreviousPeriod: model.selectPreviousPeriod,
                        onNextPeriod: model.selectNextPeriod,
                        onViewSelected: model.selectView,
                        onMonthSelected: model.selectMonth,
                        onDaySelected: (date) => context.router.push(
                          DailyChoiceDateCatalogRoute(date: date),
                        ),
                      ),
                    ),
                    IntentionStatisticsBreakdownsSliver(
                      state: state,
                      onOpenIntention: (id, breakdown) => context.router.push(
                        IntentionDetailsRoute(
                          intentionId: id,
                          target: StatisticsTarget(
                            IntentionStatisticsTarget.forBreakdown(
                              breakdown: breakdown,
                              period: state.selection.period,
                            ),
                          ),
                        ),
                      ),
                      onLoadMoreIfNeeded: model.loadMoreIfNeeded,
                      onRetry: model.retry,
                      onRetryLoadMore: model.retryLoadMore,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
