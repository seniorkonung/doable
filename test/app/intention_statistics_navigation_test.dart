import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_section.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

void main() {
  testWidgets('все четыре вида Главной передают вид и год обычной странице', (
    tester,
  ) async {
    final app = await _start(tester);
    app.homeModel.selectPeriod(StatisticsYear(2025));
    for (final (view, id) in [
      (StatisticsView.sourceIntentions, 1120),
      (StatisticsView.intermediateIntentions, 2),
      (StatisticsView.selectedActions, 2120),
      (StatisticsView.throughRelations, 2120),
    ]) {
      _scroll(tester, find.byType(HomePage)).position.jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, find.text(_viewLabel(app.texts, view)));
      await _wait(tester, () => app.home.read is HomeStatisticsData);
      final row = find.text('Намерение $id');
      await _scrollTo(tester, row, find.byType(HomePage));
      final before = app.home;
      await _tap(tester, row);
      await _expectSection(tester, app, id, view, StatisticsYear(2025));
      expect(app.router.stack, hasLength(2));
      expect(
        tester
            .getSemantics(appNavigationDestination(AppDestination.home))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      app.router.pop();
      await tester.pumpAndSettle();
      expect(app.home.selection, same(before.selection));
      expect(
        (app.home.read as HomeStatisticsData).items.length,
        (before.read as HomeStatisticsData).items.length,
      );
      expect(row.hitTestable(), findsOneWidget);
    }
  });

  testWidgets(
    'возврат и сброс истории сохраняют месяцы, вид, порции и прокрутку Главной',
    (tester) async {
      final app = await _start(tester);
      app.homeModel.selectPeriod(StatisticsYear(2024));
      app.homeModel.selectPeriod(StatisticsMonth(2025, 9));
      await _wait(tester, () => app.home.read is HomeStatisticsData);
      final row = find.text('Намерение 1010');
      await _scrollTo(tester, row, find.byType(HomePage));
      final before = app.home;
      expect((before.read as HomeStatisticsData).items, hasLength(120));
      final position = _scroll(tester, find.byType(HomePage)).position.pixels;
      expect(position, greaterThan(1000));
      await _tap(tester, row);
      await _expectSection(
        tester,
        app,
        1010,
        StatisticsView.sourceIntentions,
        StatisticsMonth(2025, 9),
      );
      app.router.pop();
      await tester.pumpAndSettle();
      expect(app.home.selection, same(before.selection));
      expect(app.home.selection.year, StatisticsYear(2024));
      expect((app.home.read as HomeStatisticsData).items, hasLength(120));
      expect(_scroll(tester, find.byType(HomePage)).position.pixels, position);
      await _tap(tester, row);
      await _expectSection(
        tester,
        app,
        1010,
        StatisticsView.sourceIntentions,
        StatisticsMonth(2025, 9),
      );
      await openHome(tester, waitFor: _untilFound);
      await tester.pumpAndSettle();
      expect(app.router.stack, hasLength(1));
      expect(app.home.selection, same(before.selection));
      expect((app.home.read as HomeStatisticsData).items, hasLength(120));
      expect(_scroll(tester, find.byType(HomePage)).position.pixels, position);
    },
  );

  testWidgets(
    'три разбивки открывают соответствующий вид и возвращают прокрученную страницу',
    (tester) async {
      final app = await _start(tester);
      app.homeModel.selectPeriod(StatisticsYear(2025));
      app.homeModel.selectView(StatisticsView.intermediateIntentions);
      await _wait(tester, () => app.home.read is HomeStatisticsData);
      await _tap(tester, find.text('Намерение 2'));
      await _expectSection(
        tester,
        app,
        2,
        StatisticsView.intermediateIntentions,
        StatisticsYear(2025),
      );
      final originalProvider = app.sectionProvider(tester);
      for (final (breakdown, rowId, view) in [
        (
          StatisticsBreakdown.sourceIntentions,
          1010,
          StatisticsView.sourceIntentions,
        ),
        (
          StatisticsBreakdown.selectedActions,
          2010,
          StatisticsView.selectedActions,
        ),
        (StatisticsBreakdown.relations, 2010, StatisticsView.throughRelations),
      ]) {
        if (breakdown == StatisticsBreakdown.relations) {
          await tester.ensureVisible(
            find.text('Статистика', skipOffstage: false),
          );
          await _tap(tester, find.text(app.texts.statisticsThroughRelations));
          await _wait(
            tester,
            () =>
                app.container.read(originalProvider).read
                    is IntentionStatisticsLoaded,
          );
        }
        final group = find.byKey(ValueKey(breakdown));
        final row = find.descendant(
          of: group,
          matching: find.text('Намерение $rowId'),
        );
        await _scrollTo(tester, row, find.byType(IntentionDetailsPage));
        final before = app.container.read(originalProvider);
        final data = before.read as IntentionStatisticsLoaded;
        expect(switch (breakdown) {
          StatisticsBreakdown.sourceIntentions =>
            data.breakdowns.sourceIntentions!.items.length,
          StatisticsBreakdown.selectedActions =>
            data.breakdowns.selectedActions!.items.length,
          StatisticsBreakdown.relations =>
            data.breakdowns.relations!.items.length,
        }, 120);
        final offset = _scroll(
          tester,
          find.byType(IntentionDetailsPage),
        ).position.pixels;
        await _tap(tester, row);
        await _expectSection(tester, app, rowId, view, StatisticsYear(2025));
        expect(app.router.stack, hasLength(3));
        app.router.pop();
        await tester.pumpAndSettle();
        final after = app.container.read(originalProvider);
        expect(after.selection, same(before.selection));
        final restored = (after.read as IntentionStatisticsLoaded).breakdowns;
        expect(
          restored.sourceIntentions,
          same(data.breakdowns.sourceIntentions),
        );
        expect(restored.selectedActions, same(data.breakdowns.selectedActions));
        expect(restored.relations, same(data.breakdowns.relations));
        expect(
          _scroll(tester, find.byType(IntentionDetailsPage)).position.pixels,
          offset,
        );
        expect(row.hitTestable(), findsOneWidget);
      }
    },
  );

  testWidgets(
    'повторное намерение получает свою цель, день открывает каталог, язык и возврат сохраняют состояние',
    (tester) async {
      final app = await _start(tester);
      app.homeModel.selectPeriod(StatisticsMonth(2025, 9));
      app.homeModel.selectView(StatisticsView.intermediateIntentions);
      await _wait(tester, () => app.home.read is HomeStatisticsData);
      await _tap(tester, find.text('Намерение 2'));
      await _expectSection(
        tester,
        app,
        2,
        StatisticsView.intermediateIntentions,
        StatisticsMonth(2025, 9),
      );
      final first = app.sectionProvider(tester);
      final action = find.descendant(
        of: find.byKey(const ValueKey(StatisticsBreakdown.selectedActions)),
        matching: find.text('Намерение 2120'),
      );
      await _scrollTo(tester, action, find.byType(IntentionDetailsPage));
      final original = app.container.read(first);
      final offset = _scroll(
        tester,
        find.byType(IntentionDetailsPage),
      ).position.pixels;
      await _tap(tester, action);
      await _expectSection(
        tester,
        app,
        2120,
        StatisticsView.selectedActions,
        StatisticsMonth(2025, 9),
      );
      await _tap(tester, find.text(app.texts.statisticsThroughRelations));
      final relation = find.descendant(
        of: find.byKey(const ValueKey(StatisticsBreakdown.relations)),
        matching: find.text('Намерение 2'),
      );
      // Обратная активная связь позволяет открыть то же намерение с новой целью.
      await _scrollTo(tester, relation, find.byType(IntentionDetailsPage));
      await _tap(tester, relation);
      await _expectSection(
        tester,
        app,
        2,
        StatisticsView.throughRelations,
        StatisticsMonth(2025, 9),
      );
      final second = app.sectionProvider(tester);
      expect(second, isNot(first));
      await _tap(tester, find.text(app.texts.statisticsSourceIntentions));
      await _tap(tester, find.byTooltip(app.texts.statisticsPreviousMonth));
      await _wait(
        tester,
        () => app.container.read(second).read is IntentionStatisticsLoaded,
      );
      final topState = app.container.read(second);
      expect(topState.selection.period, StatisticsMonth(2025, 8));
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      await tester.pumpAndSettle();
      expect(find.text('Statistics'), findsOneWidget);
      expect(app.container.read(second).selection, same(topState.selection));
      expect(app.container.read(first).selection, same(original.selection));
      final depth = app.router.stack.length;
      final english = lookupAppLocalizations(const Locale('en'));
      final day = find.bySemanticsLabel(
        english.statisticsCalendarDaySemantics(
          DateTime.utc(2025, 8, 1),
          english.statisticsCalendarDayNoChoices,
        ),
      );
      await tester.ensureVisible(day);
      await tester.pumpAndSettle();
      final calendarOffset = _scroll(
        tester,
        find.byType(IntentionDetailsPage),
      ).position.pixels;
      await _tap(tester, day);
      await _untilFound(tester, find.byType(DailyChoiceDateCatalogPage));
      expect(app.router.stack, hasLength(depth + 1));
      expect(
        tester
            .widget<DailyChoiceDateCatalogPage>(
              find.byType(DailyChoiceDateCatalogPage),
            )
            .date,
        CalendarDate.fromParts(2025, 8, 1),
      );
      expect(
        tester
            .getSemantics(appNavigationDestination(AppDestination.home))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await _tap(tester, find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(app.router.stack, hasLength(depth));
      expect(
        app.container.read(second).selection.period,
        topState.selection.period,
      );
      expect(
        app.container.read(second).selection.view,
        topState.selection.view,
      );
      expect(
        _scroll(tester, find.byType(IntentionDetailsPage)).position.pixels,
        calendarOffset,
      );
      expect(day.hitTestable(), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        app.router.pop();
        await tester.pumpAndSettle();
      }
      expect(app.sectionProvider(tester), first);
      expect(app.container.read(first).selection, same(original.selection));
      expect(
        _scroll(tester, find.byType(IntentionDetailsPage)).position.pixels,
        offset,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

String _viewLabel(AppLocalizations texts, StatisticsView view) =>
    switch (view) {
      StatisticsView.sourceIntentions => texts.statisticsSourceIntentions,
      StatisticsView.intermediateIntentions =>
        texts.statisticsIntermediateIntentions,
      StatisticsView.selectedActions => texts.statisticsSelectedActions,
      StatisticsView.throughRelations => texts.statisticsThroughRelations,
    };

final class _App {
  _App(this.container);
  final ProviderContainer container;
  AppRouter get router => container.read(appRouterProvider);
  AppLocalizations get texts => lookupAppLocalizations(const Locale('ru'));
  HomeStatisticsState get home =>
      container.read(homeStatisticsViewModelProvider);
  HomeStatisticsViewModel get homeModel =>
      container.read(homeStatisticsViewModelProvider.notifier);

  IntentionStatisticsViewModelProvider sectionProvider(WidgetTester tester) =>
      tester
          .widget<IntentionStatisticsSectionSliver>(
            find.byType(IntentionStatisticsSectionSliver),
          )
          .provider;
}

Future<_App> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late AppDatabase database;
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    dailyChoiceLocalDateSource: () => DailyChoiceLocalDay(
      date: CalendarDate.fromParts(2026, 10, 12),
      untilNextDate: const Duration(hours: 12),
    ),
    repositoryFactory: (opened) {
      database = opened;
      return durabilityRepository(opened);
    },
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  await tester.runAsync(() => _seed(database));
  await tester.pumpWidget(MainApp(runtime: runtime));
  final app = _App(ready.container);
  await _wait(tester, () => app.home.read is HomeStatisticsLoaded);
  return app;
}

Future<void> _expectSection(
  WidgetTester tester,
  _App app,
  int id,
  StatisticsView view,
  StatisticsPeriod period,
) async {
  await tester.pumpAndSettle();
  await _untilFound(tester, find.byType(IntentionDetailsPage));
  await _wait(
    tester,
    () => find.byType(IntentionStatisticsSectionSliver).evaluate().isNotEmpty,
  );
  final provider = app.sectionProvider(tester);
  await _wait(
    tester,
    () => app.container.read(provider).read is IntentionStatisticsLoaded,
  );
  await tester.pumpAndSettle();
  final page = tester.widget<IntentionDetailsPage>(
    find.byType(IntentionDetailsPage),
  );
  expect(page.intentionId, durabilityIntention(id));
  expect(page.statisticsTarget!.view, view);
  expect(page.statisticsTarget!.period, period);
  final section = app.container.read(provider);
  expect(section.selection.view, view);
  expect(section.selection.period, period);
  expect(find.text('Статистика').hitTestable(), findsOneWidget);
}

ScrollableState _scroll(WidgetTester tester, Finder page) =>
    tester.state<ScrollableState>(
      find.descendant(of: page, matching: find.byType(Scrollable)).first,
    );

Future<void> _scrollTo(WidgetTester tester, Finder row, Finder page) async {
  for (var i = 0; i < 150; i++) {
    if (row.evaluate().isNotEmpty) {
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(page, const Offset(0, -900));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('Строка не появилась: $row');
}

Future<void> _untilFound(WidgetTester tester, Finder finder) =>
    _wait(tester, () => finder.evaluate().isNotEmpty);

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Ожидаемое состояние не наступило');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _untilFound(tester, finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _seed(AppDatabase database) => database.transaction(() async {
  for (final id in [
    2,
    for (var i = 1; i <= 120; i++) ...[1000 + i, 2000 + i],
  ]) {
    await database.customStatement(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 1, 0, 1, 1)',
      [durabilityUuid(id), 'Намерение $id'],
    );
  }
  for (var i = 1; i <= 120; i++) {
    final firstRelation = 3000 + i * 2;
    for (final (relation, source, related) in [
      (firstRelation, 1000 + i, 2),
      (firstRelation + 1, 2, 2000 + i),
    ]) {
      await database.customStatement(
        "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, 'need', 2)",
        [
          durabilityUuid(relation),
          durabilityUuid(source),
          durabilityUuid(related),
        ],
      );
    }
    await database.customStatement(
      "INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, '2025-09-12', 1)",
      [
        durabilityUuid(4000 + i),
        durabilityUuid(1000 + i),
        durabilityUuid(2000 + i),
      ],
    );
    for (var step = 0; step < 2; step++) {
      await database.customStatement(
        'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id, previous_step_id) VALUES (?, ?, ?, ?)',
        [
          durabilityUuid(5000 + i * 2 + step),
          durabilityUuid(4000 + i),
          durabilityUuid(firstRelation + step),
          step == 0 ? null : durabilityUuid(5000 + i * 2),
        ],
      );
    }
  }
  await database.customStatement(
    "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, 'can', 2)",
    [durabilityUuid(6000), durabilityUuid(2120), durabilityUuid(2)],
  );
});
