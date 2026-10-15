part of 'intention_statistics_app_flow_test.dart';

void _catalogNavigationScenarios() {
  testWidgets(
    'сброс из каталога на дату сохраняет корень, повторный выбор Главной и позднее чтение не возвращают историю',
    (tester) async {
      final app = await _start(tester, seed: _seedCatalogChoices);
      await openDailyChoices(tester);
      await _wait(
        tester,
        () => find.byType(DailyChoiceCatalogBody).evaluate().isNotEmpty,
      );
      final root = _visibleCatalog(tester);
      await _prepareCatalog(
        tester,
        app,
        root,
        completed: 'Не выполненные',
        total: 121,
      );
      final offset = _catalogScroll(tester).position.pixels;
      final calendar = tester.widget<DailyChoiceCalendar>(
        find.byType(DailyChoiceCalendar, skipOffstage: false),
      );
      final viewport = (calendar.viewport.focusedDate, calendar.viewport.mode);
      final items = _catalogData(
        app,
        root,
      ).items.map((item) => item.id).toList();

      for (final resetToDaily in [false, true]) {
        await openHome(tester);
        final section = await app.open(tester);
        await app.ready(tester, section);
        final (catalog, _) = await _openStatisticsDay(
          tester,
          app,
          CalendarDate.fromParts(2026, 10, 7),
        );
        expect(_catalogData(app, catalog).selection.isCompleted, isNull);
        expect(_catalogData(app, catalog).items, hasLength(50));
        expect(find.text('Все состояния'), findsOneWidget);
        expect(
          find.bySemanticsLabel(app.texts.dailyChoiceCalendarExpand),
          findsOneWidget,
        );
        final held = app.probe.holdNextCatalogRead();
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-completion-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Выполненные').last);
        await _wait(tester, () => held.started.isCompleted);
        final finished = _finishedCatalogReads(app);

        if (resetToDaily) {
          await openDailyChoices(tester);
        } else {
          await openHome(tester);
        }
        await tester.pumpAndSettle();
        final router = app.container.read(appRouterProvider);
        if (resetToDaily) {
          expectDailyChoicesRootPage(router);
        } else {
          expectHomeRootPage(router);
        }
        held.release.complete();
        await _wait(tester, () => _finishedCatalogReads(app) == finished + 1);
        await tester.pumpAndSettle();
        if (resetToDaily) {
          expectDailyChoicesRootPage(router);
        } else {
          expectHomeRootPage(router);
        }
        expect(
          find.byType(DailyChoiceDateCatalogPage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(IntentionDetailsPage, skipOffstage: false),
          findsNothing,
        );
        await openDailyChoices(tester);
        await tester.pumpAndSettle();
        expect(_catalogData(app, root).selection.date, _today);
        expect(_catalogData(app, root).selection.isCompleted, isFalse);
        expect(_catalogData(app, root).items.map((item) => item.id), items);
        expect(_catalogScroll(tester).position.pixels, offset);
        final restored = tester.widget<DailyChoiceCalendar>(
          find.byType(DailyChoiceCalendar, skipOffstage: false),
        );
        expect((
          restored.viewport.focusedDate,
          restored.viewport.mode,
        ), viewport);
        _catalogScroll(tester).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('Не выполненные'), findsOneWidget);
        expect(
          find.text(app.texts.dailyChoiceCatalogTotalCount(121)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(app.texts.dailyChoiceCalendarCollapse),
          findsOneWidget,
        );
        _catalogScroll(tester).position.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'два каталога одной даты и скрытый корневой согласуют выполнение и перенос, сохраняя порции и просмотр',
    (tester) async {
      final app = await _start(tester, seed: _seedCatalogChoices);
      final day = CalendarDate.fromParts(2026, 10, 7);
      await openDailyChoices(tester);
      await _wait(
        tester,
        () => find.byType(DailyChoiceCatalogBody).evaluate().isNotEmpty,
      );
      final root = _visibleCatalog(tester);
      await _prepareCatalog(
        tester,
        app,
        root,
        completed: 'Не выполненные',
        total: 121,
      );
      final rootOffset = _catalogScroll(tester).position.pixels;
      final rootViewport = tester
          .widget<DailyChoiceCalendar>(
            find.byType(DailyChoiceCalendar, skipOffstage: false),
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
        completed: 'Выполненные',
        total: 122,
      );
      final firstOffset = _catalogScroll(tester).position.pixels;
      await _openChoiceRow(tester, 80);
      final participant = find.byKey(
        const ValueKey('daily-choice-intention-2'),
      );
      await tester.ensureVisible(participant);
      await tester.tap(participant);
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
      // Выбор по прямому пути 1 → 4 не засчитан намерению 2, но доступен в каталоге дня.
      expect(
        find.text(
          app.texts.dailyChoiceDetailsPhrase('Намерение 1', 'Намерение 4'),
        ),
        findsOneWidget,
      );
      await _openChoiceRow(tester, 1);
      expect(
        find.text('${app.texts.dailyChoiceDetailsSelectedAction}: Намерение 4'),
        findsOneWidget,
      );
      await _catalogBack(tester);
      await _prepareCatalog(tester, app, second, total: 122);
      final secondOffset = _catalogScroll(tester).position.pixels;
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;

      await _openChoiceRow(tester, 80);
      final changedChoice = tester
          .widget<DailyChoiceDetailsPage>(find.byType(DailyChoiceDetailsPage))
          .choiceId;
      await _editChoice(tester, completed: false);
      for (final (provider, count) in [
        (root, 121),
        (first, 121),
        (second, 122),
      ]) {
        await _catalogReady(tester, app, provider, total: count);
        expect(_catalogData(app, provider).items, hasLength(100));
      }
      expect(
        _catalogData(app, first).items.any((item) => item.id == changedChoice),
        isFalse,
      );
      expect(
        _catalogData(
          app,
          second,
        ).items.singleWhere((item) => item.id == changedChoice).isCompleted,
        isFalse,
      );
      for (final provider in [root, first, second]) {
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          day,
          DailyChoiceDayStatus.hasIncomplete,
        );
      }

      await _editChoice(tester, date: _today);
      for (final (provider, count) in [
        (root, 122),
        (first, 121),
        (second, 121),
      ]) {
        await _catalogReady(tester, app, provider, total: count);
        expect(_catalogData(app, provider).items, hasLength(100));
      }
      expect(_catalogData(app, root).items.first.id, changedChoice);
      expect(
        _catalogData(app, second).items.any((item) => item.id == changedChoice),
        isFalse,
      );
      for (final provider in [root, first, second]) {
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          day,
          DailyChoiceDayStatus.allCompleted,
        );
        await _waitForCatalogMark(
          tester,
          app,
          provider,
          _today,
          DailyChoiceDayStatus.hasIncomplete,
        );
      }
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      expect(_catalogData(app, root).selection.date, _today);
      expect(_catalogData(app, root).selection.isCompleted, isFalse);
      expect(_catalogData(app, first).selection.date, day);
      expect(_catalogData(app, first).selection.isCompleted, isTrue);
      expect(_catalogData(app, second).selection.date, day);
      expect(_catalogData(app, second).selection.isCompleted, isNull);

      await _catalogBack(tester);
      expect(_catalogScroll(tester).position.pixels, secondOffset);
      await _expectVisibleCatalogMarks(tester, day);
      await _catalogBack(tester);
      await app.ready(tester, secondSection);
      expect(_counts(app.loaded(secondSection)), (242, 120));
      await _catalogBack(tester);
      await _catalogBack(tester);
      expect(_catalogScroll(tester).position.pixels, firstOffset);
      await _expectVisibleCatalogMarks(tester, day);
      await openDailyChoices(tester);
      await tester.pumpAndSettle();
      expectDailyChoicesRootPage(app.container.read(appRouterProvider));
      expect(_catalogScroll(tester).position.pixels, rootOffset);
      await _expectVisibleCatalogMarks(tester, day);
      final restored = tester.widget<DailyChoiceCalendar>(
        find.byType(DailyChoiceCalendar),
      );
      expect(
        (restored.viewport.focusedDate, restored.viewport.mode),
        (rootViewport.focusedDate, rootViewport.mode),
      );
      expect(
        find.byType(DailyChoiceDateCatalogPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(IntentionDetailsPage, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'правка над каталогом из статистики завершается до подсчёта, скрытый раздел не читает до возврата',
    (tester) async {
      final app = await _start(tester);
      final day = CalendarDate.fromParts(2026, 10, 7);
      await app.choice(tester, durabilityCreate(date: day, completed: false));
      final section = await app.open(tester);
      await app.ready(tester, section);
      final held = app.probe.holdNextComputation();
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      await _wait(tester, () => held.started.isCompleted);
      final (catalog, offset) = await _openStatisticsDay(tester, app, day);
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;
      await _openChoiceRow(tester, 1);
      expect(app.probe.sourceReads, reads);
      final moved = CalendarDate.fromParts(2026, 10, 11);
      await _editChoice(tester, completed: false, date: moved);
      expect(held.finished.isCompleted, isFalse);
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      final saved = await tester.runAsync(
        () => durabilityRows(app.database, 'daily_choices'),
      );
      expect(saved!.single['choice_date'], moved.toCanonicalString());
      expect(saved.single['is_completed'], 0);

      final finished = app.finishedSections;
      held.release.complete();
      await _wait(tester, () => app.finishedSections == finished + 1);
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      await _catalogBack(tester);
      await _catalogReady(tester, app, catalog, total: 0);
      expect(find.text(app.texts.dailyChoiceCatalogEmpty), findsOneWidget);
      expect(app.probe.sourceReads, reads);

      await _catalogBack(tester);
      await app.ready(tester, section);
      await tester.pumpAndSettle();
      expect(app.probe.sourceReads, reads + 1);
      expect(app.probe.computations, computations + 1);
      expect(_counts(app.loaded(section)), (1, 0));
      expect(
        (app.loaded(section).section.calendar
                as IntentionStatisticsMonthCalendar)
            .statuses,
        {moved: DailyChoiceDayStatus.hasIncomplete},
      );
      expect(
        app.container.read(section).selection.view,
        StatisticsView.throughRelations,
      );
      expect(
        app.container.read(section).selection.period,
        StatisticsMonth(2026, 10),
      );
      expect(_scroll(tester).position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );
}

int _finishedCatalogReads(_App app) => app.diagnostics.events
    .whereType<DailyChoiceCatalogPageReadDiagnosticsEvent>()
    .where((event) => event.status is! DiagnosticsStarted)
    .length;

DailyChoiceCatalogViewModelProvider _visibleCatalog(WidgetTester tester) =>
    dailyChoiceCatalogViewModelProvider(
      tester
          .widget<DailyChoiceCatalogBody>(find.byType(DailyChoiceCatalogBody))
          .instance,
    );

DailyChoiceCatalogLoaded _catalogData(
  _App app,
  DailyChoiceCatalogViewModelProvider provider,
) => app.container.read(provider) as DailyChoiceCatalogLoaded;

final _catalogScrollable = find.descendant(
  of: find.byType(DailyChoiceCatalogBody),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

ScrollableState _catalogScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(_catalogScrollable);

Future<void> _prepareCatalog(
  WidgetTester tester,
  _App app,
  DailyChoiceCatalogViewModelProvider provider, {
  String? completed,
  required int total,
}) async {
  await _catalogReady(tester, app, provider);
  _catalogScroll(tester).position.jumpTo(0);
  await tester.pumpAndSettle();
  if (completed != null) {
    await tester.tap(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(completed).last);
  }
  await _catalogReady(tester, app, provider, total: total);
  await tester.tap(find.bySemanticsLabel(app.texts.dailyChoiceCalendarExpand));
  await tester.pumpAndSettle();
  final footer = find.byKey(const ValueKey('daily-choice-load-more'));
  await tester.scrollUntilVisible(footer, 500, scrollable: _catalogScrollable);
  await tester.tap(footer);
  await _wait(tester, () => _catalogData(app, provider).items.length == 100);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('daily-choice-row-80')),
    500,
    scrollable: _catalogScrollable,
  );
  await tester.pumpAndSettle();
  expect(_catalogScroll(tester).position.pixels, greaterThan(1000));
}

Future<void> _waitForCatalogMark(
  WidgetTester tester,
  _App app,
  DailyChoiceCatalogViewModelProvider provider,
  CalendarDate date,
  DailyChoiceDayStatus status,
) => _wait(tester, () {
  final instance = app.container.read(provider.notifier).instance;
  return app.container
          .read(dailyChoiceCalendarDayMarksViewModelProvider(instance))
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
    (day, DailyChoiceDayStatus.allCompleted),
    (_today, DailyChoiceDayStatus.hasIncomplete),
  ]) {
    final cell = find.byKey(
      ValueKey('daily-choice-calendar-day-${date.toCanonicalString()}'),
    );
    expect(tester.widget<DailyChoiceCalendarDay>(cell).status, status);
  }
}

Future<void> _seedCatalogChoices(AppDatabase database) =>
    database.transaction(() async {
      for (var number = 1; number <= 243; number++) {
        final id = 1000 + number;
        final foreign = number == 243;
        final date = number <= 121 ? '2026-10-12' : '2026-10-07';
        await database.customStatement(
          'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
          [
            durabilityUuid(id),
            durabilityUuid(1),
            durabilityUuid(foreign ? 4 : 3),
            date,
            number <= 121 ? 0 : 1,
          ],
        );
        final path = foreign ? [103] : [101, 102];
        for (var step = 0; step < path.length; step++) {
          await database.customStatement(
            'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id, previous_step_id) VALUES (?, ?, ?, ?)',
            [
              durabilityUuid(id * 10 + step),
              durabilityUuid(id),
              durabilityUuid(path[step]),
              step == 0 ? null : durabilityUuid(id * 10 + step - 1),
            ],
          );
        }
      }
    });

Future<(DailyChoiceCatalogViewModelProvider, double)> _openStatisticsDay(
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
    () => find.byType(DailyChoiceDateCatalogPage).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 400));
  final instance = tester
      .widget<DailyChoiceCatalogBody>(find.byType(DailyChoiceCatalogBody))
      .instance;
  final provider = dailyChoiceCatalogViewModelProvider(instance);
  await _catalogReady(tester, app, provider);
  return (provider, offset);
}

Future<void> _catalogReady(
  WidgetTester tester,
  _App app,
  DailyChoiceCatalogViewModelProvider provider, {
  int? total,
}) => _wait(
  tester,
  () => switch (app.container.read(provider)) {
    DailyChoiceCatalogLoaded(
      :final totalCount,
      freshness: DailyChoiceCatalogFreshness.current,
    )
        when total == null || total == totalCount =>
      true,
    _ => false,
  },
);

Future<void> _openChoiceRow(WidgetTester tester, int row) async {
  final target = find.byKey(ValueKey('daily-choice-row-$row'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _wait(
    tester,
    () => find
        .byKey(const ValueKey('daily-choice-edit-open'))
        .evaluate()
        .isNotEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _editChoice(
  WidgetTester tester, {
  bool? completed,
  CalendarDate? date,
}) async {
  await tester.tap(find.byKey(const ValueKey('daily-choice-edit-open')));
  await _wait(
    tester,
    () => find.byType(DailyChoiceEditPage).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
  if (completed != null) {
    final toggle = find.byKey(const ValueKey('daily-choice-edit-completed'));
    expect(tester.widget<SwitchListTile>(toggle).value, !completed);
    await tester.tap(toggle);
  }
  if (date != null) {
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-date')),
      date.toCanonicalString(),
    );
  }
  final submit = find.byKey(const ValueKey('daily-choice-edit-submit'));
  await tester.pump();
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await _wait(
    tester,
    () => find.byType(DailyChoiceEditPage).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  expect(find.byType(DailyChoiceDetailsPage), findsOneWidget);
}

Future<void> _catalogBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
