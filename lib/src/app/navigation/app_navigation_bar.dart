import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/design_system/components/nav_bar.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';

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
  static const double height = DoableMetrics.navHeight;

  final AppDestination selected;

  /// Вызывается при нажатии любого пункта, включая уже выбранный.
  final ValueChanged<AppDestination> onSelected;

  final QuickCreationMode quickCreationMode;
  final VoidCallback onQuickCreate;
  final VoidCallback onChangeQuickCreationMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return NavBar(
      items: [
        for (final destination in AppDestination.values)
          NavBarItem(
            icon: destination.icon,
            selectedIcon: destination.selectedIcon,
            title: destination.title(localizations),
          ),
      ],
      selectedIndex: selected.index,
      onSelected: (index) => onSelected(AppDestination.values[index]),
      action: QuickCreationButton(
        mode: quickCreationMode,
        onPressed: onQuickCreate,
        onChangeMode: onChangeQuickCreationMode,
      ),
    );
  }
}
