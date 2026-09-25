import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/choice_path_draft.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_description.dart';
import '../daily_choice_command_failure_message.dart';
import '../path/choice_path_page.dart';
import '../path/choice_path_view_model.dart';
import 'daily_choice_creation_state.dart';
import 'daily_choice_creation_view_model.dart';

/// Данные шага, которые нужны форме для показа подтверждаемого маршрута.
final class DailyChoiceCreationStep {
  const DailyChoiceCreationStep({
    required this.relation,
    required this.sourceTitle,
    required this.relatedTitle,
  });

  DailyChoiceCreationStep.fromSummary(LongTermRelationSummary step)
    : this(
        relation: step.relation,
        sourceTitle: step.source.title,
        relatedTitle: step.related.title,
      );

  DailyChoiceCreationStep.fromSuggestion(DailyChoicePathStepDetails step)
    : this(
        relation: step.relation,
        sourceTitle: step.source.title,
        relatedTitle: step.related.title,
      );

  final LongTermRelation relation;
  final String sourceTitle;
  final String relatedTitle;
}

/// Подтверждение одного видимого пути. Экран не меняет граф до нажатия кнопки.
final class DailyChoiceCreationPage extends ConsumerStatefulWidget {
  const DailyChoiceCreationPage({
    required this.path,
    required this.steps,
    required this.initialDate,
    this.direction = ChoicePathDraftDirection.topDown,
    super.key,
  }) : assert(steps.length > 0);

  final ConfirmedChoicePath path;
  final List<DailyChoiceCreationStep> steps;
  final CalendarDate initialDate;
  final ChoicePathDraftDirection direction;

  @override
  ConsumerState<DailyChoiceCreationPage> createState() =>
      _DailyChoiceCreationPageState();
}

final class _DailyChoiceCreationPageState
    extends ConsumerState<DailyChoiceCreationPage> {
  final _formKey = DailyChoiceCreationFormKey();
  final _dateController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();
  late List<DailyChoiceCreationStep> _visibleSteps;
  var _pathRefreshGeneration = 0;
  var _dateInvalid = false;

  @override
  void initState() {
    super.initState();
    _dateController.text = widget.initialDate.toCanonicalString();
    _visibleSteps = widget.steps;
  }

  @override
  void dispose() {
    _dateController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _changeDate(String text, DailyChoiceCreationViewModel model) {
    try {
      model.changeDate(CalendarDate.parseCanonical(text));
      if (_dateInvalid) setState(() => _dateInvalid = false);
    } on CalendarDateValidationException {
      // Исправимый ввод остаётся в поле до следующего подтверждения.
    }
  }

  void _submit(DailyChoiceCreationViewModel model) {
    try {
      model.changeDate(CalendarDate.parseCanonical(_dateController.text));
      setState(() => _dateInvalid = false);
      model.submit();
    } on CalendarDateValidationException {
      setState(() => _dateInvalid = true);
      _revealFailure();
    }
  }

  Future<void> _refreshPath(DailyChoiceCreationViewModel model) async {
    final generation = ++_pathRefreshGeneration;
    final startingId = switch (widget.direction) {
      ChoicePathDraftDirection.topDown =>
        widget.path.steps.first.sourceIntentionId,
      ChoicePathDraftDirection.bottomUp =>
        widget.path.steps.last.relatedIntentionId,
    };
    ref.invalidate(
      choicePathViewModelProvider(startingId, direction: widget.direction),
    );
    final selection = await Navigator.of(context).push<ChoicePathSelection>(
      MaterialPageRoute(
        builder: (_) => ChoicePathPage.forCreationRefresh(
          startingIntentionId: startingId,
          direction: widget.direction,
        ),
      ),
    );
    if (!mounted || generation != _pathRefreshGeneration || selection == null) {
      return;
    }
    if (!model.confirmRefreshedPath(selection.path)) return;
    setState(() => _visibleSteps = selection.steps);
  }

  void _revealFailure() {
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = dailyChoiceCreationViewModelProvider(
      _formKey,
      widget.path,
      widget.initialDate,
    );
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case DailyChoiceCreationCreated()) {
        model.consumeEvent();
        // Успех после commit предъявляет общая оболочка, включая уход с экрана.
        if (Navigator.of(context).canPop()) {
          unawaited(Navigator.of(context).maybePop());
        }
      } else if (next.operation is DailyChoiceCreationFailed &&
          previous?.operation != next.operation) {
        _revealFailure();
      }
    });

    final descriptionFailure = _descriptionFailure(l10n, state);
    final dateFailure = _dateFailure(l10n, state);
    final generalFailure = _generalFailure(l10n, state);
    final failureMessage =
        (_dateInvalid ? l10n.dailyChoiceDateInvalid : dateFailure) ??
        descriptionFailure ??
        generalFailure;
    final steps = _visibleSteps;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyChoiceCreationTitle)),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.dailyChoiceCreationPath,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.choicePathSource(steps.first.sourceTitle)),
            for (var index = 0; index < steps.length; index++)
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
            Text(l10n.dailyChoiceCreationAction(steps.last.relatedTitle)),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('daily-choice-date'),
              controller: _dateController,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.dailyChoiceCreationDate,
                hintText: 'YYYY-MM-DD',
                helperText: l10n.dailyChoiceCreationDateHint,
                errorText: _dateInvalid || dateFailure != null
                    ? dateFailure ?? l10n.dailyChoiceDateInvalid
                    : null,
              ),
              onChanged: (text) => _changeDate(text, model),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('daily-choice-description'),
              controller: _descriptionController,
              enabled:
                  state.operation is! DailyChoiceCreationSubmitting &&
                  state.operation is! DailyChoiceCreationSucceeded,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: l10n.dailyChoiceCreationDescription,
                alignLabelWithHint: true,
                errorText: descriptionFailure,
              ),
              onChanged: model.changeDescription,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('daily-choice-completed'),
              title: Text(l10n.dailyChoiceCreationCompleted),
              subtitle: Text(l10n.dailyChoiceCreationCompletedHint),
              value: state.isCompleted,
              onChanged:
                  state.operation is DailyChoiceCreationSubmitting ||
                      state.operation is DailyChoiceCreationSucceeded
                  ? null
                  : model.changeCompletion,
            ),
            if (failureMessage != null) ...[
              const SizedBox(height: 12),
              OperationFailurePresentation(
                claim: _dateInvalid ? null : state.failurePresentation,
                message: failureMessage,
                messageKey: const ValueKey('daily-choice-failure'),
              ),
              if (state.needsPathRefresh)
                TextButton(
                  onPressed: () => unawaited(_refreshPath(model)),
                  child: Text(l10n.dailyChoiceCreationRefreshPath),
                ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('daily-choice-submit'),
              onPressed: state.canSubmit ? () => _submit(model) : null,
              child: Text(switch (state.operation) {
                DailyChoiceCreationSubmitting() =>
                  l10n.dailyChoiceCreationSaving,
                DailyChoiceCreationFailed() when state.canRetry =>
                  l10n.commonRetry,
                _ => l10n.dailyChoiceCreationSave,
              }),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('daily-choice-cancel'),
              onPressed:
                  state.operation is DailyChoiceCreationSubmitting ||
                      state.operation is DailyChoiceCreationSucceeded
                  ? null
                  : () => unawaited(Navigator.of(context).maybePop()),
              child: Text(l10n.dailyChoiceCreationCancel),
            ),
          ],
        ),
      ),
    );
  }
}

String _phrase(AppLocalizations l10n, DailyChoiceCreationStep step) =>
    step.relation.type == LongTermRelationType.need
    ? l10n.relationNeighborhoodNeedPhrase(step.sourceTitle, step.relatedTitle)
    : l10n.relationNeighborhoodCanPhrase(step.sourceTitle, step.relatedTitle);

String? _descriptionFailure(
  AppLocalizations l10n,
  DailyChoiceCreationState state,
) => switch (state.operation) {
  DailyChoiceCreationFailed(
    failure: DailyChoiceCreationDescriptionInvalid(failure: final failure),
  ) =>
    switch (failure.reason) {
      DailyChoiceDescriptionValidationReason.tooLong =>
        l10n.editorDescriptionTooLong,
      DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire =>
        l10n.editorDescriptionInvalidUnicode,
      DailyChoiceDescriptionValidationReason.absent =>
        l10n.dailyChoiceDescriptionInvalid,
    },
  DailyChoiceCreationFailed(
    failure: DailyChoiceCreationCommandRejected(
      failure: DailyChoiceValidationFailure(
        field: DailyChoiceValidationField.description,
      ),
    ),
  ) =>
    l10n.dailyChoiceDescriptionInvalid,
  _ => null,
};

String? _dateFailure(AppLocalizations l10n, DailyChoiceCreationState state) =>
    switch (state.operation) {
      DailyChoiceCreationFailed(
        failure: DailyChoiceCreationCommandRejected(
          failure: DailyChoiceValidationFailure(
            field: DailyChoiceValidationField.date,
          ),
        ),
      ) =>
        l10n.dailyChoiceDateInvalid,
      _ => null,
    };

String? _generalFailure(
  AppLocalizations l10n,
  DailyChoiceCreationState state,
) => switch (state.operation) {
  DailyChoiceCreationFailed(
    failure: DailyChoiceCreationCommandRejected(failure: final failure),
  )
      when failure is! DailyChoiceValidationFailure ||
          (failure.field != DailyChoiceValidationField.date &&
              failure.field != DailyChoiceValidationField.description) =>
    dailyChoiceCommandFailureMessage(l10n, failure),
  _ => null,
};
