import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../daily_choice/application/choice_path_draft.dart';
import '../../daily_choice/presentation/daily_choice_creation_launcher.dart';
import '../../long_term_relation/presentation/editor/relation_editor_state.dart';
import '../../shared/presentation/exclusive_operation.dart';
import '../routing/app_router.gr.dart';
import 'quick_creation_mode.dart';

/// Общий вход в готовые потоки создания без изменения исходной истории.
///
/// Каждый экземпляр панели владеет своим launcher. Контекст должен принадлежать
/// текущей обычной странице, для оболочки — выбранной корневой вкладке.
/// Повторный запуск отклоняется до открытия первой страницы; у дневного выбора
/// блокировка сохраняется до окончания поиска и открытия пути. Возврат Future
/// означает окончание запуска, а не завершение создания или возврат из формы.
final class QuickCreationLauncher {
  final _operation = ExclusiveOperation<void>();
  final _dailyChoice = DailyChoiceCreationLauncher();

  Future<void> launch({
    required BuildContext sourceContext,
    required QuickCreationMode mode,
  }) => switch (_operation.start(() => _launch(sourceContext, mode))) {
    ExclusiveOperationAccepted(:final future) => future,
    ExclusiveOperationAlreadyRunning() => Future<void>.value(),
  };

  Future<void> _launch(BuildContext context, QuickCreationMode mode) async {
    if (!context.mounted) return;
    final router = context.router.root;
    final source = context.routeData;
    if (router.topRoute.matchId != source.matchId ||
        router.hasPagelessTopRoute) {
      return;
    }
    switch (mode) {
      case QuickCreationMode.intention:
        await _openFirst(router, const IntentionEditorRoute());
      case QuickCreationMode.relation:
        await _openFirst(
          router,
          RelationEditorRoute(
            editorContext: const RelationBlankCreationContext(),
          ),
        );
      case QuickCreationMode.dailyChoiceFromIntention:
        await _dailyChoice.launch(
          sourceContext: context,
          direction: ChoicePathDraftDirection.topDown,
        );
      case QuickCreationMode.dailyChoiceFromAction:
        await _dailyChoice.launch(
          sourceContext: context,
          direction: ChoicePathDraftDirection.bottomUp,
        );
    }
  }

  Future<void> _openFirst(RootStackRouter router, PageRouteInfo route) async {
    final history = [for (final data in router.stackData) data.matchId];
    final openedOrStopped = Completer<void>();
    void finish() {
      if (!openedOrStopped.isCompleted) openedOrStopped.complete();
    }

    void check() {
      final stack = router.stackData;
      final sourcePresent = listEquals(
        stack.take(history.length).map((data) => data.matchId).toList(),
        history,
      );
      final first = stack.elementAtOrNull(history.length);
      if (!sourcePresent ||
          (first != null &&
              first.name == route.routeName &&
              identical(first.args, route.args))) {
        finish();
      }
    }

    router.addListener(check);
    try {
      // push завершается при закрытии страницы. Открытие подтверждает новый
      // экземпляр маршрута непосредственно над сохранённой историей.
      // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/push.html
      unawaited(
        router
            .push<void>(
              route,
              onFailure: (_) {
                _reportFailure(StackTrace.current);
                finish();
              },
            )
            .then<void>(
              (_) => finish(),
              onError: (Object _, StackTrace stack) {
                _reportFailure(stack);
                finish();
              },
            ),
      );
      check();
      await openedOrStopped.future;
    } catch (_, stack) {
      _reportFailure(stack);
    } finally {
      router.removeListener(check);
    }
  }
}

void _reportFailure(StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError('Не удалось начать быстрое создание.'),
      stack: stack,
      library: 'quick creation',
      context: ErrorDescription('при открытии первой страницы создания'),
    ),
  );
}
