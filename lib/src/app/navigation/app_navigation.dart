import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../quick_creation/quick_creation_launcher.dart';
import '../quick_creation/quick_creation_mode_controller.dart';
import '../quick_creation/quick_creation_mode_menu.dart';
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
final class AppNavigation extends ConsumerStatefulWidget {
  const AppNavigation({this.sourceRoute, super.key});

  /// Контекст выбранной корневой страницы для панели вне вкладок.
  /// На обычной странице используется её собственный контекст.
  final RouteData? sourceRoute;

  @override
  ConsumerState<AppNavigation> createState() => _AppNavigationState();
}

final class _AppNavigationState extends ConsumerState<AppNavigation> {
  static const _heroTag = 'app-primary-navigation';
  final _launcher = QuickCreationLauncher();

  @override
  Widget build(BuildContext context) {
    final root = context.router.root;
    final tabs = root.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
    final mode = ref.watch(quickCreationModeControllerProvider);
    return ListenableBuilder(
      listenable: tabs,
      // Панель оболочки расположена вне вкладок. Передаём launcher контекст
      // именно выбранного корневого маршрута, сохраняя его matchId и router.
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/RouteDataScope-class.html
      builder: (context, _) {
        final panel = Builder(
          builder: (sourceContext) => Hero(
            // Одна метка на маршрут; панель оболочки находится вне HeroMode вкладок.
            // https://api.flutter.dev/flutter/widgets/Hero-class.html
            tag: _heroTag,
            transitionOnUserGestures: true,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: AppNavigationBar(
                selected: AppDestination.values[tabs.activeIndex],
                quickCreationMode: mode,
                onQuickCreate: () => unawaited(
                  _launcher.launch(sourceContext: sourceContext, mode: mode),
                ),
                onChangeQuickCreationMode: () =>
                    unawaited(showQuickCreationModeMenu(sourceContext)),
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
        final source = widget.sourceRoute;
        return source == null
            ? panel
            : RouteDataScope(routeData: source, child: panel);
      },
    );
  }
}
