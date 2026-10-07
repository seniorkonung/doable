import 'package:auto_route/auto_route.dart';

import '../navigation/app_destination.dart';
import 'app_router.gr.dart';

@AutoRouterConfig()
final class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    // Корневые страницы — дочерние маршруты оболочки без собственных стеков.
    // Остальные маршруты открываются поверх оболочки. Обычные страницы
    // сохраняют панель, а страницы-задачи скрывают её своим каркасом.
    AutoRoute(
      page: AppShellRoute.page,
      initial: true,
      children: [
        for (final destination in AppDestination.values)
          AutoRoute(page: destination.page),
      ],
    ),
    AutoRoute(page: TagCatalogRoute.page),
    AutoRoute(page: TagEditorRoute.page),
    AutoRoute(page: TagNavigationRoute.page),
    AutoRoute(page: TagConditionPickerRoute.page),
    AutoRoute(page: DailyChoiceActionPickerRoute.page),
    AutoRoute(page: DailyChoiceSourcePickerRoute.page),
    // Создание намерения — модальная нижняя панель над сохранённой корневой
    // страницей в этом же стеке (ADR-0018). Маршрут прозрачен и сам по фону
    // не закрывается: закрытие решает сессия создания, а вход и выход
    // анимирует сама панель. Из неё открываются только страницы-задачи
    // выбора и редактирования тегов: они сохраняют защищённую сессию.
    CustomRoute<void>(
      page: IntentionEditorRoute.page,
      opaque: false,
      maintainState: true,
      barrierDismissible: false,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    ),
    AutoRoute(page: IntentionDetailsRoute.page),
    AutoRoute(page: ChoicePathRoute.page),
    AutoRoute(page: DailyChoiceDetailsRoute.page),
    AutoRoute(page: DailyChoiceEditRoute.page),
    AutoRoute(page: RelationDetailsRoute.page),
    AutoRoute(page: RelationEditorRoute.page),
    AutoRoute(page: RelationParticipantPickerRoute.page),
  ];
}
