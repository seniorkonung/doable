import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';
import 'intention_editor_state.dart';
import 'intention_editor_view_model.dart';

/// Хост сессии создания намерения.
///
/// Любой уход с формы — кнопка «назад», системное «назад» и программный
/// `maybePop` — сначала обращается к единому решению сессии о закрытии и не
/// удаляет маршрут сам. Маршрут формы закрывается только по завершению
/// сессии: сразу для неизменённого черновика, после подтверждённого сброса
/// или успешного создания.
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

  /// Маршрут формы уже закрывается после завершения сессии.
  var _isRouteClosing = false;

  IntentionEditorViewModelProvider get _provider =>
      intentionEditorViewModelProvider(_formKey);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = _provider;
    final editor = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case IntentionEditorCreated()) {
        notifier.consumeEvent();
        // Сообщение об успехе предъявляет общий presenter оболочки.
        _closeRoute();
      }
    });

    // Во время отправки черновик зафиксирован: поля не должны показывать
    // текст, которого нет в принятой команде.
    final isDraftFixed = switch (editor.draftAvailability) {
      IntentionDraftAvailability.editable => false,
      IntentionDraftAvailability.submitting ||
      IntentionDraftAvailability.closed => true,
    };
    final generalFailure = _generalFailure(localizations, editor.operation);
    final titleFailure = _fieldFailure(
      localizations,
      editor.operation,
      IntentionTextField.title,
    );
    final descriptionFailure = _fieldFailure(
      localizations,
      editor.operation,
      IntentionTextField.description,
    );
    return PopScope<Object?>(
      // Маршрут не закрывается сам: решение принимает сессия.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(localizations.editorTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const ValueKey('intention-editor-title'),
                controller: _titleController,
                readOnly: isDraftFixed,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: localizations.editorTitleLabel,
                  error: titleFailure == null
                      ? null
                      : OperationFailurePresentation(
                          claim: editor.failurePresentation,
                          message: titleFailure,
                        ),
                ),
                onChanged: notifier.changeTitle,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('intention-editor-description'),
                controller: _descriptionController,
                readOnly: isDraftFixed,
                minLines: 4,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: localizations.editorDescriptionLabel,
                  alignLabelWithHint: true,
                  error: descriptionFailure == null
                      ? null
                      : OperationFailurePresentation(
                          claim: editor.failurePresentation,
                          message: descriptionFailure,
                        ),
                ),
                onChanged: notifier.changeDescription,
              ),
              if (generalFailure != null) ...[
                const SizedBox(height: 16),
                OperationFailurePresentation(
                  claim: editor.failurePresentation,
                  message: generalFailure,
                  messageKey: const ValueKey('intention-editor-failure'),
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
      ),
    );
  }

  /// Передаёт запрос ухода сессии и выполняет её решение.
  Future<void> _requestClose() async {
    switch (ref.read(_provider.notifier).requestClose()) {
      case IntentionCreationClosedImmediately() ||
          IntentionCreationCloseSessionEnded():
        _closeRoute();
      case IntentionCreationCloseNeedsConfirmation(:final confirmation):
        final choice = await showDialog<IntentionCreationCloseChoice>(
          context: context,
          // Подтверждение живёт в стеке маршрута своей формы.
          useRootNavigator: false,
          builder: (_) => _CloseConfirmationDialog(
            provider: _provider,
            confirmation: confirmation,
          ),
        );
        if (!mounted) {
          return;
        }
        // Закрытие диалога без выбора продолжает ввод.
        final resolution = ref
            .read(_provider.notifier)
            .resolveClose(
              confirmation,
              choice ?? IntentionCreationCloseChoice.continueEditing,
            );
        switch (resolution) {
          case IntentionCreationCloseResolution.closed:
            _closeRoute();
          case IntentionCreationCloseResolution.continued ||
              IntentionCreationCloseResolution.outdated:
            break;
        }
      case IntentionCreationCloseAwaitingConfirmation():
        // Ответа уже ожидает единственный диалог этой сессии.
        break;
    }
  }

  /// Закрывает только маршрут этой формы, минуя повторное обращение к уже
  /// завершённой сессии.
  void _closeRoute() {
    if (_isRouteClosing || !mounted) {
      return;
    }
    _isRouteClosing = true;
    context.router.removeRoute(context.routeData);
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
      IntentionTextInputValidationFailure() ||
      IntentionCreationTagsMissingFailure() => localizations.editorInvalidInput,
      IntentionConflictFailure() => localizations.editorCreateConflict,
      IntentionHasBlockingRelationsFailure() =>
        localizations.editorCreateUnexpected,
      IntentionUnavailableFailure() => localizations.editorCreateUnavailable,
      IntentionCorruptionFailure() => localizations.editorCreateCorruption,
      IntentionNotFoundFailure() ||
      IntentionUnexpectedFailure() => localizations.editorCreateUnexpected,
    },
  };
}

/// Подтверждение закрытия изменённого черновика одной сессии.
///
/// Ответ действует, пока [confirmation] остаётся ожидающим подтверждением
/// сессии. Смена состояния отправки или завершение сессии отключают ответы и
/// закрывают диалог без выбора, поэтому устаревший ответ не меняет форму.
final class _CloseConfirmationDialog extends ConsumerStatefulWidget {
  const _CloseConfirmationDialog({
    required this.provider,
    required this.confirmation,
  });

  final IntentionEditorViewModelProvider provider;
  final IntentionCreationCloseConfirmation confirmation;

  @override
  ConsumerState<_CloseConfirmationDialog> createState() =>
      _CloseConfirmationDialogState();
}

final class _CloseConfirmationDialogState
    extends ConsumerState<_CloseConfirmationDialog> {
  var _isDismissing = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isPending = ref.watch(
      widget.provider.select(
        (editor) => switch (editor.closing) {
          IntentionCreationCloseConfirming(:final confirmation) => identical(
            confirmation,
            widget.confirmation,
          ),
          IntentionCreationCloseNotRequested() ||
          IntentionCreationClosedOnRequest() => false,
        },
      ),
    );
    if (!isPending) {
      _dismissOutdated();
    }
    final (
      title,
      message,
      continueLabel,
      discardLabel,
    ) = switch (widget.confirmation.savingOnClose) {
      IntentionCreationSavingOnClose.notStarted => (
        localizations.editorCloseDiscardTitle,
        localizations.editorCloseDiscardMessage,
        localizations.editorCloseContinueAction,
        localizations.editorCloseDiscardAction,
      ),
      IntentionCreationSavingOnClose.continues => (
        localizations.editorCloseSavingTitle,
        localizations.editorCloseSavingMessage,
        localizations.editorCloseSavingStayAction,
        localizations.editorCloseSavingLeaveAction,
      ),
    };
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('intention-editor-close-confirmation'),
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const ValueKey('intention-editor-close-continue'),
          onPressed: isPending
              ? () => _answer(IntentionCreationCloseChoice.continueEditing)
              : null,
          child: Text(continueLabel),
        ),
        FilledButton(
          key: const ValueKey('intention-editor-close-discard'),
          onPressed: isPending
              ? () => _answer(IntentionCreationCloseChoice.discardDraft)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: Text(discardLabel),
        ),
      ],
    );
  }

  /// Закрывает диалог с ответом [choice], только пока он остаётся верхним
  /// маршрутом: ответ не может закрыть форму или другой маршрут под ним.
  void _answer(IntentionCreationCloseChoice? choice) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(choice);
    }
  }

  void _dismissOutdated() {
    if (_isDismissing) {
      return;
    }
    _isDismissing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _answer(null);
      }
    });
  }
}
