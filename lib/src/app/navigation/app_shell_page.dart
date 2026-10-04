import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'app_destination.dart';
import 'app_navigation_bar.dart';
import 'app_shell_tab_insets.dart';

/// Оболочка корневых страниц: область вкладок и панель основной навигации.
///
/// Оболочка знает пункты [AppDestination] и раскладку, но не содержимое
/// страниц. Собственного `Scaffold` у неё нет: каждая корневая страница
/// сохраняет свой и остаётся получателем общих сообщений, поэтому сообщение
/// появляется над панелью, а основное действие страницы поднимается над ним.
@RoutePage()
final class AppShellPage extends StatelessWidget {
  const AppShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Вкладки — дочерние маршруты оболочки в порядке [AppDestination.values]:
    // индекс вкладки и индекс пункта совпадают по построению маршрутизатора.
    return AutoTabsRouter.builder(
      // Дошедшее до приложения «назад» с каталога выбирает Главную, а с
      // Главной передаётся родителю — приложение покидается.
      homeIndex: AppDestination.home.index,
      builder: (context, children, tabsRouter) {
        final selected = AppDestination.values[tabsRouter.activeIndex];
        // Объявление платформе: пока выбран каталог, маршрут оболочки
        // запрещает закрытие, и framework сообщает о готовности обработать
        // «назад» — иначе платформа выполнит выход сама. Переход на Главную
        // выполняет только `homeIndex`, поэтому обратного вызова здесь нет.
        return PopScope<Object?>(
          canPop: selected == AppDestination.home,
          child: Column(
            children: [
              Expanded(
                child: AppShellTabInsets(
                  barHeight: AppNavigationBar.height,
                  child: _AppShellTabs(selected: selected, children: children),
                ),
              ),
              // Как и `Scaffold.bottomNavigationBar`, панель не получает
              // верхний системный отступ: он относится к содержимому страницы.
              MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: AppNavigationBar(
                  selected: selected,
                  onSelected: (destination) =>
                      tabsRouter.setActiveIndex(destination.index),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Область вкладок оболочки.
///
/// Вкладка строится при первом выборе пункта и дальше остаётся в дереве:
/// состояние страницы живёт весь запуск, а страница продолжает согласовываться
/// с подтверждёнными изменениями. Переключение идёт без анимации перехода.
final class _AppShellTabs extends StatefulWidget {
  const _AppShellTabs({required this.selected, required this.children});

  final AppDestination selected;

  /// Вкладки в порядке [AppDestination.values].
  final List<Widget> children;

  @override
  State<_AppShellTabs> createState() => _AppShellTabsState();
}

final class _AppShellTabsState extends State<_AppShellTabs> {
  /// Пункты, вкладки которых уже построены в этом запуске.
  late final Set<AppDestination> _built = {widget.selected};

  @override
  void didUpdateWidget(_AppShellTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built.add(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.selected.index,
      sizing: StackFit.expand,
      children: [
        for (final destination in AppDestination.values)
          if (_built.contains(destination))
            _tab(destination)
          else
            const SizedBox.shrink(),
      ],
    );
  }

  /// `IndexedStack` исключает невыбранную вкладку только из отрисовки,
  /// попаданий и семантики. Без `HeroMode` общее сообщение, построенное в
  /// `Scaffold` нескольких вкладок, даёт одинаковые метки `Hero`; без
  /// `TickerMode` скрытая вкладка могла бы подтвердить предъявление сообщения.
  Widget _tab(AppDestination destination) {
    final isSelected = destination == widget.selected;
    return HeroMode(
      enabled: isSelected,
      child: TickerMode(
        enabled: isSelected,
        child: widget.children[destination.index],
      ),
    );
  }
}
