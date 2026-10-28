import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/ordinary_page_scaffold.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../daily_choice/application/choice_path_draft.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../../design_system/components/page_head.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/presentation/editor/relation_editor_state.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import '../../../tag/presentation/assignments/tag_assignments_section.dart';
import '../../../tag/presentation/panel/tags_panel.dart';
import '../../../tag/presentation/panel/tags_panel_context.dart';
import '../../../statistics/presentation/intention_statistics_section.dart';
import '../../../statistics/presentation/intention_statistics_view_model.dart';
import 'intention_details_state.dart';
import 'intention_details_view_model.dart';
import 'intention_details_tabs.dart';
import 'intention_page_target.dart';

@RoutePage()
final class IntentionDetailsPage extends ConsumerStatefulWidget {
  const IntentionDetailsPage({
    required this.intentionId,
    this.target = const OverviewTarget(),
    super.key,
  });

  final IntentionId intentionId;
  final IntentionPageTarget target;

  @override
  ConsumerState<IntentionDetailsPage> createState() =>
      _IntentionDetailsPageState();
}

final class _IntentionDetailsPageState
    extends ConsumerState<IntentionDetailsPage> {
  final _headKey = GlobalKey();
  final _scrollController = ScrollController();
  final _headHidden = ValueNotifier(false);
  double? _headExtent;
  var _headMeasurementScheduled = false;
  late IntentionPageInstance _pageInstance;
  late final DailyChoiceLocalDayObserver _localDay;
  var _routeIsCurrent = false;
  late IntentionDetailsTab _selectedTab;
  ProviderSubscription<RelationNeighborhoodState>? _neighborhoodSubscription;

  IntentionStatisticsViewModelProvider get _statisticsProvider =>
      intentionStatisticsViewModelProvider(
        widget.intentionId,
        _pageInstance,
        target: switch (_pageInstance.target) {
          StatisticsTarget(:final statistics) => statistics,
          OverviewTarget() || RelationsTarget() => null,
        },
      );

  @override
  void initState() {
    super.initState();
    _startPageInstance();
    _scrollController.addListener(_syncHeadHidden);
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () =>
          ref.read(_statisticsProvider.notifier).setLocalDate(_localDay.today),
    );
  }

  void _startPageInstance() {
    _pageInstance = IntentionPageInstance(target: widget.target);
    _selectedTab = switch (_pageInstance.target) {
      OverviewTarget() => IntentionDetailsTab.overview,
      RelationsTarget() => IntentionDetailsTab.relations,
      StatisticsTarget() => IntentionDetailsTab.statistics,
    };
    if (_selectedTab == IntentionDetailsTab.relations) _retainNeighborhood();
  }

  void _retainNeighborhood() {
    // Подписка удерживает соседство с первого показа до закрытия страницы.
    // https://pub.dev/documentation/flutter_riverpod/latest/flutter_riverpod/WidgetRef/listenManual.html
    _neighborhoodSubscription ??= ref.listenManual(
      relationNeighborhoodViewModelProvider(widget.intentionId),
      (_, _) {},
    );
  }

  void _selectTab(IntentionDetailsTab tab) {
    if (tab == _selectedTab) return;
    if (_headHidden.value) {
      // https://api.flutter.dev/flutter/widgets/ScrollController/jumpTo.html
      _scrollController.jumpTo(_headExtent!);
    }
    if (tab == IntentionDetailsTab.relations) {
      _retainNeighborhood();
    }
    setState(() {
      _selectedTab = tab;
    });
    _syncStatisticsVisibility();
  }

  void _showArchivedRelations() {
    final details = ref.read(
      intentionDetailsViewModelProvider(widget.intentionId),
    );
    if (details is! IntentionDetailsLoaded) return;
    _selectTab(IntentionDetailsTab.relations);
    ref
        .read(
          relationNeighborhoodViewModelProvider(widget.intentionId).notifier,
        )
        .showArchivedRelations(details.details.relationCounts);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Учитывает также диалоги и удаление маршрута до конца его анимации.
    // https://api.flutter.dev/flutter/widgets/ModalRoute/isCurrentOf.html
    _routeIsCurrent = ModalRoute.isCurrentOf(context) == true;
    _syncStatisticsVisibility();
    if (_routeIsCurrent) _refreshOperationRunning();
  }

  /// Пока страница была скрыта, например экраном изменения, координатор мог
  /// принять команду намерения не от её модели. Блок тегов перечитывает
  /// занятость в перестройке, которую вызывает новое состояние модели.
  void _refreshOperationRunning() {
    scheduleMicrotask(() {
      if (!mounted) return;
      ref
          .read(intentionDetailsViewModelProvider(widget.intentionId).notifier)
          .refreshOperationRunning();
    });
  }

  void _syncStatisticsVisibility() {
    scheduleMicrotask(() {
      if (!mounted) return;
      final model = ref.read(_statisticsProvider.notifier);
      model.setLocalDate(_localDay.today);
      model.setVisible(
        _routeIsCurrent && _selectedTab == IntentionDetailsTab.statistics,
      );
    });
  }

  @override
  void dispose() {
    _localDay.dispose();
    _scrollController.dispose();
    _headHidden.dispose();
    super.dispose();
  }

  void _syncHeadHidden() {
    final extent = _headExtent;
    _headHidden.value =
        extent != null &&
        _scrollController.hasClients &&
        _scrollController.offset >= extent;
  }

  void _scheduleHeadMeasurement() {
    if (_headMeasurementScheduled) return;
    _headMeasurementScheduled = true;
    // Первую высоту и изменения размера читаем после завершения раскладки:
    // https://api.flutter.dev/flutter/widgets/SizeChangedLayoutNotifier-class.html
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _headMeasurementScheduled = false;
      if (!mounted) return;
      _headExtent = _headKey.currentContext?.size?.height;
      _syncHeadHidden();
    });
  }

  /// Модель могла ещё не отразить команду, которую координатор принял не от
  /// этой страницы, поэтому перед открытием занятость читается у него.
  void _openEdit() {
    final intentionId = widget.intentionId;
    final details = ref.read(intentionDetailsViewModelProvider(intentionId));
    if (details is! IntentionDetailsLoaded ||
        !_canOpenEdit(details) ||
        ref
            .read(graphCommandCoordinatorProvider.notifier)
            .isRunning(intentionId)) {
      return;
    }
    unawaited(
      context.router.push(IntentionEditRoute(intentionId: intentionId)),
    );
  }

  bool _canOpenEdit(IntentionDetailsLoaded loaded) =>
      !loaded.isOperationRunning && !loaded.isAwaitingConfirmedSnapshot;

  Widget _buildHead(IntentionDetailsLoaded loaded) {
    final name = loaded.intention.title;
    _scheduleHeadMeasurement();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleHeadMeasurement();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        key: _headKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space5),
          child: PageHead(
            key: const ValueKey('intention-details-title'),
            name: name,
            editLabel: AppLocalizations.of(context).detailsEditTitleLabel(name),
            onEdit: _canOpenEdit(loaded) ? _openEdit : null,
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant IntentionDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentionId != widget.intentionId) {
      _neighborhoodSubscription?.close();
      _neighborhoodSubscription = null;
      _startPageInstance();
      _headExtent = null;
      _headHidden.value = false;
      _syncStatisticsVisibility();
    }
  }

  Future<void> _delete() async {
    if (!mounted) return;
    final intentionId = widget.intentionId;
    final deleted = await ref
        .read(intentionDetailsViewModelProvider(intentionId).notifier)
        .delete();
    // Результат принадлежит принявшему удаление экземпляру страницы.
    // После ожидания сброшенный маршрут уже не вправе менять историю,
    // даже если обратная анимация ещё удерживает его виджет.
    // ModalRoute.of подписывает страницу на изменения маршрута,
    // поэтому обращаемся к нему только перед успешным закрытием.
    if (deleted &&
        mounted &&
        widget.intentionId == intentionId &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      context.router.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final intentionId = widget.intentionId;
    final localizations = AppLocalizations.of(context);
    final provider = intentionDetailsViewModelProvider(intentionId);
    final details = ref.watch(provider);
    // Подписка принадлежит странице, в том числе пока её данные загружаются.
    ref.watch(_statisticsProvider);
    return OrdinaryPageScaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(DoableMetrics.tapMin),
        // Флаг прокрутки перестраивает только панель, сохраняя тело страницы:
        // https://api.flutter.dev/flutter/widgets/ValueListenableBuilder-class.html
        child: ValueListenableBuilder(
          valueListenable: _headHidden,
          builder: (context, headHidden, _) {
            final backLabel = MaterialLocalizations.of(context)
                .backButtonTooltip;
            void onBack() => context.router.pop();
            if (details is! IntentionDetailsLoaded) {
              return TopBar.withoutTitle(
                routeName: localizations.detailsTitle,
                backLabel: backLabel,
                onBack: onBack,
              );
            }
            final intention = details.intention;
            final (type, typeIcon) = switch (intention.readiness) {
              IntentionReadiness.ready => (
                localizations.detailsTypeAction,
                DoableIconData.bolt,
              ),
              IntentionReadiness.notReady => (
                localizations.detailsTypeIntention,
                DoableIconData.intention,
              ),
            };
            return TopBar.back(
              title: headHidden ? intention.title : type,
              titleIcon: headHidden ? null : typeIcon,
              muted:
                  headHidden &&
                  intention.archiveState == IntentionArchiveState.archived,
              backLabel: backLabel,
              onBack: onBack,
            );
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (details.isOperationRunning) const _RunningOperationStatus(),
            Expanded(
              child: _DetailsContent(
                intentionId: intentionId,
                state: details,
                scrollController: _scrollController,
                buildHead: _buildHead,
                headHidden: _headHidden,
                selectedTab: _selectedTab,
                onSelectTab: _selectTab,
                statisticsSection: IntentionStatisticsSectionSliver(
                  provider: _statisticsProvider,
                ),
                onDelete: _delete,
                onShowArchivedRelations: _showArchivedRelations,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _RunningOperationStatus extends StatelessWidget {
  const _RunningOperationStatus();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(localizations.detailsOperationRunning)),
          ],
        ),
      ),
    );
  }
}

final class _DetailsContent extends ConsumerWidget {
  const _DetailsContent({
    required this.intentionId,
    required this.state,
    required this.scrollController,
    required this.buildHead,
    required this.headHidden,
    required this.selectedTab,
    required this.onSelectTab,
    required this.statisticsSection,
    required this.onDelete,
    required this.onShowArchivedRelations,
  });

  final IntentionId intentionId;
  final IntentionDetailsState state;
  final ScrollController scrollController;
  final Widget Function(IntentionDetailsLoaded loaded) buildHead;
  final ValueListenable<bool> headHidden;
  final IntentionDetailsTab selectedTab;
  final ValueChanged<IntentionDetailsTab> onSelectTab;
  final Widget statisticsSection;
  final VoidCallback onDelete;
  final VoidCallback onShowArchivedRelations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionDetailsLoading() => _DetailsStatus(
        message: localizations.detailsLoading,
        progressIndicator: true,
      ),
      final IntentionDetailsLoaded loaded => _LoadedDetails(
        state: loaded,
        scrollController: scrollController,
        pageHead: buildHead(loaded),
        headHidden: headHidden,
        selectedTab: selectedTab,
        onSelectTab: onSelectTab,
        statisticsSection: statisticsSection,
        onEnableReadiness: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .enableReadiness,
        onDisableReadiness: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .disableReadiness,
        onArchive: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .archive,
        onRestore: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .restore,
        onDelete: onDelete,
        onShowArchivedRelations: onShowArchivedRelations,
      ),
      IntentionDetailsNotFound() => _DetailsStatus(
        message: localizations.detailsNotFound,
      ),
      IntentionDetailsUnavailable() => _DetailsStatus(
        message: localizations.detailsUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .retry,
      ),
      IntentionDetailsCorruption() => _DetailsStatus(
        message: localizations.detailsCorruption,
      ),
      IntentionDetailsUnexpected() => _DetailsStatus(
        message: localizations.detailsUnexpected,
      ),
      IntentionDetailsDeleted() => _DetailsStatus(
        message: localizations.detailsNotFound,
      ),
    };
  }
}

final class _LoadedDetails extends StatelessWidget {
  const _LoadedDetails({
    required this.state,
    required this.scrollController,
    required this.pageHead,
    required this.headHidden,
    required this.selectedTab,
    required this.onSelectTab,
    required this.statisticsSection,
    required this.onEnableReadiness,
    required this.onDisableReadiness,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onShowArchivedRelations,
  });

  final IntentionDetailsLoaded state;
  final ScrollController scrollController;
  final Widget pageHead;
  final ValueListenable<bool> headHidden;
  final IntentionDetailsTab selectedTab;
  final ValueChanged<IntentionDetailsTab> onSelectTab;
  final Widget statisticsSection;
  final VoidCallback onEnableReadiness;
  final VoidCallback onDisableReadiness;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onShowArchivedRelations;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final intention = state.intention;
    final readiness = switch (intention.readiness) {
      IntentionReadiness.ready => localizations.catalogReady,
      IntentionReadiness.notReady => localizations.catalogNotReady,
    };
    final archiveState = switch (intention.archiveState) {
      IntentionArchiveState.active => localizations.detailsActive,
      IntentionArchiveState.archived => localizations.detailsArchived,
    };
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(child: pageHead),
        IntentionDetailsTabs(
          headHidden: headHidden,
          value: selectedTab,
          onChange: onSelectTab,
          counts: state.details.relationCounts,
        ),
        IntentionDetailsTabBody(
          slivers: [
            if (selectedTab == IntentionDetailsTab.overview) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailsField(
                        label: localizations.detailsDescriptionLabel,
                        value:
                            intention.description ??
                            localizations.detailsNoDescription,
                      ),
                      const SizedBox(height: 16),
                      _DetailsField(
                        label: localizations.detailsReadinessLabel,
                        value: readiness,
                      ),
                      const SizedBox(height: 16),
                      _DetailsField(
                        label: localizations.detailsArchiveStateLabel,
                        value: archiveState,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _DetailsActions(
                    state: state,
                    onEnableReadiness: onEnableReadiness,
                    onDisableReadiness: onDisableReadiness,
                    onArchive: onArchive,
                    onRestore: onRestore,
                    onDelete: onDelete,
                    onShowArchivedRelations: onShowArchivedRelations,
                    onChoosePath: () => unawaited(
                      context.router.push(
                        ChoicePathRoute(
                          sourceIntentionId: intention.id,
                          direction: ChoicePathDraftDirection.topDown,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: TagAssignmentsSection(
                    intentionId: intention.id,
                    isArchived:
                        intention.archiveState ==
                        IntentionArchiveState.archived,
                    onChooseTag: (intentionId) => unawaited(
                      showTagsPanel(
                        context,
                        TagsPanelAssignmentContext(intentionId),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (selectedTab == IntentionDetailsTab.statistics)
              statisticsSection,
            if (selectedTab == IntentionDetailsTab.relations)
              RelationNeighborhoodSliver(
                intentionId: intention.id,
                onOpenRelation: (relationId) => unawaited(
                  context.router.push(
                    RelationDetailsRoute(relationId: relationId),
                  ),
                ),
                onOpenDailyChoice: (choiceId) => unawaited(
                  context.router.push(
                    DailyChoiceDetailsRoute(choiceId: choiceId),
                  ),
                ),
                onCreateRelation: (direction) => unawaited(
                  context.router.push(
                    RelationEditorRoute(
                      editorContext: RelationCreationContext(
                        participant: RelationParticipantSummary(
                          id: intention.id,
                          title: intention.title,
                          archiveState: intention.archiveState,
                        ),
                        direction: direction,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

final class _DetailsActions extends StatelessWidget {
  const _DetailsActions({
    required this.state,
    required this.onEnableReadiness,
    required this.onDisableReadiness,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onShowArchivedRelations,
    required this.onChoosePath,
  });

  final IntentionDetailsLoaded state;
  final VoidCallback onEnableReadiness;
  final VoidCallback onDisableReadiness;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onShowArchivedRelations;
  final VoidCallback onChoosePath;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final controlsEnabled = !state.isOperationRunning;
    final isArchived =
        state.intention.archiveState == IntentionArchiveState.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Переход состояния объясняется до его запуска: архивирование
        // каскадно архивирует связи, а восстановление их не возвращает.
        if (isArchived)
          _RelationImpactExplanation(
            explanationKey: const ValueKey(
              'intention-details-restore-explanation',
            ),
            message: localizations.detailsRestoreRelationsExplanation(
              state.details.relationCounts.archived,
            ),
            actionKey: const ValueKey(
              'intention-details-show-archived-relations',
            ),
            actionLabel: localizations.detailsShowArchivedRelationsAction,
            onAction: onShowArchivedRelations,
          )
        else
          _RelationImpactExplanation(
            explanationKey: const ValueKey(
              'intention-details-archive-explanation',
            ),
            message: localizations.detailsArchiveCascadeExplanation,
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (!isArchived)
              FilledButton.icon(
                key: const ValueKey('intention-details-choose-path'),
                onPressed: controlsEnabled ? onChoosePath : null,
                icon: const Icon(Icons.route_outlined),
                label: Text(localizations.detailsChoosePathAction),
              ),
            if (state.intention.readiness == IntentionReadiness.notReady)
              OutlinedButton.icon(
                key: const ValueKey('intention-details-enable-readiness'),
                onPressed: controlsEnabled
                    ? () => unawaited(_confirmReadiness(context))
                    : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(localizations.detailsEnableReadinessAction),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('intention-details-disable-readiness'),
                onPressed: controlsEnabled ? onDisableReadiness : null,
                icon: const Icon(Icons.remove_circle_outline),
                label: Text(localizations.detailsDisableReadinessAction),
              ),
            if (state.intention.archiveState == IntentionArchiveState.active)
              OutlinedButton.icon(
                key: const ValueKey('intention-details-archive'),
                onPressed: controlsEnabled ? onArchive : null,
                icon: const Icon(Icons.archive_outlined),
                label: Text(localizations.detailsArchiveAction),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('intention-details-restore'),
                onPressed: controlsEnabled ? onRestore : null,
                icon: const Icon(Icons.unarchive_outlined),
                label: Text(localizations.detailsRestoreAction),
              ),
            FilledButton.icon(
              key: const ValueKey('intention-details-delete'),
              onPressed: controlsEnabled
                  ? () => unawaited(_confirmDeletion(context))
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(localizations.detailsDeleteAction),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReadiness(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.detailsReadinessConfirmationTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.detailsReadinessOneDayCriterion),
            const SizedBox(height: 12),
            Text(localizations.detailsReadinessClarityCriterion),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.detailsCancelEditAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.detailsConfirmReadinessAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onEnableReadiness();
    }
  }

  Future<void> _confirmDeletion(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.detailsDeleteConfirmationTitle),
        content: Text(localizations.detailsDeleteConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.detailsCancelEditAction),
          ),
          FilledButton(
            key: const ValueKey('intention-details-confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(localizations.detailsConfirmDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onDelete();
    }
  }
}

final class _DetailsField extends StatelessWidget {
  const _DetailsField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

final class _DetailsStatus extends StatelessWidget {
  const _DetailsStatus({
    required this.message,
    this.progressIndicator = false,
    this.retryLabel,
    this.onRetry,
  }) : assert((retryLabel == null) == (onRetry == null));

  final String message;
  final bool progressIndicator;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progressIndicator) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(message, textAlign: TextAlign.center),
              if (onRetry case final retry?) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: retry, child: Text(retryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Объяснение влияния связей на переход состояния намерения.
///
/// Объяснение доступно до запуска операции, а переход ведёт в существующее
/// соседство того же намерения.
final class _RelationImpactExplanation extends StatelessWidget {
  const _RelationImpactExplanation({
    required this.explanationKey,
    required this.message,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null)),
       assert((actionKey == null) == (onAction == null));

  final Key explanationKey;
  final String message;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    key: explanationKey,
    container: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (onAction case final action?) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: actionKey,
            onPressed: action,
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}
