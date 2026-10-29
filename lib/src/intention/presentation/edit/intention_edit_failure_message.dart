import '../../../../l10n/app_localizations.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

/// Объяснение отказа проверки [field], которое показывается у этого поля.
String? intentionEditFieldFailureMessage(
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
      (IntentionTextField.description, IntentionTextValidationReason.tooLong) =>
        localizations.editorDescriptionTooLong,
      (
        IntentionTextField.description,
        IntentionTextValidationReason.invalidUnicodeRepertoire,
      ) =>
        localizations.editorDescriptionInvalidUnicode,
      (IntentionTextField.description, IntentionTextValidationReason.empty) ||
      (
        IntentionTextField.titleFilter,
        _,
      ) => localizations.detailsUpdateInvalidInput,
    };
  }
  return null;
}

/// Объяснение отказа изменения, которое не относится к названию или
/// описанию и показывается над полями.
String? intentionEditGeneralFailureMessage(
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
    IntentionCreationTagsMissingFailure() =>
      localizations.detailsUpdateInvalidInput,
    IntentionNotFoundFailure() => localizations.detailsUpdateNotFound,
    IntentionConflictFailure() => localizations.detailsUpdateConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsUpdateUnexpected,
    IntentionUnavailableFailure() => localizations.detailsUpdateUnavailable,
    IntentionCorruptionFailure() => localizations.detailsUpdateCorruption,
    IntentionUnexpectedFailure() => localizations.detailsUpdateUnexpected,
  },
};
