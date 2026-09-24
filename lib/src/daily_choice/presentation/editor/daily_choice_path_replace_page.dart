import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/choice_path_draft.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_details.dart';
import '../../domain/daily_choice_id.dart';
import '../daily_choice_command_failure_message.dart';
import 'daily_choice_creation_page.dart';
import 'daily_choice_path_replace_state.dart';
import 'daily_choice_path_replace_view_model.dart';

/// Отдельное подтверждение полной замены пути существующего дневного выбора.
final class DailyChoicePathReplacePage extends ConsumerStatefulWidget {
  factory DailyChoicePathReplacePage({
    required DailyChoiceId choiceId,
    required ConfirmedChoicePath path,
    required Iterable<DailyChoiceCreationStep> steps,
    ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
    Key? key,
  }) {
    final visibleSteps = List<DailyChoiceCreationStep>.unmodifiable(steps);
    DailyChoicePathReplaceProposal(path);
    if (visibleSteps.length != path.steps.length) {
      throw ArgumentError.value(steps, 'steps');
    }
    for (var index = 0; index < visibleSteps.length; index++) {
      final shown = visibleSteps[index].relation;
      final confirmed = path.steps[index];
      if (shown.id != confirmed.relationId ||
          shown.sourceIntentionId != confirmed.sourceIntentionId ||
          shown.relatedIntentionId != confirmed.relatedIntentionId ||
          shown.type != confirmed.type) {
        throw ArgumentError.value(steps, 'steps');
      }
    }
    return DailyChoicePathReplacePage._(
      choiceId: choiceId,
      path: path,
      steps: visibleSteps,
      direction: direction,
      key: key,
    );
  }

  const DailyChoicePathReplacePage._({
    required this.choiceId,
    required this.path,
    required this.steps,
    required this.direction,
    super.key,
  });

  final DailyChoiceId choiceId;
  final ConfirmedChoicePath path;
  final List<DailyChoiceCreationStep> steps;
  final ChoicePathDraftDirection direction;

  @override
  ConsumerState<DailyChoicePathReplacePage> createState() =>
      _DailyChoicePathReplacePageState();
}

final class _DailyChoicePathReplacePageState
    extends ConsumerState<DailyChoicePathReplacePage> {
  late DailyChoicePathReplaceViewModel _model;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _createModel();
  }

  @override
  void didUpdateWidget(covariant DailyChoicePathReplacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choiceId != widget.choiceId ||
        oldWidget.path != widget.path) {
      _model.dispose();
      _createModel();
    }
  }

  void _createModel() {
    _model = DailyChoicePathReplaceViewModel(
      ref.read(personalGraphRepositoryProvider),
      ref.read(graphCommandCoordinatorProvider.notifier),
      widget.choiceId,
    )..addListener(_onModelChanged);
  }

  void _onModelChanged() {
    switch (_model.state) {
      case DailyChoicePathReplaceChoosing():
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _model.state is DailyChoicePathReplaceChoosing) {
            _model.selectPath(widget.path);
          }
        });
      case DailyChoicePathReplaceSucceeded():
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              (ModalRoute.of(context)?.isCurrent ?? false) &&
              Navigator.of(context).canPop()) {
            unawaited(Navigator.of(context).maybePop());
          }
        });
      case DailyChoicePathReplaceRejected():
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          unawaited(
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
          );
        });
      default:
        break;
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final state = _model.state;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.dailyChoiceReplaceTitle)),
        body: SafeArea(
          child: switch (state) {
            DailyChoicePathReplaceLoading() => _Status(
              l10n.dailyChoiceDetailsLoading,
              isLoading: true,
            ),
            DailyChoicePathReplaceChoosing() => _Status(
              l10n.dailyChoiceReplacePreparing,
              isLoading: true,
            ),
            DailyChoicePathReplaceReady(:final details) => _Confirmation(
              details: details,
              steps: widget.steps,
              direction: widget.direction,
              scrollController: _scrollController,
              onConfirm: _model.confirm,
            ),
            DailyChoicePathReplaceSubmitting(:final details) => _Confirmation(
              details: details,
              steps: widget.steps,
              direction: widget.direction,
              scrollController: _scrollController,
              isSubmitting: true,
            ),
            DailyChoicePathReplaceRejected(
              :final details,
              :final failure,
              :final failurePresentation,
              :final canRetry,
            ) =>
              _Confirmation(
                details: details,
                steps: widget.steps,
                direction: widget.direction,
                scrollController: _scrollController,
                failure: dailyChoiceCommandFailureMessage(l10n, failure),
                failurePresentation: failurePresentation,
                onConfirm: canRetry ? _model.confirm : null,
                retry: canRetry,
              ),
            DailyChoicePathReplaceSucceeded() => _Status(
              l10n.dailyChoicePathReplaced,
            ),
            DailyChoicePathReplaceNotFound(:final failurePresentation) =>
              _Status(
                l10n.dailyChoiceDetailsNotFound,
                failurePresentation: failurePresentation,
                onBack: () => unawaited(Navigator.of(context).maybePop()),
              ),
            DailyChoicePathReplaceReadFailed(:final failure, :final canRetry) =>
              _Status(
                switch (failure) {
                  DailyChoiceReadUnavailableFailure() =>
                    l10n.dailyChoiceDetailsUnavailable,
                  DailyChoiceReadCorruptionFailure() =>
                    l10n.dailyChoiceDetailsCorruption,
                  DailyChoiceReadUnexpectedFailure() =>
                    l10n.dailyChoiceDetailsUnexpected,
                },
                onRetry: canRetry ? _model.retryRead : null,
                onBack: () => unawaited(Navigator.of(context).maybePop()),
              ),
          },
        ),
      );
    },
  );
}

final class _Status extends StatelessWidget {
  const _Status(
    this.message, {
    this.isLoading = false,
    this.failurePresentation,
    this.onRetry,
    this.onBack,
  });

  final String message;
  final bool isLoading;
  final GraphInitiatorPresentationClaim? failurePresentation;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) const CircularProgressIndicator(),
            const SizedBox(height: 8),
            if (failurePresentation == null)
              Semantics(
                liveRegion: true,
                child: Text(message, textAlign: TextAlign.center),
              )
            else
              OperationFailurePresentation(
                claim: failurePresentation,
                message: message,
                messageKey: const ValueKey('daily-choice-replace-failure'),
              ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
            if (onBack != null)
              TextButton(
                onPressed: onBack,
                child: Text(l10n.dailyChoiceCreationCancel),
              ),
          ],
        ),
      ),
    );
  }
}

final class _Confirmation extends StatelessWidget {
  const _Confirmation({
    required this.details,
    required this.steps,
    required this.direction,
    required this.scrollController,
    this.isSubmitting = false,
    this.failure,
    this.failurePresentation,
    this.onConfirm,
    this.retry = false,
  });

  final DailyChoiceDetails details;
  final List<DailyChoiceCreationStep> steps;
  final ChoicePathDraftDirection direction;
  final ScrollController scrollController;
  final bool isSubmitting;
  final String? failure;
  final GraphInitiatorPresentationClaim? failurePresentation;
  final VoidCallback? onConfirm;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choice = details.choice;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.dailyChoiceReplaceCurrent,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          l10n.dailyChoiceDetailsPhrase(
            details.source.title,
            details.selected.title,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.dailyChoiceDetailsDate(choice.date.toCanonicalString())),
        Text(
          choice.isCompleted
              ? l10n.dailyChoiceDetailsCompleted
              : l10n.dailyChoiceDetailsNotCompleted,
        ),
        Text(l10n.dailyChoiceDetailsDescription),
        Text(choice.description?.value ?? l10n.dailyChoiceReplaceNoDescription),
        const SizedBox(height: 12),
        Text(l10n.dailyChoiceReplaceFieldsPreserved),
        if (choice.isCompleted)
          Text(l10n.dailyChoiceReplaceCompletionPreserved),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            l10n.dailyChoiceReplaceNewPath,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          direction == ChoicePathDraftDirection.bottomUp
              ? l10n.choicePathBottomTraversal
              : l10n.choicePathDirection,
        ),
        if (direction == ChoicePathDraftDirection.bottomUp)
          Text(l10n.choicePathBottomPathDirection),
        const SizedBox(height: 8),
        Text(l10n.choicePathSource(steps.first.sourceTitle)),
        for (var index = 0; index < steps.length; index++) ...[
          Semantics(
            label: l10n.choicePathStepSemantics(
              index + 1,
              _phrase(l10n, steps[index]),
              steps[index].relation.priority.name.toUpperCase(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_phrase(l10n, steps[index])),
            ),
          ),
          if (index < steps.length - 1)
            Text(
              '${l10n.dailyChoiceDetailsIntermediate}: ${steps[index].relatedTitle}',
            ),
        ],
        Text(l10n.dailyChoiceCreationAction(steps.last.relatedTitle)),
        if (failure != null) ...[
          const SizedBox(height: 16),
          OperationFailurePresentation(
            claim: failurePresentation,
            message: failure!,
            messageKey: const ValueKey('daily-choice-replace-failure'),
          ),
          if (!retry)
            TextButton(
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
              child: Text(l10n.dailyChoiceReplaceChooseAgain),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('daily-choice-replace-confirm'),
          onPressed: onConfirm,
          child: Text(
            isSubmitting
                ? l10n.dailyChoiceReplaceSubmitting
                : retry
                ? l10n.commonRetry
                : l10n.dailyChoiceReplaceConfirm,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('daily-choice-replace-cancel'),
          onPressed: isSubmitting
              ? null
              : () => unawaited(Navigator.of(context).maybePop()),
          child: Text(l10n.dailyChoiceCreationCancel),
        ),
      ],
    );
  }
}

String _phrase(AppLocalizations l10n, DailyChoiceCreationStep step) =>
    step.relation.type == LongTermRelationType.need
    ? l10n.relationNeighborhoodNeedPhrase(step.sourceTitle, step.relatedTitle)
    : l10n.relationNeighborhoodCanPhrase(step.sourceTitle, step.relatedTitle);
