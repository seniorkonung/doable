/// Общие шаги управления каталогом дневных выборов в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать день каталога»,
/// «какой день каталог показывает выбранным», «где выбирается день» — и не
/// знает, каким элементом страница позволяет выбрать дату. Шаги действуют и
/// наблюдают через интерфейс каталога и не обращаются к его модели.
///
/// Каталог выбирает день встроенным календарём: шаги, как человек,
/// перелистывают его командами шапки и нажимают день. Смена способа выбора
/// дня меняет только этот файл, а не сценарии.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Элемент открытого каталога дневных выборов, которым человек выбирает день.
///
/// Для проверок его размещения на странице: видимости, доступности нажатия и
/// соседства с другими элементами.
final dailyChoiceCatalogDateControl = find.byType(DailyChoiceCalendar);

/// День [date] в календаре открытого каталога дневных выборов.
///
/// Находится, только пока календарь показывает период с этим днём.
Finder dailyChoiceCatalogDay(CalendarDate date) => find.byKey(
  ValueKey('daily-choice-calendar-day-${date.toCanonicalString()}'),
);

/// Выбирает [date] днём открытого каталога дневных выборов.
///
/// Если день не виден, шаг перелистывает календарь к нему командами шапки:
/// далёкий день он находит по месяцам в раскрытом календаре, а свёрнутый
/// календарь сворачивает обратно до нажатия дня. Поэтому представление
/// календаря шаг не меняет, а последним действием остаётся нажатие дня.
///
/// Шаг выполняет выбор и не ждёт выдачи этого дня: её дожидается сам
/// сценарий. [tap] — нажатие сценария для команд календаря; по умолчанию
/// [tapWhenFound].
Future<void> selectDailyChoiceCatalogDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, dailyChoiceCatalogDateControl);
  final day = dailyChoiceCatalogDay(date);
  if (day.evaluate().isEmpty) {
    final texts = AppLocalizations.of(
      tester.element(dailyChoiceCatalogDateControl),
    );
    final expand = find.byTooltip(texts.dailyChoiceCalendarExpand);
    final collapsed = expand.evaluate().isNotEmpty;
    if (collapsed) {
      await _runCommand(tester, tap, expand);
    }
    await _turnUntilShown(
      tester,
      date,
      tap,
      previous: texts.dailyChoiceCalendarPreviousMonth,
      next: texts.dailyChoiceCalendarNextMonth,
    );
    if (collapsed) {
      await _runCommand(
        tester,
        tap,
        find.byTooltip(texts.dailyChoiceCalendarCollapse),
      );
      await _turnUntilShown(
        tester,
        date,
        tap,
        previous: texts.dailyChoiceCalendarPreviousWeek,
        next: texts.dailyChoiceCalendarNextWeek,
      );
    }
  }
  // Нажатие сценария доводит до видимости сам элемент через все объемлющие
  // прокрутки, и прокрутка к дню перелистнула бы заодно страницы календаря.
  // Поэтому к дню прокручивается только страница каталога.
  await Scrollable.of(tester.element(dailyChoiceCatalogDateControl)).position
      .ensureVisible(day.evaluate().single.renderObject!);
  await tester.pump();
  await tester.tap(day);
  await tester.pump();
}

/// День, который открытый каталог дневных выборов показывает выбранным.
///
/// Календарь называет выбранный день полной датой и тогда, когда просматривает
/// другой период. Календарь прокручивается вместе с выдачей, поэтому шаг
/// читает его и за краем видимой части страницы. Каталог, который не называет
/// выбранный день, проваливает проверку.
CalendarDate shownDailyChoiceCatalogDate(WidgetTester tester) {
  final calendar = find.byType(DailyChoiceCalendar, skipOffstage: false);
  final selected = tester.widget<DailyChoiceCalendar>(calendar).selectedDate;
  final context = tester.element(calendar);
  final label = AppLocalizations.of(context).dailyChoiceCalendarSelectedDate(
    MaterialLocalizations.of(
      context,
    ).formatFullDate(DateTime.utc(selected.year, selected.month, selected.day)),
  );
  final shown = find.descendant(
    of: calendar,
    matching: find.text(label, skipOffstage: false),
  );
  if (shown.evaluate().isEmpty) {
    fail('Каталог дневных выборов не называет выбранный день $selected.');
  }
  return selected;
}

/// Наибольшее число перелистываний к одному дню: далёкий день календарь
/// находит по месяцам.
const _maxTurns = 240;

/// Перелистывает календарь командами [previous] и [next] текущего
/// представления, пока он не покажет [date].
Future<void> _turnUntilShown(
  WidgetTester tester,
  CalendarDate date,
  RootPageTap tap, {
  required String previous,
  required String next,
}) async {
  for (var turn = 0; turn < _maxTurns; turn++) {
    final shown = [
      for (final element in find.byType(DailyChoiceCalendarDay).evaluate())
        (element.widget as DailyChoiceCalendarDay).date,
    ];
    if (shown.contains(date)) return;
    final isEarlier = shown.every((day) => _isBefore(date, day));
    await _runCommand(tester, tap, find.byTooltip(isEarlier ? previous : next));
  }
  fail('Календарь каталога не показал день $date.');
}

/// Выполняет команду шапки календаря и доводит смену периода до конца.
///
/// Индикатор загрузки выдачи может не дать дождаться покоя всех анимаций,
/// поэтому шаг продвигает время сам: перелистывание короче секунды.
Future<void> _runCommand(
  WidgetTester tester,
  RootPageTap tap,
  Finder command,
) async {
  await tap(tester, command);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Каноническая запись даты имеет постоянную ширину, поэтому её порядок —
/// календарный.
bool _isBefore(CalendarDate a, CalendarDate b) =>
    a.toCanonicalString().compareTo(b.toCanonicalString()) < 0;
