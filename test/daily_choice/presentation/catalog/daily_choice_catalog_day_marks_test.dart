import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  testWidgets(
    'отметки всех выборов не зависят от фильтра выдачи и выбранного дня',
    (tester) async {
      final today = date(2026, 10, 6);
      final repository = CatalogPageRepository();
      await pumpCatalogPage(
        tester,
        repository,
        today: today,
        locale: const Locale('ru'),
        size: const Size(1200, 2400),
      );
      expect(repository.dayStatusQueries, hasLength(1));
      expect(repository.dayStatusQueries.single.firstDate, date(2026, 8, 31));
      expect(repository.dayStatusQueries.single.lastDate, date(2026, 12, 6));
      repository.completeFirst(0, [catalogPageItem(1, date: today)], total: 2);
      repository.completeDayStatuses(0, {
        today: DailyChoiceDayStatus.hasIncomplete,
        date(2026, 10, 5): DailyChoiceDayStatus.allCompleted,
      });
      await tester.pumpAndSettle();
      expect(_mark(today, Icons.circle_outlined), findsOneWidget);
      expect(_mark(date(2026, 10, 5), Icons.check), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<bool?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выполненные').last);
      await tester.pump();
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.isCompleted, isTrue);
      repository.completeFirst(1, [
        catalogPageItem(2, date: today, isCompleted: true),
      ], total: 1);
      await tester.pumpAndSettle();
      expect(_mark(today, Icons.circle_outlined), findsOneWidget);
      expect(repository.dayStatusQueries, hasLength(1));
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);

      await tester.tap(calendarDay(date(2026, 10, 5)));
      await tester.pump();
      expect(repository.queries, hasLength(3));
      expect(repository.queries.last.date, date(2026, 10, 5));
      expect(repository.queries.last.isCompleted, isTrue);
      expect(repository.dayStatusQueries, hasLength(1));
    },
  );

  testWidgets('соседняя неделя показывает отметки до завершения жеста, '
      'смена локали и представления сохраняет просмотр и выдачу', (
    tester,
  ) async {
    final today = date(2026, 10, 6);
    final nextTuesday = date(2026, 10, 13);
    final repository = CatalogPageRepository();
    await pumpCatalogPage(
      tester,
      repository,
      today: today,
      locale: const Locale('ru'),
      size: const Size(1200, 2400),
    );
    repository.completeFirst(0, [catalogPageItem(1, date: today)], total: 1);
    repository.completeDayStatuses(0, {
      nextTuesday: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();

    final gesture = await _beginNextPeriod(tester);
    _expectVisibleMark(tester, nextTuesday, Icons.circle_outlined);
    expect(find.textContaining('Выбранная дата:'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));

    await tester.tap(find.byTooltip('Развернуть календарь'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byTooltip('Collapse calendar'), findsOneWidget);
    _expectVisibleMark(tester, nextTuesday, Icons.circle_outlined);
    expect(find.text('Total daily choices: 1'), findsOneWidget);
    expect(find.text('To Основание, today I Действие'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse calendar'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
    expect(find.textContaining('Tuesday, October 6, 2026'), findsOneWidget);
    expect(repository.queries, hasLength(1));
    expect(repository.dayStatusQueries, hasLength(1));
  });

  testWidgets('переход в декабрь до ответа ноября сохраняет полученные отметки '
      'и выдачу; только ответ текущего окна добавляет новые отметки', (
    tester,
  ) async {
    final today = date(2026, 10, 6);
    final novemberDay = date(2026, 11, 10);
    final novemberLastDay = date(2026, 11, 30);
    final decemberDay = date(2026, 12, 15);
    final repository = CatalogPageRepository();
    await pumpCatalogPage(
      tester,
      repository,
      today: today,
      locale: const Locale('ru'),
      size: const Size(1200, 2400),
    );
    repository.completeFirst(0, [catalogPageItem(1, date: today)], total: 2);
    repository.completeDayStatuses(0, {
      novemberDay: DailyChoiceDayStatus.allCompleted,
      novemberLastDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<bool?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выполненные').last);
    await tester.pump();
    repository.completeFirst(1, [
      catalogPageItem(2, date: today, isCompleted: true),
    ], total: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Развернуть календарь'));
    await tester.pumpAndSettle();

    final toNovember = await _beginNextPeriod(tester);
    _expectVisibleMark(tester, novemberDay, Icons.check);
    await toNovember.up();
    await tester.pumpAndSettle();
    expect(find.text('ноябрь 2026\u202Fг.'), findsOneWidget);
    expect(repository.dayStatusQueries, hasLength(2));

    final toDecember = await _beginNextPeriod(tester);
    _expectVisibleMark(tester, novemberLastDay, Icons.circle_outlined);
    expect(calendarDay(decemberDay), findsOneWidget);
    expect(_mark(decemberDay, Icons.circle_outlined), findsNothing);
    await toDecember.up();
    await tester.pumpAndSettle();
    expect(find.text('декабрь 2026\u202Fг.'), findsOneWidget);
    expect(repository.dayStatusQueries, hasLength(2));

    repository.completeDayStatuses(1, {
      novemberLastDay: DailyChoiceDayStatus.allCompleted,
      decemberDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 10, 26));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 1, 31));
    _expectVisibleMark(tester, novemberLastDay, Icons.circle_outlined);
    expect(_mark(novemberLastDay, Icons.check), findsNothing);
    expect(_mark(decemberDay, Icons.circle_outlined), findsNothing);

    repository.completeDayStatuses(2, {
      novemberLastDay: DailyChoiceDayStatus.hasIncomplete,
      decemberDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    _expectVisibleMark(tester, decemberDay, Icons.circle_outlined);
    expect(find.textContaining('вторник, 6 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(repository.queries, hasLength(2));

    await tester.tap(calendarDay(novemberLastDay));
    await tester.pump();
    expect(repository.dayStatusQueries, hasLength(4));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 9, 28));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 1, 3));
    expect(repository.queries, hasLength(3));
    expect(repository.queries.last.date, novemberLastDay);
    expect(repository.queries.last.isCompleted, isTrue);
  });
}

Finder _mark(CalendarDate value, IconData icon) =>
    find.descendant(of: calendarDay(value), matching: find.byIcon(icon));

Future<TestGesture> _beginNextPeriod(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(calendarPeriodArea),
  );
  await gesture.moveBy(const Offset(-20, 0));
  await tester.pump();
  await gesture.moveBy(Offset(-tester.view.physicalSize.width * 0.8, 0));
  await tester.pump();
  return gesture;
}

void _expectVisibleMark(
  WidgetTester tester,
  CalendarDate value,
  IconData icon,
) {
  final bounds = Offset.zero & tester.view.physicalSize;
  final isVisible = _mark(value, icon).evaluate().any((element) {
    final box = element.renderObject! as RenderBox;
    return bounds.overlaps(box.localToGlobal(Offset.zero) & box.size);
  });
  expect(isVisible, isTrue, reason: 'Отметка дня $value видна.');
}
