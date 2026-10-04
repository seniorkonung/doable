import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:flutter/material.dart';

/// Нижняя панель основной навигации.
///
/// Показывает пункты [AppDestination] без видимых подписей. Панель получает
/// выбранный пункт и сообщает о выборе: маршрутов и содержимого страниц она
/// не знает.
final class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.selected,
    required this.onSelected,
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return NavigationBar(
      height: height,
      // Подпись не рисуется, но остаётся источником подсказки по долгому
      // нажатию и названия пункта для экранного диктора.
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      selectedIndex: selected.index,
      onDestinationSelected: (index) =>
          onSelected(AppDestination.values[index]),
      destinations: [
        for (final destination in AppDestination.values)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.title(localizations),
          ),
      ],
    );
  }
}
