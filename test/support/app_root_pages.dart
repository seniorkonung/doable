/// Общие шаги входа в корневые страницы приложения и возврата на них.
///
/// Это единственное место в `test/`, которое знает способ входа в каталог
/// намерений и каталог дневных выборов и вид нижнего маршрута под открытыми
/// страницами. Сценарий называет только намерение — «открыть граф намерений»,
/// «открыть дневные выборы», «вернулись на корневую страницу» — и не зависит
/// от того, как приложение размещает корневые страницы.
///
/// Корневые страницы — вкладки оболочки с нижней панелью: приложение
/// открывается на Главной, каталоги открываются выбором пункта панели, а
/// нижний маршрут под открытыми страницами — оболочка с выбранным пунктом.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Способ сценария дождаться появления элемента.
///
/// Сценарии продвигают время по-разному — кадрами, реальным ожиданием
/// хранилища или управляемыми завершениями, — поэтому шаг принимает ожидание
/// сценария, а не навязывает своё.
typedef RootPageWait = Future<void> Function(
  WidgetTester tester,
  Finder finder,
);

/// Способ сценария нажать элемент, дождавшись его появления.
typedef RootPageTap = Future<void> Function(WidgetTester tester, Finder finder);

/// Пункт панели основной навигации.
Finder _destination(AppDestination destination) => find.descendant(
  of: find.byType(AppNavigationBar),
  matching: find.byIcon(destination.icon),
);

/// Ожидание по умолчанию: кадры без реального времени.
///
/// Уже показанный элемент не вызывает ни одного кадра, поэтому шаг не меняет
/// ход сценария, который сам довёл приложение до нужного экрана.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Ожидаемый элемент не появился: $finder');
}

/// Нажатие по умолчанию: дождаться элемента, довести до видимости и нажать.
Future<void> tapWhenFound(WidgetTester tester, Finder finder) async {
  await pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Открывает граф намерений — каталог намерений как корневую страницу.
///
/// Шаг выбирает пункт панели и завершается, когда каталог намерений показан.
/// Каталог строится при первом выборе пункта и получает выдачу уже после
/// входа, поэтому сценарий, которому сразу нужна строка выдачи, называет её
/// в [content]: шаг дожидается и её. [waitFor] — ожидание сценария; по
/// умолчанию [pumpUntilFound].
Future<void> openIntentionGraph(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
  Finder? content,
}) async {
  final entry = _destination(AppDestination.intentionGraph);
  await waitFor(tester, entry);
  await tester.tap(entry);
  await tester.pump();
  await waitFor(tester, find.byType(IntentionCatalogPage));
  if (content != null) await waitFor(tester, content);
}

/// Открывает дневные выборы — каталог дневных выборов как корневую страницу.
///
/// Шаг нажимает вход и не ждёт содержимого каталога: его дожидается сам
/// сценарий. [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> openDailyChoices(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, _destination(AppDestination.dailyChoices));

/// Открывает дневные выборы переходом маршрутизатора, без нажатия.
///
/// Для страничных проверок, которые показывают каталог дневных выборов до
/// первого кадра и поэтому не могут нажать вход: переход начинается сразу, а
/// кадры продвигает сам сценарий.
void openDailyChoicesOn(StackRouter router) {
  unawaited(
    router.navigate(const AppShellRoute(children: [DailyChoiceCatalogRoute()])),
  );
}

/// Проверяет, что все страницы поверх закрыты и открыт граф намерений.
void expectIntentionGraphRootPage(StackRouter router) {
  _expectRootPage(router, IntentionCatalogRoute.name);
}

/// Проверяет, что все страницы поверх закрыты и открыты дневные выборы.
void expectDailyChoicesRootPage(StackRouter router) {
  _expectRootPage(router, DailyChoiceCatalogRoute.name);
}

/// Нижний маршрут — оболочка, а её выбранный пункт показывает [rootPage].
void _expectRootPage(StackRouter router, String rootPage) {
  expect(router.current.name, AppShellRoute.name);
  expect(router.topRoute.name, rootPage);
}
