import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_description.dart';
import '../daily_choice_command_failure_message.dart';
import 'daily_choice_edit_state.dart';
import 'daily_choice_edit_view_model.dart';

@RoutePage()
final class DailyChoiceEditPage extends ConsumerStatefulWidget {
  const DailyChoiceEditPage({required this.details, super.key});

  final DailyChoiceDetails details;

  @override
  ConsumerState<DailyChoiceEditPage> createState() =>
      _DailyChoiceEditPageState();
}

final class _DailyChoiceEditPageState
    extends ConsumerState<DailyChoiceEditPage> {
  final _dateController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();
  var _dateInvalid = false;

  @override
  void initState() {
    super.initState();
    final choice = widget.details.choice;
    _dateController.text = choice.date.toCanonicalString();
    _descriptionController.text = choice.description?.value ?? '';
  }

  @override
  void dispose() {
    _dateController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _changeDate(String text, DailyChoiceEditViewModel model) {
    try {
      model.changeDate(CalendarDate.parseCanonical(text));
      if (_dateInvalid) setState(() => _dateInvalid = false);
    } on CalendarDateValidationException {
      // Ввод остаётся в поле, пока пользователь исправляет дату.
      setState(() {});
    }
  }

  void _submit(DailyChoiceEditViewModel model) {
    try {
      model.changeDate(CalendarDate.parseCanonical(_dateController.text));
      if (_dateInvalid) setState(() => _dateInvalid = false);
      model.submit();
    } on CalendarDateValidationException {
      setState(() => _dateInvalid = true);
      _revealFailure();
    }
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
    final provider = dailyChoiceEditViewModelProvider(widget.details.choice);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.operation is DailyChoiceEditSucceeded &&
          previous?.operation is! DailyChoiceEditSucceeded) {
        // Подтверждённый успех предъявляет оболочка приложения.
        if (Navigator.of(context).canPop()) {
          unawaited(Navigator.of(context).maybePop());
        }
      } else if (next.operation is DailyChoiceEditFailed &&
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
    final isSubmitting = state.operation is DailyChoiceEditSubmitting;
    final canSubmit =
        state.canSubmit ||
        (state.operation is DailyChoiceEditIdle &&
            _dateController.text != state.date.toCanonicalString());
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyChoiceEditTitle)),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.dailyChoiceDetailsPhrase(
                widget.details.source.title,
                widget.details.selected.title,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('daily-choice-edit-date'),
              controller: _dateController,
              enabled: !isSubmitting,
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
              key: const ValueKey('daily-choice-edit-description'),
              controller: _descriptionController,
              enabled: !isSubmitting,
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
              key: const ValueKey('daily-choice-edit-completed'),
              title: Text(l10n.dailyChoiceCreationCompleted),
              subtitle: Text(l10n.dailyChoiceCreationCompletedHint),
              value: state.isCompleted,
              onChanged: isSubmitting ? null : model.changeCompletion,
            ),
            if (failureMessage != null) ...[
              const SizedBox(height: 12),
              OperationFailurePresentation(
                claim: _dateInvalid ? null : state.failurePresentation,
                message: failureMessage,
                messageKey: const ValueKey('daily-choice-edit-failure'),
              ),
              if (state.operation case DailyChoiceEditFailed(
                failure: DailyChoiceEditCommandRejected(
                  failure: DailyChoiceConflictFailure() ||
                      DailyChoiceNotFoundFailure(),
                ),
              ))
                TextButton(
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                  child: Text(l10n.dailyChoiceEditRefresh),
                ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('daily-choice-edit-submit'),
              onPressed: canSubmit ? () => _submit(model) : null,
              child: Text(switch (state.operation) {
                DailyChoiceEditSubmitting() => l10n.dailyChoiceCreationSaving,
                DailyChoiceEditFailed() when state.canRetry => l10n.commonRetry,
                _ => l10n.dailyChoiceEditSave,
              }),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('daily-choice-edit-cancel'),
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
              child: Text(l10n.dailyChoiceCreationCancel),
            ),
          ],
        ),
      ),
    );
  }
}

String? _descriptionFailure(
  AppLocalizations l10n,
  DailyChoiceEditState state,
) => switch (state.operation) {
  DailyChoiceEditFailed(
    failure: DailyChoiceEditDescriptionInvalid(failure: final failure),
  ) =>
    switch (failure.reason) {
      DailyChoiceDescriptionValidationReason.tooLong =>
        l10n.editorDescriptionTooLong,
      DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire =>
        l10n.editorDescriptionInvalidUnicode,
      DailyChoiceDescriptionValidationReason.absent =>
        l10n.dailyChoiceDescriptionInvalid,
    },
  DailyChoiceEditFailed(
    failure: DailyChoiceEditCommandRejected(
      failure: DailyChoiceValidationFailure(
        field: DailyChoiceValidationField.description,
      ),
    ),
  ) =>
    l10n.dailyChoiceDescriptionInvalid,
  _ => null,
};

String? _dateFailure(AppLocalizations l10n, DailyChoiceEditState state) =>
    switch (state.operation) {
      DailyChoiceEditFailed(
        failure: DailyChoiceEditCommandRejected(
          failure: DailyChoiceValidationFailure(
            field: DailyChoiceValidationField.date,
          ),
        ),
      ) =>
        l10n.dailyChoiceDateInvalid,
      _ => null,
    };

String? _generalFailure(AppLocalizations l10n, DailyChoiceEditState state) =>
    switch (state.operation) {
      DailyChoiceEditFailed(
        failure: DailyChoiceEditCommandRejected(failure: final failure),
      )
          when failure is! DailyChoiceValidationFailure ||
              (failure.field != DailyChoiceValidationField.date &&
                  failure.field != DailyChoiceValidationField.description) =>
        dailyChoiceCommandFailureMessage(l10n, failure),
      _ => null,
    };
