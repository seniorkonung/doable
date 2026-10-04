import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final language = locale.languageCode;

    testWidgets(
      'недельное представление показывает неделю даты просмотра с понедельника ($language)',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: locale,
        );

        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
        expect(dayCell(tester, date(2026, 9, 30)).isOutsideMonth, isFalse);
        expect(consumer.events, isEmpty);
      },
    );

    testWidgets(
      'месячное представление показывает все дни месяца даты просмотра с понедельника ($language)',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 11, 15)),
          today: date(2026, 10, 4),
          locale: locale,
        );

        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        expect(dayCell(tester, date(2026, 10, 26)).isOutsideMonth, isTrue);
        expect(dayCell(tester, date(2026, 11, 1)).isOutsideMonth, isFalse);
        expect(dayCell(tester, date(2026, 11, 30)).isOutsideMonth, isFalse);
        expect(dayCell(tester, date(2026, 12, 6)).isOutsideMonth, isTrue);
        expect(consumer.events, isEmpty);
      },
    );
  }

  testWidgets('выбранный и сегодняшний дни отмечены по входам потребителя', (
    tester,
  ) async {
    await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 1),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    expect(dayCell(tester, date(2026, 10, 1)).isSelected, isTrue);
    expect(dayCell(tester, date(2026, 10, 1)).isToday, isFalse);
    expect(dayCell(tester, date(2026, 10, 4)).isSelected, isFalse);
    expect(dayCell(tester, date(2026, 10, 4)).isToday, isTrue);
  });

  testWidgets('выбранный сегодняшний день сохраняет оба признака', (
    tester,
  ) async {
    await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    expect(dayCell(tester, date(2026, 10, 4)).isSelected, isTrue);
    expect(dayCell(tester, date(2026, 10, 4)).isToday, isTrue);
  });

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
      expect(dayCell(tester, date(2026, 11, 1)).isOutsideMonth, isTrue);

      await tester.tap(calendarDay(date(2026, 11, 1)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2026, 11, 1))]);
      expect(consumer.viewport, month(date(2026, 11, 1)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(dayCell(tester, date(2026, 11, 1)).isSelected, isTrue);
      expect(dayCell(tester, date(2026, 11, 1)).isOutsideMonth, isFalse);
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

  testWidgets('перелистывание недели сообщает только изменение просмотра', (
    tester,
  ) async {
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    await swipeToNextPeriod(tester);

    expect(consumer.events, [ViewportChanged(week(date(2026, 10, 11)))]);
    expect(consumer.selectedDate, date(2026, 10, 4));
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
  });
}
