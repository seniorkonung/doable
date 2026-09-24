import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../daily_choice/application/daily_choice_catalog.dart';
import '../../../daily_choice/domain/daily_choice_id.dart';
import '../../../graph/application/blocking_relation_reference.dart';
import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import 'blocking_relations_selection_state.dart';
import 'blocking_relations_selection_view_model.dart';

/// Открывает проверку неизменяемого набора и показывает исход принятой команды.
final class BlockingRelationsConfirmationAction extends ConsumerWidget {
  const BlockingRelationsConfirmationAction({
    required this.intentionId,
    required this.intentionTitle,
    required this.onOpenDailyChoice,
    super.key,
  });

  final IntentionId intentionId;
  final String intentionTitle;
  final ValueChanged<DailyChoiceId> onOpenDailyChoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = blockingRelationsSelectionViewModelProvider(intentionId);
    final selection = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selection is BlockingRelationsSelectionEditing &&
            selection.selectedByReference.isNotEmpty &&
            selection.invalidReasonsByReference.isEmpty)
          FilledButton.icon(
            key: const ValueKey('blocking-relations-review'),
            onPressed: () => _review(context, ref, provider),
            icon: const Icon(Icons.preview_outlined),
            label: Text(localizations.blockingRelationsReviewAction),
          ),
        if (selection is BlockingRelationsSelectionEditing)
          for (final entry in selection.invalidReasonsByReference.entries)
            Card(
              key: ValueKey(
                'blocking-relations-invalid-${_referenceKey(entry.key)}',
              ),
              child: Semantics(
                container: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations
                            .blockingRelationsInvalidSelectedRelationId(
                              _referenceId(entry.key),
                            ),
                      ),
                      Text(
                        _selectedPhrase(
                          localizations,
                          selection.selectedByReference[entry.key]!,
                        ),
                      ),
                      Text(switch (entry.value) {
                        BlockingRelationsInvalidReason.missing =>
                          localizations.blockingRelationsInvalidMissing,
                        BlockingRelationsInvalidReason.noLongerBlocking =>
                          localizations.blockingRelationsInvalidMoved,
                        BlockingRelationsInvalidReason.referencedByDailyPath =>
                          localizations.blockingRelationsInvalidProtected,
                      }),
                      TextButton(
                        key: ValueKey(
                          'blocking-relations-remove-invalid-${_referenceKey(entry.key)}',
                        ),
                        onPressed: () => ref
                            .read(provider.notifier)
                            .unselectReference(entry.key),
                        child: Text(
                          localizations.relationNeighborhoodRemoveFromSelection,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (selection is BlockingRelationsSelectionRefreshing)
          Semantics(
            liveRegion: true,
            child: Text(localizations.blockingRelationsRefreshingSelection),
          ),
        if (selection is BlockingRelationsSelectionRefreshFailed) ...[
          Text(_refreshFailureMessage(localizations, selection.failure)),
          if (selection.failure == BlockingRelationsRefreshFailure.unavailable)
            OutlinedButton(
              key: const ValueKey('blocking-relations-refresh-retry'),
              onPressed: ref.read(provider.notifier).refreshSelection,
              child: Text(
                localizations.blockingRelationsRefreshSelectionAction,
              ),
            ),
        ],
        if (selection is BlockingRelationsSelectionRunning)
          Semantics(
            liveRegion: true,
            child: Text(localizations.blockingRelationsDeleting),
          ),
        if (selection is BlockingRelationsSelectionFailed) ...[
          OperationFailurePresentation(
            claim: selection.presentationClaim,
            message: _failureMessage(localizations, selection.failure),
            messageKey: const ValueKey('blocking-relations-delete-failure'),
          ),
          const SizedBox(height: 8),
          if (selection.requiresRefresh)
            OutlinedButton(
              key: const ValueKey('blocking-relations-refresh-selection'),
              onPressed: ref.read(provider.notifier).refreshSelection,
              child: Text(
                localizations.blockingRelationsRefreshSelectionAction,
              ),
            )
          else if (selection.failure
                  is! BlockingRelationsSelectionCommandFailure ||
              (selection.failure as BlockingRelationsSelectionCommandFailure)
                      .failure
                  is DeleteBlockingRelationsUnavailableFailure)
            OutlinedButton(
              key: const ValueKey('blocking-relations-edit-selection'),
              onPressed: ref.read(provider.notifier).resumeEditing,
              child: Text(localizations.blockingRelationsEditSelectionAction),
            ),
        ],
      ],
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    BlockingRelationsSelectionViewModelProvider provider,
  ) async {
    final viewModel = ref.read(provider.notifier);
    if (!await viewModel.refreshSelection() || !context.mounted) {
      return;
    }
    if (!viewModel.prepare()) {
      return;
    }
    final prepared = ref.read(provider) as BlockingRelationsSelectionPrepared;
    viewModel.observePrepared();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BlockingRelationsConfirmation(
        snapshot: prepared.snapshot,
        provider: provider,
        onOpenDailyChoice: onOpenDailyChoice,
      ),
    );
    if (!context.mounted) {
      return;
    }
    final current = ref.read(provider);
    if (current is! BlockingRelationsSelectionPrepared) {
      return;
    }
    if (confirmed == true) {
      viewModel.confirm(presentationTitle: intentionTitle);
    } else {
      viewModel.cancel();
    }
  }
}

String _refreshFailureMessage(
  AppLocalizations localizations,
  BlockingRelationsRefreshFailure failure,
) => switch (failure) {
  BlockingRelationsRefreshFailure.intentionNotFound =>
    localizations.blockingRelationsRefreshIntentionNotFound,
  BlockingRelationsRefreshFailure.unavailable =>
    localizations.blockingRelationsRefreshUnavailable,
  BlockingRelationsRefreshFailure.corruption =>
    localizations.blockingRelationsRefreshCorruption,
  BlockingRelationsRefreshFailure.unexpected =>
    localizations.blockingRelationsRefreshUnexpected,
};

String _failureMessage(
  AppLocalizations localizations,
  BlockingRelationsSelectionFailure failure,
) => switch (failure) {
  BlockingRelationsSelectionBusy() => localizations.blockingRelationsBusy,
  BlockingRelationsSelectionDraining() =>
    localizations.blockingRelationsDraining,
  BlockingRelationsSelectionCommandFailure(:final failure) => switch (failure) {
    DeleteBlockingRelationsIntentionNotFoundFailure() =>
      localizations.blockingRelationsDeleteIntentionNotFound,
    DeleteBlockingRelationsSelectionConflictFailure(:final reason) =>
      switch (reason) {
        BlockingRelationConflictReason.relationMissing =>
          localizations.blockingRelationsDeleteMissing,
        BlockingRelationConflictReason.noLongerBlocking =>
          localizations.blockingRelationsDeleteMoved,
        BlockingRelationConflictReason.deletionProhibited =>
          localizations.blockingRelationsDeleteProhibited,
      },
    DeleteBlockingRelationsUnavailableFailure() =>
      localizations.blockingRelationsDeleteUnavailable,
    DeleteBlockingRelationsCorruptionFailure() =>
      localizations.blockingRelationsDeleteCorruption,
    DeleteBlockingRelationsUnexpectedFailure() =>
      localizations.blockingRelationsDeleteUnexpected,
  },
};

String _referenceId(BlockingRelationReference reference) => switch (reference) {
  LongTermBlockingRelationReference(:final id) => id.toCanonicalString(),
  DailyChoiceBlockingRelationReference(:final id) => id.toCanonicalString(),
};

String _referenceKey(BlockingRelationReference reference) =>
    switch (reference) {
      LongTermBlockingRelationReference() => _referenceId(reference),
      DailyChoiceBlockingRelationReference() =>
        'daily-${_referenceId(reference)}',
    };

String _selectedPhrase(
  AppLocalizations localizations,
  BlockingRelationsSelectedItem item,
) => switch (item) {
  BlockingRelationsSelectedLongTerm(:final row) =>
    row.relation.type == LongTermRelationType.need
        ? localizations.relationNeighborhoodNeedPhrase(
            row.source.title,
            row.related.title,
          )
        : localizations.relationNeighborhoodCanPhrase(
            row.source.title,
            row.related.title,
          ),
  BlockingRelationsSelectedDailyChoice(:final item) =>
    localizations.dailyChoiceDetailsPhrase(
      item.source.title,
      item.selected.title,
    ),
};

final class _BlockingRelationsConfirmation extends ConsumerStatefulWidget {
  const _BlockingRelationsConfirmation({
    required this.snapshot,
    required this.provider,
    required this.onOpenDailyChoice,
  });

  final BlockingRelationsPreparedSelection snapshot;
  final BlockingRelationsSelectionViewModelProvider provider;
  final ValueChanged<DailyChoiceId> onOpenDailyChoice;

  @override
  ConsumerState<_BlockingRelationsConfirmation> createState() =>
      _BlockingRelationsConfirmationState();
}

final class _BlockingRelationsConfirmationState
    extends ConsumerState<_BlockingRelationsConfirmation> {
  bool _decided = false;

  void _finish(bool confirmed) {
    if (_decided) {
      return;
    }
    _decided = true;
    Navigator.of(context).pop(confirmed);
  }

  void _openDailyChoice(DailyChoiceId id) {
    _finish(false);
    widget.onOpenDailyChoice(id);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final selection = ref.watch(widget.provider);
    final canConfirm = selection is BlockingRelationsSelectionPrepared;
    final snapshot = selection is BlockingRelationsSelectionPrepared
        ? selection.snapshot
        : widget.snapshot;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.blockingRelationsConfirmationTitle),
        ),
        body: SafeArea(
          child: ListView.builder(
            key: const ValueKey('blocking-relations-confirm-list'),
            itemCount: snapshot.items.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    container: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.blockingRelationsConfirmationWarning,
                        ),
                        if (!canConfirm) ...[
                          const SizedBox(height: 8),
                          Text(switch (selection) {
                            BlockingRelationsSelectionEditing(
                              :final invalidReasons,
                            )
                                when invalidReasons.values.contains(
                                  BlockingRelationsInvalidReason
                                      .referencedByDailyPath,
                                ) =>
                              localizations.blockingRelationsInvalidProtected,
                            BlockingRelationsSelectionRefreshFailed(
                              :final failure,
                            ) =>
                              _refreshFailureMessage(localizations, failure),
                            _ => localizations.blockingRelationsDeleteConflict,
                          }),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          localizations.blockingRelationsConfirmationCount(
                            snapshot.items.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (index <= snapshot.items.length) {
                return switch (snapshot.items[index - 1]) {
                  BlockingRelationsSelectedLongTerm(:final row) =>
                    _ConfirmationRow(
                      row: row,
                      intentionId: snapshot.command.intentionId,
                      description: snapshot.descriptions[row.relation.id],
                    ),
                  BlockingRelationsSelectedDailyChoice(:final item) =>
                    _DailyConfirmationRow(
                      item: item,
                      intentionId: snapshot.command.intentionId,
                      onOpen: () => _openDailyChoice(item.id),
                    ),
                };
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('blocking-relations-cancel'),
                      onPressed: () => _finish(false),
                      child: Text(localizations.detailsCancelEditAction),
                    ),
                    FilledButton(
                      key: const ValueKey('blocking-relations-confirm-delete'),
                      onPressed: canConfirm ? () => _finish(true) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      child: Text(
                        localizations.relationDetailsConfirmDeleteAction,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({
    required this.row,
    required this.intentionId,
    this.description,
  });

  final LongTermRelationSummary row;
  final IntentionId intentionId;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final relation = row.relation;
    final phrase = relation.type == LongTermRelationType.need
        ? localizations.relationNeighborhoodNeedPhrase(
            row.source.title,
            row.related.title,
          )
        : localizations.relationNeighborhoodCanPhrase(
            row.source.title,
            row.related.title,
          );
    final direction = relation.sourceIntentionId == intentionId
        ? localizations.relationNeighborhoodDirectionOutgoing
        : localizations.relationNeighborhoodDirectionIncoming;
    final scope = relation.scope == RelationScope.active
        ? localizations.relationNeighborhoodRelationActive
        : localizations.relationNeighborhoodRelationArchived;
    final relationId = localizations.blockingRelationsInvalidSelectedRelationId(
      relation.id.toCanonicalString(),
    );
    final source =
        '${localizations.relationNeighborhoodSourceParticipant}: ${row.source.title}. '
        '${localizations.blockingRelationsParticipantId(row.source.id.toCanonicalString())}';
    final related =
        '${localizations.relationNeighborhoodRelatedParticipant}: ${row.related.title}. '
        '${localizations.blockingRelationsParticipantId(row.related.id.toCanonicalString())}';
    return Card(
      key: ValueKey(
        'blocking-relations-confirm-row-${relation.id.toCanonicalString()}',
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Semantics(
        key: ValueKey(
          'blocking-relations-confirm-semantics-${relation.id.toCanonicalString()}',
        ),
        container: true,
        label:
            '$phrase. $relationId. $direction. $scope. '
            '${localizations.relationDetailsPriorityLabel}: ${relation.priority.name.toUpperCase()}. '
            '$source. $related. ${description ?? ''}',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phrase, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(relationId),
                Text(direction),
                Text(scope),
                Text(
                  '${localizations.relationDetailsPriorityLabel}: ${relation.priority.name.toUpperCase()}',
                ),
                if (description != null) Text(description!),
                const SizedBox(height: 8),
                Text(
                  '${localizations.relationNeighborhoodSourceParticipant}: ${row.source.title}',
                ),
                Text(
                  localizations.blockingRelationsParticipantId(
                    row.source.id.toCanonicalString(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${localizations.relationNeighborhoodRelatedParticipant}: ${row.related.title}',
                ),
                Text(
                  localizations.blockingRelationsParticipantId(
                    row.related.id.toCanonicalString(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DailyConfirmationRow extends StatelessWidget {
  const _DailyConfirmationRow({
    required this.item,
    required this.intentionId,
    required this.onOpen,
  });

  final DailyChoiceCatalogItem item;
  final IntentionId intentionId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final phrase = localizations.dailyChoiceDetailsPhrase(
      item.source.title,
      item.selected.title,
    );
    final role = item.source.id == intentionId
        ? localizations.relationNeighborhoodDailySourceRole
        : localizations.relationNeighborhoodDailySelectedRole;
    final date = localizations.dailyChoiceDetailsDate(
      item.date.toCanonicalString(),
    );
    final completion = item.isCompleted
        ? localizations.dailyChoiceDetailsCompleted
        : localizations.dailyChoiceDetailsNotCompleted;
    final id = localizations.blockingRelationsParticipantId(
      item.id.toCanonicalString(),
    );
    return Card(
      key: ValueKey(
        'blocking-relations-confirm-daily-${item.id.toCanonicalString()}',
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              key: ValueKey(
                'blocking-relations-confirm-daily-semantics-${item.id.toCanonicalString()}',
              ),
              container: true,
              label: [
                localizations.dailyChoiceDetailsTitle,
                phrase,
                role,
                date,
                completion,
                id,
              ].join('. '),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.dailyChoiceDetailsTitle,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      phrase,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(role),
                    Text(date),
                    Text(completion),
                    Text(id),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: ValueKey(
                'blocking-relations-open-daily-${item.id.toCanonicalString()}',
              ),
              onPressed: onOpen,
              icon: const Icon(Icons.route_outlined),
              label: Text(localizations.relationNeighborhoodOpenDailyChoice),
            ),
          ],
        ),
      ),
    );
  }
}
