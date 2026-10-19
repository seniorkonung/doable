import '../../../l10n/app_localizations.dart';
import '../../graph/application/graph_command_coordinator.dart';

/// Локализованный текст отказа импорта для строки «Импорт данных» и общей
/// поверхности результатов: он называет способ исправления и сообщает, что
/// ничего не изменено.
String graphImportFailureMessage(
  AppLocalizations localizations,
  GraphImportFailure failure,
) => switch (failure) {
  GraphImportFailure.invalidFile => localizations.dataImportInvalidFile,
  GraphImportFailure.newerFormatVersion => localizations.dataImportNewerVersion,
  GraphImportFailure.storageFull => localizations.dataReplacementStorageFull,
  GraphImportFailure.documentUnreadable => localizations.dataImportUnreadable,
  GraphImportFailure.unknown => localizations.dataImportFailed,
};
