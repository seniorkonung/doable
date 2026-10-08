import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'quick_creation_mode.dart';

/// Представление режима для кнопки и меню; хранение не зависит от интерфейса.
extension QuickCreationModePresentation on QuickCreationMode {
  String title(AppLocalizations localizations) => switch (this) {
    QuickCreationMode.intention => localizations.quickCreationModeIntention,
    QuickCreationMode.relation => localizations.quickCreationModeRelation,
    QuickCreationMode.dailyChoiceFromIntention =>
      localizations.quickCreationModeDailyChoiceFromIntention,
    QuickCreationMode.dailyChoiceFromAction =>
      localizations.quickCreationModeDailyChoiceFromAction,
  };

  IconData get icon => switch (this) {
    QuickCreationMode.intention => Icons.circle_outlined,
    QuickCreationMode.relation => Icons.link,
    QuickCreationMode.dailyChoiceFromIntention => Icons.arrow_downward,
    QuickCreationMode.dailyChoiceFromAction => Icons.arrow_upward,
  };
}

/// Стрелки смены режима отличаются от направлений построения дневного пути.
const IconData quickCreationChangeModeIcon = Icons.unfold_more;
