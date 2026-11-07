import '../../../../l10n/app_localizations.dart';
import '../catalog/intention_catalog_purpose.dart';

/// Что показывает поиск намерений: от этого зависят заголовок и начало ключей.
///
/// Единственный исчерпывающий разбор [IntentionCatalogPurpose] в модуле
/// поиска: части поиска узнают о назначении только отсюда.
enum IntentionSearchKind {
  catalog('intention-catalog'),
  relationParticipant('participant-picker'),
  pathStart('path-start-picker');

  const IntentionSearchKind(this.keyPrefix);

  static IntentionSearchKind of(IntentionCatalogPurpose purpose) =>
      switch (purpose) {
        BrowseIntentionCatalog() => catalog,
        SelectRelationParticipant() => relationParticipant,
        SelectPathStart() => pathStart,
      };

  /// Начало ключей элементов поиска, по которым их находят сценарии.
  final String keyPrefix;

  String title(AppLocalizations l10n) => switch (this) {
    catalog => l10n.appDestinationIntentionGraph,
    relationParticipant => l10n.participantPickerTitle,
    pathStart => l10n.pathStartPickerTitle,
  };
}
