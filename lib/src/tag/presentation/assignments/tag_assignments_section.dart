import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/tag_assignments.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../tag_failure_message.dart';
import 'tag_assignments_state.dart';
import 'tag_assignments_view_model.dart';

/// Назначения тегов намерению в его собственном архивном состоянии.
final class TagAssignmentsSection extends ConsumerStatefulWidget {
  const TagAssignmentsSection({
    required this.intentionId,
    required this.isArchived,
    required this.onChooseTag,
    required this.onOpenTag,
    super.key,
  });

  final IntentionId intentionId;
  final bool isArchived;
  final ValueChanged<IntentionId> onChooseTag;
  final ValueChanged<TagId> onOpenTag;

  @override
  ConsumerState<TagAssignmentsSection> createState() =>
      _TagAssignmentsSectionState();
}

final class _TagAssignmentsSectionState
    extends ConsumerState<TagAssignmentsSection> {
  late final GraphCommandCoordinator _coordinator;
  StreamSubscription<GraphCommandCompletion>? _completions;
  TagOperationToken? _activeRemoveToken;
  TagOperationToken? _failureToken;
  GraphInitiatorPresentationClaim? _failureClaim;
  TagCommandFailure? _removeFailure;
  bool _commandBusy = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _completions = _coordinator.completions.listen((_) {
      if (!mounted) return;
      setState(() => _commandBusy = false);
    });
  }

  @override
  void didUpdateWidget(TagAssignmentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentionId != widget.intentionId) {
      _releasePresentation();
      _activeRemoveToken = null;
      _removeFailure = null;
      _commandBusy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_completions?.cancel());
    _releasePresentation();
    super.dispose();
  }

  void _releasePresentation() {
    if (_activeRemoveToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    if (_failureToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _failureToken = null;
    _failureClaim = null;
  }

  bool get _intentionBusy =>
      _activeRemoveToken != null || _coordinator.isRunning(widget.intentionId);

  void _choose(IntentionId intentionId) {
    if (!mounted || widget.intentionId != intentionId || _intentionBusy) return;
    final state = ref.read(tagAssignmentsViewModelProvider(intentionId));
    if (state is! TagAssignmentsLoaded || !state.canUseCurrentItems) return;
    widget.onChooseTag(intentionId);
  }

  void _open(IntentionId intentionId, TagId tagId) {
    if (!mounted || widget.intentionId != intentionId) return;
    final model = ref.read(
      tagAssignmentsViewModelProvider(intentionId).notifier,
    );
    if (!model.canActOn(tagId)) return;
    widget.onOpenTag(tagId);
  }

  void _remove(IntentionId intentionId, Tag tag) {
    if (!mounted || widget.intentionId != intentionId) return;
    final model = ref.read(
      tagAssignmentsViewModelProvider(intentionId).notifier,
    );
    if (_activeRemoveToken != null || !model.canActOn(tag.id)) return;
    _releasePresentation();
    final start = _coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: tag.id, intentionId: intentionId),
    );
    switch (start) {
      case TagCommandAccepted(:final token, :final future):
        setState(() {
          _activeRemoveToken = token;
          _removeFailure = null;
          _commandBusy = false;
        });
        unawaited(_finishRemove(intentionId, token, future));
      case TagCommandAlreadyRunning():
        setState(() {
          _removeFailure = null;
          _commandBusy = true;
        });
      case GraphCommandCoordinatorDraining():
        setState(() {
          _removeFailure = const TagUnexpectedFailure();
          _commandBusy = false;
        });
    }
  }

  Future<void> _finishRemove(
    IntentionId intentionId,
    TagOperationToken token,
    Future<TagCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!mounted ||
          widget.intentionId != intentionId ||
          !identical(_activeRemoveToken, token)) {
        return;
      }
      switch (completion.result) {
        case GraphResultSuccess():
          setState(() => _activeRemoveToken = null);
        case GraphResultFailure(:final failure):
          final canPresentHere = ModalRoute.of(context)?.isCurrent ?? false;
          if (!canPresentHere) {
            _coordinator.releaseInitiatorPresentation(token);
          }
          setState(() {
            _activeRemoveToken = null;
            _removeFailure = canPresentHere ? failure : null;
            _failureToken = canPresentHere ? token : null;
            _failureClaim = canPresentHere
                ? _coordinator.claimInitiatorFailure(token)
                : null;
          });
      }
    } on Object {
      if (!mounted ||
          widget.intentionId != intentionId ||
          !identical(_activeRemoveToken, token)) {
        return;
      }
      _coordinator.releaseInitiatorPresentation(token);
      setState(() {
        _activeRemoveToken = null;
        _removeFailure = const TagUnexpectedFailure();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final intentionId = widget.intentionId;
    final state = ref.watch(tagAssignmentsViewModelProvider(intentionId));
    final model = ref.read(
      tagAssignmentsViewModelProvider(intentionId).notifier,
    );
    final intentionKind = l10n.tagAssignmentsIntention;
    final archiveState = widget.isArchived
        ? l10n.tagAssignmentsArchived
        : l10n.tagAssignmentsActive;
    final canChoose =
        state is TagAssignmentsLoaded &&
        state.canUseCurrentItems &&
        !_intentionBusy;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.tagAssignmentsContext(intentionKind, archiveState),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tagAssignmentsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Tooltip(
            message: l10n.tagAssignmentsChooseSemantic(
              intentionKind,
              archiveState,
            ),
            child: TextButton.icon(
              key: const ValueKey('tag-assignments-choose'),
              onPressed: canChoose ? () => _choose(intentionId) : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.tagAssignmentsChoose),
            ),
          ),
          if (_activeRemoveToken != null)
            _AssignmentStatus(
              message: l10n.tagAssignmentsRemoving,
              loading: true,
            ),
          if (_commandBusy)
            _AssignmentStatus(message: l10n.tagAssignmentAlreadyRunning),
          if (_removeFailure case final failure?)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OperationFailurePresentation(
                claim: _failureClaim,
                message: tagAssignmentFailureMessage(l10n, failure),
                messageKey: const ValueKey('tag-assignments-remove-failure'),
              ),
            ),
          switch (state) {
            TagAssignmentsInitialLoading() => _AssignmentStatus(
              message: l10n.tagAssignmentsLoading,
              loading: true,
            ),
            TagAssignmentsIntentionMissing() => _AssignmentStatus(
              message: l10n.tagAssignmentTargetNotFound,
            ),
            TagAssignmentsInitialFailure(:final failure, :final canRetry) =>
              _AssignmentStatus(
                message: _readFailure(l10n, failure),
                onAction: canRetry ? model.retryInitialLoad : null,
                actionLabel: l10n.commonRetry,
              ),
            TagAssignmentsLoaded loaded => _LoadedAssignments(
              state: loaded,
              model: model,
              canRemove: !_intentionBusy,
              isTagBusy: _coordinator.isTagRunning,
              onRemove: (tag) => _remove(intentionId, tag),
              onOpen: (tagId) => _open(intentionId, tagId),
            ),
          },
        ],
      ),
    );
  }
}

final class _LoadedAssignments extends StatelessWidget {
  const _LoadedAssignments({
    required this.state,
    required this.model,
    required this.canRemove,
    required this.isTagBusy,
    required this.onRemove,
    required this.onOpen,
  });

  final TagAssignmentsLoaded state;
  final TagAssignmentsViewModel model;
  final bool canRemove;
  final bool Function(TagId) isTagBusy;
  final ValueChanged<Tag> onRemove;
  final ValueChanged<TagId> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.freshness == TagAssignmentsFreshness.refreshing)
          _AssignmentStatus(
            message: l10n.tagAssignmentsRefreshing,
            loading: true,
          ),
        if (state.freshness == TagAssignmentsFreshness.stale)
          _AssignmentStatus(
            message: _readFailure(l10n, state.refreshFailure!),
            onAction: state.refreshFailure is TagAssignmentsUnavailableFailure
                ? model.retryRefresh
                : null,
            actionLabel: l10n.commonRetry,
          ),
        if (state.isEmpty && state.canUseCurrentItems)
          _AssignmentStatus(message: l10n.tagAssignmentsEmpty),
        for (final tag in state.items)
          Semantics(
            key: ValueKey('tag-assignment-row-${tag.id.toCanonicalString()}'),
            container: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tag.name.value),
                  Semantics(
                    container: true,
                    child: Tooltip(
                      message: l10n.tagNavigationTag(tag.name.value),
                      child: TextButton.icon(
                        key: ValueKey(
                          'tag-assignment-open-${tag.id.toCanonicalString()}',
                        ),
                        onPressed: model.canActOn(tag.id)
                            ? () => onOpen(tag.id)
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(l10n.tagNavigationTitle),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: l10n.tagAssignmentsRemoveNamed(tag.name.value),
                    child: TextButton.icon(
                      key: ValueKey(
                        'tag-assignment-remove-${tag.id.toCanonicalString()}',
                      ),
                      onPressed:
                          state.canUseCurrentItems &&
                              canRemove &&
                              !isTagBusy(tag.id) &&
                              model.canActOn(tag.id)
                          ? () => onRemove(tag)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(l10n.tagAssignmentsRemove),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final class _AssignmentStatus extends StatelessWidget {
  const _AssignmentStatus({
    required this.message,
    this.loading = false,
    this.onAction,
    this.actionLabel,
  });

  final String message;
  final bool loading;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
          ],
          Text(message),
          if (onAction case final action?) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _readFailure(AppLocalizations l10n, TagAssignmentsReadFailure failure) =>
    switch (failure) {
      TagAssignmentsUnavailableFailure() => l10n.tagAssignmentsUnavailable,
      TagAssignmentsCorruptionFailure() => l10n.tagAssignmentsCorruption,
      TagAssignmentsIntentionNotFound() ||
      TagAssignmentsUnexpectedFailure() => l10n.tagAssignmentsUnexpected,
    };
