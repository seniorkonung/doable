import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../application/choice_path_continuations.dart';
import '../../application/choice_path_draft.dart';
import '../../application/choice_path_suggestions.dart';
import '../../application/confirmed_choice_path.dart';
import '../../domain/calendar_date.dart';
import '../editor/daily_choice_creation_page.dart';
import 'choice_path_state.dart';
import 'choice_path_suggestions_view.dart';
import 'choice_path_suggestions_view_model.dart';
import 'choice_path_view_model.dart';

@RoutePage()
final class ChoicePathPage extends ConsumerStatefulWidget {
  const ChoicePathPage({required this.sourceIntentionId, super.key})
    : direction = ChoicePathDraftDirection.topDown,
      purpose = ChoicePathPurpose.create;

  const ChoicePathPage.fromAction({
    required IntentionId actionIntentionId,
    super.key,
  }) : sourceIntentionId = actionIntentionId,
       direction = ChoicePathDraftDirection.bottomUp,
       purpose = ChoicePathPurpose.create;

  const ChoicePathPage.forCreationRefresh({
    required IntentionId startingIntentionId,
    required this.direction,
    super.key,
  }) : sourceIntentionId = startingIntentionId,
       purpose = ChoicePathPurpose.refreshCreation;

  const ChoicePathPage.forReplacement({
    required IntentionId startingIntentionId,
    required this.direction,
    super.key,
  }) : sourceIntentionId = startingIntentionId,
       purpose = ChoicePathPurpose.replace;

  final IntentionId sourceIntentionId;
  final ChoicePathDraftDirection direction;
  final ChoicePathPurpose purpose;

  @override
  ConsumerState<ChoicePathPage> createState() => _ChoicePathPageState();
}

enum ChoicePathPurpose { create, refreshCreation, replace }

final class ChoicePathSelection {
  ChoicePathSelection({
    required this.path,
    required Iterable<DailyChoiceCreationStep> steps,
  }) : steps = List<DailyChoiceCreationStep>.unmodifiable(steps);

  final ConfirmedChoicePath path;
  final List<DailyChoiceCreationStep> steps;
}

final class _ChoicePathPageState extends ConsumerState<ChoicePathPage> {
  late final ChoicePathSuggestionsViewModel _suggestions;
  ConfirmedChoicePath? _selectedPath;
  GraphRevision? _selectedRevision;
  bool _openingConfirmation = false;

  @override
  void initState() {
    super.initState();
    _suggestions = ChoicePathSuggestionsViewModel.fromCoordinator(
      ref.read(personalGraphRepositoryProvider),
      ref.read(graphCommandCoordinatorProvider.notifier),
      switch (widget.direction) {
        ChoicePathDraftDirection.topDown => ChoicePathSuggestionsForSource(
          widget.sourceIntentionId,
        ),
        ChoicePathDraftDirection.bottomUp => ChoicePathSuggestionsForAction(
          widget.sourceIntentionId,
        ),
      },
    );
  }

  @override
  void dispose() {
    _suggestions.dispose();
    super.dispose();
  }

  Future<void> _openConfirmation(ChoicePathSelection selection) async {
    if (_openingConfirmation) return;
    _openingConfirmation = true;
    if (widget.purpose != ChoicePathPurpose.create) {
      Navigator.of(context).pop(selection);
      return;
    }
    final now = DateTime.now();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DailyChoiceCreationPage(
          path: selection.path,
          steps: selection.steps,
          direction: widget.direction,
          initialDate: CalendarDate.fromParts(now.year, now.month, now.day),
        ),
      ),
    );
    if (!mounted) return;
    _openingConfirmation = false;
    setState(() {
      _selectedPath = null;
      _selectedRevision = null;
    });
    unawaited(
      ref
          .read(
            choicePathViewModelProvider(
              widget.sourceIntentionId,
              direction: widget.direction,
            ).notifier,
          )
          .refresh(),
    );
  }

  void _selectSuggestion(AvailableChoicePathSuggestion suggestion) {
    if (!identical(
      _suggestions.confirmable(suggestion.originChoiceId),
      suggestion,
    )) {
      return;
    }
    unawaited(
      _openConfirmation(
        ChoicePathSelection(
          path: suggestion.confirmedPath,
          steps: [
            for (final step in suggestion.path)
              DailyChoiceCreationStep.fromSuggestion(step),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = choicePathViewModelProvider(
      widget.sourceIntentionId,
      direction: widget.direction,
    );
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final confirmed = state.confirmedPath;
    final selected =
        state is ChoicePathConfirmedState &&
        confirmed != null &&
        _selectedPath != null &&
        _selectedRevision != null &&
        state.revision.compareTo(_selectedRevision!) ==
            GraphRevisionOrder.same &&
        _samePath(confirmed, _selectedPath!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.purpose == ChoicePathPurpose.replace
              ? l10n.dailyChoiceReplaceSelectPath
              : widget.direction == ChoicePathDraftDirection.bottomUp
              ? l10n.choicePathBottomTitle
              : l10n.choicePathTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.direction == ChoicePathDraftDirection.bottomUp
                  ? l10n.choicePathBottomTraversal
                  : l10n.choicePathDirection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (widget.direction == ChoicePathDraftDirection.bottomUp) ...[
              Text(l10n.choicePathBottomPathDirection),
              const SizedBox(height: 12),
            ],
            ListenableBuilder(
              listenable: _suggestions,
              builder: (context, _) => ChoicePathSuggestionsView(
                state: _suggestions.state,
                onSelected: _selectSuggestion,
                onRetry: _suggestions.retry,
                onRefresh: _suggestions.refresh,
              ),
            ),
            const SizedBox(height: 16),
            _PathPrefix(
              state: state,
              onBack: (stepCount) {
                setState(() {
                  _selectedPath = null;
                  _selectedRevision = null;
                });
                model.backToStep(stepCount);
              },
            ),
            if (selected) ...[
              const SizedBox(height: 16),
              Semantics(
                key: ValueKey(
                  widget.direction == ChoicePathDraftDirection.bottomUp
                      ? 'choice-path-selected-source'
                      : 'choice-path-selected-action',
                ),
                liveRegion: true,
                child: Text(
                  widget.direction == ChoicePathDraftDirection.bottomUp
                      ? l10n.choicePathSourceSelected
                      : l10n.choicePathActionSelected,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('choice-path-open-confirmation'),
                onPressed: () => unawaited(
                  _openConfirmation(
                    ChoicePathSelection(
                      path: confirmed,
                      steps: [
                        for (final step in state.visibleSteps)
                          DailyChoiceCreationStep.fromSummary(step),
                      ],
                    ),
                  ),
                ),
                child: Text(
                  widget.purpose == ChoicePathPurpose.replace
                      ? l10n.dailyChoiceReplaceOpenConfirmation
                      : l10n.choicePathOpenConfirmation,
                ),
              ),
            ],
            if (confirmed != null && state is ChoicePathConfirmedState) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: ValueKey(
                  widget.direction == ChoicePathDraftDirection.bottomUp
                      ? 'choice-path-select-source'
                      : 'choice-path-select-action',
                ),
                onPressed: () => setState(() {
                  _selectedPath = confirmed;
                  _selectedRevision = state.revision;
                }),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  widget.direction == ChoicePathDraftDirection.bottomUp
                      ? l10n.choicePathSelectSource(state.current.title)
                      : l10n.choicePathSelectAction(state.current.title),
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.choicePathSelectionNotSaved),
            ],
            const SizedBox(height: 24),
            Text(
              l10n.choicePathContinuations,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            switch (state) {
              ChoicePathLoading() => _Status(
                message: l10n.choicePathLoading,
                loading: true,
              ),
              ChoicePathEmpty() => _Status(
                key: const ValueKey('choice-path-empty'),
                message: state.draft.steps.isEmpty
                    ? widget.direction == ChoicePathDraftDirection.bottomUp
                          ? l10n.choicePathBottomNoPath
                          : l10n.choicePathNoPath
                    : l10n.choicePathNoFurtherPath,
              ),
              ChoicePathData() => _ContinuationList(
                state: state,
                onSelect: (id) {
                  setState(() {
                    _selectedPath = null;
                    _selectedRevision = null;
                  });
                  model.selectContinuation(id);
                },
                onLoadMore: () => unawaited(model.loadMore()),
                onRetry: () => unawaited(model.retry()),
              ),
              ChoicePathConflict() => _Status(
                key: const ValueKey('choice-path-conflict'),
                message: l10n.choicePathConflict,
                actionLabel: l10n.choicePathRefresh,
                actionKey: const ValueKey('choice-path-refresh'),
                onAction: () => unawaited(model.refresh()),
              ),
              ChoicePathNotFound() => _Status(message: l10n.choicePathNotFound),
              ChoicePathFailure(:final failure, :final canRetry) => _Status(
                key: const ValueKey('choice-path-failure'),
                message: _failureMessage(l10n, failure),
                actionLabel: canRetry ? l10n.commonRetry : null,
                actionKey: const ValueKey('choice-path-retry'),
                onAction: canRetry ? () => unawaited(model.retry()) : null,
              ),
            },
          ],
        ),
      ),
    );
  }
}

final class _PathPrefix extends StatelessWidget {
  const _PathPrefix({required this.state, required this.onBack});

  final ChoicePathState state;
  final ValueChanged<int> onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = state.visibleSteps;
    final bottomUp = state.draft.direction == ChoicePathDraftDirection.bottomUp;
    final current = state is ChoicePathConfirmedState
        ? (state as ChoicePathConfirmedState).current.title
        : null;
    final source = steps.isNotEmpty
        ? steps.first.source.title
        : bottomUp
        ? null
        : current;
    final action = bottomUp
        ? steps.isNotEmpty
              ? steps.last.related.title
              : current
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bottomUp) ...[
          if (action != null)
            _PathNode(
              label: l10n.choicePathFixedAction(action),
              backLabel: steps.isNotEmpty
                  ? l10n.choicePathReturnTo(action)
                  : null,
              backKey: const ValueKey('choice-path-back-0'),
              onBack: steps.isNotEmpty ? () => onBack(0) : null,
            )
          else
            Text(l10n.choicePathActionPending),
          if (steps.isNotEmpty) const SizedBox(height: 8),
        ],
        if (source != null)
          _PathNode(
            label: bottomUp
                ? l10n.choicePathCurrentSource(source)
                : l10n.choicePathSource(source),
            backLabel: !bottomUp && steps.isNotEmpty
                ? l10n.choicePathReturnTo(source)
                : null,
            backKey: const ValueKey('choice-path-back-0'),
            onBack: !bottomUp && steps.isNotEmpty ? () => onBack(0) : null,
          ),
        for (var index = 0; index < steps.length; index++) ...[
          const Icon(Icons.arrow_downward, semanticLabel: null),
          Semantics(
            explicitChildNodes: true,
            label: l10n.choicePathStepSemantics(
              index + 1,
              _relationPhrase(l10n, steps[index]),
              _priorityLabel(steps[index].relation),
            ),
            child: _PathNode(
              label: _relationPhrase(l10n, steps[index]),
              subtitle: _priorityLabel(steps[index].relation),
              backLabel: index + 1 < steps.length
                  ? l10n.choicePathReturnTo(steps[index].related.title)
                  : null,
              backKey: ValueKey(
                'choice-path-back-${bottomUp ? steps.length - index - 1 : index + 1}',
              ),
              onBack: index + 1 < steps.length
                  ? () =>
                        onBack(bottomUp ? steps.length - index - 1 : index + 1)
                  : null,
            ),
          ),
        ],
        if (!bottomUp && source == null && steps.isEmpty)
          Text(l10n.choicePathSourcePending),
      ],
    );
  }
}

final class _PathNode extends StatelessWidget {
  const _PathNode({
    required this.label,
    required this.backKey,
    this.subtitle,
    this.backLabel,
    this.onBack,
  });

  final String label;
  final String? subtitle;
  final String? backLabel;
  final Key backKey;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          if (subtitle != null) Text(subtitle!),
          if (onBack != null)
            TextButton(
              key: backKey,
              onPressed: onBack,
              child: Text(backLabel!),
            ),
        ],
      ),
    ),
  );
}

final class _ContinuationList extends StatelessWidget {
  const _ContinuationList({
    required this.state,
    required this.onSelect,
    required this.onLoadMore,
    required this.onRetry,
  });

  final ChoicePathData state;
  final ValueChanged<LongTermRelationId> onSelect;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < state.items.length; index++) ...[
          if (index == 0 ||
              state.items[index - 1].relation.type !=
                  state.items[index].relation.type)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                state.items[index].relation.type == LongTermRelationType.need
                    ? l10n.relationNeighborhoodTypeNeed
                    : l10n.relationNeighborhoodTypeCan,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          Semantics(
            button: true,
            label: l10n.choicePathContinueSemantics(
              _relationPhrase(l10n, state.items[index]),
              _priorityLabel(state.items[index].relation),
            ),
            child: OutlinedButton(
              key: ValueKey(
                'choice-path-continue-${state.items[index].relation.id.toCanonicalString()}',
              ),
              onPressed: () => onSelect(state.items[index].relation.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_relationPhrase(l10n, state.items[index])),
                    Text(_priorityLabel(state.items[index].relation)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (state.nextCursor != null)
          OutlinedButton(
            key: const ValueKey('choice-path-load-more'),
            onPressed: switch (state.progress) {
              ChoicePathPageIdle() => onLoadMore,
              ChoicePathPageLoading() => null,
              ChoicePathPageFailure(:final canRetry) =>
                canRetry ? onLoadMore : null,
            },
            child: Text(l10n.choicePathLoadMore),
          ),
        switch (state.progress) {
          ChoicePathPageLoading() => _Status(
            message: l10n.choicePathLoadingMore,
            loading: true,
          ),
          ChoicePathPageFailure(:final failure, :final canRetry) => _Status(
            message: _failureMessage(l10n, failure),
            actionLabel: canRetry ? l10n.commonRetry : null,
            onAction: canRetry ? onRetry : null,
          ),
          ChoicePathPageIdle() => const SizedBox.shrink(),
        },
      ],
    );
  }
}

final class _Status extends StatelessWidget {
  const _Status({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.actionKey,
    this.onAction,
    super.key,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) const LinearProgressIndicator(),
        Text(message),
        if (onAction != null)
          TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    ),
  );
}

String _relationPhrase(AppLocalizations l10n, LongTermRelationSummary item) =>
    item.relation.type == LongTermRelationType.need
    ? l10n.relationNeighborhoodNeedPhrase(item.source.title, item.related.title)
    : l10n.relationNeighborhoodCanPhrase(item.source.title, item.related.title);

String _priorityLabel(LongTermRelation relation) =>
    relation.priority.name.toUpperCase();

String _failureMessage(
  AppLocalizations l10n,
  ChoicePathContinuationFailure failure,
) => switch (failure) {
  ChoicePathContinuationValidationFailure() => l10n.choicePathInvalid,
  ChoicePathContinuationIntentionNotFoundFailure() => l10n.choicePathNotFound,
  ChoicePathContinuationSnapshotExpired() => l10n.choicePathConflict,
  ChoicePathContinuationUnavailableFailure() => l10n.choicePathUnavailable,
  ChoicePathContinuationCorruptionFailure() => l10n.choicePathCorruption,
  ChoicePathContinuationUnexpectedFailure() => l10n.choicePathUnexpected,
};

bool _samePath(ConfirmedChoicePath left, ConfirmedChoicePath right) {
  if (left.steps.length != right.steps.length) {
    return false;
  }
  for (var index = 0; index < left.steps.length; index++) {
    if (left.steps[index].relationId != right.steps[index].relationId ||
        left.steps[index].sourceIntentionId !=
            right.steps[index].sourceIntentionId ||
        left.steps[index].relatedIntentionId !=
            right.steps[index].relatedIntentionId ||
        left.steps[index].type != right.steps[index].type) {
      return false;
    }
  }
  return true;
}
