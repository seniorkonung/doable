import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ожидание страницы с учётом управляемых кадров и хранилища сценария.
typedef QuickCreationWait = Future<void> Function(
  WidgetTester tester,
  Finder finder,
);

/// Общая кнопка создания на текущей обычной странице.
Finder quickCreationAction() => find.byType(QuickCreationButton);

/// Выбирает режим через меню, проверяет отсутствие запуска от выбора
/// и отдельно активирует кнопку. Способ активации и ожидание результата
/// могут принадлежать сценарию доступности или управляемой отправки.
Future<void> openQuickCreation(
  WidgetTester tester,
  QuickCreationMode mode, {
  required Finder openedPage,
  Future<void> Function(WidgetTester tester, Finder button)? activate,
  QuickCreationWait? wait,
}) async {
  final button = quickCreationAction();
  expect(button.hitTestable(), findsOneWidget);
  final context = tester.element(button);
  final localizations = AppLocalizations.of(context);
  final router = AutoRouter.of(context).root;
  final history = [for (final route in router.stackData) route.matchId];
  final top = router.topRoute.matchId;
  final hadPagelessTopRoute = router.hasPagelessTopRoute;

  await tester.longPress(button);
  await tester.pumpAndSettle();
  final option = find.widgetWithText(ListTile, mode.title(localizations));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  expect(option.hitTestable(), findsOneWidget);
  await tester.tap(option);
  await tester.pumpAndSettle();

  expect(option, findsNothing);
  expect(
    [for (final route in router.stackData) route.matchId],
    history,
    reason: 'Выбор режима не запускает создание и сохраняет историю',
  );
  expect(router.topRoute.matchId, top);
  expect(router.hasPagelessTopRoute, hadPagelessTopRoute);
  expect(button.hitTestable(), findsOneWidget);
  expect(tester.widget<QuickCreationButton>(button).mode, mode);

  if (activate == null) {
    await tester.tap(button);
  } else {
    await activate(tester, button);
  }
  await tester.pump();
  if (wait != null) await wait(tester, openedPage);
  await tester.pumpAndSettle();
  expect(openedPage, findsOneWidget);
}
