import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_catalog_controls.dart';
import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  testWidgets('повторный выбор ноября после отказа восстанавливает отметки; '
      'перестройка, промежуточные шаги, закрытие заголовком и повтор после '
      'успеха не читают', (tester) async {
    final markedDay = date(2026, 11, 1);
    final repository = CatalogPageRepository();
    await _pumpFilteredNovember(tester, repository, hasReadFailure: true);
    expect(
      _mark(markedDay, DailyChoiceDayStatus.hasIncomplete),
      findsOneWidget,
    );

    tester.element(find.byType(DailyChoiceCatalogBody)).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(2));

    await _browseAndClosePicker(tester, repository, dayStatusReads: 2);
    expect(find.byType(Notice), findsOneWidget);
    expect(
      _mark(markedDay, DailyChoiceDayStatus.hasIncomplete),
      findsOneWidget,
    );

    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(2));
    await tester.tap(find.text('Ноябрь'));
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 9, 28));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 1, 10));
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
    expect(find.byType(Notice), findsOneWidget);
    expect(
      _mark(markedDay, DailyChoiceDayStatus.hasIncomplete),
      findsOneWidget,
    );
    _expectFilteredOctoberCatalog(repository);

    repository.completeDayStatuses(2, {
      markedDay: DailyChoiceDayStatus.allCompleted,
    });
    await tester.pumpAndSettle();
    expect(_mark(markedDay, DailyChoiceDayStatus.allCompleted), findsOneWidget);
    expect(_mark(markedDay, DailyChoiceDayStatus.hasIncomplete), findsNothing);
    expect(find.byType(Notice), findsNothing);
    expect(repository.dayStatusQueries, hasLength(3));
    _expectFilteredOctoberCatalog(repository);

    await _browseAndClosePicker(tester, repository, dayStatusReads: 3);
    expect(_mark(markedDay, DailyChoiceDayStatus.allCompleted), findsOneWidget);
    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ноябрь'));
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
    expect(_mark(markedDay, DailyChoiceDayStatus.allCompleted), findsOneWidget);
    expect(find.byType(Notice), findsNothing);
    _expectFilteredOctoberCatalog(repository);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбор другого месяца после отказа читает его окно один раз '
      'и восстанавливает отметки без смены выдачи', (tester) async {
    final markedDay = date(2026, 12, 1);
    final repository = CatalogPageRepository();
    await _pumpFilteredNovember(tester, repository, hasReadFailure: true);

    await _command(tester, 'Выбрать год и месяц');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(2));
    await tester.tap(find.text('Декабрь'));
    await tester.pumpAndSettle();
    expect(repository.dayStatusQueries, hasLength(3));
    expect(repository.dayStatusQueries.last.firstDate, date(2026, 10, 26));
    expect(repository.dayStatusQueries.last.lastDate, date(2027, 2, 7));
    expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 30), 6));
    expect(find.byType(Notice), findsOneWidget);
    _expectFilteredOctoberCatalog(repository);

    repository.completeDayStatuses(2, {
      markedDay: DailyChoiceDayStatus.allCompleted,
    });
    await tester.pumpAndSettle();
    expect(_mark(markedDay, DailyChoiceDayStatus.allCompleted), findsOneWidget);
    expect(find.byType(Notice), findsNothing);
    expect(repository.dayStatusQueries, hasLength(3));
    _expectFilteredOctoberCatalog(repository);
    expect(tester.takeException(), isNull);
  });

  for (final hasReadFailure in [true, false]) {
    final outcome = hasReadFailure ? 'отказа' : 'успеха';
    testWidgets('ручка закрывает выбор после $outcome к неделе прежней даты; '
        'чтение повторяется только после отказа', (tester) async {
      final markedDay = date(2026, 11, 1);
      final repository = CatalogPageRepository();
      await _pumpFilteredNovember(
        tester,
        repository,
        hasReadFailure: hasReadFailure,
      );
      await _command(tester, 'Выбрать год и месяц');
      await tester.tap(find.text('2030'));
      await tester.pumpAndSettle();
      expect(repository.dayStatusQueries, hasLength(2));
      expect(
        find.byType(Notice),
        hasReadFailure ? findsOneWidget : findsNothing,
      );
      _expectFilteredOctoberCatalog(repository);

      await _command(tester, 'Свернуть календарь');
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      final reads = hasReadFailure ? 3 : 2;
      expect(repository.dayStatusQueries, hasLength(reads));
      expect(
        _mark(markedDay, DailyChoiceDayStatus.hasIncomplete),
        findsOneWidget,
      );
      _expectFilteredOctoberCatalog(repository);
      if (hasReadFailure) {
        expect(find.byType(Notice), findsOneWidget);
        expect(repository.dayStatusQueries.last.firstDate, date(2026, 9, 28));
        expect(repository.dayStatusQueries.last.lastDate, date(2027, 1, 10));
        repository.completeDayStatuses(2, {
          markedDay: DailyChoiceDayStatus.allCompleted,
        });
        await tester.pumpAndSettle();
        expect(
          _mark(markedDay, DailyChoiceDayStatus.allCompleted),
          findsOneWidget,
        );
      }
      expect(find.byType(Notice), findsNothing);
      expect(repository.dayStatusQueries, hasLength(reads));
      _expectFilteredOctoberCatalog(repository);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Notice под ручкой остаётся над прокрученной выдачей; '
      'отказ сохраняет отметки и смещение, успех убирает сообщение', (
    tester,
  ) async {
    final today = date(2026, 10, 6);
    final repository = CatalogPageRepository();
    await pumpCatalogPage(
      tester,
      repository,
      today: today,
      locale: const Locale('ru'),
      size: const Size(360, 780),
    );
    repository.completeFirst(0, [
      for (var number = 1; number <= 20; number++)
        catalogPageItem(number, date: today),
    ], total: 20);
    repository.completeDayStatuses(0, {
      today: DailyChoiceDayStatus.hasIncomplete,
    });
    await tester.pumpAndSettle();
    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, -350));
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    final offset = scroll.pixels;
    expect(offset, greaterThan(0));
    final coordinator = ProviderScope.containerOf(
      tester.element(calendarDay(today)),
    ).read(graphCommandCoordinatorProvider.notifier);
    await repository.confirmTagRename(coordinator, revision: 1);
    repository.failDayStatuses(1);
    await tester.pumpAndSettle();

    final notice = find.byType(Notice);
    expect(notice.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(notice).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(CalendarHandle)).bottom),
    );
    expect(scroll.pixels, offset);
    expect(_mark(today, DailyChoiceDayStatus.hasIncomplete), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    final noticeRect = tester.getRect(notice);
    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(offset));
    expect(tester.getRect(notice), noticeRect);

    final afterScroll = scroll.pixels;
    await swipeToNextPeriod(tester);
    repository.completeDayStatuses(2, {}, revision: 1);
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(scroll.pixels, afterScroll);
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('6 октября 2026'), findsOneWidget);
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
    expect(find.text('7 октября 2026'), findsOneWidget);
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
    expect(find.text('7 октября 2026'), findsOneWidget);
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
    expect(find.text('6 октября 2026'), findsOneWidget);
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
    expect(find.text('6 октября 2026'), findsOneWidget);
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
    expect(find.text('6 октября 2026'), findsOneWidget);
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
    expect(find.text('6 October 2026'), findsOneWidget);
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
    expect(find.text('6 октября 2026'), findsOneWidget);
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

Future<void> _pumpFilteredNovember(
  WidgetTester tester,
  CatalogPageRepository repository, {
  required bool hasReadFailure,
}) async {
  final selected = date(2026, 10, 8);
  final markedDay = date(2026, 11, 1);
  await pumpCatalogPage(
    tester,
    repository,
    today: selected,
    locale: const Locale('ru'),
    size: const Size(1200, 2400),
  );
  repository.completeFirst(0, [
    catalogPageItem(1, date: selected, isCompleted: true),
  ], total: 1);
  repository.completeDayStatuses(0, {
    markedDay: DailyChoiceDayStatus.hasIncomplete,
  });
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<bool?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Выполненные').last);
  await tester.pump();
  repository.completeFirst(1, [
    catalogPageItem(1, date: selected, isCompleted: true),
  ], total: 1);
  await tester.pumpAndSettle();
  await _command(tester, 'Развернуть календарь');
  await _command(tester, 'Следующий месяц');
  expect(repository.dayStatusQueries, hasLength(2));
  if (hasReadFailure) {
    repository.failDayStatuses(1);
  } else {
    repository.completeDayStatuses(1, {
      markedDay: DailyChoiceDayStatus.hasIncomplete,
    });
  }
  await tester.pumpAndSettle();
  expect(find.text('Ноябрь 2026'), findsOneWidget);
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
  _expectFilteredOctoberCatalog(repository);
}

Future<void> _browseAndClosePicker(
  WidgetTester tester,
  CatalogPageRepository repository, {
  required int dayStatusReads,
}) async {
  for (final label in [
    'Выбрать год и месяц',
    'Следующие годы',
    'Предыдущие годы',
  ]) {
    await _command(tester, label);
    expect(repository.dayStatusQueries, hasLength(dayStatusReads));
  }
  await tester.tap(find.text('2026'));
  await tester.pumpAndSettle();
  expect(repository.dayStatusQueries, hasLength(dayStatusReads));
  for (final label in [
    'Следующий год',
    'Предыдущий год',
    'Вернуться к дням месяца',
  ]) {
    await _command(tester, label);
    expect(repository.dayStatusQueries, hasLength(dayStatusReads));
  }
  expect(find.text('Ноябрь 2026'), findsOneWidget);
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
  _expectFilteredOctoberCatalog(repository);
}

void _expectFilteredOctoberCatalog(CatalogPageRepository repository) {
  expect(find.text('8 октября 2026'), findsOneWidget);
  expect(find.text('Выполненные'), findsOneWidget);
  expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
  expect(find.text('Чтобы Основание, я сегодня Действие'), findsOneWidget);
  expect(repository.queries, hasLength(2));
  expect(repository.queries.last.date, date(2026, 10, 8));
  expect(repository.queries.last.isCompleted, isTrue);
}

Future<void> _command(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
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
