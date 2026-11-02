/// Общие действия и наблюдения подробного просмотра дневного выбора.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_sheet.dart';
import 'package:doable/src/design_system/components/choice_head.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Открытый подробный просмотр. Панель, перекрытая страницей, не считается.
Finder get dailyChoiceDetails => find.byType(DailyChoiceSheet);

/// Выбор, открытый в подробном просмотре.
DailyChoiceId shownDailyChoice(WidgetTester tester) =>
    tester.widget<DailyChoiceSheet>(dailyChoiceDetails).choiceId;

/// Подробный просмотр загрузил данные и готов к действиям.
Finder get dailyChoiceDetailsReady =>
    find.descendant(of: dailyChoiceDetails, matching: find.byType(ChoiceHead));

/// Шапка подробного просмотра с выполнением и приоритетом выбора.
ChoiceHead shownDailyChoiceHead(WidgetTester tester) =>
    tester.widget<ChoiceHead>(dailyChoiceDetailsReady);

/// Значение [value] поля на вкладке «Обзор».
Finder dailyChoiceDetailsField(String value) =>
    find.descendant(of: dailyChoiceDetails, matching: find.text(value));

/// Кнопка параметров подробного просмотра.
Finder get dailyChoiceDetailsOptions => find.descendant(
  of: dailyChoiceDetailsReady,
  matching: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.more,
    description: 'три точки шапки выбора',
  ),
);

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
}) => _chooseOption(tester, tap, (l10n) => l10n.dailyChoiceEditTitle);

/// Начинает удаление выбора.
Future<void> startDailyChoiceDeletion(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => _chooseOption(tester, tap, (l10n) => l10n.dailyChoiceSheetOptionDelete);

/// Показывает вкладку сохранённого пути.
Future<void> showDailyChoicePath(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, dailyChoiceDetailsReady);
  // Панель могла ещё въезжать, и нажатие пришлось бы мимо вкладки.
  await tester.pumpAndSettle();
  await tap(
    tester,
    find.descendant(
      of: dailyChoiceDetails,
      matching: find.text(_l10n(tester).dailyChoiceSheetPathTab),
    ),
  );
  await tester.pumpAndSettle();
}

/// Открывает намерение сохранённого пути.
Future<void> openDailyChoicePathIntention(
  WidgetTester tester,
  int number, {
  RootPageTap tap = tapWhenFound,
}) async {
  await showDailyChoicePath(tester, tap: tap);
  await tap(tester, dailyChoiceDetailsIntention(number));
}

/// Открывает связь сохранённого пути.
Future<void> openDailyChoicePathRelation(
  WidgetTester tester,
  int number, {
  RootPageTap tap = tapWhenFound,
}) async {
  await showDailyChoicePath(tester, tap: tap);
  await tap(tester, dailyChoiceDetailsRelation(number));
}

/// Выбирает пункт меню параметров. Действие пункта начинается после закрытия
/// меню, поэтому результат дожидается сам сценарий.
Future<void> _chooseOption(
  WidgetTester tester,
  RootPageTap tap,
  String Function(AppLocalizations) name,
) async {
  await tap(tester, dailyChoiceDetailsOptions);
  await tester.pumpAndSettle();
  await tap(tester, find.text(name(_l10n(tester))));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(dailyChoiceDetails));
