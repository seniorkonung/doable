/// Общие шаги входа в корневые страницы приложения и возврата на них.
///
/// Это единственное место в `test/`, которое знает способ входа в каталог
/// намерений и каталог дневных выборов и вид нижнего маршрута под открытыми
/// страницами. Сценарий называет только намерение — «открыть граф намерений»,
/// «открыть дневные выборы», «вернулись на корневую страницу» — и не зависит
/// от того, как приложение размещает корневые страницы.
///
/// Сейчас каталог намерений — начальный маршрут: он уже открыт после запуска,
/// дневные выборы открываются переходом из его шапки, а нижний маршрут — сам
/// каталог.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter/widgets.dart';
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

/// Переход к каталогу дневных выборов в шапке каталога намерений.
final Finder _dailyChoicesEntry = find.byKey(
  const ValueKey('catalog-open-daily-choices'),
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
/// Шаг завершается, когда каталог намерений показан. [waitFor] — ожидание
/// сценария; по умолчанию [pumpUntilFound].
Future<void> openIntentionGraph(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
}) => waitFor(tester, find.byType(IntentionCatalogPage));

/// Открывает дневные выборы — каталог дневных выборов как корневую страницу.
///
/// Шаг нажимает вход и не ждёт содержимого каталога: его дожидается сам
/// сценарий. [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> openDailyChoices(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, _dailyChoicesEntry);

/// Открывает дневные выборы переходом маршрутизатора, без нажатия.
///
/// Для страничных проверок, которые показывают каталог дневных выборов до
/// первого кадра и поэтому не могут нажать вход: переход начинается сразу, а
/// кадры продвигает сам сценарий.
void openDailyChoicesOn(StackRouter router) {
  unawaited(router.push(const DailyChoiceCatalogRoute()));
}

/// Проверяет, что все страницы поверх закрыты и открыт граф намерений.
void expectIntentionGraphRootPage(StackRouter router) {
  expect(router.current.name, IntentionCatalogRoute.name);
}

/// Проверяет, что все страницы поверх закрыты и открыты дневные выборы.
void expectDailyChoicesRootPage(StackRouter router) {
  expect(router.current.name, DailyChoiceCatalogRoute.name);
}
