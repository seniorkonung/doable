import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';
import 'intention_editor_state.dart';
import 'intention_editor_view_model.dart';

@RoutePage()
final class IntentionEditorPage extends ConsumerStatefulWidget {
  const IntentionEditorPage({super.key});

  @override
  ConsumerState<IntentionEditorPage> createState() =>
      _IntentionEditorPageState();
}

final class _IntentionEditorPageState
    extends ConsumerState<IntentionEditorPage> {
  final _formKey = IntentionCreationFormKey();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = intentionEditorViewModelProvider(_formKey);
    final editor = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case IntentionEditorCreated()) {
        notifier.consumeEvent();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(localizations.editorCreated)));
        unawaited(context.router.maybePop());
      }
    });

    final generalFailure = _generalFailure(localizations, editor.operation);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.editorTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('intention-editor-title'),
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: localizations.editorTitleLabel,
                errorText: _fieldFailure(
                  localizations,
                  editor.operation,
                  IntentionTextField.title,
                ),
              ),
              onChanged: notifier.changeTitle,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('intention-editor-description'),
              controller: _descriptionController,
              minLines: 4,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: localizations.editorDescriptionLabel,
                alignLabelWithHint: true,
                errorText: _fieldFailure(
                  localizations,
                  editor.operation,
                  IntentionTextField.description,
                ),
              ),
              onChanged: notifier.changeDescription,
            ),
            if (generalFailure != null) ...[
              const SizedBox(height: 16),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  generalFailure,
                  key: const ValueKey('intention-editor-failure'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('intention-editor-submit'),
              onPressed: editor.canSubmit ? notifier.submit : null,
              child: Text(_submitLabel(localizations, editor)),
            ),
          ],
        ),
      ),
    );
  }

  String _submitLabel(
    AppLocalizations localizations,
    IntentionEditorState editor,
  ) => switch (editor.operation) {
    OperationRunning<Intention>() => localizations.editorCreating,
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) =>
      localizations.commonRetry,
    OperationIdle<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => localizations.editorCreateAction,
  };

  String? _fieldFailure(
    AppLocalizations localizations,
    OperationState<Intention> operation,
    IntentionTextField field,
  ) {
    if (operation
        case OperationFailed<Intention>(
          failure: IntentionTextInputValidationFailure(:final textFailure),
        )
        when textFailure.field == field) {
      return switch ((field, textFailure.reason)) {
        (IntentionTextField.title, IntentionTextValidationReason.empty) =>
          localizations.editorTitleEmpty,
        (IntentionTextField.title, IntentionTextValidationReason.tooLong) =>
          localizations.editorTitleTooLong,
        (
          IntentionTextField.title,
          IntentionTextValidationReason.invalidUnicodeRepertoire,
        ) =>
          localizations.editorTitleInvalidUnicode,
        (
          IntentionTextField.description,
          IntentionTextValidationReason.tooLong,
        ) =>
          localizations.editorDescriptionTooLong,
        (
          IntentionTextField.description,
          IntentionTextValidationReason.invalidUnicodeRepertoire,
        ) =>
          localizations.editorDescriptionInvalidUnicode,
        (IntentionTextField.description, IntentionTextValidationReason.empty) ||
        (IntentionTextField.titleFilter, _) => localizations.editorInvalidInput,
      };
    }
    return null;
  }

  String? _generalFailure(
    AppLocalizations localizations,
    OperationState<Intention> operation,
  ) => switch (operation) {
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() => null,
    OperationFailed<Intention>(:final failure) => switch (failure) {
      IntentionTextInputValidationFailure(:final textFailure)
          when textFailure.field == IntentionTextField.title ||
              textFailure.field == IntentionTextField.description =>
        null,
      IntentionGenericValidationFailure() ||
      IntentionTextInputValidationFailure() => localizations.editorInvalidInput,
      IntentionConflictFailure() => localizations.editorCreateConflict,
      IntentionUnavailableFailure() => localizations.editorCreateUnavailable,
      IntentionCorruptionFailure() => localizations.editorCreateCorruption,
      IntentionNotFoundFailure() ||
      IntentionUnexpectedFailure() => localizations.editorCreateUnexpected,
    },
  };
}
