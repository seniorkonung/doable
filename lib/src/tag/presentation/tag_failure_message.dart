import '../../../l10n/app_localizations.dart';
import '../application/tag_result.dart';
import '../domain/tag_name.dart';

/// Безопасный локализованный текст отказа для общей и экранной поверхности.
String tagFailureMessage(
  AppLocalizations localizations,
  TagCommandFailure failure,
) => switch (failure) {
  TagNameInputFailure(:final reason) => switch (reason) {
    TagNameFailureReason.invalidUnicodeRepertoire =>
      localizations.tagNameInvalidUnicode,
    TagNameFailureReason.empty => localizations.tagNameEmpty,
    TagNameFailureReason.tooLong => localizations.tagNameTooLong,
    TagNameFailureReason.nonCanonical => localizations.tagNameNonCanonical,
  },
  TagNameOccupiedFailure() => localizations.tagNameOccupied,
  TagNotFoundFailure() => localizations.tagNotFound,
  TagUnavailableFailure() => localizations.tagUnavailable,
  TagCorruptionFailure() => localizations.tagCorruption,
  TagUnexpectedFailure() => localizations.tagUnexpected,
};
