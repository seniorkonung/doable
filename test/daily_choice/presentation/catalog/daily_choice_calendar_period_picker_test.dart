import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
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
    await tester.drag(find.text('2025'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('2020–2031'), findsOneWidget);

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
      await _command(tester, year == 1 ? 'Следующие годы' : 'Предыдущие годы');
      expect(find.text('$otherYear'), findsOneWidget);
      await _command(tester, year == 1 ? 'Предыдущие годы' : 'Следующие годы');
      await tester.tap(find.text('$year'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel(disabledYear)),
        isSemantics(isButton: true, isEnabled: false),
      );
      await _command(tester, disabledYear);
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
    testWidgets('$catalog сохраняет выбранную дату, фильтр и выдачу при '
        'выборе далёкого месяца', (tester) async {
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
      await tester.tap(find.text('2028'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Март'));
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 6));
      expect(find.text('8 октября 2026'), findsOneWidget);
      expect(find.text('Не выполненные'), findsOneWidget);
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.isCompleted, isFalse);

      final marked = date(2028, 3, 7);
      repository.completeDayStatuses(1, {
        marked: DailyChoiceDayStatus.allCompleted,
      });
      await tester.pumpAndSettle();
      expect(dayCell(tester, marked).status, DailyChoiceDayStatus.allCompleted);
      await _command(tester, 'Свернуть календарь');
      expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 1));
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
