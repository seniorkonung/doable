import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_catalog_controls.dart';
import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  testWidgets('отказ первого чтения отметок не мешает фильтру и выбору дня; '
      'перелистывание внутри окна восстанавливает отметки без смены выдачи', (
    tester,
  ) async {
    final today = date(2026, 10, 6);
    final selectedDay = date(2026, 10, 7);
    final nextWeekDay = date(2026, 10, 14);
    final repository = CatalogPageRepository();
    await pumpCatalogPage(
      tester,
      repository,
      today: today,
      locale: const Locale('ru'),
      size: const Size(1200, 2400),
    );
    repository.completeFirst(0, [
      catalogPageItem(1, date: today, isCompleted: true),
    ], total: 1);
    repository.failDayStatuses(0);
    await tester.pumpAndSettle();
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DailyChoiceCalendarDay),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(find.textContaining('вторник, 6 октября 2026'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<bool?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выполненные').last);
    await tester.pump();
    repository.completeFirst(1, [
      catalogPageItem(1, date: today, isCompleted: true),
    ], total: 1);
    await tester.pumpAndSettle();
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);

    await tester.tap(calendarDay(selectedDay));
    await tester.pump();
    expect(repository.queries.last.date, selectedDay);
    expect(repository.queries.last.isCompleted, isTrue);
    expect(repository.dayStatusQueries, hasLength(2));
    repository.completeFirst(2, [
      catalogPageItem(3, date: selectedDay, isCompleted: true),
    ], total: 1);
    repository.failDayStatuses(1);
    await tester.pumpAndSettle();
    expect(find.textContaining('среда, 7 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);

    await swipeToNextPeriod(tester);
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
    expect(repository.dayStatusQueries, hasLength(3));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 8, 31));
    expect(repository.dayStatusQueries.last.lastDate, date(2026, 12, 6));
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(
      _mark(nextWeekDay, DailyChoiceDayStatus.hasIncomplete),
      findsNothing,
    );
    repository.completeDayStatuses(2, {
      today: DailyChoiceDayStatus.allCompleted,
      selectedDay: DailyChoiceDayStatus.allCompleted,
      nextWeekDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    expect(
      _mark(nextWeekDay, DailyChoiceDayStatus.hasIncomplete),
      findsOneWidget,
    );
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    expect(find.textContaining('среда, 7 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(repository.queries, hasLength(3));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('задержка и отказ обновления сохраняют прежние отметки и выдачу; '
      'подтверждённое изменение восстанавливает отметки', (tester) async {
    final today = date(2026, 10, 6);
    final repository = CatalogPageRepository();
    await pumpCatalogPage(
      tester,
      repository,
      today: today,
      locale: const Locale('ru'),
      size: const Size(1200, 2400),
    );
    repository.completeFirst(0, [
      catalogPageItem(1, date: today),
      catalogPageItem(2, date: today, isCompleted: true),
    ], total: 2);
    repository.completeDayStatuses(0, {
      today: DailyChoiceDayStatus.hasIncomplete,
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
    final coordinator = ProviderScope.containerOf(
      tester.element(calendarDay(today)),
    ).read(graphCommandCoordinatorProvider.notifier);

    await repository.confirmTagRename(coordinator, revision: 1);
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(2));
    expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    repository.failDayStatuses(1);
    await tester.pumpAndSettle();
    expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(find.textContaining('вторник, 6 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await repository.confirmTagRename(coordinator, revision: 2);
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    repository.completeDayStatuses(2, {
      today: DailyChoiceDayStatus.hasIncomplete,
    }, revision: 2);
    await tester.pumpAndSettle();
    expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    expect(find.textContaining('вторник, 6 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(repository.queries, hasLength(2));
    expect(find.byType(SnackBar), findsNothing);
  });

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
      expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
      expect(
        _mark(date(2026, 10, 5), DailyChoiceDayStatus.allCompleted),
        findsOneWidget,
      );

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
      expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
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
    _expectVisibleMark(tester, nextTuesday, DailyChoiceDayStatus.hasIncomplete);
    expect(find.textContaining('Выбранная дата:'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));

    await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('Collapse calendar'), findsOneWidget);
    _expectVisibleMark(tester, nextTuesday, DailyChoiceDayStatus.hasIncomplete);
    expect(find.text('Total daily choices: 1'), findsOneWidget);
    expect(find.text('To Основание, today I Действие'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Collapse calendar'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
    expect(find.textContaining('Tuesday, October 6, 2026'), findsOneWidget);
    expect(repository.queries, hasLength(1));
    expect(repository.dayStatusQueries, hasLength(1));
  });

  testWidgets('первый свайп апреля к маю показывает отметку 7 июня в шестой '
      'строке до завершения нового чтения', (tester) async {
    final today = date(2026, 4, 15);
    final juneDay = date(2026, 6, 7);
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
      juneDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 3, 30), 6));
    expect(repository.dayStatusQueries, hasLength(1));
    expect(calendarDay(juneDay), findsNothing);

    final gesture = await _beginNextPeriod(tester);
    // Воскресенье входит в экран последним: жест продолжается, пока видна
    // правая колонка соседнего месяца, но палец ещё не отпущен.
    await gesture.moveBy(Offset(-tester.view.physicalSize.width * 0.15, 0));
    await tester.pump();
    _expectVisibleMark(tester, juneDay, DailyChoiceDayStatus.hasIncomplete);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 4, 27), 6));
    expect(repository.dayStatusQueries, hasLength(2));
    _expectVisibleMark(tester, juneDay, DailyChoiceDayStatus.hasIncomplete);

    repository.completeDayStatuses(1, {
      juneDay: DailyChoiceDayStatus.allCompleted,
    });
    await tester.pumpAndSettle();
    _expectVisibleMark(tester, juneDay, DailyChoiceDayStatus.allCompleted);
    expect(_mark(juneDay, DailyChoiceDayStatus.hasIncomplete), findsNothing);
    expect(shownDailyChoiceCatalogDate(tester), today);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(repository.queries, hasLength(1));
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
    await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
    await tester.pumpAndSettle();

    final toNovember = await _beginNextPeriod(tester);
    _expectVisibleMark(tester, novemberDay, DailyChoiceDayStatus.allCompleted);
    await toNovember.up();
    await tester.pumpAndSettle();
    expect(find.text('Ноябрь 2026'), findsOneWidget);
    expect(repository.dayStatusQueries, hasLength(2));

    final toDecember = await _beginNextPeriod(tester);
    _expectVisibleMark(
      tester,
      novemberLastDay,
      DailyChoiceDayStatus.hasIncomplete,
    );
    expect(calendarDay(decemberDay), findsOneWidget);
    expect(
      _mark(decemberDay, DailyChoiceDayStatus.hasIncomplete),
      findsNothing,
    );
    await toDecember.up();
    await tester.pumpAndSettle();
    expect(find.text('Декабрь 2026'), findsOneWidget);
    expect(repository.dayStatusQueries, hasLength(2));

    repository.completeDayStatuses(1, {
      novemberLastDay: DailyChoiceDayStatus.allCompleted,
      decemberDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 10, 26));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 2, 7));
    _expectVisibleMark(
      tester,
      novemberLastDay,
      DailyChoiceDayStatus.hasIncomplete,
    );
    expect(
      _mark(novemberLastDay, DailyChoiceDayStatus.allCompleted),
      findsNothing,
    );
    expect(
      _mark(decemberDay, DailyChoiceDayStatus.hasIncomplete),
      findsNothing,
    );

    repository.completeDayStatuses(2, {
      novemberLastDay: DailyChoiceDayStatus.hasIncomplete,
      decemberDay: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    _expectVisibleMark(tester, decemberDay, DailyChoiceDayStatus.hasIncomplete);
    expect(find.textContaining('вторник, 6 октября 2026'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
    expect(repository.queries, hasLength(2));

    await tester.tap(calendarDay(novemberLastDay));
    await tester.pump();
    expect(repository.dayStatusQueries, hasLength(4));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 9, 28));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 1, 10));
    expect(repository.queries, hasLength(3));
    expect(repository.queries.last.date, novemberLastDay);
    expect(repository.queries.last.isCompleted, isTrue);
  });
}

Finder _mark(CalendarDate value, DailyChoiceDayStatus status) =>
    dailyChoiceCatalogDayMark(
      value,
      mark: switch (status) {
        DailyChoiceDayStatus.hasIncomplete => DayMark.todo,
        DailyChoiceDayStatus.allCompleted => DayMark.done,
      },
    );

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
  DailyChoiceDayStatus status,
) {
  final bounds = Offset.zero & tester.view.physicalSize;
  final isVisible = _mark(value, status).evaluate().any((element) {
    final box = element.renderObject! as RenderBox;
    return bounds.overlaps(box.localToGlobal(Offset.zero) & box.size);
  });
  expect(isVisible, isTrue, reason: 'Отметка дня $value видна.');
}
