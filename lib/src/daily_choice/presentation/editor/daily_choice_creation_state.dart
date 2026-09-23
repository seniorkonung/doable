import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_description.dart';
import '../../domain/daily_choice_id.dart';

sealed class DailyChoiceCreationOperation {
  const DailyChoiceCreationOperation();
}

final class DailyChoiceCreationIdle extends DailyChoiceCreationOperation {
  const DailyChoiceCreationIdle();
}

final class DailyChoiceCreationSubmitting extends DailyChoiceCreationOperation {
  const DailyChoiceCreationSubmitting();
}

final class DailyChoiceCreationSucceeded extends DailyChoiceCreationOperation {
  const DailyChoiceCreationSucceeded(this.choiceId);

  final DailyChoiceId choiceId;
}

sealed class DailyChoiceCreationFailure {
  const DailyChoiceCreationFailure();
}

final class DailyChoiceCreationDescriptionInvalid
    extends DailyChoiceCreationFailure {
  const DailyChoiceCreationDescriptionInvalid(this.failure);

  final DailyChoiceDescriptionValidationFailure failure;
}

final class DailyChoiceCreationCommandRejected
    extends DailyChoiceCreationFailure {
  const DailyChoiceCreationCommandRejected(this.failure);

  final DailyChoiceCommandFailure failure;
}

final class DailyChoiceCreationFailed extends DailyChoiceCreationOperation {
  const DailyChoiceCreationFailed(this.failure);

  final DailyChoiceCreationFailure failure;
}

final class DailyChoiceCreationCreated {
  const DailyChoiceCreationCreated(this.choiceId);

  final DailyChoiceId choiceId;
}

/// Черновик одной формы. Путь уже подтверждён в обходе и повторно проверяется
/// репозиторием при сохранении. Дата и выполнение не выводятся друг из друга.
final class DailyChoiceCreationState {
  const DailyChoiceCreationState({
    required this.path,
    required this.date,
    required this.description,
    required this.isCompleted,
    required this.operation,
    required this.event,
    required this.failurePresentation,
  });

  DailyChoiceCreationState.initial({required this.path, required this.date})
    : description = '',
      isCompleted = false,
      operation = const DailyChoiceCreationIdle(),
      event = null,
      failurePresentation = null;

  final ConfirmedChoicePath path;
  final CalendarDate date;
  final String description;
  final bool isCompleted;
  final DailyChoiceCreationOperation operation;
  final DailyChoiceCreationCreated? event;

  /// Право локальной поверхности предъявить ошибку после видимого кадра.
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get canRetry => switch (operation) {
    DailyChoiceCreationFailed(
      failure: DailyChoiceCreationCommandRejected(
        failure: DailyChoiceUnavailableFailure(),
      ),
    ) =>
      true,
    DailyChoiceCreationIdle() ||
    DailyChoiceCreationSubmitting() ||
    DailyChoiceCreationSucceeded() ||
    DailyChoiceCreationFailed() => false,
  };

  bool get canSubmit => operation is DailyChoiceCreationIdle || canRetry;

  bool get needsPathRefresh => switch (operation) {
    DailyChoiceCreationFailed(
      failure: DailyChoiceCreationCommandRejected(
        failure: DailyChoiceConflictFailure(),
      ),
    ) =>
      true,
    _ => false,
  };

  DailyChoiceCreationState withDate(CalendarDate value) =>
      _withField(date: value, corrects: DailyChoiceValidationField.date);

  DailyChoiceCreationState withDescription(String value) => _withField(
    description: value,
    corrects: DailyChoiceValidationField.description,
  );

  DailyChoiceCreationState withCompletion(bool value) =>
      _withField(isCompleted: value);

  /// Вызывается только после нового пользовательского подтверждения
  /// актуализированного пути, сохраняя независимые поля формы.
  DailyChoiceCreationState withRefreshedPath(ConfirmedChoicePath value) {
    if (!needsPathRefresh) return this;
    return DailyChoiceCreationState(
      path: value,
      date: date,
      description: description,
      isCompleted: isCompleted,
      operation: const DailyChoiceCreationIdle(),
      event: null,
      failurePresentation: null,
    );
  }

  DailyChoiceCreationState withOperation(
    DailyChoiceCreationOperation value, {
    DailyChoiceCreationCreated? event,
    GraphInitiatorPresentationClaim? failurePresentation,
  }) => DailyChoiceCreationState(
    path: path,
    date: date,
    description: description,
    isCompleted: isCompleted,
    operation: value,
    event: event,
    failurePresentation: failurePresentation,
  );

  DailyChoiceCreationState withoutEvent() => DailyChoiceCreationState(
    path: path,
    date: date,
    description: description,
    isCompleted: isCompleted,
    operation: operation,
    event: null,
    failurePresentation: failurePresentation,
  );

  DailyChoiceCreationState _withField({
    CalendarDate? date,
    String? description,
    bool? isCompleted,
    DailyChoiceValidationField? corrects,
  }) {
    if (operation is DailyChoiceCreationSubmitting ||
        operation is DailyChoiceCreationSucceeded) {
      return this;
    }
    final nextOperation = switch (operation) {
      DailyChoiceCreationFailed(
        failure: DailyChoiceCreationDescriptionInvalid(),
      )
          when corrects == DailyChoiceValidationField.description =>
        const DailyChoiceCreationIdle(),
      DailyChoiceCreationFailed(
        failure: DailyChoiceCreationCommandRejected(
          failure: DailyChoiceValidationFailure(field: final field),
        ),
      )
          when corrects == field =>
        const DailyChoiceCreationIdle(),
      _ => operation,
    };
    return DailyChoiceCreationState(
      path: path,
      date: date ?? this.date,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      operation: nextOperation,
      event: null,
      failurePresentation: nextOperation is DailyChoiceCreationFailed
          ? failurePresentation
          : null,
    );
  }
}
