part of 'intention_statistics_app_flow_test.dart';

void _catalogNavigationScenarios() {
  testWidgets(
    'сброс с экрана дня на дату сохраняет корень, повторный выбор Главной и позднее чтение не возвращают историю',
    (tester) async {
      final app = await _start(tester, seed: _seedCatalogActions);
      await openActions(tester);
      await _wait(
        tester,
        () => find.byType(ActionDayBody).evaluate().isNotEmpty,
      );
      final root = _visibleCatalog(tester);
      await _prepareCatalog(
        tester,
        app,
        root,
        section: ActionDaySection.incomplete,
        total: 121,
      );
      final offset = _catalogScroll(tester).position.pixels;
      final calendar = tester.widget<ActionDayCalendar>(
        find.byType(ActionDayCalendar, skipOffstage: false),
      );
      final viewport = (calendar.viewport.focusedDate, calendar.viewport.mode);
      final items = _catalogData(
        app,
        root,
      ).items.map((item) => item.id).toList();

      for (final resetToActions in [false, true]) {
        await openHome(tester);
        final section = await app.open(tester);
        await app.ready(tester, section);
        final (catalog, _) = await _openStatisticsDay(
          tester,
          app,
          CalendarDate.fromParts(2026, 10, 7),
        );
        expect(_catalogData(app, catalog).selection.completedExpanded, isTrue);
        expect(_catalogData(app, catalog).completed.items, hasLength(50));
        expect(find.text('Невыполненные'), findsOneWidget);
        expect(
          find.bySemanticsLabel(app.texts.actionCalendarExpand),
          findsOneWidget,
        );
        await showActionDaySection(tester, ActionDaySection.completed);
        final held = app.probe.holdNextCatalogRead();
        await scrollToActionDayEnd(tester, ActionDaySection.completed);
        await _wait(tester, () => held.started.isCompleted);
        final finished = _finishedCatalogReads(app);

        if (resetToActions) {
          await openActions(tester);
        } else {
          await openHome(tester);
        }
        await tester.pumpAndSettle();
        final router = app.container.read(appRouterProvider);
        if (resetToActions) {
          expectActionsRootPage(router);
        } else {
          expectHomeRootPage(router);
        }
        held.release.complete();
        await _wait(tester, () => _finishedCatalogReads(app) == finished + 1);
        await tester.pumpAndSettle();
        if (resetToActions) {
          expectActionsRootPage(router);
        } else {
          expectHomeRootPage(router);
        }
        expect(
          find.byType(ActionDayDatePage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(IntentionDetailsPage, skipOffstage: false),
          findsNothing,
        );
        await openActions(tester);
        await tester.pumpAndSettle();
        expect(_catalogData(app, root).selection.date, _today);
        expect(_catalogData(app, root).selection.completedExpanded, isFalse);
        expect(_catalogData(app, root).items.map((item) => item.id), items);
        expect(_catalogScroll(tester).position.pixels, offset);
        final restored = tester.widget<ActionDayCalendar>(
          find.byType(ActionDayCalendar, skipOffstage: false),
        );
        expect((
          restored.viewport.focusedDate,
          restored.viewport.mode,
        ), viewport);
        _catalogScroll(tester).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('Невыполненные'), findsOneWidget);
        expect(
          actionDaySectionCount(tester, section: ActionDaySection.incomplete),
          '121',
        );
        expect(
          find.bySemanticsLabel(app.texts.actionCalendarCollapse),
          findsOneWidget,
        );
        _catalogScroll(tester).position.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'два экрана одной даты и скрытый корневой согласуют выполнение и перенос, сохраняя порции и просмотр',
    (tester) async {
      final app = await _start(tester, seed: _seedCatalogActions);
      final day = CalendarDate.fromParts(2026, 10, 7);
      await openActions(tester);
      await _wait(
        tester,
        () => find.byType(ActionDayBody).evaluate().isNotEmpty,
      );
      final root = _visibleCatalog(tester);
      await _prepareCatalog(
        tester,
        app,
        root,
        section: ActionDaySection.incomplete,
        total: 121,
      );
      final rootOffset = _catalogScroll(tester).position.pixels;
      final rootViewport = tester
          .widget<ActionDayCalendar>(
            find.byType(ActionDayCalendar, skipOffstage: false),
          )
          .viewport;
      await openHome(tester);
      final firstSection = await app.open(tester);
      await app.ready(tester, firstSection);
      final (first, _) = await _openStatisticsDay(tester, app, day);
      await _prepareCatalog(
        tester,
        app,
        first,
        section: ActionDaySection.completed,
        total: 122,
      );
      final firstOffset = _catalogScroll(tester).position.pixels;
      await _openActionRow(tester, 80);
      await showActionPanelPath(tester, waitFor: _waitForFinder);
      await openActionPanelPathIntention(tester, 'Намерение 2');
      await _wait(
        tester,
        () => find.text(app.texts.statisticsSectionTitle).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(app.texts.statisticsSectionTitle).first);
      await _wait(
        tester,
        () =>
            find.byType(IntentionStatisticsSectionSliver).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      final secondSection = tester
          .widget<IntentionStatisticsSectionSliver>(
            find.byType(IntentionStatisticsSectionSliver),
          )
          .provider;
      await app.ready(tester, secondSection);
      final (second, _) = await _openStatisticsDay(tester, app, day);
      // Действие с путём 1 → 4 не проходит через намерение 2, но день
      // показывает все свои действия.
      await showActionDaySection(tester, ActionDaySection.completed);
      await tester.pumpAndSettle();
      expect(find.text('Действие 122'), findsOneWidget);
      await _openActionRow(tester, 1);
      expect(shownActionHead(tester).action, 'Действие 122');
      await closeActionPanel(tester);
      await _prepareCatalog(
        tester,
        app,
        second,
        section: ActionDaySection.completed,
        total: 122,
      );
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;

      final changedAction = _catalogData(app, second).completed.items[79].id;
      final completion = find.byKey(
        ValueKey('action-day-completion-${changedAction.toCanonicalString()}'),
      );
      await tester.ensureVisible(completion);
      await tester.pumpAndSettle();
      final secondOffset = _catalogScroll(tester).position.pixels;
      expect(actionCompletionState(tester, completion).completed, isTrue);
      await tester.tap(completion);
      for (final (provider, count) in [
        (root, 121),
        (first, 122),
        (second, 122),
      ]) {
        await _catalogReady(tester, app, provider, total: count);
        expect(
          _catalogData(app, provider)
              .section(
                provider == root
                    ? ActionDaySection.incomplete
                    : ActionDaySection.completed,
              )
              .items,
          hasLength(100),
        );
      }
      expect(
        _catalogData(
          app,
          first,
        ).completed.items.any((item) => item.id == changedAction),
        isFalse,
      );
      expect(
        _catalogData(
          app,
          second,
        ).items.singleWhere((item) => item.id == changedAction).isCompleted,
        isFalse,
      );
      for (final provider in [root, first, second]) {
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          day,
          ActionDayStatus.hasIncomplete,
        );
      }

      expect(_catalogScroll(tester).position.pixels, secondOffset);
      for (final provider in [root, first, second]) {
        final selection = _catalogData(app, provider).selection;
        expect(selection.date, provider == root ? _today : day);
        expect(selection.incompleteExpanded, provider == root);
        expect(selection.completedExpanded, provider != root);
      }
      // Для отдельной правки даты человек раскрывает новую секцию действия.
      await showActionDaySection(tester, ActionDaySection.incomplete);
      await tester.pumpAndSettle();
      final editOffset = _catalogScroll(tester).position.pixels;
      await _openActionRow(tester, 1);
      expect(shownActionId(tester), changedAction);
      await chooseActionPanelDate(tester, _today, from: day);
      await _wait(
        tester,
        () => actionPanelField('Сегодня').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      for (final (provider, count) in [
        (root, 122),
        (first, 121),
        (second, 121),
      ]) {
        await _catalogReady(tester, app, provider, total: count);
        expect(
          _catalogData(app, provider)
              .section(
                provider == root
                    ? ActionDaySection.incomplete
                    : ActionDaySection.completed,
              )
              .items,
          hasLength(100),
        );
      }
      expect(
        _catalogData(
          app,
          root,
        ).incomplete.items.any((item) => item.id == changedAction),
        isFalse,
      );
      expect(_catalogData(app, root).incomplete.nextCursor, isNotNull);
      expect(
        _catalogData(app, second).items.any((item) => item.id == changedAction),
        isFalse,
      );
      for (final provider in [root, first, second]) {
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          day,
          ActionDayStatus.allCompleted,
        );
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          _today,
          ActionDayStatus.hasIncomplete,
        );
      }
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      expect(_catalogData(app, root).selection.date, _today);
      expect(_catalogData(app, root).selection.completedExpanded, isFalse);
      expect(_catalogData(app, first).selection.date, day);
      expect(_catalogData(app, first).selection.completedExpanded, isTrue);
      expect(_catalogData(app, second).selection.date, day);
      expect(_catalogData(app, second).selection.incompleteExpanded, isTrue);
      expect(_catalogData(app, second).selection.completedExpanded, isFalse);

      await closeActionPanel(tester);
      expect(_catalogScroll(tester).position.pixels, editOffset);
      await _expectVisibleCatalogMarks(tester, day);
      await _catalogBack(tester);
      await app.ready(tester, secondSection);
      await _catalogBack(tester);
      await _catalogBack(tester);
      expect(_catalogScroll(tester).position.pixels, firstOffset);
      await _expectVisibleCatalogMarks(tester, day);
      await openActions(tester);
      await tester.pumpAndSettle();
      expectActionsRootPage(app.container.read(appRouterProvider));
      expect(_catalogScroll(tester).position.pixels, rootOffset);
      await _expectVisibleCatalogMarks(tester, day);
      final restored = tester.widget<ActionDayCalendar>(
        find.byType(ActionDayCalendar),
      );
      expect(
        (restored.viewport.focusedDate, restored.viewport.mode),
        (rootViewport.focusedDate, rootViewport.mode),
      );
      expect(find.byType(ActionDayDatePage, skipOffstage: false), findsNothing);
      expect(
        find.byType(IntentionDetailsPage, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

int _finishedCatalogReads(_App app) => app.diagnostics.events
    .whereType<ActionDayPageReadDiagnosticsEvent>()
    .where((event) => event.status is! DiagnosticsStarted)
    .length;

ActionDayViewModelProvider _visibleCatalog(WidgetTester tester) =>
    actionDayViewModelProvider(
      tester.widget<ActionDayBody>(find.byType(ActionDayBody)).instance,
    );

ActionDayLoaded _catalogData(_App app, ActionDayViewModelProvider provider) =>
    app.container.read(provider) as ActionDayLoaded;

final _catalogScrollable = find.descendant(
  of: find.byType(ActionDayBody),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

ScrollableState _catalogScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(_catalogScrollable);

/// Показывает секцию [section] с полной порцией в 100 строк и прокручивает
/// выдачу ниже восьмидесятой строки.
Future<void> _prepareCatalog(
  WidgetTester tester,
  _App app,
  ActionDayViewModelProvider provider, {
  required ActionDaySection section,
  required int total,
}) async {
  await _catalogReady(tester, app, provider);
  _catalogScroll(tester).position.jumpTo(0);
  await tester.pumpAndSettle();
  await showActionDaySection(tester, section);
  await _catalogReady(tester, app, provider, total: total);
  await tester.tap(find.bySemanticsLabel(app.texts.actionCalendarExpand));
  await tester.pumpAndSettle();
  await scrollToActionDayEnd(tester, section);
  await _wait(
    tester,
    () => _catalogData(app, provider).section(section).items.length == 100,
  );
  // Строки нумеруются сквозно: у выполненных перед ними стоят невыполненные.
  final skipped = switch (section) {
    ActionDaySection.incomplete => 0,
    ActionDaySection.completed => _catalogData(
      app,
      provider,
    ).incomplete.items.length,
  };
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('action-day-row-${80 + skipped}')),
    500,
    scrollable: _catalogScrollable,
  );
  await tester.pumpAndSettle();
  expect(_catalogScroll(tester).position.pixels, greaterThan(1000));
}

Future<void> _waitForCatalogMark(
  WidgetTester tester,
  _App app,
  ActionDayViewModelProvider provider,
  CalendarDate date,
  ActionDayStatus status,
) => _wait(tester, () {
  final instance = app.container.read(provider.notifier).instance;
  return app.container
          .read(actionDayMarksViewModelProvider(instance))
          .dayStatuses
          ?.statuses[date] ==
      status;
});

Future<void> _expectVisibleCatalogMarks(
  WidgetTester tester,
  CalendarDate day,
) async {
  _catalogScroll(tester).position.jumpTo(0);
  await tester.pumpAndSettle();
  for (final (date, status) in [
    (day, ActionDayStatus.allCompleted),
    (_today, ActionDayStatus.hasIncomplete),
  ]) {
    final cell = find.byKey(
      ValueKey('action-day-calendar-day-${date.toCanonicalString()}'),
    );
    expect(tester.widget<ActionDayCalendarDay>(cell).status, status);
  }
}

/// 243 действия «Действие N»: первые 121 невыполненные на [_today], остальные
/// выполненные на 7 октября. Действие 122 идёт по пути 1 → 4, остальные — по
/// пути 1 → 2 → 3.
Future<void> _seedCatalogActions(AppDatabase database) =>
    seedGraph(database, () async {
      for (var number = 1; number <= 243; number++) {
        final id = seedUuid(1000 + number);
        final path = number == 122 ? [1, 4] : [1, 2, 3];
        await database.customStatement(
          'INSERT INTO actions (id, title, date, priority, is_completed, '
          'created_at, updated_at) VALUES (?, ?, ?, 4, ?, 1, 1)',
          [
            id,
            'Действие $number',
            number <= 121 ? '2026-10-12' : '2026-10-07',
            number <= 121 ? 0 : 1,
          ],
        );
        for (final (position, intention) in path.indexed) {
          await database.customStatement(
            'INSERT INTO action_path_items (action_id, position, '
            'intention_id, previous_intention_id) VALUES (?, ?, ?, ?)',
            [
              id,
              position,
              seedUuid(intention),
              position == 0 ? null : seedUuid(path[position - 1]),
            ],
          );
        }
      }
    });

Future<(ActionDayViewModelProvider, double)> _openStatisticsDay(
  WidgetTester tester,
  _App app,
  CalendarDate day,
) async {
  final dateLabel = app.texts.statisticsCalendarDaySemantics(
    DateTime.utc(day.year, day.month, day.day),
    '',
  );
  final target = find.bySemanticsLabel(RegExp('^${RegExp.escape(dateLabel)}'));
  await tester.ensureVisible(target);
  await tester.pump();
  final offset = _scroll(tester).position.pixels;
  await tester.tap(target);
  await _wait(
    tester,
    () => find.byType(ActionDayDatePage).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 400));
  final instance = tester
      .widget<ActionDayBody>(find.byType(ActionDayBody))
      .instance;
  final provider = actionDayViewModelProvider(instance);
  await _catalogReady(tester, app, provider);
  return (provider, offset);
}

Future<void> _catalogReady(
  WidgetTester tester,
  _App app,
  ActionDayViewModelProvider provider, {
  int? total,
}) => _wait(
  tester,
  () => switch (app.container.read(provider)) {
    ActionDayLoaded(:final totalCount, freshness: ActionDayFreshness.current)
        when total == null || total == totalCount =>
      true,
    _ => false,
  },
);

/// Открывает панель действия строки [row] открытого экрана дня.
Future<void> _openActionRow(WidgetTester tester, int row) async {
  final body = tester.widget<ActionDayBody>(find.byType(ActionDayBody));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ActionDayBody)),
  );
  final state = container.read(
    actionDayViewModelProvider(body.instance),
  ) as ActionDayLoaded;
  await showActionDaySection(
    tester,
    row > state.incomplete.items.length
        ? ActionDaySection.completed
        : ActionDaySection.incomplete,
  );
  final target = find.byKey(ValueKey('action-day-row-$row'));
  await tester.scrollUntilVisible(target, 500, scrollable: _catalogScrollable);
  await tester.tap(target);
  await _wait(tester, () => actionPanelReady.evaluate().isNotEmpty);
  await tester.pumpAndSettle();
}

/// Ожидание сценария для шагов, которые ждут появления элемента.
Future<void> _waitForFinder(WidgetTester tester, Finder finder) =>
    _wait(tester, () => finder.evaluate().isNotEmpty);

Future<void> _catalogBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
