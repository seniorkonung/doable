import '../../../../l10n/app_localizations.dart';
import '../catalog/intention_catalog_purpose.dart';

/// Что показывает поиск намерений: от этого зависят заголовок, тексты
/// загрузки и отказов, начало ключей и то, называет ли строка тип.
///
/// Единственный исчерпывающий разбор [IntentionCatalogPurpose] в модуле
/// поиска: части поиска узнают о назначении только отсюда. Выбор исходного
/// намерения и выбор участника различаются лишь началом ключей, но остаются
/// двумя вариантами, чтобы ни один из экранов не получил чужие ключи.
enum IntentionSearchKind {
  catalog('intention-catalog', namesKind: true),
  dailyChoiceAction('daily-choice-action', namesKind: false),
  dailyChoiceSource('daily-choice-source', namesKind: true),
  relationParticipant('participant-picker', namesKind: true);

  const IntentionSearchKind(this.keyPrefix, {required this.namesKind});

  static IntentionSearchKind of(IntentionCatalogPurpose purpose) =>
      switch (purpose) {
        BrowseIntentionCatalog() => catalog,
        SelectDailyChoiceAction() => dailyChoiceAction,
        SelectDailyChoiceSource() => dailyChoiceSource,
        SelectRelationParticipant() => relationParticipant,
      };

  /// Начало ключей элементов поиска, по которым их находят сценарии.
  final String keyPrefix;

  /// Называет ли строка тип найденного: поиск действий выбирает только
  /// действия, и называть вид в нём незачем.
  final bool namesKind;

  String title(AppLocalizations l10n) => switch (this) {
    catalog => l10n.appDestinationIntentionGraph,
    dailyChoiceAction => l10n.intentionPickerActionTitle,
    dailyChoiceSource ||
    relationParticipant => l10n.intentionPickerIntentionTitle,
  };

  String loading(AppLocalizations l10n) => switch (this) {
    dailyChoiceAction => l10n.actionPickerLoading,
    catalog || dailyChoiceSource || relationParticipant => l10n.catalogLoading,
  };

  String loadingMore(AppLocalizations l10n) => switch (this) {
    dailyChoiceAction => l10n.intentionPickerLoadingMoreActions,
    catalog ||
    dailyChoiceSource ||
    relationParticipant => l10n.intentionPickerLoadingMoreIntentions,
  };

  String unavailable(AppLocalizations l10n) => switch (this) {
    dailyChoiceAction => l10n.actionPickerUnavailable,
    catalog ||
    dailyChoiceSource ||
    relationParticipant => l10n.catalogUnavailable,
  };

  String corruption(AppLocalizations l10n) => switch (this) {
    dailyChoiceAction => l10n.actionPickerCorruption,
    catalog ||
    dailyChoiceSource ||
    relationParticipant => l10n.catalogCorruption,
  };

  String unexpected(AppLocalizations l10n) => switch (this) {
    dailyChoiceAction => l10n.actionPickerUnexpected,
    catalog ||
    dailyChoiceSource ||
    relationParticipant => l10n.catalogUnexpectedFailure,
  };
}
