/// Общие шаги подтверждения создания дневного выбора.
///
/// Сценарий называет намерение человека: дождаться готового подтверждения,
/// задать дату или приоритет, прочитать показанные значения. Подтверждение
/// показывает общий блок полей, поэтому шаги идут через шаги этого блока.
library;

import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_detail_fields.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';
import 'daily_choice_detail_fields_controls.dart';

/// Дожидается готового подтверждения создания.
///
/// Подтверждение готово, когда его поля показаны и страница завершила
/// переход: пока страница въезжает, нажатие по её полям не попадает в них.
/// [waitFor] — ожидание сценария; по умолчанию [pumpUntilFound].
Future<void> awaitDailyChoiceConfirmation(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
}) async {
  await waitFor(tester, dailyChoiceDetailFields);
  await tester.pumpAndSettle();
}

/// Задаёт создаваемому выбору [date]. Подтверждение уже готово. [tap]
/// нажимает поле «Дата».
Future<void> setDailyChoiceCreationDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) => setDailyChoiceDate(tester, date, tap: tap);

/// Задаёт создаваемому выбору [priority]. Подтверждение уже готово. [tap]
/// нажимает выбранный вариант.
Future<void> setDailyChoiceCreationPriority(
  WidgetTester tester,
  DailyChoicePriority priority, {
  RootPageTap tap = tapWhenFound,
}) => setDailyChoicePriority(tester, priority, tap: tap);

/// Дата и приоритет, которые подтверждение показывает сейчас.
({CalendarDate date, DailyChoicePriority priority}) shownDailyChoiceCreation(
  WidgetTester tester,
) {
  final fields = tester.widget<DailyChoiceDetailFields>(
    dailyChoiceDetailFields,
  );
  return (date: fields.date, priority: fields.priority);
}
