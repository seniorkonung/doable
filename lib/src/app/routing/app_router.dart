import 'package:auto_route/auto_route.dart';

import 'app_router.gr.dart';

@AutoRouterConfig()
final class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: IntentionCatalogRoute.page, initial: true),
    AutoRoute(page: TagCatalogRoute.page),
    AutoRoute(page: TagEditorRoute.page),
    AutoRoute(page: DailyChoiceCatalogRoute.page),
    AutoRoute(page: DailyChoiceActionPickerRoute.page),
    AutoRoute(page: DailyChoiceSourcePickerRoute.page),
    AutoRoute(page: IntentionEditorRoute.page),
    AutoRoute(page: IntentionDetailsRoute.page),
    AutoRoute(page: ChoicePathRoute.page),
    AutoRoute(page: DailyChoiceDetailsRoute.page),
    AutoRoute(page: DailyChoiceEditRoute.page),
    AutoRoute(page: RelationDetailsRoute.page),
    AutoRoute(page: RelationEditorRoute.page),
    AutoRoute(page: RelationParticipantPickerRoute.page),
  ];
}
