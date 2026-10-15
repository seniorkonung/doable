import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  testWidgets('страницы лет следуют за удерживаемым жестом в обе стороны '
      'с постоянной высотой и без событий календаря', (tester) async {
    final selected = date(2026, 10, 8);
    final viewport = month(selected);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: viewport,
      today: selected,
    );
    await _command(tester, 'Выбрать год и месяц');
    final handle = find.bySemanticsLabel('Свернуть календарь');
    final handleTop = tester.getTopLeft(handle).dy;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    for (final (outgoing, incoming, direction, title) in const [
      ('2025', '2032', -1, '2032–2043'),
      ('2032', '2031', 1, '2020–2031'),
    ]) {
      final year = find.text(outgoing);
      final initialX = tester.getCenter(year).dx;
      final gesture = await tester.startGesture(tester.getCenter(year));
      await gesture.moveBy(Offset(direction * 24, 0));
      await tester.pump();
      await gesture.moveBy(Offset(direction * width * 0.25, 0));
      await tester.pump();
      final movedX = tester.getCenter(year).dx;
      expect(movedX, closeTo(initialX + direction * width * 0.25, 1));
      expect(
        tester.getCenter(find.text(incoming)).dx,
        inExclusiveRange(0, width),
      );
      expect(tester.getTopLeft(handle).dy, handleTop);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getCenter(year).dx, movedX);
      await gesture.moveBy(Offset(direction * width * 0.4, 0));
      await tester.pump();
      expect(find.text(title), findsOneWidget);
      expect(tester.getTopLeft(handle).dy, handleTop);
      expect(consumer.events, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(consumer.viewport, viewport);
    expect(consumer.selectedDate, selected);
    expect(consumer.events, isEmpty);
  });

  testWidgets('стрелки плавно перемещают страницы лет в обе стороны '
      'без изменения высоты и просмотра', (tester) async {
    final selected = date(2026, 10, 8);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: month(selected),
      today: selected,
    );
    await _command(tester, 'Выбрать год и месяц');
    final handle = find.bySemanticsLabel('Свернуть календарь');
    final handleTop = tester.getTopLeft(handle).dy;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final (outgoing, incoming, direction, command, title) in const [
      ('2025', '2032', -1, 'Следующие годы', '2032–2043'),
      ('2032', '2031', 1, 'Предыдущие годы', '2020–2031'),
    ]) {
      final year = find.text(outgoing);
      final initialX = tester.getCenter(year).dx;
      await tester.tap(find.bySemanticsLabel(command));
      await tester.pump();
      expect(tester.getCenter(year).dx, initialX);
      await tester.pump(const Duration(milliseconds: 60));
      final movedX = tester.getCenter(year).dx;
      expect((movedX - initialX) * direction, greaterThan(0));
      expect(
        tester.getCenter(find.text(incoming)).dx,
        inExclusiveRange(0, width),
      );
      expect(tester.getTopLeft(handle).dy, handleTop);
      await tester.pump(const Duration(milliseconds: 60));
      expect((tester.getCenter(year).dx - movedX) * direction, greaterThan(0));
      expect(tester.getTopLeft(handle).dy, handleTop);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(consumer.viewport, month(selected));
    expect(consumer.selectedDate, selected);
    expect(consumer.events, isEmpty);
  });

  testWidgets('стрелки плавно перемещают месяцы 2028 → 2029 и обратно '
      'без изменения высоты и просмотра', (tester) async {
    final selected = date(2026, 10, 8);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: month(selected),
      today: selected,
    );
    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2028'));
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel('Свернуть календарь');
    final handleTop = tester.getTopLeft(handle).dy;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    for (final (outgoing, incoming, direction, command, title) in const [
      ('Апрель 2028', 'Январь 2029', -1, 'Следующий год', '2029'),
      ('Январь 2029', 'Декабрь 2028', 1, 'Предыдущий год', '2028'),
    ]) {
      final cell = find.bySemanticsLabel(outgoing);
      final initialX = tester.getCenter(cell).dx;
      await tester.tap(find.bySemanticsLabel(command));
      await tester.pump();
      expect(tester.getCenter(cell).dx, initialX);
      await tester.pump(const Duration(milliseconds: 60));
      final movedX = tester.getCenter(cell).dx;
      expect((movedX - initialX) * direction, greaterThan(0));
      expect(
        tester.getCenter(find.bySemanticsLabel(incoming)).dx,
        inExclusiveRange(0, width),
      );
      expect(tester.getTopLeft(handle).dy, handleTop);
      await tester.pump(const Duration(milliseconds: 60));
      expect((tester.getCenter(cell).dx - movedX) * direction, greaterThan(0));
      expect(tester.getTopLeft(handle).dy, handleTop);
      expect(find.text(title), findsOneWidget);
      expect(consumer.events, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(consumer.viewport, month(selected));
    expect(consumer.selectedDate, selected);
    expect(consumer.events, isEmpty);
  });

  for (final fromMonths in [false, true]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    testWidgets('повторная стрелка и смена направления во время перехода '
        '$level оставляют страницу последней команды', (tester) async {
      final selected = date(2026, 10, 8);
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: selected,
        viewport: month(selected),
        today: selected,
      );
      await _command(tester, 'Выбрать год и месяц');
      if (fromMonths) {
        await tester.tap(find.text('2028'));
        await tester.pumpAndSettle();
      }
      final next = fromMonths ? 'Следующий год' : 'Следующие годы';
      await tester.tap(find.bySemanticsLabel(next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.bySemanticsLabel(next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(fromMonths ? '2029' : '2032–2043'), findsOneWidget);
      await _command(tester, fromMonths ? 'Предыдущий год' : 'Предыдущие годы');
      expect(find.text(fromMonths ? '2028' : '2020–2031'), findsOneWidget);
      expect(consumer.events, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (fromMonths, action) in [
    (false, 'заголовок'),
    (false, 'ручка'),
    (false, 'выбор года'),
    (true, 'заголовок'),
    (true, 'ручка'),
    (true, 'выбор месяца'),
  ]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    final selectPeriod = action == 'выбор года' || action == 'выбор месяца';
    testWidgets('$action прерывает переход $level без поздних событий '
        'и исключений', (tester) async {
      final semantics = tester.ensureSemantics();
      final selected = date(2026, 10, 8);
      final viewport = month(date(2026, 11, 15));
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: selected,
        viewport: viewport,
        today: selected,
      );
      await _command(tester, 'Выбрать год и месяц');
      if (fromMonths) {
        await tester.tap(find.text('2028'));
        await tester.pumpAndSettle();
      }
      if (selectPeriod) {
        final cell = find.text(fromMonths ? 'Март' : '2028');
        for (var tab = 0; tab < 16; tab++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          if (Focus.of(tester.element(cell)).hasFocus) {
            break;
          }
        }
      }
      final next = tester.getSemantics(
        find.bySemanticsLabel(fromMonths ? 'Следующий год' : 'Следующие годы'),
      );
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        next.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text(fromMonths ? '2029' : '2032–2043'), findsOneWidget);
      if (selectPeriod) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        final command = action == 'заголовок'
            ? 'Вернуться к дням месяца'
            : 'Свернуть календарь';
        final node = tester.getSemantics(find.bySemanticsLabel(command));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
      }
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));

      if (action == 'выбор года') {
        expect(find.text('2028'), findsOneWidget);
        expect(find.text('Январь'), findsOneWidget);
        expect(visibleWeeks(tester), isEmpty);
      } else if (action == 'выбор месяца') {
        expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 6));
      } else {
        expect(
          visibleWeeks(tester),
          action == 'ручка'
              ? weeksFrom(date(2026, 11, 9), 1)
              : weeksFrom(date(2026, 10, 26), 6),
        );
      }
      expect(consumer.events, switch (action) {
        'ручка' => [ViewportChanged(week(viewport.focusedDate))],
        'выбор месяца' => [MonthSelectionCompleted(month(date(2028, 3, 1)))],
        _ => isEmpty,
      });
      expect(consumer.selectedDate, selected);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final fromMonths in [false, true]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    testWidgets('перестроение, отметки, сегодня, тема и локаль сохраняют '
        'пролистанную страницу $level без событий календаря', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final selected = date(2026, 10, 8);
      final viewport = month(date(2026, 11, 1));
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: selected,
        viewport: viewport,
        today: selected,
      );
      await _command(tester, 'Выбрать год и месяц');
      await tester.drag(find.text('2025'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      if (fromMonths) {
        await tester.tap(find.text('2035'));
        await tester.pumpAndSettle();
        await _command(tester, 'Следующий год');
      }
      final title = fromMonths ? '2036' : '2032–2043';
      consumer.rebuild();
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      consumer.replaceInputs(
        today: date(2026, 10, 9),
        dayStatuses: {selected: DailyChoiceDayStatus.allCompleted},
        hasDayMarksReadFailure: true,
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text('Отметки дней не загружены.'), findsOneWidget);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text(title))).brightness,
        Brightness.dark,
      );
      expect(find.text(title), findsOneWidget);

      for (final (locale, january, back) in const [
        (Locale('en'), 'January', 'Back to the days of the month'),
        (Locale('ru'), 'Январь', 'Вернуться к дням месяца'),
      ]) {
        tester.platformDispatcher.localesTestValue = [locale];
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text(january), fromMonths ? findsOneWidget : findsNothing);
        expect(
          find.bySemanticsLabel(fromMonths ? '$january 2036' : '2032'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(back), findsOneWidget);
        expect(visibleWeeks(tester), isEmpty);
        expect(consumer.viewport, viewport);
        expect(consumer.selectedDate, selected);
        expect(consumer.events, isEmpty);
      }

      await _command(tester, 'Вернуться к дням месяца');
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(consumer.events, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор марта 2028 из октября 2026 сообщает только итоговый '
      'просмотр и сворачивается к 28 февраля — 5 марта', (tester) async {
    final selected = date(2026, 10, 8);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: month(selected),
      today: selected,
    );

    await _command(tester, 'Выбрать год и месяц');
    expect(find.text('2020–2031'), findsOneWidget);
    expect(visibleWeeks(tester), isEmpty);
    await _command(tester, 'Следующие годы');
    expect(find.text('2032–2043'), findsOneWidget);
    await _command(tester, 'Предыдущие годы');
    await tester.tap(find.text('2028'));
    await tester.pumpAndSettle();
    await _command(tester, 'Следующий год');
    expect(find.text('2029'), findsOneWidget);
    await _command(tester, 'Предыдущий год');
    expect(find.text('2028'), findsOneWidget);
    await tester.drag(find.text('Март'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('2028'), findsOneWidget);
    expect(consumer.events, isEmpty);

    await tester.tap(find.text('Март'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 6));
    expect(consumer.events, [MonthSelectionCompleted(month(date(2028, 3, 1)))]);
    expect(consumer.selectedDate, selected);

    await _command(tester, 'Свернуть календарь');
    expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 1));
    expect(consumer.events, [
      MonthSelectionCompleted(month(date(2028, 3, 1))),
      ViewportChanged(week(date(2028, 3, 1))),
    ]);
    expect(consumer.selectedDate, selected);

    await swipeToNextPeriod(tester);
    expect(visibleWeeks(tester), weeksFrom(date(2028, 3, 6), 1));
  });

  testWidgets('возврат к месяцу выбранной даты восстанавливает её неделю', (
    tester,
  ) async {
    final selected = date(2026, 10, 15);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: month(date(2026, 11, 1)),
      today: selected,
    );

    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Октябрь'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
    expect(dayCell(tester, selected).isSelected, isTrue);
    expect(consumer.events, [MonthSelectionCompleted(month(selected))]);

    await _command(tester, 'Свернуть календарь');
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
    expect(consumer.selectedDate, selected);
  });

  testWidgets('повторный выбор месяца сообщает одно завершение при равном '
      'просмотре', (tester) async {
    final viewport = month(date(2026, 11, 1));
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 8),
      viewport: viewport,
      today: date(2026, 10, 8),
    );

    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ноябрь'));
    await tester.pumpAndSettle();

    expect(consumer.events, [MonthSelectionCompleted(viewport)]);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
  });

  // Оба уровня используют одно закрытие: диагональ покрывает уровни и команды.
  for (final (fromMonths, collapse) in [(false, false), (true, true)]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    final action = collapse ? 'ручкой' : 'заголовком';
    testWidgets('отмена со страницы $level $action сохраняет прежнюю дату '
        'просмотра', (tester) async {
      final focused = date(2026, 11, 15);
      final selected = date(2026, 10, 8);
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: selected,
        viewport: month(focused),
        today: selected,
      );
      await _command(tester, 'Выбрать год и месяц');
      await _command(tester, 'Следующие годы');
      if (fromMonths) {
        await tester.tap(find.text('2035'));
        await tester.pumpAndSettle();
      }
      expect(consumer.events, isEmpty);

      await _command(
        tester,
        collapse ? 'Свернуть календарь' : 'Вернуться к дням месяца',
      );
      expect(
        visibleWeeks(tester),
        weeksFrom(
          collapse ? date(2026, 11, 9) : date(2026, 10, 26),
          collapse ? 1 : 6,
        ),
      );
      expect(
        consumer.events,
        collapse ? [ViewportChanged(week(focused))] : isEmpty,
      );
      expect(consumer.selectedDate, selected);
      await _command(
        tester,
        collapse ? 'Развернуть календарь' : 'Выбрать год и месяц',
      );
      if (collapse) await _command(tester, 'Выбрать год и месяц');
      expect(find.text('2020–2031'), findsOneWidget);
    });
  }

  for (final (year, otherYear, disabledYears, disabledYear) in const [
    (1, 4, 'Предыдущие годы', 'Предыдущий год'),
    (9999, 9987, 'Следующие годы', 'Следующий год'),
  ]) {
    testWidgets('страница у границы $year не предлагает годы за диапазоном '
        'CalendarDate', (tester) async {
      final semantics = tester.ensureSemantics();
      final focused = date(year, 6, 15);
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 8),
        viewport: month(focused),
        today: date(2026, 10, 8),
      );
      await _command(tester, 'Выбрать год и месяц');
      expect(find.text('0'), findsNothing);
      expect(find.text('-1'), findsNothing);
      expect(find.text('10000'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel(disabledYears)),
        isSemantics(isButton: true, isEnabled: false),
      );
      await _command(tester, disabledYears);
      await tester.drag(find.text('$year'), Offset(year == 1 ? 500 : -500, 0));
      await tester.pumpAndSettle();
      expect(find.text(year == 1 ? '1–3' : '9988–9999'), findsOneWidget);
      expect(consumer.events, isEmpty);
      await _command(tester, year == 1 ? 'Следующие годы' : 'Предыдущие годы');
      expect(find.text('$otherYear'), findsOneWidget);
      final back = find.bySemanticsLabel(disabledYears);
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text(year == 1 ? '1–3' : '9988–9999'), findsOneWidget);
      expect(
        tester.getSemantics(back),
        isSemantics(isButton: true, isEnabled: false),
      );
      await tester.tap(find.text('$year'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel(disabledYear)),
        isSemantics(isButton: true, isEnabled: false),
      );
      await _command(tester, disabledYear);
      await _command(tester, year == 1 ? 'Следующий год' : 'Предыдущий год');
      expect(find.text('${year == 1 ? 2 : 9998}'), findsOneWidget);
      final backToBoundary = find.bySemanticsLabel(disabledYear);
      await tester.tap(backToBoundary);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(backToBoundary);
      await tester.pumpAndSettle();
      expect(find.text('$year'), findsOneWidget);
      expect(
        tester.getSemantics(backToBoundary),
        isSemantics(isButton: true, isEnabled: false),
      );
      expect(consumer.events, isEmpty);
      await tester.tap(find.text('Июнь'));
      await tester.pumpAndSettle();
      expect(consumer.events, [
        MonthSelectionCompleted(month(date(year, 6, 1))),
      ]);
      expect(
        visibleWeeks(tester).expand((row) => row),
        contains(date(year, 6, 15)),
      );
      semantics.dispose();
    });
  }

  for (final onDate in [false, true]) {
    final catalog = onDate ? 'каталог на дату' : 'корневой каталог';
    testWidgets('$catalog не читает выдачу и отметки при перелистывании '
        'выбора периода, а после выбора месяца обновляет только отметки', (
      tester,
    ) async {
      final selected = date(2026, 10, 8);
      final repository = CatalogPageRepository();
      await pumpCatalogPage(
        tester,
        repository,
        today: selected,
        locale: const Locale('ru'),
        size: const Size(390, 844),
        catalogDate: onDate ? selected : null,
      );
      repository.completeFirst(0, [
        catalogPageItem(1, date: selected),
      ], total: 1);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-completion-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не выполненные').last);
      await tester.pump();
      repository.completeFirst(1, [
        catalogPageItem(1, date: selected),
      ], total: 1);
      await tester.pumpAndSettle();

      await _command(tester, 'Развернуть календарь');
      await _command(tester, 'Выбрать год и месяц');
      await tester.drag(find.text('2025'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2032–2043'), findsOneWidget);
      await _command(tester, 'Следующие годы');
      expect(find.text('2044–2055'), findsOneWidget);
      await tester.tap(find.text('2046'));
      await tester.pumpAndSettle();
      await _command(tester, 'Следующий год');
      expect(find.text('2047'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(repository.dayStatusQueries, hasLength(1));
      expect(find.text('8 октября 2026'), findsOneWidget);
      expect(find.text('Не выполненные'), findsOneWidget);
      await tester.tap(find.text('Март'));
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(2047, 2, 25), 6));
      expect(find.text('8 октября 2026'), findsOneWidget);
      expect(find.text('Не выполненные'), findsOneWidget);
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.isCompleted, isFalse);

      expect(repository.dayStatusQueries, hasLength(2));
      final marked = date(2047, 3, 7);
      repository.completeDayStatuses(1, {
        marked: DailyChoiceDayStatus.allCompleted,
      });
      await tester.pumpAndSettle();
      expect(dayCell(tester, marked).status, DailyChoiceDayStatus.allCompleted);
      await _command(tester, 'Свернуть календарь');
      expect(visibleWeeks(tester), weeksFrom(date(2047, 2, 25), 1));
      expect(find.text('8 октября 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _command(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}
