import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/tag_chip.dart';
import '../../../design_system/components/tags_section.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/tag_assignments.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../tag_color_presentation.dart';
import '../tag_failure_message.dart';
import 'tag_assignments_state.dart';
import 'tag_assignments_view_model.dart';

/// Назначения тегов намерению в его собственном архивном состоянии.
final class TagAssignmentsSection extends ConsumerStatefulWidget {
  const TagAssignmentsSection({
    required this.intentionId,
    required this.isArchived,
    required this.onChooseTag,
    super.key,
  });

  final IntentionId intentionId;
  final bool isArchived;
  final ValueChanged<IntentionId> onChooseTag;

  @override
  ConsumerState<TagAssignmentsSection> createState() =>
      _TagAssignmentsSectionState();
}

final class _TagAssignmentsSectionState
    extends ConsumerState<TagAssignmentsSection> {
  late final GraphCommandCoordinator _coordinator;
  StreamSubscription<GraphCommandCompletion>? _completions;
  TagOperationToken? _activeRemoveToken;

  /// Отказ снятия, который не является результатом операции: старт не принят
  /// или ожидание прервалось. Отказы операции предъявляет общая поверхность.
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
      _activeRemoveToken = null;
      _removeFailure = null;
      _commandBusy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_completions?.cancel());
    super.dispose();
  }

  bool get _intentionBusy =>
      _activeRemoveToken != null || _coordinator.isRunning(widget.intentionId);

  void _choose(IntentionId intentionId) {
    if (!mounted || widget.intentionId != intentionId || _intentionBusy) return;
    final state = ref.read(tagAssignmentsViewModelProvider(intentionId));
    if (state is! TagAssignmentsLoaded || !state.canUseCurrentItems) return;
    widget.onChooseTag(intentionId);
  }

  void _remove(IntentionId intentionId, Tag tag) {
    if (!mounted || widget.intentionId != intentionId) return;
    final model = ref.read(
      tagAssignmentsViewModelProvider(intentionId).notifier,
    );
    if (_activeRemoveToken != null || !model.canActOn(tag.id)) return;
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
      await future;
      if (!mounted ||
          widget.intentionId != intentionId ||
          !identical(_activeRemoveToken, token)) {
        return;
      }
      setState(() => _activeRemoveToken = null);
    } on Object {
      if (!mounted ||
          widget.intentionId != intentionId ||
          !identical(_activeRemoveToken, token)) {
        return;
      }
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
    final archiveState = widget.isArchived
        ? l10n.tagAssignmentsArchived
        : l10n.tagAssignmentsActive;
    final canChoose =
        state is TagAssignmentsLoaded &&
        state.canUseCurrentItems &&
        !_intentionBusy;
    final tags = switch (state) {
      TagAssignmentsLoaded(:final items) => items,
      _ => const <Tag>[],
    };

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.tagAssignmentsContext(
        l10n.tagAssignmentsIntention,
        archiveState,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TagsSection(
            title: l10n.tagAssignmentsTitle,
            addText: l10n.tagAssignmentsAdd,
            addLabel: tags.isEmpty
                ? l10n.tagAssignmentsAddEmptyLabel
                : l10n.tagAssignmentsAddLabel(
                    tags.map((tag) => tag.name.value).join(', '),
                  ),
            onAdd: canChoose ? () => _choose(intentionId) : null,
            addKey: const ValueKey('tag-assignments-choose'),
            chips: [
              if (state case final TagAssignmentsLoaded loaded)
                for (final tag in loaded.items)
                  TagChip.medium(
                    key: ValueKey(
                      'tag-assignment-row-${tag.id.toCanonicalString()}',
                    ),
                    name: tag.name.value,
                    color: tagColorPresentation(tag.color),
                    removeLabel: l10n.tagAssignmentsRemoveNamed(tag.name.value),
                    removeKey: ValueKey(
                      'tag-assignment-remove-${tag.id.toCanonicalString()}',
                    ),
                    onRemove:
                        loaded.canUseCurrentItems &&
                            !_intentionBusy &&
                            !_coordinator.isTagRunning(tag.id) &&
                            model.canActOn(tag.id)
                        ? () => _remove(intentionId, tag)
                        : null,
                  ),
            ],
          ),
          for (final status in [
            if (_activeRemoveToken != null)
              ListState.loading(text: l10n.tagAssignmentsRemoving),
            if (_commandBusy) Notice(message: l10n.tagAssignmentAlreadyRunning),
            if (_removeFailure case final failure?)
              Notice.content(
                message: OperationFailurePresentation(
                  claim: null,
                  message: tagAssignmentFailureMessage(l10n, failure),
                  messageKey: const ValueKey('tag-assignments-remove-failure'),
                  inheritsColor: true,
                ),
              ),
            ...switch (state) {
              TagAssignmentsInitialLoading() => [
                ListState.loading(text: l10n.tagAssignmentsLoading),
              ],
              TagAssignmentsIntentionMissing() => [
                ListState.error(message: l10n.tagAssignmentIntentionNotFound),
              ],
              TagAssignmentsInitialFailure(:final failure, :final canRetry) => [
                ListState.error(
                  message: _readFailure(l10n, failure),
                  retry: canRetry
                      ? (
                          label: l10n.commonRetry,
                          onPressed: model.retryInitialLoad,
                        )
                      : null,
                ),
              ],
              TagAssignmentsLoaded(:final freshness, :final refreshFailure) =>
                switch (freshness) {
                  TagAssignmentsFreshness.refreshing => [
                    ListState.loading(text: l10n.tagAssignmentsRefreshing),
                  ],
                  TagAssignmentsFreshness.stale => [
                    Notice.content(
                      message: Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(_readFailure(l10n, refreshFailure!)),
                      ),
                      action: refreshFailure is TagAssignmentsUnavailableFailure
                          ? (
                              label: l10n.commonRetry,
                              onPressed: model.retryRefresh,
                            )
                          : null,
                    ),
                  ],
                  TagAssignmentsFreshness.current => const <Widget>[],
                },
            },
          ])
            Padding(
              padding: const EdgeInsets.only(top: DoableMetrics.space2),
              child: status,
            ),
        ],
      ),
    );
  }
}

String _readFailure(AppLocalizations l10n, TagAssignmentsReadFailure failure) =>
    switch (failure) {
      TagAssignmentsUnavailableFailure() => l10n.tagAssignmentsUnavailable,
      TagAssignmentsCorruptionFailure() => l10n.tagAssignmentsCorruption,
      TagAssignmentsIntentionNotFound() ||
      TagAssignmentsUnexpectedFailure() => l10n.tagAssignmentsUnexpected,
    };
