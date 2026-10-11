import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/routing/app_router.gr.dart';
import '../domain/daily_choice_id.dart';
import 'daily_choice_creation_flow_session.dart';

/// Прекращает создание до удаления его страниц; чужая история и новая сессия
/// недоступны.
/// [previewRoute] — конкретный безымянный просмотр подсказки над корнем.
void leaveDailyChoiceCreation({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required LocalKey ownerMatchId,
  Route<void>? previewRoute,
}) {
  bool hasStack(List<LocalKey> suffix) => listEquals(
    router.stackData.map((route) => route.matchId).toList(),
    [...session.originalHistory, ...suffix],
  );

  final top = router.stackData.lastOrNull;
  if (top == null || top.matchId != ownerMatchId) return;
  final suffix = <LocalKey>[session.rootMatchId];
  if (top.matchId != session.rootMatchId) {
    if (top.args case DailyChoiceCreationRouteArgs(session: final owner)
        when identical(owner, session)) {
      suffix.add(top.matchId);
    } else {
      return;
    }
  }
  if (!hasStack(suffix)) return;
  final pageless = router.pagelessRoutesObserver;
  if (previewRoute != null) {
    if (top.matchId != session.rootMatchId ||
        !identical(pageless.current, previewRoute) ||
        !previewRoute.isCurrent) {
      return;
    }
  } else if (pageless.hasPagelessTopRoute) {
    return;
  }

  session.leave();
  if (previewRoute != null) {
    // Уведомление сессии тоже может передать верхнюю позицию другой странице.
    if (!hasStack(suffix) ||
        !identical(pageless.current, previewRoute) ||
        !previewRoute.isCurrent) {
      return;
    }
    // Удаляем именно собственную подсказку, не произвольный верхний маршрут:
    // https://api.flutter.dev/flutter/widgets/NavigatorState/removeRoute.html
    previewRoute.navigator!.removeRoute(previewRoute);
  }
  while (suffix.isNotEmpty) {
    if (session.state is! DailyChoiceCreationFlowLeft ||
        !hasStack(suffix) ||
        pageless.hasPagelessTopRoute) {
      return;
    }
    // removeRoute проверяет matchId и синхронно меняет stackData:
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
    router.removeRoute(router.stackData.last);
    suffix.removeLast();
  }
}

/// Открывает сохранённый выбор одной попыткой, удерживая сессию независимо
/// от виджетов. Удаляет только конкретное подтверждение и заменяет его корень;
/// перед каждой мутацией проверяет полную исходную историю и экземпляры.
void completeDailyChoiceCreation({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required LocalKey confirmationMatchId,
  required DailyChoiceId choiceId,
}) {
  final rootMatchId = session.rootMatchId;
  bool hasStack(List<LocalKey> suffix) => listEquals(
    router.stackData.map((route) => route.matchId).toList(),
    [...session.originalHistory, ...suffix],
  );

  bool isActive() => session.state is DailyChoiceCreationFlowSaved;
  final ownsConfirmation = switch (router.stackData.lastOrNull?.args) {
    DailyChoiceCreationRouteArgs(session: final owner) => identical(
      owner,
      session,
    ),
    _ => false,
  };
  if (!isActive() ||
      !hasStack([rootMatchId, confirmationMatchId]) ||
      !ownsConfirmation ||
      router.pagelessRoutesObserver.hasPagelessTopRoute ||
      !session.claimOpening(choiceId)) {
    return;
  }
  // removeRoute учитывает matchId и уведомляет без ожидания анимации:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
  router.removeRoute(router.stackData.last);
  if (!isActive() || !hasStack([rootMatchId])) return;
  // replace удаляет корень до асинхронной установки нового маршрута. Его
  // Future относится к возврату со страницы, а не к открытию:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/replace.html
  unawaited(
    router.replace<void>(
      DailyChoiceDetailsRoute(choiceId: choiceId, key: UniqueKey()),
    ),
  );
}
