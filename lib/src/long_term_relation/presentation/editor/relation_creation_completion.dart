import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../domain/long_term_relation_id.dart';

/// Закрывает только собственную форму после синхронной утраты прав создания.
void leaveRelationCreation({
  required StackRouter router,
  required LocalKey formMatchId,
}) {
  if (router.stackData.lastOrNull?.matchId != formMatchId ||
      router.pagelessRoutesObserver.hasPagelessTopRoute) {
    return;
  }
  // removeRoute удаляет конкретный matchId, не исходную страницу:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
  router.removeRoute(router.stackData.last);
}

/// Заменяет только актуальную форму подробным просмотром созданной связи.
/// Переход не зависит от жизни виджета; поздний вызов не получает права менять
/// новый маршрут.
void openCreatedRelation({
  required StackRouter router,
  required LocalKey formMatchId,
  required LongTermRelationId relationId,
}) {
  if (router.stackData.lastOrNull?.matchId != formMatchId ||
      router.pagelessRoutesObserver.hasPagelessTopRoute) {
    return;
  }
  // Future replace завершается при возврате со страницы, а не при открытии:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/replace.html
  unawaited(
    router.replace<void>(
      RelationDetailsRoute(relationId: relationId, key: UniqueKey()),
    ),
  );
}
