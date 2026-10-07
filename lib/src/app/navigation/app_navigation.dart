import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../routing/app_router.gr.dart';
import 'app_destination.dart';
import 'app_navigation_bar.dart';

/// Сборка основной навигации для оболочки и обычных страниц над ней.
///
/// Требует смонтированную оболочку [AppShellRoute] в начале корневого стека.
/// Единственный источник выбранного пункта — её маршрутизатор вкладок.
/// Выбор любого пункта удаляет всю историю над оболочкой без подтверждения
/// и выбирает сохранённую корневую страницу, включая повторный выбор пункта.
/// Страницы не управляют индексами вкладок или удалением маршрутов.
final class AppNavigation extends StatelessWidget {
  const AppNavigation({super.key});

  static const _heroTag = 'app-primary-navigation';

  @override
  Widget build(BuildContext context) {
    final root = context.router.root;
    final tabs = root.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) => Hero(
        // Одна метка на маршрут; панель оболочки находится вне HeroMode вкладок.
        // https://api.flutter.dev/flutter/widgets/Hero-class.html
        tag: _heroTag,
        transitionOnUserGestures: true,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: AppNavigationBar(
            selected: AppDestination.values[tabs.activeIndex],
            onSelected: (destination) {
              // Удаляет также безымянные маршруты через Navigator.popUntil.
              // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/popUntilRoot.html
              root.popUntilRoot();
              tabs.setActiveIndex(destination.index);
            },
          ),
        ),
      ),
    );
  }
}
