import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Ожидаемые подписи шапки при выбранной 2026-10-04. Русские даты Flutter
/// форматирует с узким неразрывным пробелом перед «г.».
final _localizedTexts = [
  (
    locale: const Locale('ru'),
    selectedDate: 'Выбранная дата: воскресенье, 4 октября 2026\u202Fг.',
    october: 'октябрь 2026\u202Fг.',
    november: 'ноябрь 2026\u202Fг.',
    december: 'декабрь 2026\u202Fг.',
    previousWeek: 'Предыдущая неделя',
    nextWeek: 'Следующая неделя',
    previousMonth: 'Предыдущий месяц',
    nextMonth: 'Следующий месяц',
    expand: 'Развернуть календарь',
    collapse: 'Свернуть календарь',
  ),
  (
    locale: const Locale('en'),
    selectedDate: 'Selected date: Sunday, October 4, 2026',
    october: 'October 2026',
    november: 'November 2026',
    december: 'December 2026',
    previousWeek: 'Previous week',
    nextWeek: 'Next week',
    previousMonth: 'Previous month',
    nextMonth: 'Next month',
    expand: 'Expand calendar',
    collapse: 'Collapse calendar',
  ),
];

void main() {
  for (final texts in _localizedTexts) {
    final language = texts.locale.languageCode;

    group('шапка ($language)', () {
      testWidgets('сообщает месяц просмотра, выбранную дату и команды недели', (
        tester,
      ) async {
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        expect(find.text(texts.october), findsOneWidget);
        expect(find.text(texts.selectedDate), findsOneWidget);
        expect(find.byTooltip(texts.previousWeek), findsOneWidget);
        expect(find.byTooltip(texts.nextWeek), findsOneWidget);
        expect(find.byTooltip(texts.previousMonth), findsNothing);
        expect(find.byTooltip(texts.nextMonth), findsNothing);
        expect(find.byTooltip(texts.expand), findsOneWidget);
        expect(find.byTooltip(texts.collapse), findsNothing);
      });

      testWidgets('в месячном представлении называет команды месяца', (
        tester,
      ) async {
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        expect(find.text(texts.october), findsOneWidget);
        expect(find.text(texts.selectedDate), findsOneWidget);
        expect(find.byTooltip(texts.previousMonth), findsOneWidget);
        expect(find.byTooltip(texts.nextMonth), findsOneWidget);
        expect(find.byTooltip(texts.previousWeek), findsNothing);
        expect(find.byTooltip(texts.nextWeek), findsNothing);
        expect(find.byTooltip(texts.collapse), findsOneWidget);
        expect(find.byTooltip(texts.expand), findsNothing);
      });
    });

    group('перелистывание недель ($language)', () {
      testWidgets(
        'кнопка следующей недели показывает 2026-10-05 — 2026-10-11 без выбора дня',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(date(2026, 10, 4)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          await tester.tap(find.byTooltip(texts.nextWeek));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
          expect(consumer.events, [ViewportChanged(week(date(2026, 10, 11)))]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          // Выбранного дня нет в видимой неделе, но подпись сообщает его.
          expect(calendarDay(date(2026, 10, 4)), findsNothing);
          expect(find.text(texts.selectedDate), findsOneWidget);
          expect(find.text(texts.october), findsOneWidget);
        },
      );

      testWidgets(
        'кнопки и свайп перелистывают одни и те же недели через границу месяца',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(date(2026, 10, 25)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          await tester.tap(find.byTooltip(texts.nextWeek));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
          expect(find.text(texts.november), findsOneWidget);

          await swipeToNextPeriod(tester);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 2), 1));

          await tester.tap(find.byTooltip(texts.previousWeek));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));

          await swipeToPreviousPeriod(tester);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 19), 1));
          expect(find.text(texts.october), findsOneWidget);

          expect(consumer.events, [
            ViewportChanged(week(date(2026, 11, 1))),
            ViewportChanged(week(date(2026, 11, 8))),
            ViewportChanged(week(date(2026, 11, 1))),
            ViewportChanged(week(date(2026, 10, 25))),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          expect(find.text(texts.selectedDate), findsOneWidget);
        },
      );
    });

    group('перелистывание месяцев ($language)', () {
      testWidgets('кнопка следующего месяца показывает ноябрь без выбора дня', (
        tester,
      ) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        await tester.tap(find.byTooltip(texts.nextMonth));
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        expect(consumer.events, [ViewportChanged(month(date(2026, 11, 1)))]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(find.text(texts.november), findsOneWidget);
        expect(find.text(texts.october), findsNothing);
        // Выбранного дня нет в видимом месяце, но подпись сообщает его.
        expect(calendarDay(date(2026, 10, 4)), findsNothing);
        expect(find.text(texts.selectedDate), findsOneWidget);
      });

      testWidgets('кнопки и свайп перелистывают одни и те же месяцы', (
        tester,
      ) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        await tester.tap(find.byTooltip(texts.nextMonth));
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));

        await swipeToNextPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 30), 5));
        expect(find.text(texts.december), findsOneWidget);

        await tester.tap(find.byTooltip(texts.previousMonth));
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));

        await swipeToPreviousPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        expect(find.text(texts.october), findsOneWidget);

        expect(consumer.events, [
          ViewportChanged(month(date(2026, 11, 1))),
          ViewportChanged(month(date(2026, 12, 1))),
          ViewportChanged(month(date(2026, 11, 1))),
          ViewportChanged(month(date(2026, 10, 1))),
        ]);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(find.text(texts.selectedDate), findsOneWidget);
      });
    });

    group('раскрытие и сворачивание ($language)', () {
      testWidgets(
        'сворачивание показывает неделю точной даты просмотра, раскрытие сохраняет её',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: month(date(2026, 11, 15)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          await tester.tap(find.byTooltip(texts.collapse));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
          expect(find.text(texts.november), findsOneWidget);
          expect(find.byTooltip(texts.expand), findsOneWidget);
          expect(find.byTooltip(texts.nextWeek), findsOneWidget);

          await tester.tap(find.byTooltip(texts.expand));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
          expect(find.text(texts.november), findsOneWidget);
          expect(find.byTooltip(texts.collapse), findsOneWidget);
          expect(find.byTooltip(texts.nextMonth), findsOneWidget);

          // Повторное сворачивание возвращает ту же неделю, а не неделю
          // начала месяца.
          await tester.tap(find.byTooltip(texts.collapse));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));

          expect(consumer.events, [
            ViewportChanged(week(date(2026, 11, 15))),
            ViewportChanged(month(date(2026, 11, 15))),
            ViewportChanged(week(date(2026, 11, 15))),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          expect(find.text(texts.selectedDate), findsOneWidget);
        },
      );

      testWidgets(
        'после свайпа недели в следующий месяц раскрывается месяц даты просмотра',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(date(2026, 10, 29)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          await swipeToNextPeriod(tester);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 2), 1));

          await tester.tap(find.byTooltip(texts.expand));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
          expect(find.text(texts.november), findsOneWidget);
          expect(consumer.events, [
            ViewportChanged(week(date(2026, 11, 5))),
            ViewportChanged(month(date(2026, 11, 5))),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          expect(find.text(texts.selectedDate), findsOneWidget);
        },
      );

      testWidgets(
        'после свайпа недели в предыдущий месяц раскрывается месяц даты просмотра',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(date(2026, 12, 3)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          await swipeToPreviousPeriod(tester);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 23), 1));

          await tester.tap(find.byTooltip(texts.expand));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
          expect(find.text(texts.november), findsOneWidget);
          expect(consumer.events, [
            ViewportChanged(week(date(2026, 11, 26))),
            ViewportChanged(month(date(2026, 11, 26))),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
        },
      );
    });
  }

  group('представление переключают только команды', () {
    for (final start in [week(date(2026, 10, 4)), month(date(2026, 10, 4))]) {
      testWidgets(
        'вертикальный жест не меняет представление (${start.mode.name})',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );
          final period = visibleWeeks(tester);

          await tester.drag(calendarPeriodArea, const Offset(0, -300));
          await tester.pumpAndSettle();
          await tester.drag(calendarPeriodArea, const Offset(0, 300));
          await tester.pumpAndSettle();

          expect(consumer.events, isEmpty);
          expect(consumer.viewport, start);
          expect(visibleWeeks(tester), period);
        },
      );
    }
  });

  group('технические переходы не меняют дату просмотра', () {
    testWidgets(
      'выбор дня предыдущего месяца в раскрытом календаре сохраняет этот день',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
        );

        await tester.tap(calendarDay(date(2026, 9, 29)));
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 8, 31), 5));

        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
        expect(consumer.events, [
          DateSelected(date(2026, 9, 29)),
          ViewportChanged(week(date(2026, 9, 29))),
        ]);
        expect(consumer.selectedDate, date(2026, 9, 29));
      },
    );

    testWidgets(
      'внешняя смена выбора и просмотра не заменяется началом месяца',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
        );

        consumer.replaceInputs(
          selectedDate: date(2026, 11, 15),
          viewport: month(date(2026, 11, 15)),
        );
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        expect(consumer.events, isEmpty);

        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
        expect(consumer.events, [ViewportChanged(week(date(2026, 11, 15)))]);
        expect(consumer.selectedDate, date(2026, 11, 15));
      },
    );

    testWidgets(
      'быстрое раскрытие и сворачивание заканчиваются последней командой',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 11, 15)),
          today: date(2026, 10, 4),
        );

        // Каждая следующая команда прерывает анимацию высоты предыдущей.
        await tester.tap(find.byTooltip('Развернуть календарь'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.tap(find.byTooltip('Развернуть календарь'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        expect(consumer.events, [
          ViewportChanged(month(date(2026, 11, 15))),
          ViewportChanged(week(date(2026, 11, 15))),
          ViewportChanged(month(date(2026, 11, 15))),
        ]);
        expect(consumer.viewport, month(date(2026, 11, 15)));
        expect(consumer.selectedDate, date(2026, 10, 4));
      },
    );

    testWidgets(
      'выбор дня во время раскрытия даёт одно событие и сохраняет месяц',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 10, 4)),
          today: date(2026, 10, 4),
        );

        await tester.tap(find.byTooltip('Развернуть календарь'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.tap(calendarDay(date(2026, 10, 1)));
        await tester.pumpAndSettle();

        expect(consumer.events, [
          ViewportChanged(month(date(2026, 10, 4))),
          DateSelected(date(2026, 10, 1)),
        ]);
        expect(consumer.viewport, month(date(2026, 10, 1)));
        expect(consumer.selectedDate, date(2026, 10, 1));
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        expect(dayCell(tester, date(2026, 10, 1)).isSelected, isTrue);
      },
    );

    testWidgets(
      'выбор дня во время сворачивания даёт одно событие и сохраняет неделю',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 11, 15)),
          today: date(2026, 10, 4),
        );

        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.tap(calendarDay(date(2026, 11, 12)));
        await tester.pumpAndSettle();

        expect(consumer.events, [
          ViewportChanged(week(date(2026, 11, 15))),
          DateSelected(date(2026, 11, 12)),
        ]);
        expect(consumer.viewport, week(date(2026, 11, 12)));
        expect(consumer.selectedDate, date(2026, 11, 12));
        expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
      },
    );

    testWidgets(
      'сворачивание во время перехода к выбранному дню другого месяца показывает его неделю',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
        );

        // Выбор дня соседнего месяца перелистывает сетку анимацией.
        await tester.tap(calendarDay(date(2026, 11, 1)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
        expect(consumer.events, [
          DateSelected(date(2026, 11, 1)),
          ViewportChanged(week(date(2026, 11, 1))),
        ]);
        expect(consumer.viewport, week(date(2026, 11, 1)));
        expect(consumer.selectedDate, date(2026, 11, 1));
      },
    );

    for (final (
          :start,
          :next,
          :toggle,
          :beforeMidpoint,
          :afterMidpoint,
          :reported,
          :beforeMidpointWeeks,
          :afterMidpointWeeks,
        )
        in [
          (
            start: week(date(2026, 10, 4)),
            next: 'Следующая неделя',
            toggle: 'Развернуть календарь',
            beforeMidpoint: month(date(2026, 10, 4)),
            reported: week(date(2026, 10, 11)),
            afterMidpoint: month(date(2026, 10, 11)),
            beforeMidpointWeeks: weeksFrom(date(2026, 9, 28), 5),
            afterMidpointWeeks: weeksFrom(date(2026, 9, 28), 5),
          ),
          (
            start: month(date(2026, 10, 4)),
            next: 'Следующий месяц',
            toggle: 'Свернуть календарь',
            beforeMidpoint: week(date(2026, 10, 4)),
            reported: month(date(2026, 11, 1)),
            afterMidpoint: week(date(2026, 11, 1)),
            beforeMidpointWeeks: weeksFrom(date(2026, 9, 28), 1),
            afterMidpointWeeks: weeksFrom(date(2026, 10, 26), 1),
          ),
        ]) {
      final mode = start.mode.name;

      testWidgets(
        'смена представления до середины перелистывания отменяет его ($mode)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );

          await tester.tap(find.byTooltip(next));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(consumer.events, isEmpty);
          await tester.tap(find.byTooltip(toggle));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), beforeMidpointWeeks);
          expect(consumer.events, [ViewportChanged(beforeMidpoint)]);
          expect(consumer.viewport, beforeMidpoint);
          expect(consumer.selectedDate, date(2026, 10, 4));
        },
      );

      testWidgets(
        'смена представления после середины перелистывания сохраняет новый период ($mode)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );

          await tester.tap(find.byTooltip(next));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.hasRunningAnimations, isTrue);
          expect(consumer.events, [ViewportChanged(reported)]);
          await tester.tap(find.byTooltip(toggle));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), afterMidpointWeeks);
          expect(consumer.events, [
            ViewportChanged(reported),
            ViewportChanged(afterMidpoint),
          ]);
          expect(consumer.viewport, afterMidpoint);
          expect(consumer.selectedDate, date(2026, 10, 4));
        },
      );
    }
  });

  group('края диапазона', () {
    for (final (
          :description,
          :start,
          :towardEdge,
          :awayFromEdge,
          :edge,
          :edgePeriod,
          :backFromEdge,
        )
        in [
          (
            description: 'первая неделя',
            start: week(date(1, 1, 8)),
            towardEdge: 'Предыдущая неделя',
            awayFromEdge: 'Следующая неделя',
            edge: week(date(1, 1, 1)),
            edgePeriod: weeksFrom(date(1, 1, 1), 1),
            backFromEdge: week(date(1, 1, 8)),
          ),
          (
            description: 'последняя неделя',
            start: week(date(9999, 12, 26)),
            towardEdge: 'Следующая неделя',
            awayFromEdge: 'Предыдущая неделя',
            edge: week(date(9999, 12, 31)),
            edgePeriod: [_lastWeekPositions],
            backFromEdge: week(date(9999, 12, 24)),
          ),
          (
            description: 'первый месяц',
            start: month(date(1, 2, 15)),
            towardEdge: 'Предыдущий месяц',
            awayFromEdge: 'Следующий месяц',
            edge: month(date(1, 1, 1)),
            edgePeriod: weeksFrom(date(1, 1, 1), 5),
            backFromEdge: month(date(1, 2, 1)),
          ),
          (
            description: 'последний месяц',
            start: month(date(9999, 11, 15)),
            towardEdge: 'Следующий месяц',
            awayFromEdge: 'Предыдущий месяц',
            edge: month(date(9999, 12, 1)),
            edgePeriod: [
              ...weeksFrom(date(9999, 11, 29), 4),
              _lastWeekPositions,
            ],
            backFromEdge: month(date(9999, 11, 1)),
          ),
        ]) {
      testWidgets(
        '$description: кнопка к краю отключается, обратная возвращает',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );
          _expectCommandEnabled(tester, towardEdge, isEnabled: true);

          await tester.tap(find.byTooltip(towardEdge));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), edgePeriod);
          expect(consumer.events, [ViewportChanged(edge)]);
          _expectCommandEnabled(tester, towardEdge, isEnabled: false);
          _expectCommandEnabled(tester, awayFromEdge, isEnabled: true);

          await tester.tap(find.byTooltip(towardEdge));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), edgePeriod);
          expect(consumer.events, [ViewportChanged(edge)]);

          await tester.tap(find.byTooltip(awayFromEdge));
          await tester.pumpAndSettle();
          expect(consumer.events, [
            ViewportChanged(edge),
            ViewportChanged(backFromEdge),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          semantics.dispose();
        },
      );
    }
  });

  group('раскрытие и сворачивание у краёв диапазона', () {
    for (final (
          :description,
          :focusedDate,
          :weekPeriod,
          :monthPeriod,
          :towardEdgeWeek,
          :towardEdgeMonth,
          :awayFromEdgeWeek,
          :awayFromEdge,
          :awayFromEdgePeriod,
        )
        in [
          (
            description: 'первая неделя',
            focusedDate: date(1, 1, 3),
            weekPeriod: weeksFrom(date(1, 1, 1), 1),
            monthPeriod: weeksFrom(date(1, 1, 1), 5),
            towardEdgeWeek: 'Предыдущая неделя',
            towardEdgeMonth: 'Предыдущий месяц',
            awayFromEdgeWeek: 'Следующая неделя',
            awayFromEdge: week(date(1, 1, 10)),
            awayFromEdgePeriod: weeksFrom(date(1, 1, 8), 1),
          ),
          (
            description: 'последняя неделя',
            focusedDate: date(9999, 12, 30),
            weekPeriod: [_lastWeekPositions],
            monthPeriod: [
              ...weeksFrom(date(9999, 11, 29), 4),
              _lastWeekPositions,
            ],
            towardEdgeWeek: 'Следующая неделя',
            towardEdgeMonth: 'Следующий месяц',
            awayFromEdgeWeek: 'Предыдущая неделя',
            awayFromEdge: week(date(9999, 12, 23)),
            awayFromEdgePeriod: weeksFrom(date(9999, 12, 20), 1),
          ),
        ]) {
      testWidgets(
        '$description: полный цикл сохраняет дату просмотра и границы перелистывания',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: week(focusedDate),
            today: date(2026, 10, 4),
          );
          expect(visibleWeeks(tester), weekPeriod);

          await tester.tap(find.byTooltip('Развернуть календарь'));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), monthPeriod);
          _expectCommandEnabled(tester, towardEdgeMonth, isEnabled: false);

          await tester.tap(find.byTooltip('Свернуть календарь'));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weekPeriod);
          _expectCommandEnabled(tester, towardEdgeWeek, isEnabled: false);

          await tester.tap(find.byTooltip('Развернуть календарь'));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), monthPeriod);

          await tester.tap(find.byTooltip('Свернуть календарь'));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weekPeriod);

          // После смены представлений у края перелистывание продолжает
          // работать от точной даты просмотра.
          await tester.tap(find.byTooltip(awayFromEdgeWeek));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), awayFromEdgePeriod);

          expect(consumer.events, [
            ViewportChanged(month(focusedDate)),
            ViewportChanged(week(focusedDate)),
            ViewportChanged(month(focusedDate)),
            ViewportChanged(week(focusedDate)),
            ViewportChanged(awayFromEdge),
          ]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          semantics.dispose();
        },
      );
    }
  });

  group('удаление во время перелистывания', () {
    for (final (
          :start,
          :next,
          :previous,
          :nextViewport,
          :backViewport,
          :startWeeks,
          :nextWeeks,
        )
        in [
          (
            start: week(date(2026, 10, 4)),
            next: 'Следующая неделя',
            previous: 'Предыдущая неделя',
            nextViewport: week(date(2026, 10, 11)),
            backViewport: week(date(2026, 10, 4)),
            startWeeks: weeksFrom(date(2026, 9, 28), 1),
            nextWeeks: weeksFrom(date(2026, 10, 5), 1),
          ),
          (
            start: month(date(2026, 10, 4)),
            next: 'Следующий месяц',
            previous: 'Предыдущий месяц',
            nextViewport: month(date(2026, 11, 1)),
            backViewport: month(date(2026, 10, 1)),
            startWeeks: weeksFrom(date(2026, 9, 28), 5),
            nextWeeks: weeksFrom(date(2026, 10, 26), 6),
          ),
        ]) {
      final mode = start.mode.name;

      testWidgets(
        'календарь, удалённый до конца анимации кнопки, не сообщает о просмотре ($mode)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );

          // Страница ещё не дошла до середины перехода.
          await tester.tap(find.byTooltip(next));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          // Кадр без сдвига времени убирает календарь до следующего шага
          // анимации.
          consumer.removeCalendar();
          await tester.pump();
          await tester.pumpAndSettle();

          expect(consumer.events, isEmpty);
          expect(consumer.viewport, start);

          // Новый календарь перелистывается и кнопкой, и свайпом.
          consumer.restoreCalendar();
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), startWeeks);

          await tester.tap(find.byTooltip(next));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), nextWeeks);
          await swipeToPreviousPeriod(tester);

          expect(consumer.events, [
            ViewportChanged(nextViewport),
            ViewportChanged(backViewport),
          ]);
          expect(visibleWeeks(tester), startWeeks);
          expect(consumer.selectedDate, date(2026, 10, 4));
        },
      );

      testWidgets(
        'календарь, удалённый до конца доводки свайпа, не сообщает о просмотре повторно ($mode)',
        (tester) async {
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );

          // Жест проходит середину страницы, доводка ещё продолжается.
          await tester.drag(calendarPeriodArea, const Offset(-600, 0));
          await tester.pump(const Duration(milliseconds: 20));
          consumer.removeCalendar();
          await tester.pump();
          await tester.pumpAndSettle();

          expect(consumer.events, [ViewportChanged(nextViewport)]);

          // Новый календарь показывает принятый просмотр и перелистывается.
          consumer.restoreCalendar();
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), nextWeeks);

          await tester.tap(find.byTooltip(previous));
          await tester.pumpAndSettle();

          expect(consumer.events, [
            ViewportChanged(nextViewport),
            ViewportChanged(backViewport),
          ]);
          expect(visibleWeeks(tester), startWeeks);
          expect(consumer.selectedDate, date(2026, 10, 4));
        },
      );
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

void _expectCommandEnabled(
  WidgetTester tester,
  String tooltip, {
  required bool isEnabled,
}) {
  expect(
    tester.getSemantics(find.byTooltip(tooltip)),
    isSemantics(isButton: true, isEnabled: isEnabled),
  );
}
