import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../action/presentation/editor/action_editor_state.dart';
import '../../shared/domain/calendar_date.dart';
import '../../shared/presentation/exclusive_operation.dart';
import '../../shared/presentation/local_day/local_date_provider.dart';
import '../routing/app_router.gr.dart';
import 'quick_creation_mode.dart';

/// Общий вход в готовые потоки создания без изменения исходной истории.
///
/// Каждый экземпляр панели владеет своим launcher. Контекст должен принадлежать
/// текущей обычной странице, для оболочки — выбранной корневой вкладке.
/// Повторный запуск отклоняется до открытия первой страницы. Возврат Future
/// означает окончание запуска, а не завершение создания или возврат из формы.
final class QuickCreationLauncher {
  final _operation = ExclusiveOperation<void>();

  Future<void> launch({
    required BuildContext sourceContext,
    required QuickCreationMode mode,
    CalendarDate? actionDate,
  }) => switch (_operation.start(
    () => _launch(sourceContext, mode, actionDate),
  )) {
    ExclusiveOperationAccepted(:final future) => future,
    ExclusiveOperationAlreadyRunning() => Future<void>.value(),
  };

  Future<void> _launch(
    BuildContext context,
    QuickCreationMode mode,
    CalendarDate? actionDate,
  ) async {
    if (!context.mounted) return;
    final router = context.router.root;
    final source = context.routeData;
    if (router.topRoute.matchId != source.matchId ||
        router.hasPagelessTopRoute) {
      return;
    }
    switch (mode) {
      case QuickCreationMode.intention:
        await _openFirst(router, IntentionEditorRoute());
      case QuickCreationMode.action:
        final date =
            actionDate ??
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(localDateSourceProvider)().date;
        await _openFirst(
          router,
          ActionEditorRoute(launch: ActionEditorLaunch(date: date)),
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
      unawaited(router.push<void>(route).then<void>((_) => finish()));
      check();
      await openedOrStopped.future;
    } finally {
      router.removeListener(check);
    }
  }
}
