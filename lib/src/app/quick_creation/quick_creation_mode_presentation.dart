import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

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

  IconData get icon => switch (this) {
    QuickCreationMode.intention => Icons.adjust_outlined,
    QuickCreationMode.relation => Icons.route_outlined,
    QuickCreationMode.dailyChoice => Icons.calendar_today_outlined,
  };

  DoableIconData get miniIcon => switch (this) {
    QuickCreationMode.intention => DoableIconData.intentionMini,
    QuickCreationMode.relation => DoableIconData.relationMini,
    QuickCreationMode.dailyChoice => DoableIconData.calendarMini,
  };
}
