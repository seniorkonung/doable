import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

/// Узкий экран телефона.
const _screen = Size(360, 780);

/// Русский проверяется целиком. Английские подписи дней недели длиннее
/// русских, поэтому дополнительно проверяется свёрнутая неделя на английском.
final _configurations = [
  (locale: const Locale('ru'), full: true),
  (locale: const Locale('en'), full: false),
];

/// Локальное сегодня проверок свёрнутой недели и прокрутки.
final _today = date(2026, 10, 4);

/// Месяцы разной длины с одинаковой шестинедельной сеткой:
/// сегодня и выбранный день — середина месяца.
final _months = [
  (
    name: 'февраль 2027 года',
    today: date(2027, 2, 15),
    weeks: weeksFrom(date(2027, 2, 1), 6),
  ),
  (
    name: 'март 2026 года',
    today: date(2026, 3, 15),
    weeks: weeksFrom(date(2026, 2, 23), 6),
  ),
];

void main() {
  for (final onDate in [false, true]) {
    final catalog = onDate ? 'каталог на дату' : 'корневой каталог';
    for (final cancel in [false, true]) {
      final ending = cancel ? 'системная отмена' : 'медленное отпускание';
      testWidgets('$catalog: $ending короткого сворачивания '
          'восстанавливает конец выдачи', (tester) async {
        final repository = await _openExpandedCatalogAtEnd(tester, onDate);
        final list = find.byType(CustomScrollView);
        final position = tester.state<ScrollableState>(_pageScroll).position;
        final offset = position.pixels;
        final row = find.byKey(const ValueKey('daily-choice-row-20'));
        final rowOffset =
            tester.getTopLeft(row).dy - tester.getTopLeft(list).dy;
        final calendar = find.byType(DailyChoiceCalendar);
        final height = tester.getSize(calendar).height;
        final viewport = tester.widget<DailyChoiceCalendar>(calendar).viewport;

        final gesture = await _startShortCollapse(tester);
        expect(tester.getSize(calendar).height, lessThan(height));
        expect(position.pixels, lessThan(offset));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up(timeStamp: const Duration(seconds: 2));
        }
        await tester.pumpAndSettle();

        expect(tester.getSize(calendar).height, height);
        expect(position.pixels, closeTo(offset, _epsilon));
        expect(
          tester.getTopLeft(row).dy - tester.getTopLeft(list).dy,
          closeTo(rowOffset, _epsilon),
        );
        expect(tester.widget<DailyChoiceCalendar>(calendar).viewport, viewport);
        expect(repository.queries, hasLength(1));
        expect(repository.queries.single.date, _today);
        expect(repository.queries.single.isCompleted, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$catalog: $ending после продолжения движения ручки '
          'сохраняет последнюю отдельную прокрутку выдачи', (tester) async {
        final repository = await _openExpandedCatalogAtEnd(tester, onDate);
        final calendar = find.byType(DailyChoiceCalendar);
        final height = tester.getSize(calendar).height;
        final viewport = tester.widget<DailyChoiceCalendar>(calendar).viewport;
        final list = find.byType(CustomScrollView);
        final position = tester.state<ScrollableState>(_pageScroll).position;
        final originalOffset = position.pixels;
        final gesture = await _startShortCollapse(tester);
        final clampedOffset = position.pixels;

        final scrolling = await tester.startGesture(
          tester.getCenter(list),
          pointer: 2,
        );
        await scrolling.moveBy(const Offset(0, 20));
        for (final elapsed in [20, 40, 60, 80]) {
          await scrolling.moveBy(
            const Offset(0, 5),
            timeStamp: Duration(milliseconds: elapsed),
          );
        }
        await scrolling.up(timeStamp: const Duration(milliseconds: 80));
        final dragOffset = position.pixels;
        await tester.pumpAndSettle();
        final userOffset = position.pixels;
        expect(userOffset, lessThan(dragOffset));
        expect(userOffset, lessThan(clampedOffset));
        final row = find.byKey(const ValueKey('daily-choice-row-20'));
        final rowOffset =
            tester.getTopLeft(row).dy - tester.getTopLeft(list).dy;
        final intermediateHeight = tester.getSize(calendar).height;

        await gesture.moveBy(
          const Offset(0, -60),
          timeStamp: const Duration(seconds: 3),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(calendar).height, lessThan(intermediateHeight));
        expect(position.pixels, lessThan(userOffset));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up(timeStamp: const Duration(seconds: 4));
        }
        await tester.pumpAndSettle();

        expect(tester.getSize(calendar).height, height);
        expect(position.pixels, closeTo(userOffset, _epsilon));
        expect(position.pixels, lessThan(originalOffset));
        expect(
          tester.getTopLeft(row).dy - tester.getTopLeft(list).dy,
          closeTo(rowOffset, _epsilon),
        );
        expect(tester.widget<DailyChoiceCalendar>(calendar).viewport, viewport);
        expect(repository.queries, hasLength(1));
        expect(repository.queries.single.date, _today);
        expect(repository.queries.single.isCompleted, isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$catalog: возврат календаря сохраняет прокрутку выдачи '
        'вторым указателем во время удержания ручки', (tester) async {
      final repository = await _openExpandedCatalogAtEnd(tester, onDate);
      final position = tester.state<ScrollableState>(_pageScroll).position;
      final originalOffset = position.pixels;
      final gesture = await _startShortCollapse(tester);
      final clampedOffset = position.pixels;
      final list = find.byType(CustomScrollView);
      final scrolling = await tester.startGesture(
        tester.getCenter(list),
        pointer: 2,
      );
      await scrolling.moveBy(const Offset(0, 20));
      await scrolling.moveBy(
        const Offset(0, 80),
        timeStamp: const Duration(seconds: 1),
      );
      await scrolling.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final userOffset = position.pixels;
      expect(userOffset, lessThan(clampedOffset));

      await gesture.up(timeStamp: const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(userOffset, _epsilon));
      expect(position.pixels, lessThan(originalOffset));
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$catalog: перетягивание, возврат и смена представления '
        'сдвигают выдачу без сброса прокрутки', (tester) async {
      final repository = CatalogPageRepository();
      await pumpCatalogPage(
        tester,
        repository,
        today: _today,
        catalogDate: onDate ? _today : null,
        locale: const Locale('ru'),
        size: _screen,
      );
      repository.completeFirst(0, [
        for (var number = 1; number <= 20; number++)
          catalogPageItem(number, date: _today),
      ], total: 20);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();
      await swipeToNextPeriod(tester);
      final list = find.byType(CustomScrollView);
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      final firstVisibleRow = find
          .byWidgetPredicate(
            (widget) => switch (widget.key) {
              ValueKey<String>(:final value) => value.startsWith(
                'daily-choice-row-',
              ),
              _ => false,
            },
          )
          .hitTestable()
          .first;
      final row = find.byKey(tester.widget(firstVisibleRow).key!);
      expect(row.hitTestable(), findsOneWidget);
      final rowOffset = tester.getTopLeft(row).dy - tester.getTopLeft(list).dy;
      final calendar = find.byType(DailyChoiceCalendar);

      for (final (distance, expanded) in [
        (40.0, false),
        (200.0, true),
        (-200.0, false),
      ]) {
        final height = tester.getSize(calendar).height;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CalendarHandle)),
        );
        await gesture.moveBy(Offset(0, distance.sign * 20));
        await gesture.moveBy(
          Offset(0, distance),
          timeStamp: const Duration(seconds: 1),
        );
        await tester.pump();
        expect(
          tester.getSize(calendar).height,
          distance > 0 ? greaterThan(height) : lessThan(height),
        );
        expect(position.pixels, offset);
        expect(
          tester.getTopLeft(row).dy - tester.getTopLeft(list).dy,
          closeTo(rowOffset, 0.01),
        );
        expect(repository.queries, hasLength(1));
        await gesture.up(timeStamp: const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(position.pixels, offset);
        expect(
          tester.getTopLeft(row).dy - tester.getTopLeft(list).dy,
          closeTo(rowOffset, 0.01),
        );
        expect(
          visibleWeeks(tester),
          weeksFrom(
            expanded ? date(2026, 9, 28) : date(2026, 10, 5),
            expanded ? 6 : 1,
          ),
        );
        expect(repository.queries, hasLength(1));
      }

      final calendarRect = tester.getRect(calendar);
      await tester.drag(list, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(offset));
      expect(tester.getRect(calendar), calendarRect);
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('постороннее изменение графа во время удержания ручки '
      'сохраняет восстановление неизменившейся выдачи', (tester) async {
    final repository = await _openExpandedCatalogAtEnd(tester, false);
    final position = tester.state<ScrollableState>(_pageScroll).position;
    final offset = position.pixels;
    final gesture = await _startShortCollapse(tester);
    final coordinator = ProviderScope.containerOf(
      tester.element(find.byType(DailyChoiceCalendar)),
    ).read(graphCommandCoordinatorProvider.notifier);
    await repository.confirmTagRename(coordinator, revision: 1);
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(position.pixels, closeTo(offset, _epsilon));
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final (:locale, :full) in _configurations) {
    final language = locale.languageCode;

    group('экран 360×780, $language', () {
      testWidgets('свёрнутая неделя занимает семь колонок во всю ширину, '
          'тексты страницы показаны целиком, а дни и команды нажимаются', (
        tester,
      ) async {
        final repository = CatalogPageRepository();
        await _open(tester, repository, locale, today: _today);
        repository.completeFirst(0, [
          catalogPageItem(1, date: _today),
        ], total: 1);
        await tester.pumpAndSettle();
        _expectColumns(tester, weeksFrom(date(2026, 9, 28), 1));
        _expectCommands(tester);
        expect(
          find.descendant(
            of: find.byType(DayHeading),
            matching: find.text(_selectedDateLabel(tester, _today)),
          ),
          findsOneWidget,
        );
        await _expectWholeTexts(tester);

        await swipeToNextPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
        await swipeToPreviousPeriod(tester);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));

        final day = date(2026, 10, 1);
        _expectReachable(tester, calendarDay(day));
        _expectTappable(tester, calendarDay(day));
        await tester.tap(calendarDay(day));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      if (!full) return;

      for (final shown in _months) {
        testWidgets('раскрытый ${shown.name} увеличивает высоту календаря '
            'на свои строки и сдвигает выдачу, все дни нажимаются, а '
            'сворачивание возвращает прежнюю высоту', (tester) async {
          final repository = CatalogPageRepository();
          await _open(tester, repository, locale, today: shown.today);
          repository.completeFirst(0, [
            catalogPageItem(1, date: shown.today),
          ], total: 1);
          await tester.pumpAndSettle();
          final l10n = _l10n(tester);
          final week = _measure(tester);
          expect(week.rows, 1);

          await _tapCommand(tester, l10n.dailyChoiceCalendarExpand);
          final month = _measure(tester);
          expect(visibleWeeks(tester), shown.weeks);
          expect(month.rows, shown.weeks.length);
          expect(week.rowHeight, greaterThanOrEqualTo(54));
          expect(month.rowHeight, moreOrLessEquals(44));
          // Неделя и месяц используют разные высоты строк и подписи.
          // Выдача сдвигается ровно на прирост высоты календаря.
          final grown = month.calendar.height - week.calendar.height;
          expect(grown, greaterThan(0));
          expect(month.countOffset - week.countOffset, moreOrLessEquals(grown));
          // Месяц раскрывается внутри страницы: прокрутка остаётся одной.
          expect(_pageScroll, findsOneWidget);
          _expectColumns(tester, shown.weeks);
          _expectCommands(tester);
          await _expectWholeTexts(tester);

          for (final row in shown.weeks) {
            _expectReachable(tester, calendarDay(row.first));
            for (final day in row) {
              _expectTappable(tester, calendarDay(day));
            }
          }
          // Последний день самого месяца: день соседнего месяца перенёс бы
          // просмотр в свой месяц.
          final lastDay = shown.weeks
              .expand((week) => week)
              .lastWhere((day) => day.month == shown.today.month);
          _expectReachable(tester, calendarDay(lastDay));
          await tester.tap(calendarDay(lastDay));
          await tester.pump();
          repository.completeFirst(1, [
            catalogPageItem(2, date: lastDay),
          ], total: 1);
          await _settle(tester);
          expect(visibleWeeks(tester), shown.weeks);
          expect(
            find.bySemanticsLabel(l10n.dailyChoiceCalendarCollapse),
            findsOneWidget,
          );

          // Подпись нового выбранного дня может занять другое число строк,
          // поэтому сворачивание сравнивается с раскрытым после выбора.
          final selected = _measure(tester);
          await _tapCommand(tester, l10n.dailyChoiceCalendarCollapse);
          final collapsed = _measure(tester);
          expect(collapsed.rows, 1);
          expect(
            selected.calendar.height - collapsed.calendar.height,
            moreOrLessEquals(grown),
          );
          expect(
            selected.countOffset - collapsed.countOffset,
            moreOrLessEquals(grown),
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('календарь закреплён над единственной прокруткой: '
          'вертикальный жест по нему не двигает выдачу, горизонтальный листает неделю, '
          'а фильтры, подгрузка и последняя строка достижимы жестами над '
          'панелью без зарезервированного места', (tester) async {
        final repository = CatalogPageRepository();
        await _open(tester, repository, locale, today: _today);
        repository.completeFirst(
          0,
          [
            for (var number = 1; number <= 20; number++)
              catalogPageItem(number, date: _today),
          ],
          total: 21,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        expect(_pageScroll, findsOneWidget);
        final scroll = tester.state<ScrollableState>(_pageScroll).position;

        final day = calendarDay(date(2026, 10, 1));
        _expectReachable(tester, day);
        final before = scroll.pixels;
        final calendarRect = tester.getRect(find.byType(DailyChoiceCalendar));
        await tester.drag(day, const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(scroll.pixels, before);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));

        _expectReachable(tester, day);
        final scrolled = scroll.pixels;
        // Больше половины, но меньше ширины недели.
        await tester.drag(day, const Offset(-200, 0));
        await tester.pumpAndSettle();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
        expect(scroll.pixels, scrolled);

        await tester.drag(_pageScroll, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(scroll.pixels, greaterThan(scrolled));
        expect(tester.getRect(find.byType(DailyChoiceCalendar)), calendarRect);
        expect(find.byType(DayHeading).hitTestable(), findsNothing);

        for (final key in _filterKeys) {
          await _dragUntilReachable(
            tester,
            find.byKey(ValueKey(key), skipOffstage: false),
          );
        }
        final loadMore = find.byKey(
          const ValueKey('daily-choice-load-more'),
          skipOffstage: false,
        );
        await _dragUntilReachable(tester, loadMore);
        await tester.tap(loadMore);
        await tester.pump();
        repository.completeMore(1, [catalogPageItem(21, date: _today)]);
        await tester.pumpAndSettle();

        final lastRow = find.byKey(
          const ValueKey('daily-choice-row-21'),
          skipOffstage: false,
        );
        await _dragToEnd(tester);
        _expectAtEnd(tester, lastRow);
        await _expectWholeTexts(tester);
        await _dragUntilReachable(
          tester,
          find.bySemanticsLabel(
            l10n.dailyChoiceCalendarExpand,
            skipOffstage: false,
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('смена выбранного дня возвращает выдачу к заголовку, '
          'а повторный выбор, просмотр и раскрытие сохраняют смещение', (
        tester,
      ) async {
        final repository = CatalogPageRepository();
        await _open(tester, repository, locale, today: _today);
        final items = [
          for (var number = 1; number <= 20; number++)
            catalogPageItem(number, date: _today),
        ];
        repository.completeFirst(0, items, total: 20);
        await tester.pumpAndSettle();
        final headingTop = tester.getTopLeft(find.byType(DayHeading)).dy;
        final scroll = tester.state<ScrollableState>(_pageScroll).position;
        await tester.drag(_pageScroll, const Offset(0, -350));
        await tester.pumpAndSettle();
        final offset = scroll.pixels;
        expect(offset, greaterThan(0));

        await tester.tap(calendarDay(_today));
        await tester.pumpAndSettle();
        expect(scroll.pixels, offset);
        expect(repository.queries, hasLength(1));
        await swipeToNextPeriod(tester);
        expect(scroll.pixels, offset);
        await _tapCommand(tester, _l10n(tester).dailyChoiceCalendarExpand);
        expect(scroll.pixels, offset);
        final expandedTop = tester.getTopLeft(find.byType(DailyChoiceCalendar));
        await tester.drag(_pageScroll, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(DailyChoiceCalendar)),
          expandedTop,
        );
        await _tapCommand(tester, _l10n(tester).dailyChoiceCalendarCollapse);

        final nextDay = date(2026, 10, 9);
        await tester.tap(calendarDay(nextDay));
        // Быстрый ответ не оставляет кадра с короткой загрузкой, который
        // сам ограничил бы смещение прокрутки до нуля.
        repository.completeFirst(1, [
          for (var number = 1; number <= 20; number++)
            catalogPageItem(number, date: nextDay),
        ], total: 20);
        await tester.pumpAndSettle();
        expect(find.byType(DayHeading).hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(find.byType(DayHeading)).dy, headingTop);
        expect(find.text('9 октября 2026'), findsOneWidget);
        _expectReachable(
          tester,
          find.byKey(const ValueKey('daily-choice-row-1')),
        );
        expect(scroll.pixels, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('начальные загрузка и отказ, отказ повтора и пустая '
          'выдача показаны целиком и достижимы жестами над панелью', (
        tester,
      ) async {
        final repository = CatalogPageRepository();
        await _open(tester, repository, locale, today: _today);
        final l10n = _l10n(tester);
        final retry = find.widgetWithText(
          TextButton,
          l10n.commonRetry,
          skipOffstage: false,
        );

        await _dragUntilReachable(
          tester,
          find.text(l10n.dailyChoiceCatalogLoading, skipOffstage: false),
        );
        await _expectWholeTexts(tester);

        for (final attempt in [0, 1]) {
          repository.failUnavailable(attempt);
          await tester.pumpAndSettle();
          await _dragUntilReachable(
            tester,
            find.text(l10n.dailyChoiceCatalogUnavailable, skipOffstage: false),
          );
          await _dragUntilReachable(tester, retry);
          await _expectWholeTexts(tester);
          await tester.tap(retry);
          await tester.pump();
        }

        repository.completeFirst(2, [], total: 0);
        await tester.pumpAndSettle();
        await _dragUntilReachable(
          tester,
          find.text(l10n.dailyChoiceCatalogTotalCount(0), skipOffstage: false),
        );
        await _dragUntilReachable(
          tester,
          find.text(l10n.dailyChoiceCatalogEmpty, skipOffstage: false),
        );
        await _expectWholeTexts(tester);
        await _dragUntilReachable(tester, calendarDay(date(2026, 10, 1)));
        expect(tester.takeException(), isNull);
      });

      testWidgets('фильтр выполнения показывает название и каждое '
          'состояние целиком, а меню выбирает состояние для выбранного дня', (
        tester,
      ) async {
        final repository = CatalogPageRepository();
        await _open(tester, repository, locale, today: _today);
        repository.completeFirst(0, [], total: 0);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        final filter = find.byKey(
          const ValueKey('daily-choice-completion-filter'),
          skipOffstage: false,
        );

        for (final (index, (value, state)) in [
          (false, l10n.dailyChoiceCatalogIncomplete),
          (true, l10n.dailyChoiceCatalogCompleted),
          (null, l10n.dailyChoiceCatalogAllStates),
        ].indexed) {
          await _dragUntilReachable(tester, filter);
          await tester.tap(filter);
          await tester.pumpAndSettle();
          final item = find
              .byWidgetPredicate(
                (widget) =>
                    widget is DropdownMenuItem<bool?> && widget.value == value,
              )
              .last;
          _expectTappable(tester, item);
          _expectWholeTextsIn(tester, item);
          await tester.tap(item);
          await tester.pump();
          repository.completeFirst(index + 1, [], total: 0);
          await tester.pumpAndSettle();

          await _dragUntilReachable(tester, filter);
          expect(
            find.descendant(of: filter, matching: find.text(state)),
            findsOneWidget,
          );
          await _expectWholeTexts(tester);
        }
        expect(tester.takeException(), isNull);
      });
    });
  }
}

Future<CatalogPageRepository> _openExpandedCatalogAtEnd(
  WidgetTester tester,
  bool onDate,
) async {
  final repository = CatalogPageRepository();
  await pumpCatalogPage(
    tester,
    repository,
    today: _today,
    catalogDate: onDate ? _today : null,
    locale: const Locale('ru'),
    size: _screen,
  );
  repository.completeFirst(0, [
    for (var number = 1; number <= 20; number++)
      catalogPageItem(number, date: _today),
  ], total: 20);
  repository.completeDayStatuses(0, {});
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CalendarHandle));
  await tester.pumpAndSettle();
  await _dragToEnd(tester);
  final position = tester.state<ScrollableState>(_pageScroll).position;
  expect(position.pixels, closeTo(position.maxScrollExtent, _epsilon));
  return repository;
}

Future<TestGesture> _startShortCollapse(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(CalendarHandle)),
    pointer: 1,
  );
  await gesture.moveBy(const Offset(0, -20));
  await gesture.moveBy(
    const Offset(0, -40),
    timeStamp: const Duration(seconds: 1),
  );
  await tester.pumpAndSettle();
  return gesture;
}

/// Допуск сравнения координат.
const _epsilon = 0.01;

/// Фильтры каталога под календарём: выполнение и сброс.
const _filterKeys = [
  'daily-choice-completion-filter',
  'daily-choice-clear-filters',
];

/// Единственная вертикальная прокрутка выдачи под календарём.
final _pageScroll = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
  ),
);

/// Открывает каталог на узком телефоне; первое чтение остаётся незавершённым.
Future<void> _open(
  WidgetTester tester,
  CatalogPageRepository repository,
  Locale locale, {
  required CalendarDate today,
}) => pumpCatalogPage(
  tester,
  repository,
  today: today,
  locale: locale,
  size: _screen,
);

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(DailyChoiceCalendar, skipOffstage: false)),
);

/// Полная выбранная дата в заголовке дня по текущей локали.
String _selectedDateLabel(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(DailyChoiceCalendar));
  return DateFormat(
    'd MMMM y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(value.year, value.month, value.day));
}

/// Видимая часть страницы: под строкой состояния и над основной навигацией.
Rect _visibleArea(WidgetTester tester) {
  final safeTop = MediaQuery.paddingOf(
    tester.element(find.byType(DailyChoiceCalendar)),
  ).top;
  final bar = tester.getRect(find.byType(AppNavigationBar));
  expect(find.byType(FloatingActionButton), findsNothing);
  return Rect.fromLTRB(0, safeTop, _screen.width, bar.top);
}

/// Область жестов по выдаче исключает закреплённый календарь.
Rect _listArea(WidgetTester tester) {
  final area = _visibleArea(tester);
  final calendar = tester.getRect(find.byType(DailyChoiceCalendar));
  return Rect.fromLTRB(area.left, calendar.bottom, area.right, area.bottom);
}

/// Элемент [finder] целиком лежит над панелью, и касание его середины достигает его.
void _expectReachable(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  expect(
    _contains(_visibleArea(tester), rect),
    isTrue,
    reason: '$finder: $rect вне видимой части ${_visibleArea(tester)}',
  );
  _expectTappable(tester, finder);
}

/// Последний элемент выдачи [finder] на прокрученной до конца странице
/// заканчивается у верхнего края панели, и касание его видимой
/// части достигает его. Длинная строка выше видимой части
/// страницы, поэтому целиком она видна только по частям при прокрутке.
void _expectAtEnd(WidgetTester tester, Finder finder) {
  final area = _visibleArea(tester);
  final rect = tester.getRect(finder);
  expect(rect.bottom, moreOrLessEquals(area.bottom, epsilon: _epsilon));
  expect(rect.bottom, greaterThan(area.top));
  _expectHit(tester, finder, rect.intersect(area).center);
}

/// Прокручивает страницу жестами по видимой части, пока [finder] не окажется
/// в ней целиком, и проверяет его достижимость.
///
/// [finder] находит элемент и за краем видимой части; ещё не построенная
/// строка выдачи лежит ниже построенных и далеко, поэтому к ней страница
/// листается крупнее.
Future<void> _dragUntilReachable(WidgetTester tester, Finder finder) async {
  for (var step = 0; step < 200; step++) {
    final isBuilt = finder.evaluate().isNotEmpty;
    final inList = find
        .ancestor(of: finder, matching: _pageScroll)
        .evaluate()
        .isNotEmpty;
    final area = !isBuilt || inList ? _listArea(tester) : _visibleArea(tester);
    if (isBuilt && _contains(area, tester.getRect(finder))) {
      _expectReachable(tester, finder);
      return;
    }
    final double shift = !isBuilt
        ? -300
        : tester.getRect(finder).bottom > area.bottom
        ? -120
        : 120;
    final listArea = _listArea(tester);
    await tester.dragFrom(
      Offset(listArea.left + 24, listArea.center.dy),
      Offset(0, shift),
    );
    await _settle(tester);
  }
  fail('Жестами не удалось целиком показать $finder.');
}

/// Прокручивает страницу жестами до конца выдачи.
Future<void> _dragToEnd(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  for (var step = 0; step < 200; step++) {
    if (scroll.pixels >= scroll.maxScrollExtent - _epsilon) return;
    final area = _listArea(tester);
    await tester.dragFrom(
      Offset(area.left + 24, area.center.dy),
      const Offset(0, -300),
    );
    await _settle(tester);
  }
  fail('Жестами не удалось дойти до конца выдачи.');
}

/// Доводит до конца прокрутку и перелистывание календаря. Индикатор загрузки
/// выдачи не даёт дождаться покоя всех анимаций, поэтому время продвигается
/// явно.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Выполняет команду закреплённого календаря касанием.
Future<void> _tapCommand(WidgetTester tester, String name) async {
  _expectReachable(tester, find.bySemanticsLabel(name, skipOffstage: false));
  final command = find.bySemanticsLabel(name);
  _expectTappable(tester, command);
  await tester.tap(command);
  await _settle(tester);
}

/// Касание середины [finder] на экране достигает его, а не другого элемента.
void _expectTappable(WidgetTester tester, Finder finder) => _expectHit(
  tester,
  finder,
  _globalRect(tester.renderObject<RenderBox>(finder)).center,
);

/// Касание экрана в точке [position] достигает [finder], а не другого
/// элемента.
void _expectHit(WidgetTester tester, Finder finder, Offset position) {
  final box = tester.renderObject<RenderBox>(finder);
  expect(
    (Offset.zero & _screen).contains(position),
    isTrue,
    reason: 'Точка касания $finder вне экрана: $position',
  );
  expect(
    tester
        .hitTestOnBinding(position)
        .path
        .any((entry) => identical(entry.target, box)),
    isTrue,
    reason: 'Касание в $position не достигает $finder',
  );
}

/// Положение календаря и выдачи под ним в общей прокрутке.
///
/// [countOffset] — расстояние от верха календаря до количества выдачи; оно не
/// зависит от прокрутки страницы.
typedef _Layout = ({
  Rect calendar,
  int rows,
  double rowHeight,
  double countOffset,
});

_Layout _measure(WidgetTester tester) {
  final calendar = _rect(
    tester,
    find.byType(DailyChoiceCalendar, skipOffstage: false),
  );
  final weeks = visibleWeeks(tester);
  final firstDay = _rect(
    tester,
    calendarDay(weeks.first.firstWhere((day) => day != null)!),
  );
  final count = _rect(
    tester,
    find.text(
      _l10n(tester).dailyChoiceCatalogTotalCount(1),
      skipOffstage: false,
    ),
  );
  return (
    calendar: calendar,
    rows: weeks.length,
    rowHeight: firstDay.height,
    countOffset: count.top - calendar.top,
  );
}

/// Видимые недели календаря — семь смежных колонок во всю ширину экрана;
/// строки одна под другой, каждая ячейка не меньше области нажатия.
void _expectColumns(WidgetTester tester, List<List<CalendarDate>> weeks) {
  expect(visibleWeeks(tester), weeks);
  final calendar = _rect(
    tester,
    find.byType(DailyChoiceCalendar, skipOffstage: false),
  );
  expect(calendar.left, moreOrLessEquals(0));
  expect(calendar.right, moreOrLessEquals(_screen.width));
  final rows = [
    for (final week in weeks)
      [for (final day in week) _rect(tester, calendarDay(day))],
  ];
  for (final (index, row) in rows.indexed) {
    expect(row, hasLength(DateTime.daysPerWeek));
    expect(row.first.left, moreOrLessEquals(calendar.left));
    expect(row.last.right, moreOrLessEquals(calendar.right));
    for (final (column, cell) in row.indexed) {
      expect(cell.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(cell.height, greaterThanOrEqualTo(44));
      expect(cell.top, moreOrLessEquals(row.first.top));
      if (column > 0) {
        expect(cell.left, moreOrLessEquals(row[column - 1].right));
      }
    }
    if (index > 0) {
      expect(row.first.top, moreOrLessEquals(rows[index - 1].first.bottom));
    }
  }
  expect(rows.last.last.bottom, lessThanOrEqualTo(calendar.bottom + _epsilon));
}

/// Команды месяца сохраняют область нажатия, ручка занимает полосу 36 dp.
void _expectCommands(WidgetTester tester) {
  final calendar = find.byType(DailyChoiceCalendar, skipOffstage: false);
  final isExpanded =
      tester.widget<DailyChoiceCalendar>(calendar).viewport.mode ==
      DailyChoiceCalendarMode.month;
  final texts = AppLocalizations.of(tester.element(calendar));
  final handleName = isExpanded
      ? texts.dailyChoiceCalendarCollapse
      : texts.dailyChoiceCalendarExpand;
  final names = [
    if (isExpanded) ...[
      texts.dailyChoiceCalendarPreviousMonth,
      texts.dailyChoiceCalendarNextMonth,
    ],
    handleName,
  ];
  for (final name in names) {
    final command = find.bySemanticsLabel(name, skipOffstage: false);
    expect(command, findsOneWidget);
    final rect = _globalRect(tester.renderObject<RenderBox>(command));
    expect(rect.left, greaterThanOrEqualTo(-_epsilon));
    expect(rect.right, lessThanOrEqualTo(_screen.width + _epsilon));
    expect(rect.width, greaterThanOrEqualTo(DoableMetrics.tapMin));
    expect(
      rect.height,
      name == handleName
          ? equals(36)
          : greaterThanOrEqualTo(DoableMetrics.tapMin),
    );
  }
}

/// Проходит общую прокрутку страницы от начала до конца и проверяет каждый
/// построенный текст календаря, фильтров и выдачи: он показан целиком в
/// ширине экрана. Затем возвращает прежнее положение прокрутки.
Future<void> _expectWholeTexts(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  final initial = scroll.pixels;
  _expectWholeTextsIn(tester, find.byType(DailyChoiceCalendar));
  var offset = scroll.minScrollExtent;
  while (true) {
    scroll.jumpTo(offset);
    await tester.pump();
    _expectWholeTextsIn(
      tester,
      find.byType(CustomScrollView, skipOffstage: false),
    );
    if (offset >= scroll.maxScrollExtent) break;
    offset = (offset + 200).clamp(
      scroll.minScrollExtent,
      scroll.maxScrollExtent,
    );
  }
  scroll.jumpTo(initial);
  await tester.pump();
}

/// Каждый текст внутри [scope] показан целиком: без многоточия и потери
/// строк, со всей высотой строк при своей ширине и в ширине экрана.
void _expectWholeTextsIn(WidgetTester tester, Finder scope) {
  // Значки рисуются глифом шрифта без масштаба текста, поэтому проверяются
  // только тексты.
  final paragraphs = find.descendant(
    of: find.descendant(
      of: scope,
      matching: find.byType(Text, skipOffstage: false),
    ),
    matching: find.byType(RichText, skipOffstage: false),
  );
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.attached || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '«$text» обрезан');
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width) - _epsilon,
      ),
      reason: '«$text»: часть строк не помещается',
    );
    if (!paragraph.softWrap) {
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicWidth(double.infinity) - _epsilon,
        ),
        reason: '«$text» не помещается в строку',
      );
    }

    final rect = _globalRect(paragraph);
    expect(rect.left, greaterThanOrEqualTo(-_epsilon), reason: '«$text»');
    expect(
      rect.right,
      lessThanOrEqualTo(_screen.width + _epsilon),
      reason: '«$text»',
    );
  }
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - _epsilon &&
    inner.top >= outer.top - _epsilon &&
    inner.right <= outer.right + _epsilon &&
    inner.bottom <= outer.bottom + _epsilon;

Rect _rect(WidgetTester tester, Finder finder) =>
    _globalRect(tester.renderObject<RenderBox>(finder));

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
