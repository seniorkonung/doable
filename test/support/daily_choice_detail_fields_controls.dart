/// Общие шаги блока полей даты, времени и приоритета дневного выбора.
///
/// Блок один на нижнюю панель и подтверждение создания, поэтому шаги находят
/// его по типу, где бы он ни стоял, и называют намерение человека: задать
/// дату, час, «Весь день» или приоритет. Листы даты и времени и их раскладка
/// остаются внутри шагов.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_detail_fields.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_field_labels.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Блок полей, показанный на экране.
Finder get dailyChoiceDetailFields => find.byType(DailyChoiceDetailFields);

/// Дата, показанная в поле «Дата». В панели это подтверждённая дата выбора.
CalendarDate shownDailyChoiceDate(WidgetTester tester) =>
    tester.widget<DailyChoiceDetailFields>(dailyChoiceDetailFields).date;

/// Задаёт выбору [date] в листе даты: шаг переходит к её месяцу и нажимает
/// день. [tap] нажимает поле «Дата»; остальное происходит внутри листа.
Future<void> setDailyChoiceDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  final semantics = tester.ensureSemantics();
  try {
    final shown = shownDailyChoiceDate(tester);
    await _openField(tester, tap, (l10n) => l10n.dailyChoiceFieldDate);
    final l10n = _l10n(tester);
    // Каталог под панелью тоже показывает месяц с такими же подписями.
    final grid = find.byType(DateGrid);
    // Лист открывается на месяце текущей даты выбора.
    final months = (date.year - shown.year) * 12 + (date.month - shown.month);
    for (var step = 0; step < months.abs(); step++) {
      await tester.tap(
        find.descendant(
          of: grid,
          matching: find.bySemanticsLabel(
            months > 0
                ? l10n.actionCalendarNextMonth
                : l10n.actionCalendarPreviousMonth,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    final fullDate = MaterialLocalizations.of(
      tester.element(dailyChoiceDetailFields),
    ).formatFullDate(DateTime.utc(date.year, date.month, date.day));
    // Подпись дня продолжают «Сегодня» и отметка дня.
    await tester.tap(
      find.descendant(
        of: grid,
        matching: find.bySemanticsLabel(RegExp('^${RegExp.escape(fullDate)}')),
      ),
    );
    await tester.pumpAndSettle();
  } finally {
    semantics.dispose();
  }
}

/// Задаёт выбору целый [hour] на циферблате листа времени, в 24- и 12-часовом
/// формате. [tap] нажимает поле «Время».
Future<void> setDailyChoiceHour(
  WidgetTester tester,
  int hour, {
  RootPageTap tap = tapWhenFound,
}) async {
  await _openField(tester, tap, (l10n) => l10n.dailyChoiceFieldTime);
  final dial = find.byType(TimeDial);
  final halves = find.descendant(
    of: dial,
    matching: find.byType(Tabs<TimeDialHalf>),
  );
  final String text;
  if (halves.evaluate().isEmpty) {
    text = '$hour'.padLeft(2, '0');
  } else {
    final material = MaterialLocalizations.of(tester.element(dial));
    await tester.tap(
      find.descendant(
        of: halves,
        matching: find.text(
          hour >= 12
              ? material.postMeridiemAbbreviation
              : material.anteMeridiemAbbreviation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    text = '${hour % 12 == 0 ? 12 : hour % 12}';
  }
  await tester.tap(find.descendant(of: dial, matching: find.text(text)));
  await tester.pumpAndSettle();
}

/// Задаёт выбору «Весь день» в центре циферблата. [tap] нажимает поле
/// «Время».
Future<void> setDailyChoiceAllDay(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) async {
  await _openField(tester, tap, (l10n) => l10n.dailyChoiceFieldTime);
  await tester.tap(
    find.descendant(
      of: find.byType(TimeDial),
      matching: find.text(_l10n(tester).dailyChoiceAllDay),
    ),
  );
  await tester.pumpAndSettle();
}

/// Задаёт выбору [priority] в поле «Приоритет». [tap] нажимает его пилюлю.
Future<void> setDailyChoicePriority(
  WidgetTester tester,
  DailyChoicePriority priority, {
  RootPageTap tap = tapWhenFound,
}) => tap(
  tester,
  find.descendant(
    of: find.descendant(
      of: dailyChoiceDetailFields,
      matching: find.byType(PriorityPicker),
    ),
    matching: find.text(
      dailyChoicePriorityName(dailyChoiceDesignPriority(priority)),
    ),
  ),
);

/// Нажимает поле с названием [name] и ждёт открытия его листа.
Future<void> _openField(
  WidgetTester tester,
  RootPageTap tap,
  String Function(AppLocalizations) name,
) async {
  await tap(
    tester,
    find.descendant(
      of: find.descendant(
        of: dailyChoiceDetailFields,
        matching: find.widgetWithText(DetailRow, name(_l10n(tester))),
      ),
      matching: find.byType(Button),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(dailyChoiceDetailFields));
