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

/// Заменяет только актуальную форму подробным просмотром созданной или
/// восстановленной связи, удаляя поиск участника над ней. Этот поиск открывает
/// только сама форма и только с вершины стека, поэтому поиск сразу над формой
/// принадлежит её потоку. Переход не зависит от жизни виджета; поздний вызов не
/// получает права менять новый маршрут.
void openCreatedRelation({
  required StackRouter router,
  required LocalKey formMatchId,
  required LongTermRelationId relationId,
}) {
  if (router.pagelessRoutesObserver.hasPagelessTopRoute) return;
  final top = router.stackData.lastOrNull;
  if (top?.matchId != formMatchId) {
    final ownsPicker = switch (router.stackData) {
      [..., final below, final picker] =>
        below.matchId == formMatchId &&
            picker.name == RelationParticipantPickerRoute.name,
      _ => false,
    };
    if (!ownsPicker) return;
    // removeRoute учитывает matchId и уведомляет без ожидания анимации:
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
    router.removeRoute(top!);
  }
  // Future replace завершается при возврате со страницы, а не при открытии:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/replace.html
  unawaited(
    router.replace<void>(
      RelationDetailsRoute(relationId: relationId, key: UniqueKey()),
    ),
  );
}
