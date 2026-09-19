import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_details.dart' as application;
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
    required this.details,
    required super.isOperationRunning,
    this.edit,
    this.stateChange,
  });

  final application.IntentionDetails details;
  Intention get intention => details.intention;
  final IntentionDetailsEdit? edit;
  final IntentionDetailsStateChange? stateChange;

  IntentionDetailsLoaded copyWith({
    application.IntentionDetails? details,
    Intention? intention,
    bool? isOperationRunning,
    IntentionDetailsEdit? edit,
    bool clearEdit = false,
    IntentionDetailsStateChange? stateChange,
    bool clearStateChange = false,
  }) => IntentionDetailsLoaded(
    details:
        details ??
        application.IntentionDetails(
          intention: intention ?? this.intention,
          relationCounts: this.details.relationCounts,
        ),
    isOperationRunning: isOperationRunning ?? this.isOperationRunning,
    edit: clearEdit ? null : edit ?? this.edit,
    stateChange: clearStateChange ? null : stateChange ?? this.stateChange,
  );
}

enum IntentionDetailsStateChangeKind {
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

final class IntentionDetailsStateChange {
  const IntentionDetailsStateChange.running(this.kind)
    : operation = const OperationRunning<Intention>(),
      failurePresentation = null;

  IntentionDetailsStateChange.failed(
    this.kind,
    IntentionFailure failure, {
    this.failurePresentation,
  }) : operation = OperationFailed<Intention>(failure);

  final IntentionDetailsStateChangeKind kind;
  final OperationState<Intention> operation;

  /// Право открытого просмотра предъявить ошибку перехода по видимому кадру.
  final IntentionInitiatorPresentationClaim? failurePresentation;

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
    this.failurePresentation,
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

  /// Право открытой формы изменения предъявить ошибку по видимому кадру.
  final IntentionInitiatorPresentationClaim? failurePresentation;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  bool get canSubmit => operation is OperationIdle<Intention> || canRetry;

  IntentionDetailsEdit withTitle(String value) => _withEditedText(
    title: value,
    description: description,
    field: IntentionTextField.title,
  );

  IntentionDetailsEdit withDescription(String value) => _withEditedText(
    title: title,
    description: value,
    field: IntentionTextField.description,
  );

  IntentionDetailsEdit withOperation(
    OperationState<Intention> value, {
    IntentionInitiatorPresentationClaim? failurePresentation,
  }) => IntentionDetailsEdit(
    title: title,
    description: description,
    operation: value,
    failurePresentation: failurePresentation,
  );

  IntentionDetailsEdit _withEditedText({
    required String title,
    required String description,
    required IntentionTextField field,
  }) {
    final nextOperation = _operationAfterEditing(field);
    return IntentionDetailsEdit(
      title: title,
      description: description,
      operation: nextOperation,
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
