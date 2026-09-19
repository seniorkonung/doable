import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

sealed class IntentionEditorEvent {
  const IntentionEditorEvent();
}

final class IntentionEditorCreated extends IntentionEditorEvent {
  const IntentionEditorCreated();
}

final class IntentionEditorState {
  const IntentionEditorState({
    required this.title,
    required this.description,
    required this.operation,
    required this.event,
    this.failurePresentation,
  });

  const IntentionEditorState.initial()
    : title = '',
      description = '',
      operation = const OperationIdle<Intention>(),
      event = null,
      failurePresentation = null;

  final String title;
  final String description;
  final OperationState<Intention> operation;
  final IntentionEditorEvent? event;

  /// Право открытой формы предъявить текущую ошибку; подтверждается страницей
  /// только по кадру с видимым сообщением.
  final IntentionInitiatorPresentationClaim? failurePresentation;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  bool get canSubmit => operation is OperationIdle<Intention> || canRetry;

  IntentionEditorState withTitle(String value) => _withEditedText(
    title: value,
    description: description,
    field: IntentionTextField.title,
  );

  IntentionEditorState withDescription(String value) => _withEditedText(
    title: title,
    description: value,
    field: IntentionTextField.description,
  );

  IntentionEditorState withOperation(
    OperationState<Intention> value, {
    IntentionEditorEvent? event,
    IntentionInitiatorPresentationClaim? failurePresentation,
  }) => IntentionEditorState(
    title: title,
    description: description,
    operation: value,
    event: event,
    failurePresentation: failurePresentation,
  );

  IntentionEditorState withoutEvent() => IntentionEditorState(
    title: title,
    description: description,
    operation: operation,
    event: null,
    failurePresentation: failurePresentation,
  );

  IntentionEditorState _withEditedText({
    required String title,
    required String description,
    required IntentionTextField field,
  }) {
    final nextOperation = _operationAfterEditing(field);
    return IntentionEditorState(
      title: title,
      description: description,
      operation: nextOperation,
      event: null,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
    );
  }

  OperationState<Intention> _operationAfterEditing(IntentionTextField field) {
    final current = operation;
    if (current is! OperationFailed<Intention>) {
      return current;
    }
    return switch (current.failure) {
      IntentionTextInputValidationFailure(:final textFailure)
          when textFailure.field == field =>
        const OperationIdle<Intention>(),
      IntentionGenericValidationFailure() => const OperationIdle<Intention>(),
      IntentionTextInputValidationFailure() ||
      IntentionNotFoundFailure() ||
      IntentionConflictFailure() ||
      IntentionHasBlockingRelationsFailure() ||
      IntentionUnavailableFailure() ||
      IntentionCorruptionFailure() ||
      IntentionUnexpectedFailure() => current,
    };
  }
}
