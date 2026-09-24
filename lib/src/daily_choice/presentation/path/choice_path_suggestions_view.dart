import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/choice_path_suggestions.dart';
import '../../application/daily_choice_details.dart';
import 'choice_path_suggestions_state.dart';

/// Показывает один согласованный снимок; выбор доступен только в готовом состоянии.
final class ChoicePathSuggestionsView extends StatelessWidget {
  const ChoicePathSuggestionsView({
    required this.state,
    required this.onSelected,
    this.onRetry,
    this.onRefresh,
    super.key,
  });

  final ChoicePathSuggestionsState state;
  final ValueChanged<AvailableChoicePathSuggestion> onSelected;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = state.items;
    final canSelect = state is ChoicePathSuggestionsReady;
    final message = switch (state) {
      ChoicePathSuggestionsLoading() => l10n.choiceSuggestionLoading,
      ChoicePathSuggestionsEmpty() => l10n.choiceSuggestionEmpty,
      ChoicePathSuggestionsUpdating() => l10n.choiceSuggestionUpdating,
      ChoicePathSuggestionsNotFound() => l10n.choiceSuggestionNotFound,
      ChoicePathSuggestionsLoadFailure(:final failure) => _failureMessage(
        l10n,
        failure,
      ),
      ChoicePathSuggestionsRefreshFailure(:final failure) => _failureMessage(
        l10n,
        failure,
      ),
      ChoicePathSuggestionsReady() => null,
    };
    final canRetry = switch (state) {
      ChoicePathSuggestionsLoadFailure(:final canRetry) => canRetry,
      ChoicePathSuggestionsRefreshFailure(:final canRetry) => canRetry,
      _ => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.choiceSuggestionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (message != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message),
            ),
          ),
        if (state is ChoicePathSuggestionsLoading ||
            state is ChoicePathSuggestionsUpdating)
          const Center(child: CircularProgressIndicator()),
        if (canRetry && onRetry != null)
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        if (state is ChoicePathSuggestionsCurrent && onRefresh != null)
          TextButton(onPressed: onRefresh, child: Text(l10n.choicePathRefresh)),
        for (var index = 0; index < items.length; index++)
          _SuggestionCard(
            index: index,
            total: items.length,
            suggestion: items[index],
            onSelected: canSelect ? _selectionAction(items[index]) : null,
          ),
      ],
    );
  }

  VoidCallback? _selectionAction(ChoicePathSuggestion suggestion) =>
      switch (suggestion) {
        AvailableChoicePathSuggestion item => () => onSelected(item),
        UnavailableChoicePathSuggestion() => null,
      };
}

String _failureMessage(
  AppLocalizations l10n,
  ChoicePathSuggestionsFailure failure,
) => switch (failure) {
  ChoicePathSuggestionsIntentionNotFoundFailure() =>
    l10n.choiceSuggestionNotFound,
  ChoicePathSuggestionsUnavailableFailure() => l10n.choiceSuggestionUnavailable,
  ChoicePathSuggestionsCorruptionFailure() => l10n.choiceSuggestionCorruption,
  ChoicePathSuggestionsUnexpectedFailure() => l10n.choiceSuggestionUnexpected,
};

final class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.index,
    required this.total,
    required this.suggestion,
    required this.onSelected,
  });

  final int index;
  final int total;
  final ChoicePathSuggestion suggestion;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = switch (suggestion) {
      UnavailableChoicePathSuggestion(:final reason) => _reasonMessage(
        l10n,
        reason,
      ),
      AvailableChoicePathSuggestion() => null,
    };
    final position = l10n.choiceSuggestionPosition(index + 1, total);
    void openPreview() => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _SuggestionPreview(suggestion)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(position)),
            const SizedBox(height: 8),
            Text(l10n.choiceSuggestionSource(suggestion.source.title)),
            Text(l10n.choiceSuggestionAction(suggestion.action.title)),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(reason),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Semantics(
                  button: true,
                  label: '${l10n.choiceSuggestionView}. $position',
                  onTap: openPreview,
                  child: ExcludeSemantics(
                    child: OutlinedButton(
                      key: ValueKey('choice-suggestion-view-$index'),
                      onPressed: openPreview,
                      child: Text(l10n.choiceSuggestionView),
                    ),
                  ),
                ),
                if (onSelected != null)
                  Semantics(
                    button: true,
                    label: '${l10n.choiceSuggestionSelect}. $position',
                    onTap: onSelected,
                    child: ExcludeSemantics(
                      child: FilledButton(
                        key: ValueKey('choice-suggestion-select-$index'),
                        onPressed: onSelected,
                        child: Text(l10n.choiceSuggestionSelect),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonMessage(
  AppLocalizations l10n,
  ChoicePathSuggestionUnavailableReason reason,
) => switch (reason) {
  ChoicePathSuggestionUnavailableReason.archivedIntention =>
    l10n.choiceSuggestionArchivedIntention,
  ChoicePathSuggestionUnavailableReason.archivedRelation =>
    l10n.choiceSuggestionArchivedRelation,
  ChoicePathSuggestionUnavailableReason.actionNotReady =>
    l10n.choiceSuggestionActionNotReady,
};

final class _SuggestionPreview extends StatelessWidget {
  const _SuggestionPreview(this.suggestion);

  final ChoicePathSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = suggestion.path;
    final reason = switch (suggestion) {
      UnavailableChoicePathSuggestion(:final reason) => _reasonMessage(
        l10n,
        reason,
      ),
      AvailableChoicePathSuggestion() => null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.choiceSuggestionPreviewTitle)),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 2 + path.length * 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.choiceSuggestionDirection,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (reason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(reason),
                    ),
                ],
              );
            }
            if (index == 1) {
              return _IntentionTile(
                intention: suggestion.source,
                role: l10n.dailyChoiceDetailsSource,
              );
            }
            final stepIndex = (index - 2) ~/ 2;
            final step = path[stepIndex];
            if (index.isEven) {
              return _RelationTile(
                step: step,
                position: stepIndex + 1,
                total: path.length,
              );
            }
            return _IntentionTile(
              intention: step.related,
              role: stepIndex == path.length - 1
                  ? l10n.dailyChoiceDetailsSelectedAction
                  : l10n.dailyChoiceDetailsIntermediate,
              showReadiness: stepIndex == path.length - 1,
            );
          },
        ),
      ),
    );
  }
}

final class _IntentionTile extends StatelessWidget {
  const _IntentionTile({
    required this.intention,
    required this.role,
    this.showReadiness = false,
  });

  final Intention intention;
  final String role;
  final bool showReadiness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = intention.archiveState == IntentionArchiveState.archived
        ? l10n.dailyChoiceDetailsArchived
        : l10n.dailyChoiceDetailsActive;
    final readiness = intention.readiness == IntentionReadiness.ready
        ? l10n.dailyChoiceDetailsReady
        : l10n.dailyChoiceDetailsNotReady;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$role: ${intention.title}'),
      subtitle: Text(showReadiness ? '$scope · $readiness' : scope),
    );
  }
}

final class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.step,
    required this.position,
    required this.total,
  });

  final DailyChoicePathStepDetails step;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relation = step.relation;
    final type = relation.type == LongTermRelationType.need
        ? l10n.relationNeighborhoodTypeNeed
        : l10n.relationNeighborhoodTypeCan;
    final phrase = relation.type == LongTermRelationType.need
        ? l10n.relationNeighborhoodNeedPhrase(
            step.source.title,
            step.related.title,
          )
        : l10n.relationNeighborhoodCanPhrase(
            step.source.title,
            step.related.title,
          );
    final scope = relation.scope == RelationScope.archived
        ? l10n.dailyChoiceDetailsArchived
        : l10n.dailyChoiceDetailsActive;
    final priority = 'P${relation.priority.index + 1}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.choiceSuggestionStep(position, total)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$type: $phrase'),
          Text('${l10n.relationDetailsPriorityLabel}: $priority · $scope'),
          if (step.description != null) Text(step.description!.value),
        ],
      ),
    );
  }
}
