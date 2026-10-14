import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Готовое представление пункта нижней панели.
final class NavBarItem {
  const NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.title,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String title;
}

/// Нижняя панель с группой вкладок и отдельным действием в конце.
///
/// Потребитель задаёт выбранный пункт, обрабатывает выбор и оформляет действие.
/// Цвета берутся из расширения темы или палитры Doable для её яркости.
final class NavBar extends StatelessWidget {
  const NavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.action,
    super.key,
  }) : assert(selectedIndex >= 0 && selectedIndex < items.length);

  final List<NavBarItem> items;
  final int selectedIndex;

  /// Вызывается и для уже выбранного пункта.
  final ValueChanged<int> onSelected;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DoableColors>() ??
        switch (theme.brightness) {
          Brightness.light => DoableColors.light,
          Brightness.dark => DoableColors.dark,
        };
    return Material(
      color: colors.raised,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: DoableMetrics.navHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space3,
                1 + 6,
                DoableMetrics.space3,
                0,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    container: true,
                    explicitChildNodes: true,
                    role: SemanticsRole.tabBar,
                    child: Row(
                      spacing: DoableMetrics.space1,
                      children: [
                        for (final (index, item) in items.indexed)
                          Expanded(
                            child: _NavBarTab(
                              item: item,
                              colors: colors,
                              selected: selectedIndex == index,
                              position: MaterialLocalizations.of(context)
                                  .tabLabel(
                                    tabIndex: index + 1,
                                    tabCount: items.length,
                                  ),
                              onPressed: () => onSelected(index),
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  // Действие занимает равную долю, но не входит в tabBar:
                  // https://api.flutter.dev/flutter/dart-ui/SemanticsRole.html
                  Row(
                    spacing: DoableMetrics.space1,
                    children: [
                      for (final _ in items) const Spacer(),
                      Expanded(child: Center(child: action)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _NavBarTab extends StatelessWidget {
  const _NavBarTab({
    required this.item,
    required this.colors,
    required this.selected,
    required this.position,
    required this.onPressed,
  });

  final NavBarItem item;
  final DoableColors colors;
  final bool selected;
  final String position;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      button: true,
      selected: selected,
      label: '${item.title}\n$position',
      onTap: onPressed,
      child: Tooltip(
        message: item.title,
        excludeFromSemantics: true,
        // Ink оставляет отклик нажатия видимым поверх заливки пилюли.
        // https://api.flutter.dev/flutter/material/Ink-class.html
        child: Ink(
          decoration: ShapeDecoration(
            color: selected ? colors.fill : Colors.transparent,
            shape: const StadiumBorder(),
          ),
          child: InkWell(
            onTap: onPressed,
            excludeFromSemantics: true,
            customBorder: const StadiumBorder(),
            child: Center(
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: DoableMetrics.iconSize,
                color: selected ? colors.ink : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
