import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../routing/app_router.gr.dart';

/// Находится ли маршрут страницы выше поиска участника в корневой истории.
bool isAboveRelationPicker(BuildContext context) {
  final routes = context.router.root.stackData;
  final page = context
      .findAncestorWidgetOfExactType<RouteDataScope>()
      ?.routeData;
  if (page == null) return false;
  final pageIndex = routes.indexWhere((route) => route.matchId == page.matchId);
  return pageIndex >= 0 &&
      routes
          .take(pageIndex)
          .any((route) => route.name == RelationBatchPickerRoute.name);
}
