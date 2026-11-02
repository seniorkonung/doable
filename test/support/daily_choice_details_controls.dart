/// Общие действия и наблюдения подробного просмотра дневного выбора.
library;

import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Открытый подробный просмотр.
Finder get dailyChoiceDetails => find.byType(DailyChoiceDetailsPage);

/// Выбор, открытый в подробном просмотре.
DailyChoiceId shownDailyChoice(WidgetTester tester) =>
    tester.widget<DailyChoiceDetailsPage>(dailyChoiceDetails).choiceId;

/// Подробный просмотр загрузил данные и готов к действиям.
Finder get dailyChoiceDetailsReady => dailyChoiceDetailsEdit;

/// Команда открытия формы изменения выбора.
Finder get dailyChoiceDetailsEdit =>
    find.byKey(const ValueKey('daily-choice-edit-open'));

/// Команда начала удаления выбора.
Finder get dailyChoiceDetailsDelete =>
    find.byKey(const ValueKey('daily-choice-delete-open'));

/// Намерение с номером [number] в сохранённом пути.
Finder dailyChoiceDetailsIntention(int number) =>
    find.byKey(ValueKey('daily-choice-intention-$number'));

/// Связь с номером [number] в сохранённом пути.
Finder dailyChoiceDetailsRelation(int number) =>
    find.byKey(ValueKey('daily-choice-relation-$number'));

/// Закрывает подробный просмотр.
Future<void> closeDailyChoiceDetails(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(dailyChoiceDetails, findsNothing);
}

/// Открывает форму изменения выбора.
Future<void> openDailyChoiceEdit(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, dailyChoiceDetailsEdit);

/// Начинает удаление выбора.
Future<void> startDailyChoiceDeletion(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, dailyChoiceDetailsDelete);

/// Открывает намерение сохранённого пути.
Future<void> openDailyChoicePathIntention(
  WidgetTester tester,
  int number, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, dailyChoiceDetailsIntention(number));

/// Открывает связь сохранённого пути.
Future<void> openDailyChoicePathRelation(
  WidgetTester tester,
  int number, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, dailyChoiceDetailsRelation(number));
