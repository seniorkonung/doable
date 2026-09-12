import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

final class IntentionEditorSession {
  IntentionEditorSession();
}

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
  });

  const IntentionEditorState.initial()
    : title = '',
      description = '',
      operation = const OperationIdle<Intention>(),
      event = null;

  final String title;
  final String description;
  final OperationState<Intention> operation;
  final IntentionEditorEvent? event;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  bool get canSubmit => operation is OperationIdle<Intention> || canRetry;

  IntentionEditorState withTitle(String value) => IntentionEditorState(
    title: value,
    description: description,
    operation: _operationAfterEditing(IntentionTextField.title),
    event: null,
  );

  IntentionEditorState withDescription(String value) => IntentionEditorState(
    title: title,
    description: value,
    operation: _operationAfterEditing(IntentionTextField.description),
    event: null,
  );

  IntentionEditorState withOperation(
    OperationState<Intention> value, {
    IntentionEditorEvent? event,
  }) => IntentionEditorState(
    title: title,
    description: description,
    operation: value,
    event: event,
  );

  IntentionEditorState withoutEvent() => IntentionEditorState(
    title: title,
    description: description,
    operation: operation,
    event: null,
  );

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
      IntentionUnavailableFailure() ||
      IntentionCorruptionFailure() ||
      IntentionUnexpectedFailure() => current,
    };
  }
}
