import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

void main() {
  // Начало недели не зависит от языка. Остальные проверки файла идут на
  // русском, поэтому периоды отдельно проверяются на английском, где неделя
  // по умолчанию начиналась бы не с понедельника.
  const locale = Locale('en');

  testWidgets(
    'недельное представление показывает неделю даты просмотра с понедельника',
    (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2026, 10, 4)),
        today: date(2026, 10, 4),
        locale: locale,
      );

      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
      expect(consumer.events, isEmpty);
    },
  );

  testWidgets(
    'месячное представление показывает все дни месяца даты просмотра с понедельника',
    (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 11, 15)),
        today: date(2026, 10, 4),
        locale: locale,
      );

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(consumer.events, isEmpty);
    },
  );

  testWidgets('нажатие дня передаёт одно событие выбора с датой этой ячейки', (
    tester,
  ) async {
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    await tester.tap(calendarDay(date(2026, 10, 1)));
    await tester.pumpAndSettle();

    expect(consumer.events, [DateSelected(date(2026, 10, 1))]);
    expect(consumer.selectedDate, date(2026, 10, 1));
    expect(consumer.viewport, week(date(2026, 10, 1)));
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
    expect(dayCell(tester, date(2026, 10, 1)).isSelected, isTrue);
    expect(dayCell(tester, date(2026, 10, 4)).isSelected, isFalse);
  });

  testWidgets(
    'выбор дня соседнего месяца в раскрытом календаре показывает его месяц',
    (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 10, 4)),
        today: date(2026, 10, 4),
      );
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));

      await tester.tap(calendarDay(date(2026, 11, 1)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2026, 11, 1))]);
      expect(consumer.viewport, month(date(2026, 11, 1)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(dayCell(tester, date(2026, 11, 1)).isSelected, isTrue);
    },
  );

  testWidgets(
    'выбор дня после раскрытия сохраняет месячное представление до сворачивания',
    (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2026, 10, 4)),
        today: date(2026, 10, 4),
      );

      await tester.tap(find.byTooltip('Развернуть календарь'));
      await tester.pumpAndSettle();
      await tester.tap(calendarDay(date(2026, 10, 15)));
      await tester.pumpAndSettle();

      expect(consumer.events, [
        ViewportChanged(month(date(2026, 10, 4))),
        DateSelected(date(2026, 10, 15)),
      ]);
      expect(consumer.viewport, month(date(2026, 10, 15)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
      expect(dayCell(tester, date(2026, 10, 15)).isSelected, isTrue);
      expect(find.byTooltip('Свернуть календарь'), findsOneWidget);

      await tester.tap(find.byTooltip('Свернуть календарь'));
      await tester.pumpAndSettle();

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
      expect(consumer.events.last, ViewportChanged(week(date(2026, 10, 15))));
      expect(consumer.selectedDate, date(2026, 10, 15));
    },
  );

  testWidgets('повторное нажатие выбранного дня снова передаёт одно событие', (
    tester,
  ) async {
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    await tester.tap(calendarDay(date(2026, 10, 4)));
    await tester.pumpAndSettle();
    expect(consumer.events, [DateSelected(date(2026, 10, 4))]);

    await tester.tap(calendarDay(date(2026, 10, 4)));
    await tester.pumpAndSettle();
    expect(consumer.events, [
      DateSelected(date(2026, 10, 4)),
      DateSelected(date(2026, 10, 4)),
    ]);
    expect(consumer.viewport, week(date(2026, 10, 4)));
  });

  testWidgets('внешние изменения входов перестраивают календарь без событий', (
    tester,
  ) async {
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    consumer.replaceInputs(
      selectedDate: date(2027, 2, 14),
      viewport: month(date(2027, 2, 10)),
      today: date(2027, 2, 1),
    );
    await tester.pumpAndSettle();

    expect(visibleWeeks(tester), weeksFrom(date(2027, 2, 1), 4));
    expect(dayCell(tester, date(2027, 2, 14)).isSelected, isTrue);
    expect(dayCell(tester, date(2027, 2, 1)).isToday, isTrue);
    expect(dayCell(tester, date(2027, 2, 1)).isSelected, isFalse);

    consumer.replaceInputs(viewport: week(date(2026, 10, 4)));
    await tester.pumpAndSettle();

    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
    expect(dayCell(tester, date(2026, 10, 4)).isSelected, isFalse);
    expect(dayCell(tester, date(2026, 10, 4)).isToday, isFalse);
    expect(consumer.selectedDate, date(2027, 2, 14));
    expect(consumer.events, isEmpty);
  });
}
