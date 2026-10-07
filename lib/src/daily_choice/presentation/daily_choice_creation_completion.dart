import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import '../../app/routing/app_router.gr.dart';
import '../domain/daily_choice_id.dart';
import 'daily_choice_creation_flow_session.dart';

/// Открывает сохранённый выбор одной попыткой, удерживая сессию независимо
/// от виджетов. Удаляет только конкретное подтверждение и заменяет его корень;
/// перед каждой мутацией проверяет полную исходную историю и экземпляры.
/// Возвращается при установке результата либо прекращении попытки, а не при
/// закрытии подробного просмотра. Отказ оставляет фактический стек и Saved,
/// диагностируется отдельно от записи и не повторяет переход.
Future<void> completeDailyChoiceCreation({
  required StackRouter router,
  required DailyChoiceCreationFlowSession session,
  required LocalKey confirmationMatchId,
  required DailyChoiceId choiceId,
}) {
  return _Opening(router, session, confirmationMatchId, choiceId).run();
}

final class _Opening {
  _Opening(
    this.router,
    DailyChoiceCreationFlowSession session,
    this.confirmationMatchId,
    DailyChoiceId choiceId,
  ) : _session = session,
      rootMatchId = session.rootMatchId,
      originalHistory = session.originalHistory,
      result = DailyChoiceDetailsRoute(choiceId: choiceId, key: UniqueKey());

  final StackRouter router;
  DailyChoiceCreationFlowSession? _session;
  final LocalKey rootMatchId;
  final List<LocalKey> originalHistory;
  final LocalKey confirmationMatchId;
  final DailyChoiceDetailsRoute result;
  final _done = Completer<void>();
  var _listening = false;
  var _reported = false;
  var _stage = _OpeningStage.confirmation;

  bool _hasStack(List<LocalKey> suffix) => listEquals(
    router.stackData.map((route) => route.matchId).toList(),
    [...originalHistory, ...suffix],
  );

  bool get _active => _session?.state is DailyChoiceCreationFlowSaved;

  bool get _ownsConfirmation => switch (router.stackData.lastOrNull?.args) {
    DailyChoiceCreationRouteArgs(:final session) => identical(
      session,
      _session,
    ),
    _ => false,
  };

  Future<void> run() {
    if (!_active ||
        !_hasStack([rootMatchId, confirmationMatchId]) ||
        !_ownsConfirmation ||
        router.pagelessRoutesObserver.hasPagelessTopRoute ||
        !_session!.claimOpening(result.args!.choiceId)) {
      return Future.value();
    }
    try {
      // removeRoute учитывает matchId и уведомляет без ожидания анимации:
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
      router.removeRoute(router.stackData.last);
      if (!_active || !_hasStack([rootMatchId])) {
        return Future.value();
      }
      _stage = _OpeningStage.root;
      router.addListener(_stackChanged);
      _listening = true;
      // replace удаляет корень до асинхронной установки нового маршрута.
      // Его Future относится к возврату; открытие подтверждает слушатель:
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/replace.html
      unawaited(
        Future<void>.sync(() => router.replace<void>(result)).then((_) {
          if (!_done.isCompleted) _failed(StackTrace.current);
        }, onError: (Object _, StackTrace stack) => _failed(stack)),
      );
    } catch (_, stack) {
      _failed(stack);
    }
    return _done.future;
  }

  void _stackChanged() {
    final stack = router.stackData;
    if (stack.length == originalHistory.length + 1 &&
        listEquals(
          stack
              .take(originalHistory.length)
              .map((route) => route.matchId)
              .toList(),
          originalHistory,
        ) &&
        identical(stack.last.args, result.args)) {
      _stage = _OpeningStage.installed;
      _finish();
    } else if (!_hasStack([rootMatchId]) && !_hasStack([])) {
      _finish();
    }
  }

  void _failed(StackTrace stack) {
    if (!_done.isCompleted) {
      _finish();
      // После отказа replace мог удалить корень без уведомления. Только
      // согласуем отображение: новых удалений и восстановления формы нет.
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/RoutingController/notifyAll.html
      if (_hasStack([]) ||
          _hasStack([rootMatchId]) ||
          _hasStack([rootMatchId, confirmationMatchId])) {
        router.notifyAll(forceUrlRebuild: true);
      }
    }
    if (_reported) return;
    _reported = true;
    // Исходный exception может содержать ID или пользовательский ввод.
    // https://api.flutter.dev/flutter/foundation/FlutterError/reportError.html
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError('Не удалось открыть созданный дневной выбор.'),
        stack: stack,
        library: 'daily choice creation',
        context: ErrorDescription(
          'при завершении дневного выбора: ${_stage.name}',
        ),
      ),
    );
  }

  void _finish() {
    if (_listening) {
      router.removeListener(_stackChanged);
      _listening = false;
    }
    // Поздний отказ Future подробного просмотра удерживает только адаптер,
    // а завершённая попытка больше не владеет сессией создания.
    _session = null;
    if (!_done.isCompleted) _done.complete();
  }
}

enum _OpeningStage { confirmation, root, installed }
