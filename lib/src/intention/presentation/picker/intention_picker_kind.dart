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
        SelectDailyChoiceSource() => intention,
      };

  String title(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerActionTitle,
    intention => l10n.intentionPickerIntentionTitle,
  };

  String header(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerActionsHeader,
    intention => l10n.intentionPickerIntentionsHeader,
  };

  String loading(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerLoading,
    intention => l10n.catalogLoading,
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
    };
