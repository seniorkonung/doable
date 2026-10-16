import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../design_system/components/nav_bar.dart';

import 'quick_creation_mode.dart';
import 'quick_creation_mode_presentation.dart';

/// Быстрое создание с отдельным действием смены режима, без состояния выбора.
/// Запуск и открытие меню принадлежат вызывающей стороне.
final class QuickCreationButton extends StatelessWidget {
  const QuickCreationButton({
    required this.mode,
    required this.onPressed,
    required this.onChangeMode,
    super.key,
  });

  final QuickCreationMode mode;
  final VoidCallback onPressed;
  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return NavBarCreateButton(
      icon: mode.miniIcon,
      label:
          '${localizations.quickCreationLabel}, ${mode.title(localizations)}',
      hint: localizations.quickCreationLongPressHint,
      longPressLabel: localizations.quickCreationChangeMode,
      onPressed: onPressed,
      onLongPress: onChangeMode,
    );
  }
}
