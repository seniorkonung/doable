import '../../../../l10n/app_localizations.dart';
import '../catalog/intention_catalog_purpose.dart';

/// Что выбирает экран выбора: от этого зависят его заголовки и тексты
/// выдачи.
enum IntentionPickerKind {
  action,
  intention;

  static IntentionPickerKind of(IntentionPickerPurpose purpose) =>
      switch (purpose) {
        SelectDailyChoiceAction() => action,
        SelectDailyChoiceSource() || SelectRelationParticipant() => intention,
      };

  String title(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerActionTitle,
    intention => l10n.intentionPickerIntentionTitle,
  };

  String loading(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerLoading,
    intention => l10n.catalogLoading,
  };

  String noMatchesByTitle(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerNoActionsByTitle,
    intention => l10n.intentionPickerNoIntentionsByTitle,
  };

  String noMatchesByTags(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerNoActionsByTags,
    intention => l10n.intentionPickerNoIntentionsByTags,
  };

  String loadingMore(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerLoadingMoreActions,
    intention => l10n.intentionPickerLoadingMoreIntentions,
  };

  String unavailable(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerUnavailable,
    intention => l10n.catalogUnavailable,
  };

  String corruption(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerCorruption,
    intention => l10n.catalogCorruption,
  };

  String unexpected(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerUnexpected,
    intention => l10n.catalogUnexpectedFailure,
  };
}

/// Начало ключей элементов экрана выбора, по которым их находят сценарии
/// поисков.
String intentionPickerKeyPrefix(IntentionPickerPurpose purpose) =>
    switch (purpose) {
      SelectDailyChoiceAction() => 'daily-choice-action',
      SelectDailyChoiceSource() => 'daily-choice-source',
      SelectRelationParticipant() => 'participant-picker',
    };
