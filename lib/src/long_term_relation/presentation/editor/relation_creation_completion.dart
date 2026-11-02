import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../domain/long_term_relation_id.dart';
import '../details/relation_details_sheet.dart';

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

/// Убирает из истории только актуальную форму и показывает панель созданной или
/// восстановленной связи над исходной страницей, удаляя и поиск участника над
/// формой. Этот поиск открывает только сама форма и только с вершины стека,
/// поэтому поиск сразу над формой принадлежит её потоку. Переход не зависит от
/// жизни виджета; поздний вызов не получает права менять новый маршрут.
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
  router.removeRoute(router.stackData.last);
  // Безымянный маршрут уходит вместе со страницей под ним, поэтому панель ждёт
  // кадра, в котором навигатор получил стек без формы:
  // https://api.flutter.dev/flutter/widgets/Navigator-class.html#using-the-pages-api
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (router.navigatorKey.currentContext case final context?) {
      unawaited(showRelationDetailsSheet(context, relationId));
    }
  });
}
