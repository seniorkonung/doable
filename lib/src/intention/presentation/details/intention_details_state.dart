import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

sealed class IntentionDetailsState {
  const IntentionDetailsState({required this.isOperationRunning});

  final bool isOperationRunning;
}

final class IntentionDetailsLoading extends IntentionDetailsState {
  const IntentionDetailsLoading({required super.isOperationRunning});
}

final class IntentionDetailsLoaded extends IntentionDetailsState {
  const IntentionDetailsLoaded({
    required this.intention,
    required super.isOperationRunning,
    this.edit,
    this.stateChange,
    this.event,
  });

  final Intention intention;
  final IntentionDetailsEdit? edit;
  final IntentionDetailsStateChange? stateChange;
  final IntentionDetailsEvent? event;

  IntentionDetailsLoaded copyWith({
    Intention? intention,
    bool? isOperationRunning,
    IntentionDetailsEdit? edit,
    bool clearEdit = false,
    IntentionDetailsStateChange? stateChange,
    bool clearStateChange = false,
    IntentionDetailsEvent? event,
    bool clearEvent = false,
  }) => IntentionDetailsLoaded(
    intention: intention ?? this.intention,
    isOperationRunning: isOperationRunning ?? this.isOperationRunning,
    edit: clearEdit ? null : edit ?? this.edit,
    stateChange: clearStateChange ? null : stateChange ?? this.stateChange,
    event: clearEvent ? null : event ?? this.event,
  );
}

enum IntentionDetailsStateChangeKind {
  enableReadiness,
  disableReadiness,
  archive,
  restore,
}

final class IntentionDetailsStateChange {
  const IntentionDetailsStateChange.running(this.kind)
    : operation = const OperationRunning<Intention>();

  IntentionDetailsStateChange.failed(this.kind, IntentionFailure failure)
    : operation = OperationFailed<Intention>(failure);

  final IntentionDetailsStateChangeKind kind;
  final OperationState<Intention> operation;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };
}

final class IntentionDetailsEdit {
  const IntentionDetailsEdit({
    required this.title,
    required this.description,
    required this.operation,
  });

  factory IntentionDetailsEdit.fromIntention(Intention intention) =>
      IntentionDetailsEdit(
        title: intention.title,
        description: intention.description ?? '',
        operation: const OperationIdle<Intention>(),
      );

  final String title;
  final String description;
  final OperationState<Intention> operation;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  bool get canSubmit => operation is OperationIdle<Intention> || canRetry;

  IntentionDetailsEdit withTitle(String value) => IntentionDetailsEdit(
    title: value,
    description: description,
    operation: _operationAfterEditing(IntentionTextField.title),
  );

  IntentionDetailsEdit withDescription(String value) => IntentionDetailsEdit(
    title: title,
    description: value,
    operation: _operationAfterEditing(IntentionTextField.description),
  );

  IntentionDetailsEdit withOperation(OperationState<Intention> value) =>
      IntentionDetailsEdit(
        title: title,
        description: description,
        operation: value,
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

sealed class IntentionDetailsEvent {
  const IntentionDetailsEvent();
}

final class IntentionDetailsSaved extends IntentionDetailsEvent {
  const IntentionDetailsSaved();
}

final class IntentionDetailsReadinessEnabled extends IntentionDetailsEvent {
  const IntentionDetailsReadinessEnabled();
}

final class IntentionDetailsReadinessDisabled extends IntentionDetailsEvent {
  const IntentionDetailsReadinessDisabled();
}

final class IntentionDetailsArchived extends IntentionDetailsEvent {
  const IntentionDetailsArchived();
}

final class IntentionDetailsRestored extends IntentionDetailsEvent {
  const IntentionDetailsRestored();
}

final class IntentionDetailsNotFound extends IntentionDetailsState {
  const IntentionDetailsNotFound({required super.isOperationRunning});
}

final class IntentionDetailsUnavailable extends IntentionDetailsState {
  const IntentionDetailsUnavailable({required super.isOperationRunning});
}

final class IntentionDetailsCorruption extends IntentionDetailsState {
  const IntentionDetailsCorruption({required super.isOperationRunning});
}

final class IntentionDetailsUnexpected extends IntentionDetailsState {
  const IntentionDetailsUnexpected({required super.isOperationRunning});
}

final class IntentionDetailsDeleted extends IntentionDetailsState {
  const IntentionDetailsDeleted() : super(isOperationRunning: false);
}
