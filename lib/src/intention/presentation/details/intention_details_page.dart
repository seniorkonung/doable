import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Badge, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/ordinary_page_scaffold.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../daily_choice/application/choice_path_draft.dart';
import '../../../daily_choice/domain/calendar_date.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/option_tiles.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/components/page_head.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../edit/intention_edit_page.dart';
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
import 'intention_dates.dart';
import 'intention_details_state.dart';
import 'intention_details_view_model.dart';
import 'intention_details_tabs.dart';
import 'intention_options.dart';
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
      onTodayChanged: () {
        ref.read(_statisticsProvider.notifier).setLocalDate(_localDay.today);
        // Строка дат «Обзора» называет год по сегодняшнему дню.
        setState(() {});
      },
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
  void _openEdit(IntentionEditFocus focus) {
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
      context.router.push(
        IntentionEditRoute(intentionId: intentionId, focus: focus),
      ),
    );
  }

  bool _canOpenEdit(IntentionDetailsLoaded loaded) =>
      !loaded.isOperationRunning && !loaded.isAwaitingConfirmedSnapshot;
  Widget _buildHead(IntentionDetailsLoaded loaded) {
    final localizations = AppLocalizations.of(context);
    final name = loaded.intention.title;
    final archived =
        loaded.intention.archiveState == IntentionArchiveState.archived;
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
            editLabel: localizations.detailsEditTitleLabel(name),
            onEdit: _canOpenEdit(loaded)
                ? () => _openEdit(IntentionEditFocus.title)
                : null,
            muted: archived,
            badge: archived
                ? Badge.archived(word: localizations.detailsArchivedBadge)
                : null,
            note: archived ? localizations.detailsArchivedNote : null,
            button: archived
                ? Button.quietBlock(
                    key: const ValueKey('intention-details-head-restore'),
                    label: localizations.detailsRestoreFromArchiveAction,
                    onPressed: loaded.isOperationRunning
                        ? null
                        : ref
                              .read(
                                intentionDetailsViewModelProvider(
                                  widget.intentionId,
                                ).notifier,
                              )
                              .restore,
                  )
                : null,
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

  /// Лист закрывается до начала действия, поэтому оно начинается уже на
  /// странице (ADR-0042).
  Future<void> _openOptions() async {
    final provider = intentionDetailsViewModelProvider(widget.intentionId);
    final option = await showDoableSheet<IntentionOption>(
      context: context,
      builder: (context, sheet) =>
          _IntentionOptionsSheet(sheet: sheet, provider: provider),
    );
    if (option == null || !mounted) return;
    final model = ref.read(provider.notifier);
    switch (option) {
      case IntentionOption.edit:
        _openEdit(IntentionEditFocus.title);
      case IntentionOption.archive:
        model.archive();
      case IntentionOption.restore:
        model.restore();
      case IntentionOption.delete:
        await _confirmDeletion();
    }
  }

  Future<void> _confirmDeletion() async {
    final details = ref.read(
      intentionDetailsViewModelProvider(widget.intentionId),
    );
    if (details is! IntentionDetailsLoaded) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: localizations.detailsDeleteDialogTitle,
      text: ConfirmDialogText(
        before: localizations.detailsDeleteDialogTextBefore,
        name: details.intention.title,
        after: localizations.detailsDeleteDialogTextAfter,
      ),
      cancelLabel: localizations.detailsDeleteDialogCancel,
      actionLabel: localizations.detailsDeleteDialogConfirm,
    );
    if (confirmed) await _delete();
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
              action: TopBarAction(
                icon: DoableIconData.more,
                label: localizations.detailsOptionsLabel,
                onPressed: () => unawaited(_openOptions()),
              ),
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
                onEditDescription:
                    details is IntentionDetailsLoaded && _canOpenEdit(details)
                    ? () => _openEdit(IntentionEditFocus.description)
                    : null,
                headHidden: _headHidden,
                today: _localDay.today,
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

/// Лист «Намерение» следит за снимком страницы: операция, начатая или
/// завершённая при открытом листе, сразу меняет доступность пунктов.
final class _IntentionOptionsSheet extends ConsumerWidget {
  const _IntentionOptionsSheet({required this.sheet, required this.provider});

  final SheetPresentation sheet;
  final IntentionDetailsViewModelProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ModalRoute.of(context);
    ref.listen(provider, (_, next) {
      // Без подробных данных параметрам не к чему относиться. Лист, который
      // уже закрывается, не текущий, и страницу под ним это не закрывает.
      if (next is! IntentionDetailsLoaded && (route?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });
    final localizations = AppLocalizations.of(context);
    return switch (ref.watch(provider)) {
      final IntentionDetailsLoaded loaded => OptionsMenu<IntentionOption>(
        sheet,
        title: localizations.detailsOptionsTitle,
        items: intentionOptions(localizations, loaded),
      ),
      // Лист уже закрывается вслед за утратой данных.
      _ => const SizedBox.shrink(),
    };
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
    required this.onEditDescription,
    required this.headHidden,
    required this.today,
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
  final VoidCallback? onEditDescription;
  final ValueListenable<bool> headHidden;
  final CalendarDate today;
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
        onEditDescription: onEditDescription,
        headHidden: headHidden,
        today: today,
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
  static const double _datesGap = 10;

  const _LoadedDetails({
    required this.state,
    required this.scrollController,
    required this.pageHead,
    required this.onEditDescription,
    required this.headHidden,
    required this.today,
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
  final VoidCallback? onEditDescription;
  final ValueListenable<bool> headHidden;
  final CalendarDate today;
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
                padding: const EdgeInsets.fromLTRB(
                  DoableMetrics.space5,
                  DoableMetrics.space1,
                  DoableMetrics.space5,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: TextField.saved(
                    value: intention.description ?? '',
                    placeholder: localizations.detailsAddDescription,
                    label: switch (intention.description) {
                      final description? =>
                        localizations.detailsEditDescriptionLabel(description),
                      null => localizations.detailsAddDescription,
                    },
                    onOpen: onEditDescription,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  DoableMetrics.space5,
                  DoableMetrics.space3,
                  DoableMetrics.space5,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: OptionTiles<IntentionReadiness>(
                    first: OptionTile(
                      id: IntentionReadiness.notReady,
                      icon: DoableIconData.intention,
                      title: localizations.detailsTypeIntention,
                      hint: localizations.detailsTypeIntentionHint,
                    ),
                    second: OptionTile(
                      id: IntentionReadiness.ready,
                      icon: DoableIconData.bolt,
                      title: localizations.detailsTypeAction,
                      hint: localizations.detailsTypeActionHint,
                    ),
                    value: intention.readiness,
                    label: localizations.detailsTypeChoiceLabel,
                    onChange: state.isOperationRunning
                        ? null
                        : (readiness) => switch (readiness) {
                            IntentionReadiness.ready => onEnableReadiness(),
                            IntentionReadiness.notReady => onDisableReadiness(),
                          },
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  DoableMetrics.space5,
                  DoableMetrics.space2,
                  DoableMetrics.space5,
                  0,
                ),
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
              SliverPadding(
                // Строка начинается вровень со словом «Теги».
                padding: const EdgeInsets.fromLTRB(
                  DoableMetrics.space5 + DoableMetrics.space1,
                  _datesGap,
                  DoableMetrics.space5 + DoableMetrics.space1,
                  DoableMetrics.space4,
                ),
                sliver: SliverToBoxAdapter(
                  child: intentionDatesLine(
                    localizations: localizations,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                    createdAt: intention.createdAt,
                    updatedAt: intention.updatedAt,
                    today: today,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _DetailsActions(
                    state: state,
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
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onShowArchivedRelations,
    required this.onChoosePath,
  });

  final IntentionDetailsLoaded state;
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
