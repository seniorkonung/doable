import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../domain/long_term_relation_id.dart';

/// Закрывает только собственную форму после синхронной утраты прав создания.
/// При частичном отказе согласует отображение с фактическим стеком.
void leaveRelationCreation({
  required StackRouter router,
  required LocalKey formMatchId,
}) {
  if (router.stackData.lastOrNull?.matchId != formMatchId ||
      router.pagelessRoutesObserver.hasPagelessTopRoute) {
    return;
  }
  final form = router.stackData.last;
  final history = router.stackData
      .take(router.stackData.length - 1)
      .map((route) => route.matchId)
      .toList();
  try {
    // removeRoute удаляет конкретный matchId, не исходную страницу:
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
    router.removeRoute(form);
  } catch (_, stack) {
    final remaining = router.stackData.map((route) => route.matchId).toList();
    if (listEquals(remaining, history) ||
        listEquals(remaining, [...history, formMatchId])) {
      // Удаление могло состояться без уведомления; новых мутаций здесь нет:
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/RoutingController/notifyAll.html
      router.notifyAll(forceUrlRebuild: true);
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError('Не удалось выйти из создания связи.'),
        stack: stack,
        library: 'relation editor',
        context: ErrorDescription(
          'при выходе из создания долговременной связи',
        ),
      ),
    );
  }
}

/// Заменяет только актуальную форму, сохраняя подтверждённую запись при отказе.
/// Обработка перехода не зависит от жизни виджета; поздний отказ не получает
/// права менять новый маршрут или восстанавливать удалённую форму.
void openCreatedRelation({
  required StackRouter router,
  required LocalKey formMatchId,
  required LongTermRelationId relationId,
}) {
  if (router.stackData.lastOrNull?.matchId != formMatchId ||
      router.pagelessRoutesObserver.hasPagelessTopRoute) {
    return;
  }
  final history = router.stackData
      .take(router.stackData.length - 1)
      .map((route) => route.matchId)
      .toList();
  final result = RelationDetailsRoute(relationId: relationId, key: UniqueKey());
  var installed = false;
  var listening = true;
  var reported = false;
  bool hasStack(List<LocalKey> suffix) => listEquals(
    router.stackData.map((route) => route.matchId).toList(),
    [...history, ...suffix],
  );

  late final VoidCallback stackChanged;
  void stopListening() {
    if (!listening) return;
    router.removeListener(stackChanged);
    listening = false;
  }

  stackChanged = () {
    if (router.stackData.length == history.length + 1 &&
        identical(router.stackData.last.args, result.args)) {
      installed = true;
      stopListening();
    } else if (!hasStack([formMatchId]) && !hasStack([])) {
      stopListening();
    }
  };

  void failed(StackTrace stack) {
    // После асинхронной границы согласуем только собственный остаток стека.
    final reconcile = listening && (hasStack([formMatchId]) || hasStack([]));
    stopListening();
    // replace мог удалить форму без уведомления. Новых мутаций истории нет:
    // https://pub.dev/documentation/auto_route/11.1.0/auto_route/RoutingController/notifyAll.html
    if (reconcile) router.notifyAll(forceUrlRebuild: true);
    if (reported) return;
    reported = true;
    // Исходное исключение может содержать пользовательские данные.
    // https://api.flutter.dev/flutter/foundation/FlutterError/reportError.html
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError('Не удалось открыть созданную связь.'),
        stack: stack,
        library: 'relation editor',
        context: ErrorDescription(
          'при открытии созданной долговременной связи',
        ),
      ),
    );
  }

  router.addListener(stackChanged);
  // Future replace завершается при возврате, установку отмечает слушатель:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/replace.html
  unawaited(
    Future<void>.sync(() => router.replace<void>(result)).then((_) {
      if (!installed && listening) failed(StackTrace.current);
    }, onError: (Object _, StackTrace stack) => failed(stack)),
  );
}
