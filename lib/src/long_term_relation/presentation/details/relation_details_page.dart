import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import '../editor/relation_editor_state.dart';
import '../relation_command_failure_message.dart';
import 'relation_details_state.dart';
import 'relation_details_view_model.dart';

/// Подробный просмотр одной долговременной связи.
///
/// Формулировка всегда сохраняет исходное направление связи, поэтому вход из
/// входящей группы не переворачивает её. Переход к участнику открывает его
/// собственную страницу с её начальной группой соседства и не раскрывает граф
/// дальше автоматически.
@RoutePage()
final class RelationDetailsPage extends ConsumerWidget {
  const RelationDetailsPage({required this.relationId, super.key});

  final LongTermRelationId relationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = relationDetailsViewModelProvider(relationId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      // Успех предъявляет общий presenter, а удалённый контекст закрывается
      // независимо от занятости общей поверхности сообщения.
      if (next is RelationDetailsDeleted) {
        unawaited(Navigator.of(context).maybePop());
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(localizations.relationDetailsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            if (state.isOperationRunning)
              const _RelationOperationRunningStatus(),
            Expanded(
              child: switch (state) {
                RelationDetailsLoading() => _RelationDetailsStatus(
                  message: localizations.relationDetailsLoading,
                  progressIndicator: true,
                ),
                final RelationDetailsLoaded loaded => _LoadedRelation(
                  state: loaded,
                  onRetry: viewModel.retry,
                  onArchive: viewModel.archive,
                  onRestore: viewModel.restore,
                  onDelete: viewModel.delete,
                  onRetryLifecycleChange: viewModel.retryLifecycleChange,
                  onEdit: loaded.isOperationRunning
                      ? null
                      : () => unawaited(
                          context.router.push(
                            RelationEditorRoute(
                              editorContext: RelationEditingContext(
                                loaded.details,
                                revision: loaded.revision,
                              ),
                            ),
                          ),
                        ),
                ),
                RelationDetailsNotFound() => _RelationDetailsStatus(
                  message: localizations.relationDetailsNotFound,
                ),
                RelationDetailsDeleted() => _RelationDetailsStatus(
                  message: localizations.relationDetailsNotFound,
                ),
                RelationDetailsUnavailable() => _RelationDetailsStatus(
                  message: localizations.relationDetailsUnavailable,
                  onRetry: viewModel.retry,
                ),
                RelationDetailsCorruption() => _RelationDetailsStatus(
                  message: localizations.relationDetailsCorruption,
                ),
                RelationDetailsUnexpected() => _RelationDetailsStatus(
                  message: localizations.relationDetailsUnexpected,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _LoadedRelation extends StatelessWidget {
  const _LoadedRelation({
    required this.state,
    required this.onRetry,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onRetryLifecycleChange,
  });

  final RelationDetailsLoaded state;
  final VoidCallback onRetry;
  final VoidCallback? onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onRetryLifecycleChange;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final details = state.details;
    final relation = details.relation;
    final lifecycleFailure = switch (state.lifecycleChange) {
      final RelationDetailsLifecycleFailed failure => failure,
      RelationDetailsLifecycleRunning() || null => null,
    };
    final sourceFailureBlocksRestore = _isArchivedParticipantFailure(
      lifecycleFailure?.failure,
      RelationParticipantRole.source,
    );
    final relatedFailureBlocksRestore = _isArchivedParticipantFailure(
      lifecycleFailure?.failure,
      RelationParticipantRole.related,
    );
    final sourceBlocksRestore =
        relation.scope == RelationScope.archived &&
        (details.source.archiveState == IntentionArchiveState.archived ||
            sourceFailureBlocksRestore);
    final relatedBlocksRestore =
        relation.scope == RelationScope.archived &&
        (details.related.archiveState == IntentionArchiveState.archived ||
            relatedFailureBlocksRestore);
    final hasKnownRestoreBlocker = sourceBlocksRestore || relatedBlocksRestore;
    final lifecycleActionEnabled =
        !state.isOperationRunning && lifecycleFailure == null;
    final phrase = relation.type == LongTermRelationType.need
        ? localizations.relationNeighborhoodNeedPhrase(
            details.source.title,
            details.related.title,
          )
        : localizations.relationNeighborhoodCanPhrase(
            details.source.title,
            details.related.title,
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (state.refreshStatus case final status
            when status is! RelationDetailsFresh) ...[
          _RelationRefreshStatus(status: status, onRetry: onRetry),
          const SizedBox(height: 24),
        ],
        Semantics(
          header: true,
          child: Text(
            phrase,
            key: const ValueKey('relation-details-phrase'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('relation-details-edit-relation'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(localizations.relationDetailsEditAction),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: relation.scope == RelationScope.active
              ? FilledButton.tonalIcon(
                  key: const ValueKey('relation-details-archive-relation'),
                  onPressed: lifecycleActionEnabled ? onArchive : null,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(localizations.relationDetailsArchiveAction),
                )
              : FilledButton.tonalIcon(
                  key: const ValueKey('relation-details-restore-relation'),
                  onPressed: lifecycleActionEnabled && !hasKnownRestoreBlocker
                      ? onRestore
                      : null,
                  icon: const Icon(Icons.unarchive_outlined),
                  label: Text(localizations.relationDetailsRestoreAction),
                ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('relation-details-delete-relation'),
            onPressed: lifecycleActionEnabled
                ? () => unawaited(_confirmDeletion(context, details, phrase))
                : null,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(localizations.relationDetailsDeleteAction),
          ),
        ),
        if (lifecycleFailure != null &&
            lifecycleFailure.failure
                is! LongTermRelationParticipantArchivedFailure) ...[
          const SizedBox(height: 16),
          OperationFailurePresentation(
            claim: lifecycleFailure.failurePresentation,
            message: _lifecycleFailureMessage(localizations, lifecycleFailure),
            messageKey: const ValueKey('relation-details-lifecycle-failure'),
          ),
          if (lifecycleFailure.canRetry) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('relation-details-lifecycle-retry'),
                onPressed: state.isOperationRunning
                    ? null
                    : onRetryLifecycleChange,
                child: Text(localizations.commonRetry),
              ),
            ),
          ],
        ],
        if (sourceBlocksRestore) ...[
          const SizedBox(height: 16),
          _ArchivedParticipantObstacle(
            role: RelationParticipantRole.source,
            participant: details.source,
            failurePresentation: sourceFailureBlocksRestore
                ? lifecycleFailure?.failurePresentation
                : null,
          ),
        ],
        if (relatedBlocksRestore) ...[
          const SizedBox(height: 16),
          _ArchivedParticipantObstacle(
            role: RelationParticipantRole.related,
            participant: details.related,
            failurePresentation: relatedFailureBlocksRestore
                ? lifecycleFailure?.failurePresentation
                : null,
          ),
        ],
        const SizedBox(height: 24),
        _RelationField(
          label: localizations.relationDetailsTypeLabel,
          value: relation.type == LongTermRelationType.need
              ? localizations.relationNeighborhoodTypeNeed
              : localizations.relationNeighborhoodTypeCan,
          valueKey: const ValueKey('relation-details-type'),
        ),
        const SizedBox(height: 16),
        _RelationField(
          label: localizations.relationDetailsPriorityLabel,
          value: _priorityLabel(relation.priority),
          valueKey: const ValueKey('relation-details-priority'),
        ),
        const SizedBox(height: 16),
        _RelationField(
          label: localizations.relationDetailsScopeLabel,
          value: relation.scope == RelationScope.active
              ? localizations.relationNeighborhoodRelationActive
              : localizations.relationNeighborhoodRelationArchived,
          valueKey: const ValueKey('relation-details-scope'),
        ),
        const SizedBox(height: 16),
        _RelationField(
          label: localizations.relationDetailsDescriptionLabel,
          value:
              details.description?.value ??
              localizations.relationDetailsNoDescription,
          valueKey: const ValueKey('relation-details-description'),
        ),
        const SizedBox(height: 24),
        _ParticipantTransition(
          label: localizations.relationNeighborhoodSourceParticipant,
          participant: details.source,
          transitionKey: const ValueKey('relation-details-source-participant'),
        ),
        const SizedBox(height: 12),
        _ParticipantTransition(
          label: localizations.relationNeighborhoodRelatedParticipant,
          participant: details.related,
          transitionKey: const ValueKey('relation-details-related-participant'),
        ),
      ],
    );
  }

  String _priorityLabel(RelationPriority priority) => switch (priority) {
    RelationPriority.p1 => 'P1',
    RelationPriority.p2 => 'P2',
    RelationPriority.p3 => 'P3',
    RelationPriority.p4 => 'P4',
  };

  Future<void> _confirmDeletion(
    BuildContext context,
    LongTermRelationDetails details,
    String phrase,
  ) async {
    final localizations = AppLocalizations.of(context);
    final scope = details.relation.scope == RelationScope.active
        ? localizations.relationNeighborhoodRelationActive
        : localizations.relationNeighborhoodRelationArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(localizations.relationDetailsDeleteConfirmationTitle),
        content: Semantics(
          container: true,
          child: Text(
            localizations.relationDetailsDeleteConfirmationMessage(
              phrase,
              details.source.title,
              details.related.title,
              scope,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.detailsCancelEditAction),
          ),
          FilledButton(
            key: const ValueKey('relation-details-confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(localizations.relationDetailsConfirmDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onDelete();
    }
  }

  bool _isArchivedParticipantFailure(
    LongTermRelationCommandFailure? failure,
    RelationParticipantRole role,
  ) => switch (failure) {
    LongTermRelationParticipantArchivedFailure(role: final failedRole) =>
      failedRole == role,
    _ => false,
  };

  String _lifecycleFailureMessage(
    AppLocalizations localizations,
    RelationDetailsLifecycleFailed change,
  ) => longTermRelationCommandFailureMessage(localizations, switch (change
      .kind) {
    RelationDetailsLifecycleKind.archive => LongTermRelationCommandKind.archive,
    RelationDetailsLifecycleKind.restore => LongTermRelationCommandKind.restore,
    RelationDetailsLifecycleKind.delete => LongTermRelationCommandKind.delete,
  }, change.failure);
}

final class _ArchivedParticipantObstacle extends StatelessWidget {
  const _ArchivedParticipantObstacle({
    required this.role,
    required this.participant,
    this.failurePresentation,
  });

  final RelationParticipantRole role;
  final RelationParticipantSummary participant;
  final GraphInitiatorPresentationClaim? failurePresentation;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isSource = role == RelationParticipantRole.source;
    final message = isSource
        ? localizations.relationRestoreSourceArchived
        : localizations.relationRestoreRelatedArchived;
    final messageKey = ValueKey(
      isSource
          ? 'relation-details-restore-source-obstacle'
          : 'relation-details-restore-related-obstacle',
    );
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failurePresentation != null)
            OperationFailurePresentation(
              claim: failurePresentation,
              message: message,
              messageKey: messageKey,
            )
          else
            Text(message, key: messageKey),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: ValueKey(
              isSource
                  ? 'relation-details-open-archived-source-participant'
                  : 'relation-details-open-archived-related-participant',
            ),
            onPressed: () => unawaited(
              context.router.push(
                IntentionDetailsRoute(intentionId: participant.id),
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: Text(
              isSource
                  ? localizations.relationDetailsOpenSourceParticipantAction
                  : localizations.relationDetailsOpenRelatedParticipantAction,
            ),
          ),
        ],
      ),
    );
  }
}

final class _RelationOperationRunningStatus extends StatelessWidget {
  const _RelationOperationRunningStatus();

  @override
  Widget build(BuildContext context) => Semantics(
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
          Expanded(
            child: Text(
              AppLocalizations.of(context).detailsOperationRunning,
              key: const ValueKey('relation-details-operation-running'),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _RelationRefreshStatus extends StatelessWidget {
  const _RelationRefreshStatus({required this.status, required this.onRetry});

  final RelationDetailsRefreshStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final message = switch (status) {
      RelationDetailsRefreshing() => localizations.relationDetailsRefreshing,
      RelationDetailsRefreshUnavailable() =>
        localizations.relationDetailsRefreshUnavailable,
      RelationDetailsRefreshCorruption() =>
        localizations.relationDetailsRefreshCorruption,
      RelationDetailsRefreshUnexpected() =>
        localizations.relationDetailsRefreshUnexpected,
      RelationDetailsFresh() => throw StateError(
        'Актуальный снимок не требует статуса обновления.',
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status is RelationDetailsRefreshing) ...[
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  key: const ValueKey('relation-details-refresh-status'),
                ),
                if (status.canRetry) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const ValueKey('relation-details-refresh-retry'),
                    onPressed: onRetry,
                    child: Text(localizations.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Переход к участнику связи с его текущими данными и активным количеством.
final class _ParticipantTransition extends StatelessWidget {
  const _ParticipantTransition({
    required this.label,
    required this.participant,
    required this.transitionKey,
  });

  final String label;
  final RelationParticipantSummary participant;
  final Key transitionKey;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        // Переход объявляется одним узлом: название, архивное состояние,
        // активное количество и назначение перехода звучат вместе.
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: IntentionSummaryView(
            key: transitionKey,
            title: participant.title,
            archiveState: participant.archiveState,
            activeRelationCount: ConfirmedActiveRelationCount(
              participant.activeRelationCount,
            ),
            showArchiveState: true,
            tapHint: localizations.relationDetailsOpenParticipant,
            onTap: () => unawaited(
              context.router.push(
                IntentionDetailsRoute(intentionId: participant.id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _RelationField extends StatelessWidget {
  const _RelationField({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(value, key: valueKey),
    ],
  );
}

final class _RelationDetailsStatus extends StatelessWidget {
  const _RelationDetailsStatus({
    required this.message,
    this.progressIndicator = false,
    this.onRetry,
  });

  final String message;
  final bool progressIndicator;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
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
            Text(
              message,
              key: const ValueKey('relation-details-status'),
              textAlign: TextAlign.center,
            ),
            if (onRetry case final retry?) ...[
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('relation-details-retry'),
                onPressed: retry,
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
