import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
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
    super.key,
  });

  final IntentionId intentionId;
  final String intentionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = blockingRelationsSelectionViewModelProvider(intentionId);
    final selection = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selection is BlockingRelationsSelectionEditing &&
            selection.selected.isNotEmpty)
          FilledButton.icon(
            key: const ValueKey('blocking-relations-review'),
            onPressed: () => _review(context, ref, provider),
            icon: const Icon(Icons.preview_outlined),
            label: Text(localizations.blockingRelationsReviewAction),
          ),
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
    if (!viewModel.prepare()) {
      return;
    }
    final prepared = ref.read(provider) as BlockingRelationsSelectionPrepared;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _BlockingRelationsConfirmation(snapshot: prepared.snapshot),
    );
    if (!context.mounted) {
      return;
    }
    final current = ref.read(provider);
    if (current is! BlockingRelationsSelectionPrepared ||
        !identical(current.snapshot, prepared.snapshot)) {
      return;
    }
    if (confirmed == true) {
      viewModel.confirm(presentationTitle: intentionTitle);
    } else {
      viewModel.cancel();
    }
  }
}

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
    DeleteBlockingRelationsSelectionConflictFailure() =>
      localizations.blockingRelationsDeleteConflict,
    DeleteBlockingRelationsUnavailableFailure() =>
      localizations.blockingRelationsDeleteUnavailable,
    DeleteBlockingRelationsCorruptionFailure() =>
      localizations.blockingRelationsDeleteCorruption,
    DeleteBlockingRelationsUnexpectedFailure() =>
      localizations.blockingRelationsDeleteUnexpected,
  },
};

final class _BlockingRelationsConfirmation extends StatefulWidget {
  const _BlockingRelationsConfirmation({required this.snapshot});

  final BlockingRelationsPreparedSelection snapshot;

  @override
  State<_BlockingRelationsConfirmation> createState() =>
      _BlockingRelationsConfirmationState();
}

final class _BlockingRelationsConfirmationState
    extends State<_BlockingRelationsConfirmation> {
  bool _decided = false;

  void _finish(bool confirmed) {
    if (_decided) {
      return;
    }
    _decided = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.blockingRelationsConfirmationTitle),
        ),
        body: SafeArea(
          child: ListView.builder(
            key: const ValueKey('blocking-relations-confirm-list'),
            itemCount: widget.snapshot.rows.length + 2,
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
                        const SizedBox(height: 8),
                        Text(
                          localizations.blockingRelationsConfirmationCount(
                            widget.snapshot.rows.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (index <= widget.snapshot.rows.length) {
                return _ConfirmationRow(
                  row: widget.snapshot.rows[index - 1],
                  intentionId: widget.snapshot.command.intentionId,
                );
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
                      onPressed: () => _finish(true),
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
  const _ConfirmationRow({required this.row, required this.intentionId});

  final LongTermRelationSummary row;
  final IntentionId intentionId;

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
        label: '$phrase. $direction. $scope. $source. $related',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phrase, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(direction),
                Text(scope),
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
