import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  for (final (locale, weekday, heading, todayLabel, allStates, back) in const [
    (
      Locale('ru'),
      'Среда',
      '7 октября 2026',
      'Сегодня',
      'Все состояния',
      'Назад',
    ),
    (
      Locale('en'),
      'Wednesday',
      '7 October 2026',
      'Today',
      'All states',
      'Back',
    ),
  ]) {
    testWidgets('каталог на дату получает только заданный день и не создаёт '
        'корневой каталог до выбора пункта (${locale.languageCode})', (
      tester,
    ) async {
      final repository = CatalogPageRepository();
      final clock = ControlledDailyChoiceLocalDate(date(2026, 10, 6));
      final router = await _start(tester, repository, clock, locale: locale);
      final selected = date(2026, 10, 7);

      unawaited(router.push(DailyChoiceDateCatalogRoute(date: selected)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.queries, hasLength(1));
      expect(repository.queries.single.date, selected);
      expect(repository.queries.single.isCompleted, isNull);
      repository.completeFirst(0, [], total: 0);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();

      expect(find.byType(DailyChoiceDateCatalogPage), findsOneWidget);
      expect(
        find.widgetWithText(
          AppBar,
          lookupAppLocalizations(locale).appDestinationDailyChoices,
        ),
        findsOneWidget,
      );
      expect(
        find.byType(DailyChoiceCatalogPage, skipOffstage: false),
        findsNothing,
      );
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(find.text(weekday, findRichText: true), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(find.text(todayLabel), findsNothing);
      expect(find.text(allStates), findsOneWidget);
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        AppDestination.home,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.today = selected;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(todayLabel), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(find.text(allStates), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(repository.dayStatusQueries, hasLength(1));

      await tester.tap(find.byTooltip(back));
      await tester.pumpAndSettle();
      expectHomeRootPage(router);
      clock.today = date(2026, 10, 13);
      await openDailyChoices(tester);
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.date, clock.today);
      repository.completeFirst(1, [], total: 0);
      repository.completeDayStatuses(1, {});
      await tester.pumpAndSettle();
      expect(dayCell(tester, clock.today).isSelected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('два открытия одной даты разделяют фильтр, просмотр, отметки '
      'и порции; возврат из подробностей сохраняет прокрутку', (tester) async {
    final repository = CatalogPageRepository();
    final selected = date(2026, 10, 7);
    final router = await _start(
      tester,
      repository,
      ControlledDailyChoiceLocalDate(date(2026, 10, 12)),
    );
    await _pushDate(tester, router, selected);
    repository.completeFirst(0, [], total: 0);
    repository.completeDayStatuses(0, {});
    await tester.pumpAndSettle();

    await _selectCompletion(tester, 'Выполненные');
    repository.completeFirst(
      1,
      [
        for (var number = 1; number <= 50; number++)
          catalogPageItem(number, date: selected, isCompleted: true),
      ],
      total: 51,
      cursor: const CatalogPageCursor(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();
    final marked = date(2026, 11, 7);
    repository.completeDayStatuses(1, {
      marked: DailyChoiceDayStatus.allCompleted,
    });
    await tester.pumpAndSettle();
    expect(dayCell(tester, marked).status, DailyChoiceDayStatus.allCompleted);

    final footer = find.byKey(const ValueKey('daily-choice-load-more'));
    await tester.scrollUntilVisible(footer, 500, scrollable: _verticalScroll);
    await tester.tap(footer);
    await tester.pump();
    repository.completeMore(2, [
      catalogPageItem(51, date: selected, isCompleted: true),
    ]);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('daily-choice-row-50'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(row).dy;
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DailyChoiceDetailsPage), findsOneWidget);
    expect(
      router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
      catalogPageItem(50, date: selected).id,
    );
    await _back(tester);
    expect(tester.getTopLeft(row).dy, closeTo(position, 1));

    await _pushDate(tester, router, selected);
    expect(repository.queries, hasLength(4));
    expect(repository.queries.last.date, selected);
    expect(repository.queries.last.isCompleted, isNull);
    expect(repository.queries.last.cursor, isNull);
    repository.completeFirst(3, [
      catalogPageItem(200, date: selected),
    ], total: 1);
    repository.failDayStatuses(2);
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
    expect(dayCell(tester, selected).isSelected, isTrue);
    expect(find.text('Все состояния'), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);

    await _selectCompletion(tester, 'Не выполненные');
    repository.completeFirst(4, [], total: 0);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(tester.getTopLeft(row).dy, closeTo(position, 1));
    await tester.drag(_verticalScroll, const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.bySemanticsLabel('Свернуть календарь'), findsOneWidget);
    expect(dayCell(tester, marked).status, DailyChoiceDayStatus.allCompleted);
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Всего дневных выборов: 51'),
      200,
      scrollable: _verticalScroll,
    );
    expect(find.text('Всего дневных выборов: 51'), findsOneWidget);
    expect(repository.queries, hasLength(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('закрытие освобождает каталог на дату, поздние ответы не меняют '
      'корневой каталог, повторное открытие начинает с параметров маршрута', (
    tester,
  ) async {
    final repository = CatalogPageRepository();
    final today = date(2026, 10, 12);
    final selected = date(2026, 10, 7);
    final router = await _start(
      tester,
      repository,
      ControlledDailyChoiceLocalDate(today),
    );
    await openDailyChoices(tester);
    repository.completeFirst(0, [], total: 0);
    repository.completeDayStatuses(0, {});
    await tester.pumpAndSettle();
    await _selectCompletion(tester, 'Не выполненные');
    repository.completeFirst(1, [catalogPageItem(1, date: today)], total: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
    await tester.pumpAndSettle();

    await _pushDate(tester, router, selected);
    repository.completeFirst(2, [], total: 0);
    await tester.pumpAndSettle();
    await _selectCompletion(tester, 'Выполненные');
    await _back(tester);
    repository.completeFirst(3, [
      catalogPageItem(2, date: selected, isCompleted: true),
    ], total: 1);
    repository.failDayStatuses(1);
    await tester.pumpAndSettle();
    expectDailyChoicesRootPage(router);
    expect(dayCell(tester, today).isSelected, isTrue);
    expect(find.text('Не выполненные'), findsOneWidget);
    expect(find.bySemanticsLabel('Свернуть календарь'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Всего дневных выборов: 1'),
      100,
      scrollable: _verticalScroll,
    );
    expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsNothing);

    await _pushDate(tester, router, selected);
    expect(repository.queries.last.date, selected);
    expect(repository.queries.last.isCompleted, isNull);
    expect(repository.queries.last.cursor, isNull);
    repository.completeFirst(4, [], total: 0);
    repository.completeDayStatuses(2, {});
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
    expect(dayCell(tester, selected).isSelected, isTrue);
    expect(find.text('Все состояния'), findsOneWidget);
    expect(find.text('Дневных выборов по фильтрам нет.'), findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      AppDestination.dailyChoices,
    );
    expect(tester.takeException(), isNull);
  });
}

final _verticalScroll = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Future<void> _pushDate(
  WidgetTester tester,
  AppRouter router,
  CalendarDate date,
) async {
  unawaited(router.push(DailyChoiceDateCatalogRoute(date: date)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectCompletion(WidgetTester tester, String label) async {
  await tester.tap(
    find.byKey(const ValueKey('daily-choice-completion-filter')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<AppRouter> _start(
  WidgetTester tester,
  CatalogPageRepository repository,
  ControlledDailyChoiceLocalDate clock, {
  Locale locale = const Locale('ru'),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        clock.override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
