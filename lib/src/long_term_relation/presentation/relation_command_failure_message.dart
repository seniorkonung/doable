import '../../../l10n/app_localizations.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../application/long_term_relation_command.dart';

/// Возвращает единый безопасный текст отказа команды долговременной связи.
String longTermRelationCommandFailureMessage(
  AppLocalizations localizations,
  LongTermRelationCommandKind kind,
  LongTermRelationCommandFailure failure,
) => switch (kind) {
  LongTermRelationCommandKind.create => switch (failure) {
    LongTermRelationCommandValidationFailure() =>
      localizations.relationEditorCreateInvalidInput,
    LongTermRelationPairOccupiedFailure() =>
      localizations.relationEditorCreatePairOccupied,
    LongTermRelationNotFoundFailure() =>
      localizations.relationEditorCreateUnexpected,
    LongTermRelationParticipantNotFoundFailure() =>
      localizations.relationEditorCreateParticipantNotFound,
    LongTermRelationParticipantArchivedFailure() =>
      localizations.relationEditorCreateParticipantArchived,
    LongTermRelationUnavailableFailure() =>
      localizations.relationEditorCreateUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationEditorCreateCorruption,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationEditorCreateUnexpected,
  },
  LongTermRelationCommandKind.update => switch (failure) {
    LongTermRelationCommandValidationFailure() =>
      localizations.relationEditorUpdateInvalidInput,
    LongTermRelationPairOccupiedFailure() =>
      localizations.relationEditorUpdatePairOccupied,
    LongTermRelationNotFoundFailure() =>
      localizations.relationEditorUpdateNotFound,
    LongTermRelationParticipantNotFoundFailure() =>
      localizations.relationEditorUpdateParticipantNotFound,
    LongTermRelationParticipantArchivedFailure() =>
      localizations.relationEditorUpdateParticipantArchived,
    LongTermRelationUnavailableFailure() =>
      localizations.relationEditorUpdateUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationEditorUpdateCorruption,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationEditorUpdateUnexpected,
  },
  LongTermRelationCommandKind.archive => switch (failure) {
    LongTermRelationNotFoundFailure() => localizations.relationArchiveNotFound,
    LongTermRelationUnavailableFailure() =>
      localizations.relationArchiveUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationArchiveCorruption,
    LongTermRelationCommandValidationFailure() ||
    LongTermRelationPairOccupiedFailure() ||
    LongTermRelationParticipantNotFoundFailure() ||
    LongTermRelationParticipantArchivedFailure() =>
      localizations.relationArchiveConflict,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationArchiveUnexpected,
  },
  LongTermRelationCommandKind.restore => switch (failure) {
    LongTermRelationNotFoundFailure() => localizations.relationRestoreNotFound,
    LongTermRelationParticipantNotFoundFailure(:final role) => switch (role) {
      RelationParticipantRole.source =>
        localizations.relationRestoreSourceNotFound,
      RelationParticipantRole.related =>
        localizations.relationRestoreRelatedNotFound,
    },
    LongTermRelationParticipantArchivedFailure(:final role) => switch (role) {
      RelationParticipantRole.source =>
        localizations.relationRestoreSourceArchived,
      RelationParticipantRole.related =>
        localizations.relationRestoreRelatedArchived,
    },
    LongTermRelationUnavailableFailure() =>
      localizations.relationRestoreUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationRestoreCorruption,
    LongTermRelationCommandValidationFailure() ||
    LongTermRelationPairOccupiedFailure() =>
      localizations.relationRestoreConflict,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationRestoreUnexpected,
  },
};
