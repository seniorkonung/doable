import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Подпись выбранной 2026-10-04. Русские даты Flutter форматирует с узким
/// неразрывным пробелом перед «г.».
const _selectedOctober4 = 'Выбранная дата: воскресенье, 4 октября 2026\u202Fг.';
const _october = 'октябрь 2026\u202Fг.';
const _november = 'ноябрь 2026\u202Fг.';

double _calendarHeight(WidgetTester tester) =>
    tester.getSize(find.byType(DailyChoiceCalendar)).height;

void main() {
  // Сценарии требования «Встроенный недельный и месячный календарь каталога»
  // в части контракта компонента: выбор и просмотр меняет только потребитель
  // по событиям календаря. Отсутствие лишних чтений каталога проверяется при
  // подключении к странице.
  group('сценарии спецификации', () {
    testWidgets('свайп недели сохраняет фильтр', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2026, 10, 4)),
        today: date(2026, 10, 4),
      );

      await swipeToNextPeriod(tester);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(consumer.events, [ViewportChanged(week(date(2026, 10, 11)))]);
      expect(consumer.selectedDate, date(2026, 10, 4));
      expect(find.text(_selectedOctober4), findsOneWidget);
    });

    testWidgets('свайп месяца сохраняет фильтр', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 10, 4)),
        today: date(2026, 10, 4),
      );

      await swipeToNextPeriod(tester);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(find.text(_november), findsOneWidget);
      expect(consumer.events, [ViewportChanged(month(date(2026, 11, 1)))]);
      expect(consumer.selectedDate, date(2026, 10, 4));
      // Выбранного дня нет в сетке ноября, но подпись сообщает его.
      expect(calendarDay(date(2026, 10, 4)), findsNothing);
      expect(find.text(_selectedOctober4), findsOneWidget);
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

      await tester.tap(find.byTooltip('Развернуть календарь'));
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
      expect(find.text(_selectedOctober4), findsOneWidget);
    });

    testWidgets('сворачивание сохраняет дату просмотра', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 11, 15)),
        today: date(2026, 10, 4),
      );
      final monthHeight = _calendarHeight(tester);

      await tester.tap(find.byTooltip('Свернуть календарь'));
      await tester.pumpAndSettle();

      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
      expect(_calendarHeight(tester), lessThan(monthHeight));
      expect(consumer.events, [ViewportChanged(week(date(2026, 11, 15)))]);
      expect(consumer.selectedDate, date(2026, 10, 4));
      expect(find.text(_selectedOctober4), findsOneWidget);
    });

    testWidgets('выбор дня сохраняет раскрытое представление', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 11, 1)),
        today: date(2026, 10, 4),
      );

      await tester.tap(calendarDay(date(2026, 11, 15)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2026, 11, 15))]);
      expect(consumer.selectedDate, date(2026, 11, 15));
      expect(consumer.viewport, month(date(2026, 11, 15)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(find.text(_november), findsOneWidget);
      expect(dayCell(tester, date(2026, 11, 15)).isSelected, isTrue);
      expect(find.byTooltip('Свернуть календарь'), findsOneWidget);
    });
  });

  group('выбор уже выбранного дня переносит просмотр в этот день', () {
    testWidgets('в недельном представлении неделя сохраняется', (tester) async {
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: week(date(2026, 9, 29)),
        today: date(2026, 10, 4),
      );

      await tester.tap(calendarDay(date(2026, 10, 4)));
      await tester.pumpAndSettle();

      expect(consumer.events, [DateSelected(date(2026, 10, 4))]);
      expect(consumer.selectedDate, date(2026, 10, 4));
      expect(consumer.viewport, week(date(2026, 10, 4)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
    });

    testWidgets(
      'в месячном представлении день соседнего месяца показывает свой месяц',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 29),
          viewport: month(date(2026, 11, 15)),
          today: date(2026, 10, 4),
        );
        expect(dayCell(tester, date(2026, 10, 29)).isSelected, isTrue);

        await tester.tap(calendarDay(date(2026, 10, 29)));
        await tester.pumpAndSettle();

        // Технический фокус библиотеки для дня до просматриваемого месяца —
        // начало этого месяца; просмотр переходит именно в нажатый день.
        expect(consumer.events, [DateSelected(date(2026, 10, 29))]);
        expect(consumer.selectedDate, date(2026, 10, 29));
        expect(consumer.viewport, month(date(2026, 10, 29)));
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        expect(find.text(_october), findsOneWidget);
        expect(dayCell(tester, date(2026, 10, 29)).isSelected, isTrue);
      },
    );
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
            next: 'Следующая неделя',
            toggle: 'Развернуть календарь',
            afterNext: week(date(2026, 10, 11)),
            afterSwipe: week(date(2026, 10, 18)),
            afterToggle: month(date(2026, 10, 18)),
            nextWeeks: weeksFrom(date(2026, 10, 5), 1),
            swipedWeeks: weeksFrom(date(2026, 10, 12), 1),
            toggledWeeks: weeksFrom(date(2026, 9, 28), 5),
          ),
          (
            start: month(date(2026, 10, 4)),
            next: 'Следующий месяц',
            toggle: 'Свернуть календарь',
            afterNext: month(date(2026, 11, 1)),
            afterSwipe: month(date(2026, 12, 1)),
            afterToggle: week(date(2026, 12, 1)),
            nextWeeks: weeksFrom(date(2026, 10, 26), 6),
            swipedWeeks: weeksFrom(date(2026, 11, 30), 5),
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

        await tester.tap(find.byTooltip(next));
        await tester.pumpAndSettle();
        await rebuildAndSettle(tester, consumer);
        expect(visibleWeeks(tester), nextWeeks);

        await swipeToNextPeriod(tester);
        await rebuildAndSettle(tester, consumer);
        expect(visibleWeeks(tester), swipedWeeks);

        await tester.tap(find.byTooltip(toggle));
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

      testWidgets(
        'во время перелистывания кнопкой до середины перехода ($mode)',
        (tester) async {
          final consumer = await pumpStart(tester);

          await tester.tap(find.byTooltip(next));
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

          await tester.tap(find.byTooltip(next));
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

  testWidgets('просмотр, раскрытие и сворачивание не выбирают дни', (
    tester,
  ) async {
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 4),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
    );

    await tester.tap(find.byTooltip('Следующая неделя'));
    await tester.pumpAndSettle();
    await swipeToNextPeriod(tester);
    await tester.tap(find.byTooltip('Развернуть календарь'));
    await tester.pumpAndSettle();
    await swipeToPreviousPeriod(tester);
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Свернуть календарь'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Предыдущая неделя'));
    await tester.pumpAndSettle();

    expect(consumer.events, [
      ViewportChanged(week(date(2026, 10, 11))),
      ViewportChanged(week(date(2026, 10, 18))),
      ViewportChanged(month(date(2026, 10, 18))),
      ViewportChanged(month(date(2026, 9, 1))),
      ViewportChanged(month(date(2026, 10, 1))),
      ViewportChanged(week(date(2026, 10, 1))),
      ViewportChanged(week(date(2026, 9, 24))),
    ]);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
    expect(consumer.selectedDate, date(2026, 10, 4));
    expect(find.text(_selectedOctober4), findsOneWidget);
  });
}
