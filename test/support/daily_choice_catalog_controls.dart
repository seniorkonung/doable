/// Общие шаги управления каталогом дневных выборов в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать день каталога» — и
/// не знает, каким элементом страница позволяет выбрать дату. Шаг действует
/// через интерфейс каталога и не обращается к его модели.
library;

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Выбирает [date] днём открытого каталога дневных выборов.
///
/// Шаг выполняет выбор и не ждёт выдачи этого дня: её дожидается сам
/// сценарий. [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> selectDailyChoiceCatalogDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  final field = find.byKey(const ValueKey('daily-choice-date-filter'));
  await tap(tester, field);
  await tester.enterText(field, date.toCanonicalString());
  await tap(tester, find.byKey(const ValueKey('daily-choice-apply-date')));
}
