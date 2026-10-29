/// Общие шаги вкладки «Выборы» открытой страницы намерения.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// «Добавить» над списком выбранной роли вкладки «Выборы».
final intentionChoicesAdd = find.byKey(const ValueKey('intention-choices-add'));

/// Выбирает вкладку «Выборы» по её названию на языке приложения.
///
/// [waitFor] и [tap] — ожидание и нажатие сценария; по умолчанию
/// [pumpUntilFound] и [tapWhenFound].
Future<void> openIntentionChoicesTab(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
  RootPageTap tap = tapWhenFound,
}) async {
  final tabs = find.byType(Tabs<IntentionDetailsTab>);
  await waitFor(tester, tabs);
  final label = AppLocalizations.of(tester.element(tabs)).detailsChoicesTab;
  await tap(tester, find.descendant(of: tabs, matching: find.text(label)));
  // Страница намерения могла ещё въезжать переходом маршрута: до его конца
  // строки вкладки вне экрана.
  await tester.pumpAndSettle();
}

/// Начинает дневной выбор от открытого намерения: выбирает вкладку
/// «Выборы» и нажимает «Добавить» у роли «исходное», выбранной по умолчанию.
Future<void> startDailyChoiceFromIntentionChoices(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
  RootPageTap tap = tapWhenFound,
}) async {
  await openIntentionChoicesTab(tester, waitFor: waitFor, tap: tap);
  await tap(tester, intentionChoicesAdd);
}
