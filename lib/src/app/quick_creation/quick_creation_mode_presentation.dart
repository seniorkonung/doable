import 'package:doable/l10n/app_localizations.dart';

import '../../design_system/doable_icon.dart';

import 'quick_creation_mode.dart';

/// Представление режима для кнопки и меню; хранение не зависит от интерфейса.
extension QuickCreationModePresentation on QuickCreationMode {
  String title(AppLocalizations localizations) => switch (this) {
    QuickCreationMode.intention => localizations.quickCreationModeIntention,
  };

  String hint(AppLocalizations localizations) => switch (this) {
    QuickCreationMode.intention => localizations.quickCreationModeIntentionHint,
  };

  DoableIconData get icon => switch (this) {
    QuickCreationMode.intention => DoableIconData.intention,
  };

  DoableIconData get miniIcon => switch (this) {
    QuickCreationMode.intention => DoableIconData.intentionMini,
  };
}
