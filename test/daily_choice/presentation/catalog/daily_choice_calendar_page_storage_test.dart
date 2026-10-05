import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Ключ, под которым общая прокрутка сохраняет смещение, как прокрутки страниц
/// приложения. Хранилище страниц маршрута ищет запись по ключам предков,
/// поэтому без изоляции календарь делил бы с прокруткой одну запись.
const _scrollStorageKey = PageStorageKey<String>('прокрутка страницы');

/// Содержимое под календарём в той же прокрутке, которое не помещается на
/// экран.
final _contentBelow = <Widget>[
  SliverList.builder(
    itemCount: 40,
    itemBuilder: (context, index) =>
        ListTile(title: Text('Строка ${index + 1}')),
  ),
];

/// Общая вертикальная прокрутка страницы.
final _pageScroll = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

ScrollPosition _pageScrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_pageScroll).position;

Future<CalendarConsumer> _pumpUnderStoredScroll(
  WidgetTester tester, {
  required DailyChoiceCalendarViewport Function(CalendarDate) viewport,
}) => pumpCalendarConsumer(
  tester,
  selectedDate: date(2026, 10, 4),
  viewport: viewport(date(2026, 10, 4)),
  today: date(2026, 10, 4),
  contentBelow: _contentBelow,
  scrollStorageKey: _scrollStorageKey,
);

/// Пользователь прокручивает страницу вниз и возвращается к началу. Прокрутка
/// записывает смещение в хранилище страниц, а календарь снова целиком на
/// экране.
Future<void> _scrollPageDownAndBack(WidgetTester tester) async {
  _pageScrollPosition(tester).jumpTo(300);
  await tester.pump();
  _pageScrollPosition(tester).jumpTo(0);
  await tester.pumpAndSettle();
}

/// Убирает календарь и создаёт его заново с прежними входами потребителя, как
/// при условном показе или ленивой перестройке элемента страницы.
Future<void> _recreateCalendar(
  WidgetTester tester,
  CalendarConsumer consumer,
) async {
  consumer.removeCalendar();
  await tester.pump();
  consumer.restoreCalendar();
  await tester.pumpAndSettle();
}

void main() {
  group('календарь под прокруткой с PageStorageKey', () {
    for (final (
          :start,
          :next,
          :afterSwipe,
          :afterSwipeWeeks,
          :afterSwipeMonth,
          :afterButton,
          :afterButtonWeeks,
          :tappedDay,
        )
        in [
          (
            start: week,
            next: 'Следующая неделя',
            afterSwipe: week(date(2026, 10, 11)),
            afterSwipeWeeks: weeksFrom(date(2026, 10, 5), 1),
            afterSwipeMonth: 'октябрь 2026 г.',
            afterButton: week(date(2026, 10, 18)),
            afterButtonWeeks: weeksFrom(date(2026, 10, 12), 1),
            tappedDay: date(2026, 10, 14),
          ),
          (
            start: month,
            next: 'Следующий месяц',
            afterSwipe: month(date(2026, 11, 1)),
            afterSwipeWeeks: weeksFrom(date(2026, 10, 26), 6),
            afterSwipeMonth: 'ноябрь 2026 г.',
            afterButton: month(date(2026, 12, 1)),
            afterButtonWeeks: weeksFrom(date(2026, 11, 30), 5),
            tappedDay: date(2026, 12, 16),
          ),
        ]) {
      final mode = afterSwipe.mode.name;

      testWidgets(
        'пересозданный после перелистывания календарь показывает период '
        'просмотра и сообщает его даты ($mode)',
        (tester) async {
          final consumer = await _pumpUnderStoredScroll(
            tester,
            viewport: start,
          );
          await swipeToNextPeriod(tester);
          expect(consumer.events, [ViewportChanged(afterSwipe)]);

          await _scrollPageDownAndBack(tester);
          await _recreateCalendar(tester, consumer);

          expect(visibleWeeks(tester), afterSwipeWeeks);
          expect(find.text(afterSwipeMonth), findsOneWidget);

          // Первое перелистывание пересозданного календаря.
          await tester.tap(find.byTooltip(next));
          await tester.pumpAndSettle();

          expect(consumer.events, [
            ViewportChanged(afterSwipe),
            ViewportChanged(afterButton),
          ]);
          expect(visibleWeeks(tester), afterButtonWeeks);

          await _scrollPageDownAndBack(tester);
          await _recreateCalendar(tester, consumer);

          expect(visibleWeeks(tester), afterButtonWeeks);

          await tester.tap(calendarDay(tappedDay));
          await tester.pumpAndSettle();

          expect(consumer.events, [
            ViewportChanged(afterSwipe),
            ViewportChanged(afterButton),
            DateSelected(tappedDay),
          ]);
          expect(consumer.selectedDate, tappedDay);
          expect(visibleWeeks(tester), afterButtonWeeks);
        },
      );
    }

    testWidgets(
      'пересозданный после смены представления календарь показывает период '
      'просмотра и сообщает его даты',
      (tester) async {
        final consumer = await _pumpUnderStoredScroll(tester, viewport: week);
        await tester.tap(find.byTooltip('Развернуть календарь'));
        await tester.pumpAndSettle();

        await _scrollPageDownAndBack(tester);
        await _recreateCalendar(tester, consumer);

        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        expect(find.text('октябрь 2026 г.'), findsOneWidget);

        await tester.tap(calendarDay(date(2026, 10, 14)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Свернуть календарь'));
        await tester.pumpAndSettle();

        await _scrollPageDownAndBack(tester);
        await _recreateCalendar(tester, consumer);

        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
        expect(find.text('октябрь 2026 г.'), findsOneWidget);

        // Первое перелистывание пересозданного календаря.
        await swipeToNextPeriod(tester);

        expect(consumer.events, [
          ViewportChanged(month(date(2026, 10, 4))),
          DateSelected(date(2026, 10, 14)),
          ViewportChanged(week(date(2026, 10, 14))),
          ViewportChanged(week(date(2026, 10, 21))),
        ]);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 19), 1));
        expect(consumer.selectedDate, date(2026, 10, 14));
      },
    );

    testWidgets(
      'новый календарь показывает неделю просмотра, а не страницу прежнего '
      'экземпляра',
      (tester) async {
        final consumer = await _pumpUnderStoredScroll(tester, viewport: month);
        await swipeToNextPeriod(tester);
        expect(consumer.events, [ViewportChanged(month(date(2026, 11, 1)))]);

        // Без календаря потребитель возвращает просмотр к неделе выбранного
        // дня; прежний экземпляр успел перелистать месяц.
        consumer.removeCalendar();
        await tester.pump();
        consumer.replaceInputs(viewport: week(date(2026, 10, 4)));
        consumer.restoreCalendar();
        await tester.pumpAndSettle();

        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
        expect(find.text('октябрь 2026 г.'), findsOneWidget);

        await tester.tap(calendarDay(date(2026, 10, 2)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Следующая неделя'));
        await tester.pumpAndSettle();

        expect(consumer.events, [
          ViewportChanged(month(date(2026, 11, 1))),
          DateSelected(date(2026, 10, 2)),
          ViewportChanged(week(date(2026, 10, 9))),
        ]);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      },
    );

    testWidgets(
      'пересозданная прокрутка страницы восстанавливает своё смещение после '
      'перелистывания, смены представления и пересоздания календаря',
      (tester) async {
        final consumer = await _pumpUnderStoredScroll(tester, viewport: week);
        // Небольшое смещение оставляет команды и дни календаря на экране.
        _pageScrollPosition(tester).jumpTo(12);
        await tester.pumpAndSettle();

        await swipeToNextPeriod(tester);
        await tester.tap(find.byTooltip('Развернуть календарь'));
        await tester.pumpAndSettle();
        await _recreateCalendar(tester, consumer);
        await tester.tap(find.byTooltip('Следующий месяц'));
        await tester.pumpAndSettle();

        expect(consumer.events, [
          ViewportChanged(week(date(2026, 10, 11))),
          ViewportChanged(month(date(2026, 10, 11))),
          ViewportChanged(month(date(2026, 11, 1))),
        ]);
        expect(_pageScrollPosition(tester).pixels, 12);

        consumer.removeScrollView();
        await tester.pump();
        consumer.restoreScrollView();
        await tester.pumpAndSettle();

        expect(_pageScrollPosition(tester).pixels, 12);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        expect(find.text('ноябрь 2026 г.'), findsOneWidget);
      },
    );
  });
}
