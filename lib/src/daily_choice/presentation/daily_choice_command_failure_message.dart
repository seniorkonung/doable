import '../../../l10n/app_localizations.dart';
import '../application/daily_choice_result.dart';

/// Безопасный локализованный текст отказа для общей и экранной поверхности.
String dailyChoiceCommandFailureMessage(
  AppLocalizations localizations,
  DailyChoiceCommandFailure failure,
) => switch (failure) {
  DailyChoiceValidationFailure(:final field) => switch (field) {
    DailyChoiceValidationField.sourceIntention =>
      localizations.dailyChoiceSourceInvalid,
    DailyChoiceValidationField.selectedIntention =>
      localizations.dailyChoiceSelectedInvalid,
    DailyChoiceValidationField.date => localizations.dailyChoiceDateInvalid,
    DailyChoiceValidationField.description =>
      localizations.dailyChoiceDescriptionInvalid,
    DailyChoiceValidationField.path => localizations.dailyChoicePathInvalid,
  },
  DailyChoiceNotFoundFailure() => localizations.dailyChoiceOperationNotFound,
  DailyChoiceConflictFailure() => localizations.dailyChoiceOperationConflict,
  DailyChoiceUnavailableFailure() =>
    localizations.dailyChoiceOperationUnavailable,
  DailyChoiceCorruptionFailure() =>
    localizations.dailyChoiceOperationCorruption,
  DailyChoiceUnexpectedFailure() =>
    localizations.dailyChoiceOperationUnexpected,
};
