import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice.dart';
import '../../domain/daily_choice_description.dart';

sealed class DailyChoiceEditOperation {
  const DailyChoiceEditOperation();
}

final class DailyChoiceEditIdle extends DailyChoiceEditOperation {
  const DailyChoiceEditIdle();
}

final class DailyChoiceEditSubmitting extends DailyChoiceEditOperation {
  const DailyChoiceEditSubmitting();
}

final class DailyChoiceEditSucceeded extends DailyChoiceEditOperation {
  const DailyChoiceEditSucceeded();
}

sealed class DailyChoiceEditFailure {
  const DailyChoiceEditFailure();
}

final class DailyChoiceEditDescriptionInvalid extends DailyChoiceEditFailure {
  const DailyChoiceEditDescriptionInvalid(this.failure);

  final DailyChoiceDescriptionValidationFailure failure;
}

final class DailyChoiceEditCommandRejected extends DailyChoiceEditFailure {
  const DailyChoiceEditCommandRejected(this.failure);

  final DailyChoiceCommandFailure failure;
}

final class DailyChoiceEditFailed extends DailyChoiceEditOperation {
  const DailyChoiceEditFailed(this.failure);

  final DailyChoiceEditFailure failure;
}

final class DailyChoiceEditState {
  const DailyChoiceEditState({
    required this.original,
    required this.date,
    required this.description,
    required this.isCompleted,
    required this.operation,
    required this.failurePresentation,
  });

  DailyChoiceEditState.initial(this.original)
    : date = original.date,
      description = original.description?.value ?? '',
      isCompleted = original.isCompleted,
      operation = const DailyChoiceEditIdle(),
      failurePresentation = null;

  final DailyChoice original;
  final CalendarDate date;
  final String description;
  final bool isCompleted;
  final DailyChoiceEditOperation operation;
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get hasEdits =>
      date != original.date ||
      description != (original.description?.value ?? '') ||
      isCompleted != original.isCompleted;

  bool get canRetry => switch (operation) {
    DailyChoiceEditFailed(
      failure: DailyChoiceEditCommandRejected(
        failure: DailyChoiceUnavailableFailure(),
      ),
    ) =>
      true,
    _ => false,
  };

  bool get canSubmit =>
      hasEdits && (operation is DailyChoiceEditIdle || canRetry);

  DailyChoiceFieldsPatch? toPatch() {
    final parsedDescription = DailyChoiceDescription.fromInput(description);
    final originalDescription = original.description;
    final descriptionPatch = parsedDescription == originalDescription
        ? const DailyChoiceDescriptionUnchanged()
        : parsedDescription == null
        ? const DailyChoiceDescriptionCleared()
        : DailyChoiceDescriptionSet(parsedDescription);
    if (date == original.date &&
        descriptionPatch is DailyChoiceDescriptionUnchanged &&
        isCompleted == original.isCompleted) {
      return null;
    }
    return DailyChoiceFieldsPatch(
      date: date == original.date
          ? const DailyChoiceFieldUnchanged<CalendarDate>()
          : DailyChoiceFieldSet(date),
      description: descriptionPatch,
      isCompleted: isCompleted == original.isCompleted
          ? const DailyChoiceFieldUnchanged<bool>()
          : DailyChoiceFieldSet(isCompleted),
    );
  }

  DailyChoiceEditState withDate(CalendarDate value) =>
      _withField(date: value, corrects: DailyChoiceValidationField.date);

  DailyChoiceEditState withDescription(String value) => _withField(
    description: value,
    corrects: DailyChoiceValidationField.description,
  );

  DailyChoiceEditState withCompletion(bool value) =>
      _withField(isCompleted: value);

  DailyChoiceEditState withOperation(
    DailyChoiceEditOperation value, {
    GraphInitiatorPresentationClaim? failurePresentation,
  }) => DailyChoiceEditState(
    original: original,
    date: date,
    description: description,
    isCompleted: isCompleted,
    operation: value,
    failurePresentation: failurePresentation,
  );

  DailyChoiceEditState _withField({
    CalendarDate? date,
    String? description,
    bool? isCompleted,
    DailyChoiceValidationField? corrects,
  }) {
    if (operation is DailyChoiceEditSubmitting ||
        operation is DailyChoiceEditSucceeded) {
      return this;
    }
    final nextOperation = switch (operation) {
      DailyChoiceEditFailed(failure: DailyChoiceEditDescriptionInvalid())
          when corrects == DailyChoiceValidationField.description =>
        const DailyChoiceEditIdle(),
      DailyChoiceEditFailed(
        failure: DailyChoiceEditCommandRejected(
          failure: DailyChoiceValidationFailure(field: final field),
        ),
      )
          when corrects == field =>
        const DailyChoiceEditIdle(),
      _ => operation,
    };
    return DailyChoiceEditState(
      original: original,
      date: date ?? this.date,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      operation: nextOperation,
      failurePresentation: nextOperation is DailyChoiceEditFailed
          ? failurePresentation
          : null,
    );
  }
}
