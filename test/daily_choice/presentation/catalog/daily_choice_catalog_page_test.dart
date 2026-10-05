import 'dart:async';
import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/favorite_read_contract_test_fallback.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';
import 'daily_choice_calendar_test_support.dart';

void main() {
  for (final (locale, label) in [
    (const Locale('ru'), 'Создать выбор от действия'),
    (const Locale('en'), 'Create a choice from an action'),
  ]) {
    testWidgets(
      'вход в нижний выбор доступен на языке ${locale.languageCode}',
      (tester) async {
        final repository = _Repository();
        final router = await _open(tester, repository, locale: locale);
        await tester.pump(const Duration(milliseconds: 400));
        final entry = find.byKey(
          const ValueKey('daily-choice-create-from-action'),
        );
        expect(find.text(label), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel(label), findsOneWidget);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(router.current.name, DailyChoiceActionPickerRoute.name);
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-action-cancel')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expectDailyChoicesRootPage(router);
        repository.completeFirst([], total: 0);
        await tester.pump();
        expect(entry, findsOneWidget);
        semantics.dispose();
      },
    );
  }

  testWidgets('показывает все записи, количество и открывает дубликат по id', (
    tester,
  ) async {
    final repository = _Repository();
    final router = await _open(tester, repository);
    expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
    repository.completeFirst([_item(1), _item(2)], total: 2);
    await tester.pumpAndSettle();
    expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-row-2')))
          .label,
      contains('№ 2'),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-row-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(
      router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
      _id(2),
    );
    semantics.dispose();
  });

  testWidgets('охват выполнения и сброс сохраняют выбранный день и просмотр '
      'календаря', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    final l10n = lookupAppLocalizations(const Locale('ru'));
    expect(repository.queries.single.date, _today);
    expect(repository.queries.single.isCompleted, isNull);
    repository.completeFirst([_item(1)], total: 2, cursor: const _Cursor());
    await tester.pumpAndSettle();
    expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-choice-load-more')));
    await tester.pump();
    expect(repository.queries[1].cursor, isA<_Cursor>());
    expect(repository.queries[1].date, _today);
    repository.completeMore(1, [_item(2)]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);

    final selectedDay = date(2026, 9, 25);
    await tester.tap(calendarDay(selectedDay));
    await tester.pump();
    expect(repository.queries[2].date, selectedDay);
    repository.completeFirst([_item(2, date: selectedDay)], index: 2, total: 1);
    await tester.pumpAndSettle();

    // Просмотр другой недели не меняет условий выдачи, а смена охвата и сброс
    // не меняют просматриваемую неделю.
    await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
    final viewed = week(date(2026, 10, 2));
    expect(_calendar(tester).viewport, viewed);
    expect(repository.queries, hasLength(3));

    await tester.tap(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выполненные').last);
    await tester.pump();
    expect(repository.queries, hasLength(4));
    expect(repository.queries[3].date, selectedDay);
    expect(repository.queries[3].isCompleted, true);
    expect(repository.queries[3].cursor, isNull);
    expect(_calendar(tester).viewport, viewed);
    repository.completeFirst([], index: 3, total: 0);
    await tester.pumpAndSettle();
    expect(find.text('Дневных выборов по фильтрам нет.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('daily-choice-clear-filters')));
    await tester.pump();
    expect(repository.queries, hasLength(5));
    expect(repository.queries[4].date, selectedDay);
    expect(repository.queries[4].isCompleted, isNull);
    expect(_calendar(tester).selectedDate, selectedDay);
    expect(_calendar(tester).viewport, viewed);
    repository.completeFirst([_item(2, date: selectedDay)], index: 4, total: 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
    expect(find.text('Все состояния'), findsOneWidget);

    // Сброс при полном охвате ничего не читает и не снимает выбранный день.
    await tester.tap(find.byKey(const ValueKey('daily-choice-clear-filters')));
    await tester.pump();
    expect(repository.queries, hasLength(5));
    expect(_calendar(tester).selectedDate, selectedDay);
    expect(find.text(_selectedDateLabel(tester, selectedDay)), findsOneWidget);
  });

  group('встроенный календарь', () {
    testWidgets('первое открытие выбирает сегодня в свёрнутой неделе и читает '
        'только этот день вместо ручного ввода даты', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);

      final calendar = _calendar(tester);
      expect(calendar.selectedDate, _today);
      expect(calendar.today, _today);
      expect(calendar.viewport, week(_today));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text(_selectedDateLabel(tester, _today)), findsOneWidget);
      final query = repository.queries.single;
      expect(query.date, _today);
      expect(query.isCompleted, isNull);
      expect(query.cursor, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-choice-apply-date')),
        findsNothing,
      );
    });

    testWidgets('календарь стоит первым в общей прокрутке над фильтром '
        'выполнения и выдачей', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([_item(1)], total: 1);
      await tester.pumpAndSettle();

      final scroll = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final first = scroll.slivers.first;
      expect(first, isA<SliverToBoxAdapter>());
      expect(
        find.descendant(
          of: find.byWidget(first),
          matching: find.byType(DailyChoiceCalendar),
        ),
        findsOneWidget,
      );
      final calendarBottom = tester
          .getRect(find.byType(DailyChoiceCalendar))
          .bottom;
      for (final key in _filterKeys) {
        expect(
          tester.getRect(find.byKey(ValueKey(key))).top,
          greaterThanOrEqualTo(calendarBottom),
          reason: key,
        );
      }
    });

    testWidgets('нажатие другого дня недели синхронно начинает одну первую '
        'порцию с прежним охватом и не показывает выдачу прежнего дня', (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([_item(1)], total: 2, cursor: const _Cursor());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-choice-load-more')));
      await tester.pump();
      repository.completeMore(1, [_item(2)]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-completion-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не выполненные').last);
      await tester.pump();
      repository.completeFirst(
        [_item(1), _item(2)],
        index: 2,
        total: 3,
        cursor: const _Cursor(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);

      final nextDay = date(2026, 9, 25);
      await tester.tap(calendarDay(nextDay));

      // Выбор применён до следующего кадра.
      expect(repository.queries, hasLength(4));
      final query = repository.queries[3];
      expect(query.date, nextDay);
      expect(query.isCompleted, false);
      expect(query.cursor, isNull);

      await tester.pump();
      expect(_calendar(tester).selectedDate, nextDay);
      expect(_calendar(tester).viewport, week(nextDay));
      expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
      expect(find.text('Всего дневных выборов: 3'), findsNothing);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-choice-load-more')),
        findsNothing,
      );

      repository.completeFirst([_item(3, date: nextDay)], index: 3, total: 1);
      await tester.pumpAndSettle();
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
      expect(repository.queries, hasLength(4));
    });

    testWidgets('в раскрытом месяце 2028-02-29 выбирается после просмотра '
        'соседнего месяца, а календарь остаётся раскрытым', (tester) async {
      final today = date(2028, 1, 20);
      final leapDay = date(2028, 2, 29);
      final repository = _Repository();
      await _open(tester, repository, today: today);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      expect(_calendar(tester).viewport, month(today));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextMonth);
      expect(_calendar(tester).viewport, month(date(2028, 2, 1)));
      expect(visibleWeeks(tester), weeksFrom(date(2028, 1, 31), 5));
      // Выбранный день вне просматриваемого месяца остаётся названным.
      expect(find.text(_selectedDateLabel(tester, today)), findsOneWidget);
      expect(repository.queries, hasLength(1));

      await tester.tap(calendarDay(leapDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, leapDay);
      expect(repository.queries[1].isCompleted, isNull);

      await _settleCalendar(tester);
      expect(_calendar(tester).selectedDate, leapDay);
      expect(_calendar(tester).viewport, month(leapDay));
      expect(visibleWeeks(tester), weeksFrom(date(2028, 1, 31), 5));
      expect(find.byTooltip(l10n.dailyChoiceCalendarCollapse), findsOneWidget);
      expect(find.text(_selectedDateLabel(tester, leapDay)), findsOneWidget);
      expect(repository.queries, hasLength(2));
    });

    testWidgets('перелистывание, раскрытие и сворачивание меняют только '
        'просмотр, не прерывая чтение и сохраняя выдачу', (tester) async {
      final today = date(2026, 10, 4);
      final repository = _Repository();
      await _open(tester, repository, today: today);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      // Первое чтение ещё не завершено: просмотр его не отменяет и не
      // повторяет.
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
      expect(_calendar(tester).viewport, week(date(2026, 10, 11)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      await _swipeCalendar(tester, toNext: true);
      expect(_calendar(tester).viewport, week(date(2026, 10, 18)));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousWeek);
      expect(_calendar(tester).viewport, week(date(2026, 10, 11)));
      expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
      expect(repository.queries, hasLength(1));

      repository.completeFirst([
        _item(1, date: today),
        _item(2, date: today),
      ], total: 2);
      await tester.pumpAndSettle();
      final count = find.text('Всего дневных выборов: 2');
      expect(count, findsOneWidget);

      // Неделя с датой просмотра в ноябре раскрывается в ноябрь, сдвигая
      // выдачу вниз.
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
      await _swipeCalendar(tester, toNext: true);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
      expect(_calendar(tester).viewport, week(date(2026, 11, 1)));
      final weekCountTop = tester.getRect(count).top;
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      expect(_calendar(tester).viewport, month(date(2026, 11, 1)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(tester.getRect(count).top, greaterThan(weekCountTop));

      await _swipeCalendar(tester, toNext: true);
      expect(_calendar(tester).viewport, month(date(2026, 12, 1)));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      expect(_calendar(tester).viewport, month(date(2026, 11, 1)));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(_calendar(tester).viewport, week(date(2026, 11, 1)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      expect(tester.getRect(count).top, moreOrLessEquals(weekCountTop));

      // Свёрнутая неделя показывает точную дату просмотра из середины месяца.
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextWeek);
      expect(_calendar(tester).viewport, week(date(2026, 11, 15)));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(_calendar(tester).viewport, week(date(2026, 11, 15)));
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));

      expect(repository.queries, hasLength(1));
      expect(_calendar(tester).selectedDate, today);
      expect(find.text(_selectedDateLabel(tester, today)), findsOneWidget);
      expect(count, findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);
    });

    testWidgets('повторное нажатие выбранного дня возвращает к нему просмотр '
        'без чтения', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([_item(1)], total: 1);
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextMonth);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      expect(_calendar(tester).viewport, month(date(2026, 9, 1)));

      await tester.tap(calendarDay(_today));
      await _settleCalendar(tester);
      expect(_calendar(tester).selectedDate, _today);
      expect(_calendar(tester).viewport, month(_today));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));

      expect(repository.queries, hasLength(1));
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
    });

    testWidgets('при отказе выбранный день сохраняется, его повторное '
        'нажатие не заменяет повтор, а другой день выбирается', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final futureDay = date(2026, 9, 26);
      await tester.tap(calendarDay(futureDay));
      await tester.pump();
      repository.failFirst(index: 1);
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsOneWidget);
      expect(_calendar(tester).selectedDate, futureDay);

      await tester.tap(calendarDay(futureDay));
      await tester.pump();
      expect(repository.queries, hasLength(2));
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, l10n.commonRetry));
      await tester.pump();
      expect(repository.queries, hasLength(3));
      expect(repository.queries[2].date, futureDay);
      expect(repository.queries[2].cursor, isNull);
      repository.failFirst(index: 2);
      await tester.pumpAndSettle();
      expect(_calendar(tester).selectedDate, futureDay);

      final otherDay = date(2026, 9, 27);
      await tester.tap(calendarDay(otherDay));
      expect(repository.queries, hasLength(4));
      expect(repository.queries[3].date, otherDay);
      await tester.pump();
      expect(_calendar(tester).selectedDate, otherDay);
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsNothing);
    });

    testWidgets('пустая выдача сохраняет выбранный день и позволяет выбрать '
        'другой', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();
      expect(find.text('Дневных выборов по фильтрам нет.'), findsOneWidget);
      expect(_calendar(tester).selectedDate, _today);

      final otherDay = date(2026, 9, 23);
      await tester.tap(calendarDay(otherDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, otherDay);
      await tester.pump();
      expect(_calendar(tester).selectedDate, otherDay);
      expect(_calendar(tester).viewport, week(otherDay));
    });
  });

  testWidgets('различает ошибку чтения и повторную попытку на английском', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository, locale: const Locale('en'));
    repository.failFirst();
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load daily choices. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    repository.completeFirst([_item(1)], index: 1, total: 1);
    await tester.pumpAndSettle();
    expect(find.text('To Основание, today I Действие'), findsOneWidget);
  });

  testWidgets('фильтры, количество и выдача прокручиваются вместе одним '
      'жестом по выдаче', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, size: _phone);
    repository.completeFirst(
      [for (var number = 1; number <= 20; number++) _item(number)],
      total: 21,
      cursor: const _Cursor(),
    );
    await tester.pumpAndSettle();
    final calendar = find.byType(DailyChoiceCalendar);
    final count = find.text('Всего дневных выборов: 21');
    final row = find.byKey(const ValueKey('daily-choice-row-2'));
    final before = [
      for (final finder in [calendar, count, row]) tester.getRect(finder).top,
    ];

    await tester.drag(row, const Offset(0, -100));
    await tester.pumpAndSettle();

    final shifts = [
      for (final (index, finder) in [calendar, count, row].indexed)
        before[index] - tester.getRect(finder).top,
    ];
    expect(shifts.first, greaterThan(0));
    expect(shifts, everyElement(moreOrLessEquals(shifts.first)));
  });

  for (final (keyboard, variant) in [
    (0.0, 'без клавиатуры'),
    (300.0, 'при открытой клавиатуре'),
  ]) {
    testWidgets('начальные загрузка, отказ с повтором и пустая выдача стоят '
        'под фильтрами и доступны над созданием дневного выбора $variant', (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository, size: _phone, keyboard: keyboard);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final create = find.byKey(
        const ValueKey('daily-choice-create-from-action'),
      );

      // Прокручивает страницу до конца жестом из-под шапки и проверяет, что
      // элемент стоит под фильтрами и целиком виден над созданием дневного
      // выбора, а значит, и над клавиатурой.
      Future<void> expectReachable(Finder finder) async {
        final appBar = tester.getRect(find.byType(AppBar));
        await tester.dragFrom(
          Offset(appBar.left + 24, appBar.bottom + 24),
          const Offset(0, -400),
        );
        // Индикатор загрузки не даёт кадрам успокоиться.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(finder, findsOneWidget);
        final filtersBottom = [
          tester
              .getRect(find.byType(DailyChoiceCalendar, skipOffstage: false))
              .bottom,
          for (final key in _filterKeys)
            tester
                .getRect(find.byKey(ValueKey(key), skipOffstage: false))
                .bottom,
        ].reduce(math.max);
        final rect = tester.getRect(finder);
        expect(
          rect.top,
          greaterThanOrEqualTo(filtersBottom),
          reason: '$finder',
        );
        expect(
          rect.top,
          greaterThanOrEqualTo(appBar.bottom),
          reason: '$finder',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(tester.getRect(create).top),
          reason: '$finder',
        );
      }

      await expectReachable(find.text(l10n.dailyChoiceCatalogLoading));

      repository.failFirst();
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(TextButton, l10n.commonRetry);
      await expectReachable(find.text(l10n.dailyChoiceCatalogUnavailable));
      await expectReachable(retry);
      expect(retry.hitTestable(), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(repository.queries, hasLength(2));
      await expectReachable(find.text(l10n.dailyChoiceCatalogLoading));

      repository.completeFirst([], index: 1, total: 0);
      await tester.pumpAndSettle();
      await expectReachable(find.text(l10n.dailyChoiceCatalogTotalCount(0)));
      await expectReachable(find.text(l10n.dailyChoiceCatalogEmpty));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('фильтры и строки доступны при увеличенном тексте', (
    tester,
  ) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final repository = _Repository();
    await _open(tester, repository, size: const Size(360, 640));
    repository.completeFirst([_item(1)], total: 1);
    await tester.pumpAndSettle();
    expect(find.byType(DailyChoiceCalendar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
      findsOneWidget,
    );
    // Строки идут за крупными фильтрами и становятся видимыми прокруткой
    // страницы.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('daily-choice-row-1')),
      find.byType(CustomScrollView),
      const Offset(0, -100),
    );
    expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
  });
}

/// Экран телефона, на котором фильтры и выдача делят высоту.
const _phone = Size(400, 800);

/// Локальное сегодня проверок страницы и дата строк фикстуры: первое чтение
/// каталога охватывает этот день.
final _today = CalendarDate.fromParts(2026, 9, 24);

/// Фильтры каталога под календарём: выполнение и сброс.
const _filterKeys = [
  'daily-choice-completion-filter',
  'daily-choice-clear-filters',
];

/// Календарь открытого каталога: его входы — состояние страницы и модели.
DailyChoiceCalendar _calendar(WidgetTester tester) =>
    tester.widget<DailyChoiceCalendar>(find.byType(DailyChoiceCalendar));

/// Подпись полной выбранной даты в шапке календаря по текущей локали.
String _selectedDateLabel(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(DailyChoiceCalendar));
  return AppLocalizations.of(context).dailyChoiceCalendarSelectedDate(
    MaterialLocalizations.of(context)
        .formatFullDate(DateTime.utc(value.year, value.month, value.day)),
  );
}

/// Доводит до конца перелистывание календаря. Индикатор загрузки выдачи не
/// даёт дождаться покоя всех анимаций, поэтому время продвигается явно.
Future<void> _settleCalendar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Выполняет команду шапки календаря по её доступному названию.
Future<void> _tapCalendarCommand(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(label));
  await _settleCalendar(tester);
}

/// Перелистывает календарь горизонтальным свайпом по дням периода.
Future<void> _swipeCalendar(WidgetTester tester, {required bool toNext}) async {
  await tester.drag(calendarPeriodArea, Offset(toNext ? -900 : 900, 0));
  await _settleCalendar(tester);
}

/// Открывает каталог дневных выборов; [today] — локальное сегодня,
/// [keyboard] — высота открытой экранной клавиатуры.
Future<AppRouter> _open(
  WidgetTester tester,
  _Repository repository, {
  CalendarDate? today,
  Locale locale = const Locale('ru'),
  Size size = const Size(1200, 2400),
  double keyboard = 0,
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ControlledDailyChoiceLocalDate(today ?? _today).override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  openDailyChoicesOn(router);
  await tester.pump();
  return router;
}

final class _Repository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final queries = <DailyChoiceCatalogQuery>[];
  final _requests = <Completer<DailyChoiceCatalogPageResult>>[];

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _requests.add(request);
    return request.future;
  }

  void completeFirst(
    List<DailyChoiceCatalogItem> items, {
    int index = 0,
    required int total,
    DailyChoiceCatalogCursor? cursor,
  }) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: items,
          totalCount: total,
          nextCursor: cursor,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void completeMore(int index, List<DailyChoiceCatalogItem> items) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogContinuationPage(
          items: items,
          nextCursor: null,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void failFirst({int index = 0}) => _requests[index].complete(
    const DailyChoiceCatalogPageError(DailyChoiceCatalogUnavailableFailure()),
  );

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => ResultSuccess(
    IntentionCatalogFirstPage(
      items: const [],
      totalCount: 0,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Cursor implements DailyChoiceCatalogCursor {
  const _Cursor();
}

DailyChoiceCatalogItem _item(int number, {CalendarDate? date}) =>
    DailyChoiceCatalogItem(
      id: _id(number),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Основание',
        archiveState: IntentionArchiveState.archived,
        readiness: IntentionReadiness.notReady,
      ),
      selected: DailyChoiceCatalogParticipant(
        id: _intentionId(2),
        title: 'Действие',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      date: date ?? _today,
      isCompleted: false,
    );

DailyChoiceId _id(int number) => (DailyChoiceId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
