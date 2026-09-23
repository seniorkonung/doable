import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../../domain/intention_text.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/presentation/editor/relation_editor_state.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
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
    ref.listen(provider, (previous, next) {
      // Сообщения об успехе предъявляет общий presenter оболочки.
      if (next is IntentionDetailsDeleted) {
        unawaited(context.router.maybePop());
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(localizations.detailsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            if (details.isOperationRunning) const _RunningOperationStatus(),
            Expanded(
              child: _DetailsContent(
                intentionId: intentionId,
                state: details,
                selectionMode: _selectionMode,
                neighborhoodKey: _neighborhoodKey,
                onShowBlockingRelations: _showBlockingRelations,
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
    required this.selectionMode,
    required this.neighborhoodKey,
    required this.onShowBlockingRelations,
  });

  final IntentionId intentionId;
  final IntentionDetailsState state;
  final bool selectionMode;
  final GlobalKey neighborhoodKey;
  final VoidCallback onShowBlockingRelations;

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
        onDelete: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .delete,
        onRetryStateChange: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .retryStateChange,
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
                    ChoicePathRoute(sourceIntentionId: intention.id),
                  ),
                ),
              ),
            },
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

  String? _failureMessage(AppLocalizations localizations) {
    final stateChange = state.stateChange;
    final operation = stateChange?.operation;
    return switch (operation) {
      OperationFailed<Intention>(:final failure) =>
        stateChange!.kind == IntentionDetailsStateChangeKind.delete
            ? _deleteFailureMessage(localizations, failure)
            : _stateChangeFailureMessage(localizations, failure),
      null ||
      OperationIdle<Intention>() ||
      OperationRunning<Intention>() ||
      OperationSucceeded<Intention>() => null,
    };
  }

  String _deleteFailureMessage(
    AppLocalizations localizations,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionGenericValidationFailure() ||
    IntentionTextInputValidationFailure() => localizations.detailsDeleteInvalid,
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
    IntentionTextInputValidationFailure() =>
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('intention-details-edit-cancel'),
              onPressed: controlsEnabled ? widget.onCancel : null,
              child: Text(localizations.detailsCancelEditAction),
            ),
            const SizedBox(width: 12),
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
      IntentionTextInputValidationFailure() =>
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
