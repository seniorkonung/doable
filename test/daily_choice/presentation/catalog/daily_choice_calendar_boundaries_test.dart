import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

// Проверки не зависят от часового пояса процесса. Отсутствие дат в местном
// времени в календарном компоненте при любом часовом поясе мгновенно проверяет
// daily_choice_calendar_utc_dates_test.dart по исходникам. Недели перехода на
// летнее время ниже взяты по правилам America/New_York: при запуске в этом
// поясе они показывают сдвиг дат на реальной сетке. Календарь считает периоды в
// UTC, поэтому зимний переход идёт тем же путём и отдельной проверки не требует.
void main() {
  group('календарные периоды', () {
    testWidgets(
      'февраль невисокосного 2027 года занимает шесть недель без 29-го числа',
      (tester) async {
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2027, 2, 14)),
          today: date(2026, 10, 4),
        );

        expect(visibleWeeks(tester), weeksFrom(date(2027, 2, 1), 6));
        expect(visibleWeeks(tester)[3], [
          date(2027, 2, 22),
          date(2027, 2, 23),
          date(2027, 2, 24),
          date(2027, 2, 25),
          date(2027, 2, 26),
          date(2027, 2, 27),
          date(2027, 2, 28),
        ]);
      },
    );

    testWidgets('1900 год показан невисокосным, а 2000 год — високосным', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(1900, 2, 1)),
        today: date(2026, 10, 4),
      );

      expect(visibleWeeks(tester), weeksFrom(date(1900, 1, 29), 6));
      expect(visibleWeeks(tester)[4], [
        date(1900, 2, 26),
        date(1900, 2, 27),
        date(1900, 2, 28),
        date(1900, 3, 1),
        date(1900, 3, 2),
        date(1900, 3, 3),
        date(1900, 3, 4),
      ]);

      consumer.replaceInputs(viewport: month(date(2000, 2, 1)));
      await tester.pumpAndSettle();

      expect(visibleWeeks(tester), weeksFrom(date(2000, 1, 31), 6));
      expect(visibleWeeks(tester)[4], [
        date(2000, 2, 28),
        date(2000, 2, 29),
        date(2000, 3, 1),
        date(2000, 3, 2),
        date(2000, 3, 3),
        date(2000, 3, 4),
        date(2000, 3, 5),
      ]);
      expect(consumer.events, isEmpty);
    });
  });

  group('смена летнего времени', () {
    for (final (
          :transition,
          :transitionDay,
          :weekStart,
          :nextFocus,
          :nextWeekStart,
          :monthStart,
        )
        in [
          (
            transition: 'летнее',
            transitionDay: date(2026, 3, 8),
            weekStart: date(2026, 3, 2),
            nextFocus: date(2026, 3, 15),
            nextWeekStart: date(2026, 3, 9),
            monthStart: date(2026, 2, 23),
          ),
        ]) {
      testWidgets(
        'неделя перехода на $transition время сохраняет даты при выборе и перелистывании',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(transitionDay),
            today: date(2026, 10, 4),
          );
          expect(visibleWeeks(tester), weeksFrom(weekStart, 1));

          await tester.tap(calendarDay(transitionDay));
          await tester.pumpAndSettle();
          await swipeToNextPeriod(tester);
          expect(visibleWeeks(tester), weeksFrom(nextWeekStart, 1));

          await swipeToPreviousPeriod(tester);

          expect(consumer.events, [
            DateSelected(transitionDay),
            ViewportChanged(week(nextFocus)),
            ViewportChanged(week(transitionDay)),
          ]);
          expect(consumer.selectedDate, transitionDay);
          expect(visibleWeeks(tester), weeksFrom(weekStart, 1));
        },
      );

      // Недели с понедельника по обе стороны перехода: при расчёте периода по
      // местному времени полночь понедельника летнего времени отстояла бы от
      // начала диапазона на час меньше целых суток, и календарь показал бы
      // предыдущую неделю.
      for (final monday in [weekStart, nextWeekStart]) {
        testWidgets(
          'неделя с понедельника ${monday.toCanonicalString()} у перехода на $transition время показывает и выбирает свои дни',
          (tester) async {
            final consumer = await pumpCalendarConsumer(
              tester,
              selectedDate: date(2026, 10, 4),
              viewport: week(monday),
              today: date(2026, 10, 4),
            );
            expect(visibleWeeks(tester), weeksFrom(monday, 1));

            await tester.tap(calendarDay(monday));
            await tester.pumpAndSettle();

            expect(consumer.events, [DateSelected(monday)]);
            expect(consumer.selectedDate, monday);
            expect(consumer.viewport, week(monday));
            expect(visibleWeeks(tester), weeksFrom(monday, 1));
          },
        );
      }

      testWidgets(
        'месяц перехода на $transition время показывает и выбирает день перехода',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: month(transitionDay),
            today: date(2026, 10, 4),
          );
          expect(visibleWeeks(tester), weeksFrom(monthStart, 6));

          await tester.tap(calendarDay(transitionDay));
          await tester.pumpAndSettle();

          expect(consumer.events, [DateSelected(transitionDay)]);
          expect(consumer.viewport, month(transitionDay));
          expect(visibleWeeks(tester), weeksFrom(monthStart, 6));
          expect(dayCell(tester, transitionDay).isSelected, isTrue);
        },
      );
    }
  });

  group('пределы диапазона CalendarDate', () {
    testWidgets('первая неделя начинается с 0001-01-01', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(1, 1, 1)),
        today: date(2026, 10, 4),
      );

      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 1));

      await tester.tap(calendarDay(date(1, 1, 1)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(1, 1, 1))]);
      expect(consumer.viewport, week(date(1, 1, 1)));
      expect(dayCell(tester, date(1, 1, 1)).isSelected, isTrue);
    });

    testWidgets(
      'последняя неделя сохраняет семь позиций и выбирает 9999-12-31',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(9999, 12, 31)),
          today: date(2026, 10, 4),
        );

        expect(visibleWeeks(tester), [_lastWeekPositions]);

        await tester.tap(calendarDay(date(9999, 12, 31)));
        await tester.pumpAndSettle();

        expect(consumer.events, [DateSelected(date(9999, 12, 31))]);
        expect(consumer.viewport, week(date(9999, 12, 31)));
        expect(visibleWeeks(tester), [_lastWeekPositions]);
        expect(dayCell(tester, date(9999, 12, 31)).isSelected, isTrue);
      },
    );

    for (final mode in DailyChoiceCalendarMode.values) {
      testWidgets(
        'позиции за пределом диапазона не выбираются (${mode.name})',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(9999, 12, 31),
            viewport: DailyChoiceCalendarViewport(
              focusedDate: date(9999, 12, 31),
              mode: mode,
            ),
            today: date(2026, 10, 4),
          );
          expect(
            unavailableCalendarDays,
            findsNWidgets(mode == DailyChoiceCalendarMode.week ? 2 : 9),
          );

          for (final position in unavailableCalendarDays.evaluate().toList()) {
            await tester.tapAt(
              (position.renderObject! as RenderBox).localToGlobal(
                const Offset(1, 1),
              ),
            );
            await tester.pumpAndSettle();
          }

          expect(consumer.events, isEmpty);
          expect(consumer.selectedDate, date(9999, 12, 31));
          expect(dayCell(tester, date(9999, 12, 31)).isSelected, isTrue);
        },
      );
    }

    testWidgets(
      'первая неделя не перелистывается назад и возвращается вперёд',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(1, 1, 1)),
          today: date(2026, 10, 4),
        );

        await swipeToPreviousPeriod(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 1));

        await swipeToNextPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 8), 1));
        await swipeToPreviousPeriod(tester);

        expect(consumer.events, [
          ViewportChanged(week(date(1, 1, 8))),
          ViewportChanged(week(date(1, 1, 1))),
        ]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 1));
      },
    );

    testWidgets(
      'последняя неделя не перелистывается вперёд и возвращается назад',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(9999, 12, 31)),
          today: date(2026, 10, 4),
        );

        await swipeToNextPeriod(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), [_lastWeekPositions]);

        await swipeToPreviousPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(9999, 12, 20), 1));
        await swipeToNextPeriod(tester);

        expect(consumer.events, [
          ViewportChanged(week(date(9999, 12, 24))),
          ViewportChanged(week(date(9999, 12, 31))),
        ]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(visibleWeeks(tester), [_lastWeekPositions]);
      },
    );

    testWidgets('первый месяц не перелистывается назад и возвращается вперёд', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(1, 1, 15),
        viewport: month(date(1, 1, 15)),
        today: date(2026, 10, 4),
      );

      await swipeToPreviousPeriod(tester);
      expect(consumer.events, isEmpty);
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 6));

      await swipeToNextPeriod(tester);
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 29), 6));
      await swipeToPreviousPeriod(tester);

      expect(consumer.events, [
        ViewportChanged(month(date(1, 2, 1))),
        ViewportChanged(month(date(1, 1, 15))),
      ]);
      expect(consumer.selectedDate, date(1, 1, 15));
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 6));

      await tester.tap(find.bySemanticsLabel('Свернуть календарь'));
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 15), 1));
      expect(dayCell(tester, date(1, 1, 15)).isSelected, isTrue);
    });

    testWidgets(
      'последний месяц не перелистывается вперёд и возвращается назад',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(9999, 12, 31),
          viewport: month(date(9999, 12, 31)),
          today: date(2026, 10, 4),
        );
        final lastMonth = [
          ...weeksFrom(date(9999, 11, 29), 4),
          _lastWeekPositions,
          List<CalendarDate?>.filled(7, null),
        ];

        await swipeToNextPeriod(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), lastMonth);

        await swipeToPreviousPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(9999, 11, 1), 6));
        await swipeToNextPeriod(tester);

        expect(consumer.events, [
          ViewportChanged(month(date(9999, 11, 1))),
          ViewportChanged(month(date(9999, 12, 31))),
        ]);
        expect(consumer.selectedDate, date(9999, 12, 31));
        expect(visibleWeeks(tester), lastMonth);

        await tester.tap(find.bySemanticsLabel('Свернуть календарь'));
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), [_lastWeekPositions]);
        expect(dayCell(tester, date(9999, 12, 31)).isSelected, isTrue);
      },
    );
  });
}

/// Последняя неделя диапазона: пять допустимых дней и две позиции за
/// пределом 9999-12-31.
final List<CalendarDate?> _lastWeekPositions = [
  date(9999, 12, 27),
  date(9999, 12, 28),
  date(9999, 12, 29),
  date(9999, 12, 30),
  date(9999, 12, 31),
  null,
  null,
];
