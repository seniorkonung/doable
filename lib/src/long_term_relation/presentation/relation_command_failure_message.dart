import '../../../l10n/app_localizations.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../application/long_term_relation_command.dart';

/// Возвращает единый безопасный текст отказа команды долговременной связи.
String longTermRelationCommandFailureMessage(
  AppLocalizations localizations,
  LongTermRelationCommandKind kind,
  LongTermRelationCommandFailure failure,
) => switch (kind) {
  LongTermRelationCommandKind.add => switch (failure) {
    LongTermRelationPairOccupiedFailure() =>
      localizations.relationsAdditionPairOccupied,
    LongTermRelationParticipantNotFoundFailure() =>
      localizations.relationsAdditionParticipantNotFound,
    LongTermRelationParticipantArchivedFailure() =>
      localizations.relationsAdditionParticipantArchived,
    LongTermRelationUnavailableFailure() =>
      localizations.relationsAdditionUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationsAdditionCorruption,
    LongTermRelationNotFoundFailure() ||
    LongTermRelationReferencedByDailyPathFailure() ||
    LongTermRelationArchivedTypeChangeFailure() ||
    LongTermRelationUnexpectedFailure() =>
      localizations.relationsAdditionUnexpected,
  },
  LongTermRelationCommandKind.update => switch (failure) {
    LongTermRelationNotFoundFailure() =>
      localizations.relationEditorUpdateNotFound,
    LongTermRelationArchivedTypeChangeFailure() =>
      localizations.relationEditorUpdateArchivedTypeChange,
    LongTermRelationUnavailableFailure() =>
      localizations.relationEditorUpdateUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationEditorUpdateCorruption,
    // Изменение связи не называет пару и участников и не проверяет шаги пути,
    // поэтому такие отказы для него неожиданны.
    LongTermRelationReferencedByDailyPathFailure() ||
    LongTermRelationPairOccupiedFailure() ||
    LongTermRelationParticipantNotFoundFailure() ||
    LongTermRelationParticipantArchivedFailure() ||
    LongTermRelationUnexpectedFailure() =>
      localizations.relationEditorUpdateUnexpected,
  },
  LongTermRelationCommandKind.archive => switch (failure) {
    LongTermRelationNotFoundFailure() => localizations.relationArchiveNotFound,
    LongTermRelationUnavailableFailure() =>
      localizations.relationArchiveUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationArchiveCorruption,
    LongTermRelationPairOccupiedFailure() ||
    LongTermRelationReferencedByDailyPathFailure() ||
    LongTermRelationArchivedTypeChangeFailure() ||
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
    LongTermRelationPairOccupiedFailure() =>
      localizations.relationRestoreConflict,
    LongTermRelationReferencedByDailyPathFailure() ||
    LongTermRelationArchivedTypeChangeFailure() =>
      localizations.relationRestoreConflict,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationRestoreUnexpected,
  },
  LongTermRelationCommandKind.delete => switch (failure) {
    LongTermRelationNotFoundFailure() => localizations.relationDeleteNotFound,
    LongTermRelationReferencedByDailyPathFailure() =>
      localizations.relationDeleteReferencedByDailyPath,
    LongTermRelationUnavailableFailure() =>
      localizations.relationDeleteUnavailable,
    LongTermRelationCorruptionFailure() =>
      localizations.relationDeleteCorruption,
    LongTermRelationPairOccupiedFailure() ||
    LongTermRelationArchivedTypeChangeFailure() ||
    LongTermRelationParticipantNotFoundFailure() ||
    LongTermRelationParticipantArchivedFailure() =>
      localizations.relationDeleteConflict,
    LongTermRelationUnexpectedFailure() =>
      localizations.relationDeleteUnexpected,
  },
};
