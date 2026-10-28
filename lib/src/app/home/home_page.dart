import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_icon.dart';
import '../../intention/presentation/details/intention_page_target.dart';
import '../../statistics/application/intention_statistics_target.dart';
import '../../statistics/presentation/home_statistics_content.dart';
import '../../statistics/presentation/home_statistics_period_selector.dart';
import '../../statistics/presentation/home_statistics_view_model.dart';
import '../navigation/app_destination.dart';
import '../routing/app_router.gr.dart';

@RoutePage()
final class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

final class _HomePageState extends ConsumerState<HomePage> {
  late final DailyChoiceLocalDayObserver _localDay;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => ref
          .read(homeStatisticsViewModelProvider.notifier)
          .setLocalDate(_localDay.today),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Вкладки оболочки сохраняются в дереве, поэтому одного ModalRoute мало.
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/AutoTabsRouter/of.html
    final tabs = AutoTabsRouter.of(context, watch: true);
    // Следит также за безымянными маршрутами, например диалогами над Главной.
    // https://api.flutter.dev/flutter/widgets/ModalRoute/isCurrentOf.html
    _visible =
        tabs.activeIndex == AppDestination.home.index &&
        ModalRoute.isCurrentOf(context) == true;
    // Модель уведомляет слушателей: обновление выполняется после построения.
    scheduleMicrotask(() {
      if (!mounted) return;
      final model = ref.read(homeStatisticsViewModelProvider.notifier);
      model.setLocalDate(_localDay.today);
      model.setVisible(_visible);
    });
  }

  @override
  void dispose() {
    _localDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(homeStatisticsViewModelProvider);
    final model = ref.read(homeStatisticsViewModelProvider.notifier);
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppDestination.home.title(localizations)),
        actions: [
          IconButton(
            tooltip: localizations.settingsTitle,
            onPressed: () => context.router.push(const SettingsRoute()),
            icon: DoableIcon(
              DoableIconData.settings,
              size: 22,
              color: colors.ink,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: HomeStatisticsContent(
          state: state,
          periodSelector: HomeStatisticsPeriodSelector(
            selection: state.selection,
            onTabSelected: model.selectTab,
            onPeriodSelected: model.selectPeriod,
            onPreviousPeriod: model.selectPreviousPeriod,
            onNextPeriod: model.selectNextPeriod,
            onExpandedChanged: model.setPeriodSelectorExpanded,
            onBrowsePreviousYear: model.browsePreviousYear,
            onBrowseNextYear: model.browseNextYear,
          ),
          onViewSelected: model.selectView,
          onOpenIntention: (id) => context.router.push(
            IntentionDetailsRoute(
              intentionId: id,
              target: StatisticsTarget(
                IntentionStatisticsTarget(
                  view: state.selection.view,
                  period: state.selection.period,
                ),
              ),
            ),
          ),
          onLoadMoreIfNeeded: model.loadMoreIfNeeded,
          onRetryFirstPage: model.retryFirstPage,
          onRetryRefresh: model.retryRefresh,
          onRetryLoadMore: model.retryLoadMore,
        ),
      ),
    );
  }
}
