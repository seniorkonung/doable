import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/navigation/ordinary_page_scaffold.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../daily_choice/application/choice_path_draft.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../../domain/intention_text.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/presentation/editor/relation_editor_state.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import '../../../tag/presentation/assignments/tag_assignments_section.dart';
import '../../../tag/presentation/catalog/tag_selection_context.dart';
import '../operation/operation_state.dart';
import 'intention_details_state.dart';
import 'intention_details_view_model.dart';

@RoutePage()
final class IntentionDetailsPage extends ConsumerStatefulWidget {
  const IntentionDetailsPage({required this.intentionId, super.key});

  final IntentionId intentionId;

  @override
  ConsumerState<IntentionDetailsPage> createState() =>
      _IntentionDetailsPageState();
}

final class _IntentionDetailsPageState
    extends ConsumerState<IntentionDetailsPage> {
  final _neighborhoodKey = GlobalKey();
  var _selectionMode = false;

  @override
  void didUpdateWidget(covariant IntentionDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentionId != widget.intentionId) {
      _selectionMode = false;
    }
  }

  void _showBlockingRelations() {
    ref
        .read(
          relationNeighborhoodViewModelProvider(widget.intentionId).notifier,
        )
        .showBlockingRelations();
    setState(() => _selectionMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final neighborhoodContext = _neighborhoodKey.currentContext;
      if (mounted && neighborhoodContext != null) {
        unawaited(
          Scrollable.ensureVisible(neighborhoodContext, alignment: 0.05),
        );
      }
    });
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
    // Открытие страницы одновременно начинает только начальную группу
    // соседства; сам sliver переиспользует это состояние после загрузки
    // подробных данных намерения.
    ref.watch(relationNeighborhoodViewModelProvider(intentionId));
    return OrdinaryPageScaffold(
      appBar: AppBar(
        title: Text(localizations.detailsTitle),
        actions: [
          // Отметка входит в подробные данные: без них управления нет, и
          // отметка не изображается отсутствующей.
          if (details is IntentionDetailsLoaded)
            _FavoriteMarkControl(
              state: details,
              onMark: ref.read(provider.notifier).markFavorite,
              onUnmark: ref.read(provider.notifier).unmarkFavorite,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (details.isOperationRunning) const _RunningOperationStatus(),
            // Отметка запускается из шапки, вне прокручиваемого содержимого:
            // её отказ остаётся виден при любом положении прокрутки.
            if (details case IntentionDetailsLoaded(
              :final stateChange?,
              :final isOperationRunning,
            ))
              if (_failureAt(stateChange, _StateChangeFailurePlace.headerBanner)
                  case final failure?)
                _FavoriteMarkFailureBanner(
                  stateChange: stateChange,
                  failure: failure,
                  onRetry: isOperationRunning
                      ? null
                      : ref.read(provider.notifier).retryStateChange,
                ),
            Expanded(
              child: _DetailsContent(
                intentionId: intentionId,
                state: details,
                selectionMode: _selectionMode,
                neighborhoodKey: _neighborhoodKey,
                onShowBlockingRelations: _showBlockingRelations,
                onDelete: _delete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Управление отметкой избранного в шапке страницы намерения.
///
/// Показывает только подтверждённую отметку: значок меняет форму после
/// подтверждённого снимка, а не после нажатия.
final class _FavoriteMarkControl extends StatelessWidget {
  const _FavoriteMarkControl({
    required this.state,
    required this.onMark,
    required this.onUnmark,
  });

  final IntentionDetailsLoaded state;
  final VoidCallback onMark;
  final VoidCallback onUnmark;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final (
      icon,
      value,
      action,
      onPressed,
    ) = switch (state.details.favoriteMark) {
      FavoriteMark.favorite => (
        Icons.star,
        localizations.detailsFavoriteMarkStateMarked,
        localizations.detailsUnmarkFavoriteAction,
        onUnmark,
      ),
      FavoriteMark.notFavorite => (
        Icons.star_border,
        localizations.detailsFavoriteMarkStateNotMarked,
        localizations.detailsMarkFavoriteAction,
        onMark,
      ),
    };
    // До снимка подтверждённой отметки действие вычислено по прежней.
    final enabled =
        !state.isOperationRunning &&
        state.edit == null &&
        !state.isAwaitingFavoriteMarkSnapshot;
    return MergeSemantics(
      child: Semantics(
        label: localizations.detailsFavoriteMarkLabel,
        value: value,
        child: IconButton(
          key: const ValueKey('intention-details-favorite-mark'),
          tooltip: action,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// Место, где страница намерения предъявляет отказ перехода состояния.
enum _StateChangeFailurePlace {
  /// Закреплённая полоса под шапкой, вне прокручиваемого содержимого.
  headerBanner,

  /// Область действий рядом с кнопкой, запустившей переход.
  actions,
}

/// Отказ отметки предъявляется рядом с её управлением в шапке, отказы
/// остальных переходов — рядом с кнопками области действий.
_StateChangeFailurePlace _failurePlace(IntentionDetailsStateChangeKind kind) =>
    switch (kind) {
      IntentionDetailsStateChangeKind.markFavorite ||
      IntentionDetailsStateChangeKind.unmarkFavorite =>
        _StateChangeFailurePlace.headerBanner,
      IntentionDetailsStateChangeKind.enableReadiness ||
      IntentionDetailsStateChangeKind.disableReadiness ||
      IntentionDetailsStateChangeKind.archive ||
      IntentionDetailsStateChangeKind.restore ||
      IntentionDetailsStateChangeKind.delete =>
        _StateChangeFailurePlace.actions,
    };

/// Отказ перехода, который предъявляет [place]; у отказа одно место.
IntentionFailure? _failureAt(
  IntentionDetailsStateChange? stateChange,
  _StateChangeFailurePlace place,
) {
  if (stateChange == null || _failurePlace(stateChange.kind) != place) {
    return null;
  }
  return switch (stateChange.operation) {
    OperationFailed<Intention>(:final failure) => failure,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() => null,
  };
}

/// Закреплённая полоса отказа отметки и её снятия под шапкой страницы.
///
/// Единственный renderer этого отказа: область действий его не повторяет.
final class _FavoriteMarkFailureBanner extends StatelessWidget {
  const _FavoriteMarkFailureBanner({
    required this.stateChange,
    required this.failure,
    required this.onRetry,
  });

  final IntentionDetailsStateChange stateChange;
  final IntentionFailure failure;

  /// Повтор недоступен, пока выполняется операция намерения.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OperationFailurePresentation(
            claim: stateChange.failurePresentation,
            message: _message(localizations),
            messageKey: const ValueKey(
              'intention-details-favorite-mark-failure',
            ),
          ),
          if (stateChange.canRetry) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                key: const ValueKey('intention-details-favorite-mark-retry'),
                onPressed: onRetry,
                child: Text(localizations.commonRetry),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  String _message(AppLocalizations localizations) => switch (failure) {
    IntentionGenericValidationFailure() ||
    IntentionTextInputValidationFailure() ||
    IntentionCreationTagsMissingFailure() =>
      localizations.detailsFavoriteMarkInvalid,
    IntentionNotFoundFailure() => localizations.detailsFavoriteMarkNotFound,
    IntentionConflictFailure() => localizations.detailsFavoriteMarkConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsFavoriteMarkUnexpected,
    IntentionUnavailableFailure() =>
      localizations.detailsFavoriteMarkUnavailable,
    IntentionCorruptionFailure() => localizations.detailsFavoriteMarkCorruption,
    IntentionUnexpectedFailure() => localizations.detailsFavoriteMarkUnexpected,
  };
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
    required this.selectionMode,
    required this.neighborhoodKey,
    required this.onShowBlockingRelations,
    required this.onDelete,
  });

  final IntentionId intentionId;
  final IntentionDetailsState state;
  final bool selectionMode;
  final GlobalKey neighborhoodKey;
  final VoidCallback onShowBlockingRelations;
  final VoidCallback onDelete;

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
        selectionMode: selectionMode,
        neighborhoodKey: neighborhoodKey,
        onBeginEditing: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .beginEditing,
        onCancelEditing: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .cancelEditing,
        onTitleChanged: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .changeTitle,
        onDescriptionChanged: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .changeDescription,
        onSave: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .saveChanges,
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
        onRetryStateChange: () {
          final provider = intentionDetailsViewModelProvider(intentionId);
          final current = ref.read(provider);
          if (current is IntentionDetailsLoaded &&
              current.stateChange?.kind ==
                  IntentionDetailsStateChangeKind.delete) {
            if (current.stateChange!.canRetry) onDelete();
          } else {
            ref.read(provider.notifier).retryStateChange();
          }
        },
        onShowBlockingRelations: onShowBlockingRelations,
        onShowArchivedRelations: ref
            .read(relationNeighborhoodViewModelProvider(intentionId).notifier)
            .showArchivedRelations,
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
    required this.selectionMode,
    required this.neighborhoodKey,
    required this.onBeginEditing,
    required this.onCancelEditing,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onSave,
    required this.onEnableReadiness,
    required this.onDisableReadiness,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onRetryStateChange,
    required this.onShowBlockingRelations,
    required this.onShowArchivedRelations,
  });

  final IntentionDetailsLoaded state;
  final bool selectionMode;
  final GlobalKey neighborhoodKey;
  final VoidCallback onBeginEditing;
  final VoidCallback onCancelEditing;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final VoidCallback onSave;
  final VoidCallback onEnableReadiness;
  final VoidCallback onDisableReadiness;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onRetryStateChange;
  final VoidCallback onShowBlockingRelations;
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
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    intention.title,
                    key: const ValueKey('intention-details-title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 24),
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
            child: switch (state.edit) {
              final edit? => _DetailsEditForm(
                edit: edit,
                isOperationRunning: state.isOperationRunning,
                onCancel: onCancelEditing,
                onTitleChanged: onTitleChanged,
                onDescriptionChanged: onDescriptionChanged,
                onSave: onSave,
              ),
              null => _DetailsActions(
                state: state,
                onBeginEditing: onBeginEditing,
                onEnableReadiness: onEnableReadiness,
                onDisableReadiness: onDisableReadiness,
                onArchive: onArchive,
                onRestore: onRestore,
                onDelete: onDelete,
                onRetryStateChange: onRetryStateChange,
                onShowBlockingRelations: onShowBlockingRelations,
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
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverToBoxAdapter(
            child: TagAssignmentsSection(
              intentionId: intention.id,
              isArchived:
                  intention.archiveState == IntentionArchiveState.archived,
              onChooseTag: (intentionId) => unawaited(
                context.router.push(
                  TagCatalogRoute(
                    selectionContext: TagAssignmentContext(intentionId),
                  ),
                ),
              ),
              onOpenTag: (tagId) => unawaited(
                context.router.push<void>(TagNavigationRoute(tagId: tagId)),
              ),
            ),
          ),
        ),
        RelationNeighborhoodSliver(
          key: neighborhoodKey,
          intentionId: intention.id,
          intentionTitle: intention.title,
          selectionMode: selectionMode,
          onOpenRelation: (relationId) => unawaited(
            context.router.push(RelationDetailsRoute(relationId: relationId)),
          ),
          onOpenDailyChoice: (choiceId) => unawaited(
            context.router.push(DailyChoiceDetailsRoute(choiceId: choiceId)),
          ),
          onCreateRelation: (direction) => unawaited(
            context.router.push(
              RelationEditorRoute(
                editorContext: RelationCreationContext(
                  participant: RelationParticipantSummary(
                    id: intention.id,
                    title: intention.title,
                    archiveState: intention.archiveState,
                    activeRelationCount: state.details.activeRelationCount,
                  ),
                  direction: direction,
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

final class _DetailsActions extends StatelessWidget {
  const _DetailsActions({
    required this.state,
    required this.onBeginEditing,
    required this.onEnableReadiness,
    required this.onDisableReadiness,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onRetryStateChange,
    required this.onShowBlockingRelations,
    required this.onShowArchivedRelations,
    required this.onChoosePath,
  });

  final IntentionDetailsLoaded state;
  final VoidCallback onBeginEditing;
  final VoidCallback onEnableReadiness;
  final VoidCallback onDisableReadiness;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onRetryStateChange;
  final VoidCallback onShowBlockingRelations;
  final VoidCallback onShowArchivedRelations;
  final VoidCallback onChoosePath;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final controlsEnabled = !state.isOperationRunning;
    final failure = _failureMessage(localizations);
    final isArchived =
        state.intention.archiveState == IntentionArchiveState.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          OperationFailurePresentation(
            claim: state.stateChange?.failurePresentation,
            message: failure,
            messageKey: const ValueKey(
              'intention-details-state-change-failure',
            ),
          ),
          if (state.stateChange?.canRetry ?? false) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('intention-details-state-change-retry'),
                onPressed: controlsEnabled ? onRetryStateChange : null,
                child: Text(localizations.commonRetry),
              ),
            ),
          ],
          // Блокирующие связи показываются в актуальном соседстве: удаление
          // остаётся запрещённым и для архивных, и для незагруженных связей.
          if (_isBlockedByRelations) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey(
                  'intention-details-show-blocking-relations',
                ),
                onPressed: onShowBlockingRelations,
                icon: const Icon(Icons.link_off_outlined),
                label: Text(localizations.detailsShowBlockingRelationsAction),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
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
            OutlinedButton.icon(
              key: const ValueKey('intention-details-edit'),
              onPressed: controlsEnabled ? onBeginEditing : null,
              icon: const Icon(Icons.edit_outlined),
              label: Text(localizations.detailsEditAction),
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

  /// Отказ удаления вызван связями намерения, а не иным конфликтом.
  bool get _isBlockedByRelations {
    final stateChange = state.stateChange;
    if (stateChange == null ||
        stateChange.kind != IntentionDetailsStateChangeKind.delete) {
      return false;
    }
    return stateChange.operation is OperationFailed<Intention> &&
        (stateChange.operation as OperationFailed<Intention>).failure
            is IntentionHasBlockingRelationsFailure;
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

  /// Сообщение отказа, который предъявляет область действий. Отказ отметки
  /// сюда не попадает: его показывает полоса под шапкой.
  String? _failureMessage(AppLocalizations localizations) {
    final stateChange = state.stateChange;
    final failure = _failureAt(stateChange, _StateChangeFailurePlace.actions);
    if (stateChange == null || failure == null) {
      return null;
    }
    return switch (stateChange.kind) {
      IntentionDetailsStateChangeKind.delete => _deleteFailureMessage(
        localizations,
        failure,
      ),
      IntentionDetailsStateChangeKind.enableReadiness ||
      IntentionDetailsStateChangeKind.disableReadiness ||
      IntentionDetailsStateChangeKind.archive ||
      IntentionDetailsStateChangeKind.restore => _stateChangeFailureMessage(
        localizations,
        failure,
      ),
      IntentionDetailsStateChangeKind.markFavorite ||
      IntentionDetailsStateChangeKind.unmarkFavorite => null,
    };
  }

  String _deleteFailureMessage(
    AppLocalizations localizations,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionGenericValidationFailure() ||
    IntentionTextInputValidationFailure() ||
    IntentionCreationTagsMissingFailure() => localizations.detailsDeleteInvalid,
    IntentionNotFoundFailure() => localizations.detailsDeleteNotFound,
    IntentionConflictFailure() => localizations.detailsDeleteConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsDeleteBlockedByRelations,
    IntentionUnavailableFailure() => localizations.detailsDeleteUnavailable,
    IntentionCorruptionFailure() => localizations.detailsDeleteCorruption,
    IntentionUnexpectedFailure() => localizations.detailsDeleteUnexpected,
  };

  String _stateChangeFailureMessage(
    AppLocalizations localizations,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionGenericValidationFailure() ||
    IntentionTextInputValidationFailure() ||
    IntentionCreationTagsMissingFailure() =>
      localizations.detailsStateChangeInvalid,
    IntentionNotFoundFailure() => localizations.detailsStateChangeNotFound,
    IntentionConflictFailure() => localizations.detailsStateChangeConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsStateChangeUnexpected,
    IntentionUnavailableFailure() =>
      localizations.detailsStateChangeUnavailable,
    IntentionCorruptionFailure() => localizations.detailsStateChangeCorruption,
    IntentionUnexpectedFailure() => localizations.detailsStateChangeUnexpected,
  };
}

final class _DetailsEditForm extends StatefulWidget {
  const _DetailsEditForm({
    required this.edit,
    required this.isOperationRunning,
    required this.onCancel,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onSave,
  });

  final IntentionDetailsEdit edit;
  final bool isOperationRunning;
  final VoidCallback onCancel;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final VoidCallback onSave;

  @override
  State<_DetailsEditForm> createState() => _DetailsEditFormState();
}

final class _DetailsEditFormState extends State<_DetailsEditForm> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.edit.title);
    _descriptionController = TextEditingController(
      text: widget.edit.description,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final edit = widget.edit;
    final controlsEnabled = !widget.isOperationRunning;
    final generalFailure = _generalFailure(localizations, edit.operation);
    final titleFailure = _fieldFailure(
      localizations,
      edit.operation,
      IntentionTextField.title,
    );
    final descriptionFailure = _fieldFailure(
      localizations,
      edit.operation,
      IntentionTextField.description,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('intention-details-edit-title'),
          controller: _titleController,
          enabled: controlsEnabled,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: localizations.editorTitleLabel,
            error: titleFailure == null
                ? null
                : OperationFailurePresentation(
                    claim: edit.failurePresentation,
                    message: titleFailure,
                  ),
          ),
          onChanged: widget.onTitleChanged,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('intention-details-edit-description'),
          controller: _descriptionController,
          enabled: controlsEnabled,
          minLines: 4,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: localizations.editorDescriptionLabel,
            alignLabelWithHint: true,
            error: descriptionFailure == null
                ? null
                : OperationFailurePresentation(
                    claim: edit.failurePresentation,
                    message: descriptionFailure,
                  ),
          ),
          onChanged: widget.onDescriptionChanged,
        ),
        if (generalFailure != null) ...[
          const SizedBox(height: 16),
          OperationFailurePresentation(
            claim: edit.failurePresentation,
            message: generalFailure,
            messageKey: const ValueKey('intention-details-edit-failure'),
          ),
        ],
        const SizedBox(height: 24),
        // При увеличенном тексте действия переходят на следующие строки.
        // https://api.flutter.dev/flutter/widgets/Wrap-class.html
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            TextButton(
              key: const ValueKey('intention-details-edit-cancel'),
              onPressed: controlsEnabled ? widget.onCancel : null,
              child: Text(localizations.detailsCancelEditAction),
            ),
            FilledButton(
              key: const ValueKey('intention-details-edit-submit'),
              onPressed: controlsEnabled && edit.canSubmit
                  ? widget.onSave
                  : null,
              child: Text(_submitLabel(localizations, edit)),
            ),
          ],
        ),
      ],
    );
  }

  String _submitLabel(
    AppLocalizations localizations,
    IntentionDetailsEdit edit,
  ) => switch (edit.operation) {
    OperationRunning<Intention>() => localizations.detailsOperationRunning,
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) =>
      localizations.commonRetry,
    OperationIdle<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => localizations.detailsSaveAction,
  };

  String? _fieldFailure(
    AppLocalizations localizations,
    OperationState<Intention> operation,
    IntentionTextField field,
  ) {
    if (operation
        case OperationFailed<Intention>(
          failure: IntentionTextInputValidationFailure(:final textFailure),
        )
        when textFailure.field == field) {
      return switch ((field, textFailure.reason)) {
        (IntentionTextField.title, IntentionTextValidationReason.empty) =>
          localizations.editorTitleEmpty,
        (IntentionTextField.title, IntentionTextValidationReason.tooLong) =>
          localizations.editorTitleTooLong,
        (
          IntentionTextField.title,
          IntentionTextValidationReason.invalidUnicodeRepertoire,
        ) =>
          localizations.editorTitleInvalidUnicode,
        (
          IntentionTextField.description,
          IntentionTextValidationReason.tooLong,
        ) =>
          localizations.editorDescriptionTooLong,
        (
          IntentionTextField.description,
          IntentionTextValidationReason.invalidUnicodeRepertoire,
        ) =>
          localizations.editorDescriptionInvalidUnicode,
        (IntentionTextField.description, IntentionTextValidationReason.empty) ||
        (
          IntentionTextField.titleFilter,
          _,
        ) => localizations.detailsUpdateInvalidInput,
      };
    }
    return null;
  }

  String? _generalFailure(
    AppLocalizations localizations,
    OperationState<Intention> operation,
  ) => switch (operation) {
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() => null,
    OperationFailed<Intention>(:final failure) => switch (failure) {
      IntentionTextInputValidationFailure(:final textFailure)
          when textFailure.field == IntentionTextField.title ||
              textFailure.field == IntentionTextField.description =>
        null,
      IntentionGenericValidationFailure() ||
      IntentionTextInputValidationFailure() ||
      IntentionCreationTagsMissingFailure() =>
        localizations.detailsUpdateInvalidInput,
      IntentionNotFoundFailure() => localizations.detailsUpdateNotFound,
      IntentionConflictFailure() => localizations.detailsUpdateConflict,
      IntentionHasBlockingRelationsFailure() =>
        localizations.detailsUpdateUnexpected,
      IntentionUnavailableFailure() => localizations.detailsUpdateUnavailable,
      IntentionCorruptionFailure() => localizations.detailsUpdateCorruption,
      IntentionUnexpectedFailure() => localizations.detailsUpdateUnexpected,
    },
  };
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
