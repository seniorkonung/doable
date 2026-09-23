import 'package:auto_route/auto_route.dart';

import 'app_router.gr.dart';

@AutoRouterConfig()
final class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: IntentionCatalogRoute.page, initial: true),
    AutoRoute(page: IntentionEditorRoute.page),
    AutoRoute(page: IntentionDetailsRoute.page),
    AutoRoute(page: ChoicePathRoute.page),
    AutoRoute(page: RelationDetailsRoute.page),
    AutoRoute(page: RelationEditorRoute.page),
    AutoRoute(page: RelationParticipantPickerRoute.page),
  ];
}
