import '../../../l10n/app_localizations.dart';
import '../application/action_result.dart';

/// Безопасный локализованный текст отказа команды действия для общей и
/// экранной поверхности.
String actionCommandFailureMessage(
  AppLocalizations localizations,
  ActionCommandFailure failure,
) => switch (failure) {
  ActionValidationFailure(:final field) => switch (field) {
    ActionValidationField.title => localizations.actionTitleInvalid,
    ActionValidationField.description => localizations.actionDescriptionInvalid,
  },
  ActionNotFoundFailure() => localizations.actionOperationNotFound,
  ActionConflictFailure() => localizations.actionOperationConflict,
  ActionUnavailableFailure() => localizations.actionOperationUnavailable,
  ActionCorruptionFailure() => localizations.actionOperationCorruption,
  ActionUnexpectedFailure() => localizations.actionOperationUnexpected,
};
