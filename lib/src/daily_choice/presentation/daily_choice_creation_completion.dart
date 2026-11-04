import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import '../../app/routing/app_router.gr.dart';
import 'daily_choice_creation_flow_session.dart';

/// Прекращает создание до удаления его страниц; чужая история и новая сессия
/// недоступны.
void leaveDailyChoiceCreation({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required LocalKey ownerMatchId,
}) {
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
  if (!_hasStack(router, session, suffix)) return;
  if (router.pagelessRoutesObserver.hasPagelessTopRoute) return;

  session.leave();
  _removeFlowRoutes(
    router: router,
    session: session,
    suffix: suffix,
    isCurrent: () => session.state is DailyChoiceCreationFlowLeft,
  );
}

/// Закрывает поток сохранённого выбора, удерживая сессию
/// независимо от виджетов. Удаляет только конкретное подтверждение и его корень,
/// поэтому наверху остаётся страница, с которой начато создание.
void completeDailyChoiceCreation({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required LocalKey confirmationMatchId,
}) {
  final suffix = <LocalKey>[session.rootMatchId, confirmationMatchId];
  bool isSaved() => session.state is DailyChoiceCreationFlowSaved;
  final ownsConfirmation = switch (router.stackData.lastOrNull?.args) {
    DailyChoiceCreationRouteArgs(session: final owner) => identical(
      owner,
      session,
    ),
    _ => false,
  };
  if (!isSaved() ||
      !_hasStack(router, session, suffix) ||
      !ownsConfirmation ||
      router.pagelessRoutesObserver.hasPagelessTopRoute) {
    return;
  }
  _removeFlowRoutes(
    router: router,
    session: session,
    suffix: suffix,
    isCurrent: isSaved,
  );
}

bool _hasStack(
  StackRouter router,
  DailyChoiceCreationFlowSession session,
  List<LocalKey> suffix,
) => listEquals(router.stackData.map((route) => route.matchId).toList(), [
  ...session.originalHistory,
  ...suffix,
]);

/// Снимает страницы потока сверху вниз. Перед каждым снятием проверяет
/// состояние сессии, полную исходную историю и верхний безымянный маршрут.
void _removeFlowRoutes({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required List<LocalKey> suffix,
  required bool Function() isCurrent,
}) {
  final pageless = router.pagelessRoutesObserver;
  while (suffix.isNotEmpty) {
    if (!isCurrent() ||
        !_hasStack(router, session, suffix) ||
        pageless.hasPagelessTopRoute) {
      return;
    }
    // removeRoute проверяет matchId и синхронно меняет stackData:
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
    router.removeRoute(router.stackData.last);
    suffix.removeLast();
  }
}
