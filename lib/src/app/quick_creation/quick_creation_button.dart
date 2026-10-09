import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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

  // Действия кешируются по локализованному названию согласно контракту Flutter:
  // https://api.flutter.dev/flutter/semantics/CustomSemanticsAction-class.html
  static final _changeModeActions = <String, CustomSemanticsAction>{};

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final changeMode = localizations.quickCreationChangeMode;
    final changeModeAction = _changeModeActions.putIfAbsent(
      changeMode,
      () => CustomSemanticsAction(label: changeMode),
    );
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return Semantics(
      container: true,
      button: true,
      label:
          '${localizations.quickCreationLabel}, ${mode.title(localizations)}',
      hint: localizations.quickCreationLongPressHint,
      onLongPressHint: changeMode,
      onTap: onPressed,
      onLongPress: onChangeMode,
      customSemanticsActions: {changeModeAction: onChangeMode},
      child: SizedBox(
        width: 64,
        height: 48,
        child: Material(
          color: colors.secondaryContainer,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            onLongPress: onChangeMode,
            excludeFromSemantics: true,
            borderRadius: borderRadius,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: colors.onSecondaryContainer),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 32,
                      child: Stack(
                        children: [
                          const Positioned(
                            top: 0,
                            left: 0,
                            child: Icon(Icons.add, size: 28),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Icon(mode.icon, size: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(quickCreationChangeModeIcon, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
