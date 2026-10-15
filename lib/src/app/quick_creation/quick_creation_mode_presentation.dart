import 'package:doable/l10n/app_localizations.dart';

import '../../design_system/doable_icon.dart';

import 'quick_creation_mode.dart';

/// Представление режима для кнопки и меню; хранение не зависит от интерфейса.
extension QuickCreationModePresentation on QuickCreationMode {
  String title(AppLocalizations localizations) => switch (this) {
    QuickCreationMode.intention => localizations.quickCreationModeIntention,
    QuickCreationMode.relation => localizations.quickCreationModeRelation,
    QuickCreationMode.dailyChoice => localizations.quickCreationModeDailyChoice,
  };

  String hint(AppLocalizations localizations) => switch (this) {
    QuickCreationMode.intention => localizations.quickCreationModeIntentionHint,
    QuickCreationMode.relation => localizations.quickCreationModeRelationHint,
    QuickCreationMode.dailyChoice =>
      localizations.quickCreationModeDailyChoiceHint,
  };

  DoableIconData get icon => switch (this) {
    QuickCreationMode.intention => DoableIconData.intention,
    QuickCreationMode.relation => DoableIconData.relation,
    QuickCreationMode.dailyChoice => DoableIconData.calendar,
  };

  DoableIconData get miniIcon => switch (this) {
    QuickCreationMode.intention => DoableIconData.intentionMini,
    QuickCreationMode.relation => DoableIconData.relationMini,
    QuickCreationMode.dailyChoice => DoableIconData.calendarMini,
  };
}
