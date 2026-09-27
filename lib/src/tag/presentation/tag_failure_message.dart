import '../../../l10n/app_localizations.dart';
import '../../graph/application/graph_command_coordinator.dart';
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
  TagTargetNotFoundFailure() => localizations.tagAssignmentTargetNotFound,
  TagUnavailableFailure() => localizations.tagUnavailable,
  TagCorruptionFailure() => localizations.tagCorruption,
  TagUnexpectedFailure() => localizations.tagUnexpected,
};

/// Причины команд назначения и снятия для общей и инлайн-поверхности.
String tagAssignmentFailureMessage(
  AppLocalizations localizations,
  TagCommandFailure failure,
) => switch (failure) {
  TagNotFoundFailure() => localizations.tagNotFound,
  TagTargetNotFoundFailure() => localizations.tagAssignmentTargetNotFound,
  TagUnavailableFailure() => localizations.tagAssignmentUnavailable,
  TagCorruptionFailure() => localizations.tagAssignmentCorruption,
  TagUnexpectedFailure() => localizations.tagAssignmentUnexpected,
  TagNameInputFailure() ||
  TagNameOccupiedFailure() => localizations.tagAssignmentUnexpected,
};

/// Отклонённая до исполнения команда не получает claim общей очереди.
String? tagAssignmentStartMessage(
  AppLocalizations localizations,
  TagCommandStart start,
) => switch (start) {
  TagCommandAccepted() => null,
  TagCommandAlreadyRunning() => localizations.tagAssignmentAlreadyRunning,
  GraphCommandCoordinatorDraining() => localizations.tagAssignmentUnexpected,
};
