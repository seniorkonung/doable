import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

/// Ключ одной экранной сессии изменения намерения. Его создаёт и держит
/// экран, поэтому повторное открытие получает новую сессию.
final class IntentionEditFormKey {
  // Не const: ключи различаются идентичностью.
  IntentionEditFormKey();
}

/// Решение сессии о запросе ухода, единое для всех способов ухода.
enum IntentionEditCloseDecision {
  /// Текст не изменён или принятое сохранение продолжится без экрана.
  close,

  /// Изменённый текст не сохраняется: нужен ответ на «Отменить изменения?».
  askDiscard,
}

final class IntentionEditState {
  const IntentionEditState._({
    required this.savedTitle,
    required this.savedDescription,
    required this.title,
    required this.description,
    required this.operation,
    required this.isIntentionBusy,
    required this.failurePresentation,
  });

  /// Черновик из сохранённых текстов на момент открытия; отсутствующее
  /// описание — пустой текст.
  factory IntentionEditState.opened(
    Intention intention, {
    required bool isIntentionBusy,
  }) {
    final description = intention.description ?? '';
    return IntentionEditState._(
      savedTitle: intention.title,
      savedDescription: description,
      title: intention.title,
      description: description,
      operation: const OperationIdle<Intention>(),
      isIntentionBusy: isIntentionBusy,
      failurePresentation: null,
    );
  }

  final String savedTitle;
  final String savedDescription;

  /// Сырые тексты черновика без нормализации.
  final String title;
  final String description;
  final OperationState<Intention> operation;

  /// Выполняется ли для намерения изменяющая команда по последнему прочтению
  /// координатора.
  final bool isIntentionBusy;

  /// Право экрана предъявить текущий отказ сохранения. Право, которое
  /// состояние перестало публиковать, сессия передаёт общей поверхности.
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get isChanged => title != savedTitle || description != savedDescription;

  bool get acceptsDraftChanges => switch (operation) {
    OperationIdle<Intention>() || OperationFailed<Intention>() => true,
    OperationRunning<Intention>() || OperationSucceeded<Intention>() => false,
  };

  bool get canSave =>
      acceptsDraftChanges &&
      isChanged &&
      !IntentionText.isBlankTitle(title) &&
      !isIntentionBusy;

  IntentionEditCloseDecision get closeDecision => switch (operation) {
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() => IntentionEditCloseDecision.close,
    OperationIdle<Intention>() || OperationFailed<Intention>() =>
      isChanged
          ? IntentionEditCloseDecision.askDiscard
          : IntentionEditCloseDecision.close,
  };

  IntentionEditState withTitle(String value) => _withEditedText(
    title: value,
    description: description,
    field: IntentionTextField.title,
  );

  IntentionEditState withDescription(String value) => _withEditedText(
    title: title,
    description: value,
    field: IntentionTextField.description,
  );

  /// Публикует только переданное право отказа [failurePresentation].
  IntentionEditState withOperation(
    OperationState<Intention> value, {
    GraphInitiatorPresentationClaim? failurePresentation,
  }) => _copy(operation: value, failurePresentation: failurePresentation);

  IntentionEditState withIntentionBusy(bool value) => _copy(
    operation: operation,
    failurePresentation: failurePresentation,
    isIntentionBusy: value,
  );

  IntentionEditState _withEditedText({
    required String title,
    required String description,
    required IntentionTextField field,
  }) {
    final nextOperation = _operationAfterEditing(field);
    return _copy(
      title: title,
      description: description,
      operation: nextOperation,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
    );
  }

  /// Правка снимает отказ проверки своего поля и общий отказ проверки;
  /// остальные отказы остаются вместе с правом предъявления.
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
      IntentionCreationTagsMissingFailure() ||
      IntentionNotFoundFailure() ||
      IntentionConflictFailure() ||
      IntentionHasBlockingRelationsFailure() ||
      IntentionUnavailableFailure() ||
      IntentionCorruptionFailure() ||
      IntentionUnexpectedFailure() => current,
    };
  }

  IntentionEditState _copy({
    required OperationState<Intention> operation,
    required GraphInitiatorPresentationClaim? failurePresentation,
    String? title,
    String? description,
    bool? isIntentionBusy,
  }) => IntentionEditState._(
    savedTitle: savedTitle,
    savedDescription: savedDescription,
    title: title ?? this.title,
    description: description ?? this.description,
    operation: operation,
    isIntentionBusy: isIntentionBusy ?? this.isIntentionBusy,
    failurePresentation: failurePresentation,
  );
}
