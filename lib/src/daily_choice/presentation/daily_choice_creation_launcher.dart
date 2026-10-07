import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/routing/app_router.gr.dart';
import '../../intention/domain/intention_id.dart';
import '../application/choice_path_draft.dart';
import 'daily_choice_picker_context.dart';

/// Самостоятельный вход через поиск основания или действия.
///
/// Исходная страница передаёт собственный контекст и держит один экземпляр
/// запускающего объекта. Повторный вызов во время живого запуска отклоняется;
/// разные страницы используют независимые экземпляры. Возврат из поиска
/// открывает путь только над той же исходной историей. Future завершается
/// при открытии пути или закрытии поиска; отказ диагностируется без повтора.
final class DailyChoiceCreationLauncher {
  _Launch? _pending;

  Future<void> launch({
    required BuildContext sourceContext,
    required ChoicePathDraftDirection direction,
  }) async {
    if (_pending?.isActive ?? false) return;
    if (!sourceContext.mounted) return;
    final router = sourceContext.router.root;
    final source = sourceContext.routeData;
    if (router.topRoute.matchId != source.matchId ||
        router.hasPagelessTopRoute) {
      return;
    }
    final launch = _Launch(sourceContext, source, router);
    _pending = launch;
    try {
      final pickerContext = InitialDailyChoicePickerContext(launch: launch);
      final id = await router.push<IntentionId>(switch (direction) {
        ChoicePathDraftDirection.topDown => DailyChoiceSourcePickerRoute(
          pickerContext: pickerContext,
        ),
        ChoicePathDraftDirection.bottomUp => DailyChoiceActionPickerRoute(
          pickerContext: pickerContext,
        ),
      });
      if (id == null || !launch.canOpenPath) return;
      await launch.openPath(id, direction);
    } catch (_, stack) {
      _reportFailure(stack);
    } finally {
      launch.dispose();
      if (identical(_pending, launch)) _pending = null;
    }
  }
}

final class _Launch implements DailyChoicePickerLaunch {
  _Launch(this.sourceContext, RouteData source, this.router)
    : sourceRouter = source.router,
      sourceMatchId = source.matchId,
      history = [for (final route in router.stackData) route.matchId] {
    router.addListener(_checkSource);
    if (!identical(sourceRouter, router)) {
      sourceRouter.addListener(_checkSource);
    }
  }

  final BuildContext sourceContext;
  final RootStackRouter router;
  final RoutingController sourceRouter;
  final LocalKey sourceMatchId;
  final List<LocalKey> history;
  bool _active = true;

  bool get _sourcePresent =>
      sourceContext.mounted &&
      listEquals(
        router.stackData
            .take(history.length)
            .map((route) => route.matchId)
            .toList(),
        history,
      ) &&
      sourceRouter.stackData.any((route) => route.matchId == sourceMatchId) &&
      (sourceRouter is! TabsRouter ||
          sourceRouter.current.matchId == sourceMatchId);

  @override
  bool get isActive => _active && _sourcePresent;

  // topRoute учитывает выбранную вкладку, а matchId — конкретную страницу:
  // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/topRoute.html
  bool get canOpenPath =>
      isActive &&
      listEquals(
        router.stackData.map((route) => route.matchId).toList(),
        history,
      ) &&
      router.topRoute.matchId == sourceMatchId &&
      !router.hasPagelessTopRoute;

  Future<void> openPath(
    IntentionId id,
    ChoicePathDraftDirection direction,
  ) async {
    final path = ChoicePathRoute(sourceIntentionId: id, direction: direction);
    final opened = Completer<void>();
    void finish() {
      if (!opened.isCompleted) opened.complete();
    }

    void check() {
      if (!isActive ||
          identical(router.stackData.lastOrNull?.args, path.args)) {
        finish();
      }
    }

    router.addListener(check);
    try {
      // Future push означает возврат со страницы. Открытие подтверждает
      // конкретный маршрут: replace пути может вообще не завершить Future.
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/push.html
      unawaited(
        router
            .push<void>(path)
            .then<void>(
              (_) => finish(),
              onError: (Object _, StackTrace stack) {
                _reportFailure(stack);
                finish();
              },
            ),
      );
      check();
      await opened.future;
    } finally {
      router.removeListener(check);
    }
  }

  void _checkSource() {
    // Сброс лишает права продолжения до dispose. Возврат к прежней вкладке
    // не возобновляет запуск, отменённый при её переключении.
    if (!_sourcePresent) cancel();
  }

  @override
  void cancel() => _active = false;

  void dispose() {
    cancel();
    router.removeListener(_checkSource);
    if (!identical(sourceRouter, router)) {
      sourceRouter.removeListener(_checkSource);
    }
  }
}

void _reportFailure(StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError('Не удалось начать дневной выбор.'),
      stack: stack,
      library: 'daily choice creation',
      context: ErrorDescription('при запуске создания через поиск'),
    ),
  );
}
