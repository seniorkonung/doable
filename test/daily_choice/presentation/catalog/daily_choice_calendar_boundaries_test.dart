import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

// Проверки не зависят от часового пояса процесса. Их следует повторять при
// TZ=UTC и TZ=America/New_York: недели перехода на летнее и зимнее время ниже
// взяты по правилам America/New_York.
void main() {
  group('календарные периоды', () {
    testWidgets('неделя на границе года показывает дни обоих лет по порядку', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2027, 1, 1)),
        today: date(2026, 10, 4),
      );

      expect(visibleWeeks(tester), [
        [
          date(2026, 12, 28),
          date(2026, 12, 29),
          date(2026, 12, 30),
          date(2026, 12, 31),
          date(2027, 1, 1),
          date(2027, 1, 2),
          date(2027, 1, 3),
        ],
      ]);

      await tester.tap(calendarDay(date(2026, 12, 31)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2026, 12, 31))]);
      expect(consumer.viewport, week(date(2026, 12, 31)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 12, 28), 1));
    });

    testWidgets('февраль високосного 2028 года содержит 29-е число', (
      tester,
    ) async {
      await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2028, 2, 10)),
        today: date(2026, 10, 4),
      );

      expect(visibleWeeks(tester), weeksFrom(date(2028, 1, 31), 5));
      expect(visibleWeeks(tester).last, [
        date(2028, 2, 28),
        date(2028, 2, 29),
        date(2028, 3, 1),
        date(2028, 3, 2),
        date(2028, 3, 3),
        date(2028, 3, 4),
        date(2028, 3, 5),
      ]);
      expect(dayCell(tester, date(2028, 2, 29)).isOutsideMonth, isFalse);
      expect(dayCell(tester, date(2028, 3, 1)).isOutsideMonth, isTrue);
    });

    testWidgets('выбор 29 февраля 2028 года передаёт эту календарную дату', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2028, 2, 10)),
        today: date(2026, 10, 4),
      );

      await tester.tap(calendarDay(date(2028, 2, 29)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2028, 2, 29))]);
      expect(consumer.selectedDate, date(2028, 2, 29));
      expect(consumer.viewport, month(date(2028, 2, 29)));
      expect(visibleWeeks(tester), weeksFrom(date(2028, 1, 31), 5));
      expect(dayCell(tester, date(2028, 2, 29)).isSelected, isTrue);
    });

    testWidgets(
      'февраль невисокосного 2027 года занимает четыре недели без 29-го числа',
      (tester) async {
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2027, 2, 14)),
          today: date(2026, 10, 4),
        );

        expect(visibleWeeks(tester), weeksFrom(date(2027, 2, 1), 4));
        expect(visibleWeeks(tester).last, [
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

      expect(visibleWeeks(tester), weeksFrom(date(1900, 1, 29), 5));
      expect(visibleWeeks(tester).last, [
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

      expect(visibleWeeks(tester), weeksFrom(date(2000, 1, 31), 5));
      expect(visibleWeeks(tester).last, [
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

  group('смена летнего и зимнего времени', () {
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
          (
            transition: 'зимнее',
            transitionDay: date(2026, 11, 1),
            weekStart: date(2026, 10, 26),
            nextFocus: date(2026, 11, 8),
            nextWeekStart: date(2026, 11, 2),
            monthStart: date(2026, 10, 26),
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
          await tester.drag(
            find.byType(DailyChoiceCalendar),
            const Offset(-600, 0),
          );
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(nextWeekStart, 1));

          await tester.drag(
            find.byType(DailyChoiceCalendar),
            const Offset(600, 0),
          );
          await tester.pumpAndSettle();

          expect(consumer.events, [
            DateSelected(transitionDay),
            ViewportChanged(week(nextFocus)),
            ViewportChanged(week(transitionDay)),
          ]);
          expect(consumer.selectedDate, transitionDay);
          expect(visibleWeeks(tester), weeksFrom(weekStart, 1));
        },
      );

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
    for (final locale in const [Locale('ru'), Locale('en')]) {
      final language = locale.languageCode;

      testWidgets('первая неделя начинается с 0001-01-01 ($language)', (
        tester,
      ) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(1, 1, 1)),
          today: date(2026, 10, 4),
          locale: locale,
        );

        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 1));

        await tester.tap(calendarDay(date(1, 1, 1)));
        await tester.pumpAndSettle();

        expect(consumer.events, [DateSelected(date(1, 1, 1))]);
        expect(consumer.viewport, week(date(1, 1, 1)));
        expect(dayCell(tester, date(1, 1, 1)).isSelected, isTrue);
      });

      testWidgets('первый месяц начинается с 0001-01-01 ($language)', (
        tester,
      ) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(1, 1, 1)),
          today: date(2026, 10, 4),
          locale: locale,
        );

        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 5));

        await tester.tap(calendarDay(date(1, 1, 1)));
        await tester.pumpAndSettle();

        expect(consumer.events, [DateSelected(date(1, 1, 1))]);
        expect(consumer.viewport, month(date(1, 1, 1)));
        expect(dayCell(tester, date(1, 1, 1)).isSelected, isTrue);
      });

      testWidgets(
        'последняя неделя сохраняет семь позиций и выбирает 9999-12-31 ($language)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(date(9999, 12, 31)),
            today: date(2026, 10, 4),
            locale: locale,
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

      testWidgets(
        'последний месяц сохраняет семь позиций и выбирает 9999-12-31 ($language)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: month(date(9999, 12, 31)),
            today: date(2026, 10, 4),
            locale: locale,
          );

          expect(visibleWeeks(tester), [
            ...weeksFrom(date(9999, 11, 29), 4),
            _lastWeekPositions,
          ]);

          await tester.tap(calendarDay(date(9999, 12, 31)));
          await tester.pumpAndSettle();

          expect(consumer.events, [DateSelected(date(9999, 12, 31))]);
          expect(consumer.viewport, month(date(9999, 12, 31)));
          expect(dayCell(tester, date(9999, 12, 31)).isSelected, isTrue);
        },
      );
    }

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
          expect(unavailableCalendarDays, findsNWidgets(2));

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

        await _swipeToPrevious(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 1));

        await _swipeToNext(tester);
        expect(visibleWeeks(tester), weeksFrom(date(1, 1, 8), 1));
        await _swipeToPrevious(tester);

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

        await _swipeToNext(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), [_lastWeekPositions]);

        await _swipeToPrevious(tester);
        expect(visibleWeeks(tester), weeksFrom(date(9999, 12, 20), 1));
        await _swipeToNext(tester);

        expect(consumer.events, [
          ViewportChanged(week(date(9999, 12, 24))),
          ViewportChanged(week(date(9999, 12, 31))),
        ]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(visibleWeeks(tester), [_lastWeekPositions]);
      },
    );

    testWidgets(
      'переход к последней неделе заменяет фокус за пределом на 9999-12-31',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(9999, 12, 26)),
          today: date(2026, 10, 4),
        );
        expect(visibleWeeks(tester), weeksFrom(date(9999, 12, 20), 1));

        await _swipeToNext(tester);

        expect(consumer.events, [ViewportChanged(week(date(9999, 12, 31)))]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(visibleWeeks(tester), [_lastWeekPositions]);
      },
    );

    testWidgets('первый месяц не перелистывается назад и возвращается вперёд', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(1, 1, 15)),
        today: date(2026, 10, 4),
      );

      await _swipeToPrevious(tester);
      expect(consumer.events, isEmpty);
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 5));

      await _swipeToNext(tester);
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 29), 5));
      await _swipeToPrevious(tester);

      expect(consumer.events, [
        ViewportChanged(month(date(1, 2, 1))),
        ViewportChanged(month(date(1, 1, 1))),
      ]);
      expect(consumer.selectedDate, date(2026, 10, 4));
      expect(visibleWeeks(tester), weeksFrom(date(1, 1, 1), 5));
    });

    testWidgets(
      'последний месяц не перелистывается вперёд и возвращается назад',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(9999, 12, 31)),
          today: date(2026, 10, 4),
        );
        final lastMonth = [
          ...weeksFrom(date(9999, 11, 29), 4),
          _lastWeekPositions,
        ];

        await _swipeToNext(tester);
        expect(consumer.events, isEmpty);
        expect(visibleWeeks(tester), lastMonth);

        await _swipeToPrevious(tester);
        expect(visibleWeeks(tester), weeksFrom(date(9999, 11, 1), 5));
        await _swipeToNext(tester);

        expect(consumer.events, [
          ViewportChanged(month(date(9999, 11, 1))),
          ViewportChanged(month(date(9999, 12, 1))),
        ]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(visibleWeeks(tester), lastMonth);
      },
    );

    for (final (description, viewport, positions) in [
      ('первая неделя', week(date(1, 1, 1)), 7),
      ('первый месяц', month(date(1, 1, 1)), 35),
      ('последняя неделя', week(date(9999, 12, 31)), 7),
      ('последний месяц', month(date(9999, 12, 31)), 35),
    ]) {
      testWidgets('$description строит только позиции видимого периода', (
        tester,
      ) async {
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: viewport,
          today: date(2026, 10, 4),
        );

        final builtPositions =
            find
                .byType(DailyChoiceCalendarDay, skipOffstage: false)
                .evaluate()
                .length +
            find
                .byKey(
                  const ValueKey('daily-choice-calendar-unavailable-day'),
                  skipOffstage: false,
                )
                .evaluate()
                .length;
        expect(builtPositions, positions);
      });
    }
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

Future<void> _swipeToNext(WidgetTester tester) async {
  await tester.drag(find.byType(DailyChoiceCalendar), const Offset(-600, 0));
  await tester.pumpAndSettle();
}

Future<void> _swipeToPrevious(WidgetTester tester) async {
  await tester.drag(find.byType(DailyChoiceCalendar), const Offset(600, 0));
  await tester.pumpAndSettle();
}
