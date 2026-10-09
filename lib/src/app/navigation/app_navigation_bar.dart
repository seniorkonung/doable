import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../quick_creation/quick_creation_button.dart';
import '../quick_creation/quick_creation_mode.dart';

/// Нижняя панель основной навигации.
///
/// Показывает пункты [AppDestination] без видимых подписей. Панель получает
/// выбранный пункт и сообщает о выборе: маршрутов и содержимого страниц она
/// не знает.
final class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.selected,
    required this.onSelected,
    required this.quickCreationMode,
    required this.onQuickCreate,
    required this.onChangeQuickCreationMode,
    super.key,
  });

  /// Высота панели без нижнего безопасного отступа.
  ///
  /// Задана явно: раскладка корневых страниц опирается на неё без измерения
  /// панели после раскладки.
  static const double height = 64;

  final AppDestination selected;

  /// Вызывается при нажатии любого пункта, включая уже выбранный.
  final ValueChanged<AppDestination> onSelected;

  final QuickCreationMode quickCreationMode;
  final VoidCallback onQuickCreate;
  final VoidCallback onChangeQuickCreationMode;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: theme.backgroundColor ?? colors.surfaceContainer,
      elevation: theme.elevation ?? 3,
      shadowColor: theme.shadowColor ?? Colors.transparent,
      surfaceTintColor: theme.surfaceTintColor ?? Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                container: true,
                explicitChildNodes: true,
                role: SemanticsRole.tabBar,
                child: Row(
                  children: [
                    for (final destination in AppDestination.values) ...[
                      if (destination == AppDestination.intentionGraph)
                        const Expanded(child: SizedBox.shrink()),
                      Expanded(
                        child: _Destination(
                          destination: destination,
                          selected: selected == destination,
                          onPressed: () => onSelected(destination),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Действие находится вне группы вкладок: tabBar допускает
              // только дочерние tab и не должен считать кнопку четвёртым пунктом.
              Row(
                children: [
                  const Spacer(flex: 2),
                  Expanded(
                    child: Center(
                      child: QuickCreationButton(
                        mode: quickCreationMode,
                        onPressed: onQuickCreate,
                        onChangeMode: onChangeQuickCreationMode,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = destination.title(AppLocalizations.of(context));
    final position = MaterialLocalizations.of(context).tabLabel(
      tabIndex: destination.index + 1,
      tabCount: AppDestination.values.length,
    );
    final theme = NavigationBarTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    final states = {if (selected) WidgetState.selected};
    final iconTheme = IconThemeData(
      size: 24,
      color: selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
    ).merge(theme.iconTheme?.resolve(states));
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      button: true,
      selected: selected,
      label: '$title\n$position',
      onTap: onPressed,
      child: Tooltip(
        message: title,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          overlayColor: theme.overlayColor,
          child: SizedBox.expand(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: selected ? 1 : 0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubicEmphasized,
                builder: (context, value, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    // Индикатор Material 3 остаётся за значком пункта.
                    // https://api.flutter.dev/flutter/material/NavigationIndicator-class.html
                    NavigationIndicator(
                      animation: AlwaysStoppedAnimation(value),
                      color: theme.indicatorColor ?? colors.secondaryContainer,
                      shape: theme.indicatorShape ?? const StadiumBorder(),
                    ),
                    IconTheme(
                      data: iconTheme,
                      child: Icon(
                        selected ? destination.selectedIcon : destination.icon,
                      ),
                    ),
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
