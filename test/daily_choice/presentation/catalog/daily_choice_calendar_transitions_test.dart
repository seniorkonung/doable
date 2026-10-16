import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

const _november = 'Ноябрь 2026';

double _calendarHeight(WidgetTester tester) =>
    tester.getSize(find.byType(DailyChoiceCalendar)).height;

void main() {
  testWidgets('нажатие непрерывно меняет высоту и сдвигает содержимое, '
      'сообщая просмотр только в конце перехода', (tester) async {
    final focused = date(2026, 11, 15);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(focused),
      today: date(2026, 10, 4),
      hasDayMarksReadFailure: true,
      contentBelow: const [
        SliverToBoxAdapter(child: Text('Выдача под календарём')),
      ],
    );
    final weekHeight = _calendarHeight(tester);
    final weekContentTop = tester
        .getTopLeft(find.text('Выдача под календарём'))
        .dy;
    final weekCellHeight = tester.getSize(calendarDay(focused)).height;

    await tester.tap(find.byType(CalendarHandle));
    await tester.pump();
    expect(_calendarHeight(tester), weekHeight);
    expect(consumer.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 60));
    final intermediateHeight = _calendarHeight(tester);
    expect(intermediateHeight, greaterThan(weekHeight));
    expect(consumer.events, isEmpty);
    consumer.rebuild();
    await tester.pump();
    expect(_calendarHeight(tester), intermediateHeight);
    expect(
      tester.getTopLeft(find.text('Выдача под календарём')).dy - weekContentTop,
      moreOrLessEquals(intermediateHeight - weekHeight),
    );
    expect(tester.getSize(calendarDay(focused).first).height, weekCellHeight);
    expect(
      tester.getTopLeft(find.byType(Notice)).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(CalendarHandle)).dy,
      ),
    );

    // Flutter завершает симуляцию при t > duration, а не при равенстве.
    await tester.pump(const Duration(microseconds: 140001));
    await tester.pump();
    final monthHeight = _calendarHeight(tester);
    expect(
      intermediateHeight,
      moreOrLessEquals(
        weekHeight + Curves.easeOut.transform(0.3) * (monthHeight - weekHeight),
      ),
    );
    expect(consumer.events, [ViewportChanged(month(focused))]);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
    expect(consumer.selectedDate, date(2026, 10, 4));

    await tester.tap(find.byType(CalendarHandle));
    await tester.pump();
    expect(_calendarHeight(tester), monthHeight);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      _calendarHeight(tester),
      moreOrLessEquals(
        monthHeight -
            Curves.easeOut.transform(0.3) * (monthHeight - weekHeight),
      ),
    );
    expect(consumer.events, [ViewportChanged(month(focused))]);
    await tester.pump(const Duration(microseconds: 140001));
    await tester.pump();
    expect(_calendarHeight(tester), weekHeight);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
    expect(consumer.events, [
      ViewportChanged(month(focused)),
      ViewportChanged(week(focused)),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('повторное нажатие меняет цель без скачка высоты '
      'и возвращается без события за оставшуюся долю 200 мс', (tester) async {
    final focused = date(2026, 10, 15);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: focused,
      viewport: month(focused),
      today: focused,
    );
    final monthHeight = _calendarHeight(tester);
    consumer.replaceInputs(viewport: week(focused));
    await tester.pumpAndSettle();
    final weekHeight = _calendarHeight(tester);

    for (final start in [week(focused), month(focused)]) {
      consumer.replaceInputs(viewport: start);
      await tester.pumpAndSettle();
      final startHeight = _calendarHeight(tester);
      await tester.tap(find.byType(CalendarHandle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final turningHeight = _calendarHeight(tester);
      expect(consumer.events, isEmpty);

      await tester.tap(find.byType(CalendarHandle));
      await tester.pump();
      expect(_calendarHeight(tester), moreOrLessEquals(turningHeight));
      final remainingFraction =
          (turningHeight - startHeight).abs() / (monthHeight - weekHeight);
      await tester.pump(
        Duration(microseconds: (200000 * remainingFraction).ceil() + 1),
      );
      await tester.pump();
      expect(_calendarHeight(tester), moreOrLessEquals(startHeight));
      expect(consumer.viewport, start);
      expect(consumer.events, isEmpty);
      expect(tester.hasRunningAnimations, isFalse);
    }
  });

  testWidgets('внешняя смена просмотра прекращает переход '
      'без обратного или позднего события', (tester) async {
    final focused = date(2026, 10, 4);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: focused,
      viewport: week(focused),
      today: focused,
    );
    await tester.tap(find.byType(CalendarHandle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final replacement = month(date(2028, 3, 1));
    consumer.replaceInputs(viewport: replacement);
    await tester.pumpAndSettle();

    expect(consumer.events, isEmpty);
    expect(consumer.viewport, replacement);
    expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 6));
    expect(find.text('Март 2028'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byType(CalendarHandle));
    await tester.pumpAndSettle();
    expect(consumer.events, [ViewportChanged(week(replacement.focusedDate))]);
    expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 1));
    expect(consumer.selectedDate, focused);
  });

  testWidgets('удаление календаря во время раскрытия '
      'отменяет завершение и не создаёт поздних событий', (tester) async {
    final focused = date(2026, 10, 4);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: focused,
      viewport: week(focused),
      today: focused,
    );
    await tester.tap(find.byType(CalendarHandle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    consumer.removeCalendar();
    await tester.pumpAndSettle();

    expect(consumer.events, isEmpty);
    expect(tester.takeException(), isNull);
    consumer.restoreCalendar();
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
    expect(consumer.events, isEmpty);
  });

  testWidgets('выбор периода участвует в плавном сворачивании '
      'и закрывается только при достижении недели', (tester) async {
    final focused = date(2026, 10, 15);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: focused,
      viewport: month(focused),
      today: focused,
    );
    await tester.tap(find.bySemanticsLabel('Выбрать год и месяц'));
    await tester.pumpAndSettle();
    final expandedHeight = _calendarHeight(tester);
    await tester.tap(find.byType(CalendarHandle));
    await tester.pump();
    expect(_calendarHeight(tester), expandedHeight);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_calendarHeight(tester), lessThan(expandedHeight));
    expect(find.text('2020–2031'), findsOneWidget);
    expect(consumer.events, isEmpty);
    await tester.tap(find.byType(CalendarHandle));
    await tester.pumpAndSettle();
    expect(_calendarHeight(tester), expandedHeight);
    expect(find.text('2020–2031'), findsOneWidget);
    expect(consumer.events, isEmpty);

    await tester.tap(find.byType(CalendarHandle));
    await tester.pumpAndSettle();
    expect(find.text('2020–2031'), findsNothing);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
    expect(consumer.events, [ViewportChanged(week(focused))]);
    await tester.tap(find.byType(CalendarHandle));
    await tester.pumpAndSettle();
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(find.text('2020–2031'), findsNothing);
  });

  testWidgets('сворачивание до смены страницы останавливает перелистывание '
      'и сохраняет уже сообщённый период', (tester) async {
    final focused = date(2026, 11, 1);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 15),
      viewport: month(focused),
      today: date(2026, 10, 15),
    );
    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(consumer.events, isEmpty);
    await tester.tap(find.byType(CalendarHandle));
    await tester.pumpAndSettle();
    expect(consumer.events, [ViewportChanged(week(focused))]);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
    expect(tester.takeException(), isNull);
  });

  // Сценарии требования «Встроенный недельный и месячный календарь каталога»
  // в части контракта компонента: выбор и просмотр меняет только потребитель
  // по событиям календаря. Отсутствие лишних чтений каталога проверяется при
  // подключении к странице.
  group('сценарии спецификации', () {
    testWidgets('сворачивание прерывает возврат к месяцу выбранного дня '
        'и показывает его неделю', (tester) async {
      final selected = date(2026, 10, 15);
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: selected,
        viewport: month(date(2026, 11, 1)),
        today: selected,
      );

      await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.tap(find.bySemanticsLabel('Свернуть календарь'));
      await tester.pumpAndSettle();

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(consumer.events, [
        ViewportChanged(month(selected)),
        ViewportChanged(week(selected)),
      ]);
      expect(consumer.selectedDate, selected);
    });

    testWidgets('раскрытие сохраняет просмотр соседнего периода', (
      tester,
    ) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2026, 10, 4)),
        today: date(2026, 10, 4),
      );
      for (var i = 0; i < 4; i++) {
        await swipeToNextPeriod(tester);
      }
      // Большая часть недели — октябрь, но дата просмотра уже в ноябре.
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      expect(consumer.viewport, week(date(2026, 11, 1)));
      final weekHeight = _calendarHeight(tester);

      await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
      await tester.pumpAndSettle();

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(find.text(_november), findsOneWidget);
      expect(_calendarHeight(tester), greaterThan(weekHeight));
      expect(consumer.events, [
        ViewportChanged(week(date(2026, 10, 11))),
        ViewportChanged(week(date(2026, 10, 18))),
        ViewportChanged(week(date(2026, 10, 25))),
        ViewportChanged(week(date(2026, 11, 1))),
        ViewportChanged(month(date(2026, 11, 1))),
      ]);
      expect(consumer.selectedDate, date(2026, 10, 4));
    });
  });

  group('перестроение потребителя не возвращает начальный период', () {
    for (final (
          :start,
          :next,
          :toggle,
          :afterNext,
          :afterSwipe,
          :afterToggle,
          :nextWeeks,
          :swipedWeeks,
          :toggledWeeks,
        )
        in [
          (
            start: week(date(2026, 10, 4)),
            next: null,
            toggle: 'Развернуть календарь',
            afterNext: week(date(2026, 10, 11)),
            afterSwipe: week(date(2026, 10, 18)),
            afterToggle: month(date(2026, 10, 18)),
            nextWeeks: weeksFrom(date(2026, 10, 5), 1),
            swipedWeeks: weeksFrom(date(2026, 10, 12), 1),
            toggledWeeks: weeksFrom(date(2026, 9, 28), 6),
          ),
          (
            start: month(date(2026, 10, 4)),
            next: 'Следующий месяц',
            toggle: 'Свернуть календарь',
            afterNext: month(date(2026, 11, 1)),
            afterSwipe: month(date(2026, 12, 1)),
            afterToggle: week(date(2026, 12, 1)),
            nextWeeks: weeksFrom(date(2026, 10, 26), 6),
            swipedWeeks: weeksFrom(date(2026, 11, 30), 6),
            toggledWeeks: weeksFrom(date(2026, 11, 30), 1),
          ),
        ]) {
      final mode = start.mode.name;
      final nextPeriod = [ViewportChanged(afterNext)];

      Future<CalendarConsumer> pumpStart(WidgetTester tester) =>
          pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: start,
            today: date(2026, 10, 4),
          );

      Future<void> rebuildAndSettle(
        WidgetTester tester,
        CalendarConsumer consumer,
      ) async {
        consumer.rebuild();
        await tester.pumpAndSettle();
      }

      testWidgets('после перелистывания и смены представления ($mode)', (
        tester,
      ) async {
        final consumer = await pumpStart(tester);

        if (next == null) {
          await swipeToNextPeriod(tester);
        } else {
          await tester.tap(find.bySemanticsLabel(next));
        }
        await tester.pumpAndSettle();
        await rebuildAndSettle(tester, consumer);
        expect(visibleWeeks(tester), nextWeeks);

        await swipeToNextPeriod(tester);
        await rebuildAndSettle(tester, consumer);
        expect(visibleWeeks(tester), swipedWeeks);

        await tester.tap(find.bySemanticsLabel(toggle));
        await tester.pumpAndSettle();
        await rebuildAndSettle(tester, consumer);
        expect(visibleWeeks(tester), toggledWeeks);

        expect(consumer.events, [
          ViewportChanged(afterNext),
          ViewportChanged(afterSwipe),
          ViewportChanged(afterToggle),
        ]);
        expect(consumer.viewport, afterToggle);
        expect(consumer.selectedDate, date(2026, 10, 4));
      });

      // Перестроение посреди перехода не зависит от представления: страницы и
      // их анимацией ведёт одна и та же сетка, поэтому достаточно месяца.
      if (next case final nextCommand?) {
        testWidgets(
          'во время перелистывания кнопкой до середины перехода ($mode)',
          (tester) async {
            final consumer = await pumpStart(tester);

            await tester.tap(find.bySemanticsLabel(nextCommand));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            expect(consumer.events, isEmpty);
            consumer.rebuild();
            await tester.pump();
            expect(tester.hasRunningAnimations, isTrue);
            expect(consumer.events, isEmpty);
            await tester.pumpAndSettle();

            expect(visibleWeeks(tester), nextWeeks);
            expect(consumer.events, nextPeriod);
            expect(consumer.selectedDate, date(2026, 10, 4));
          },
        );

        testWidgets(
          'во время перелистывания кнопкой после середины перехода ($mode)',
          (tester) async {
            final consumer = await pumpStart(tester);

            await tester.tap(find.bySemanticsLabel(nextCommand));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.hasRunningAnimations, isTrue);
            expect(consumer.events, nextPeriod);
            consumer.rebuild();
            await tester.pump();
            expect(tester.hasRunningAnimations, isTrue);
            await tester.pumpAndSettle();

            expect(visibleWeeks(tester), nextWeeks);
            expect(consumer.events, nextPeriod);
            expect(consumer.selectedDate, date(2026, 10, 4));
          },
        );

        continue;
      }

      testWidgets('во время свайпа, пока палец на календаре ($mode)', (
        tester,
      ) async {
        final consumer = await pumpStart(tester);

        final gesture = await tester.startGesture(
          tester.getCenter(calendarPeriodArea),
        );
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(-50, 0));
          await tester.pump();
        }
        consumer.rebuild();
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(-100, 0));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), nextWeeks);
        expect(consumer.events, nextPeriod);
        expect(consumer.selectedDate, date(2026, 10, 4));
      });
    }
  });
}
