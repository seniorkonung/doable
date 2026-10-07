part of 'creation_flows_integration_test.dart';

/// Четыре публичных входа Phase 2, без временных кнопок в приложении.
enum _Flow {
  intention(
    'намерение',
    'intentions',
    5,
    'intention-editor-submit',
    IntentionDetailsRoute.name,
  ),
  relation(
    'пустая связь',
    'long_term_relations',
    4,
    'relation-editor-submit',
    RelationDetailsRoute.name,
  ),
  topDown(
    'дневной выбор от намерения',
    'daily_choices',
    0,
    'daily-choice-submit',
    DailyChoiceDetailsRoute.name,
  ),
  bottomUp(
    'дневной выбор от действия',
    'daily_choices',
    0,
    'daily-choice-submit',
    DailyChoiceDetailsRoute.name,
  );

  const _Flow(
    this.label,
    this.table,
    this.initialRows,
    this.submit,
    this.resultRoute,
  );
  final String label;
  final String table;
  final int initialRows;
  final String submit;
  final String resultRoute;

  Future<void> open(
    WidgetTester tester,
    _App app,
    IntentionCreationOrigin origin,
  ) async {
    switch (this) {
      case intention:
        unawaited(app.router.push(const IntentionEditorRoute()));
      case relation:
        unawaited(
          app.router.push(
            RelationEditorRoute(
              editorContext: const RelationBlankCreationContext(),
            ),
          ),
        );
      case topDown || bottomUp:
        final page = origin == IntentionCreationOrigin.deep
            ? IntentionDetailsPage
            : switch (origin.destination) {
                AppDestination.home => HomePage,
                AppDestination.dailyChoices => DailyChoiceCatalogPage,
                AppDestination.intentionGraph => IntentionCatalogPage,
              };
        unawaited(
          DailyChoiceCreationLauncher().launch(
            sourceContext: tester.element(find.byType(page)),
            direction: this == topDown
                ? ChoicePathDraftDirection.topDown
                : ChoicePathDraftDirection.bottomUp,
          ),
        );
    }
    await tester.pumpAndSettle();
    expect(app.router.current.name, switch (this) {
      intention => IntentionEditorRoute.name,
      relation => RelationEditorRoute.name,
      topDown => DailyChoiceSourcePickerRoute.name,
      bottomUp => DailyChoiceActionPickerRoute.name,
    });
    // Под модальной панелью намерения исходная панель видна, но недоступна.
    expect(find.byType(AppNavigationBar).hitTestable(), findsNothing);
    if (this != intention) expect(find.byType(AppNavigationBar), findsNothing);
  }

  Future<void> fill(WidgetTester tester) async {
    switch (this) {
      case intention:
        await tester.enterText(_key('intention-editor-title'), 'Новое');
        await tester.enterText(
          _key('intention-editor-description'),
          'Сохранённое описание',
        );
      case relation:
        for (final (role, number) in [('source', 5), ('related', 4)]) {
          await _tap(tester, _key('relation-editor-select-$role'));
          await _tap(
            tester,
            find.widgetWithText(IntentionSummaryView, 'Намерение $number'),
          );
        }
        await _tap(tester, _key('relation-editor-type-need'));
        await _tap(tester, _key('relation-editor-priority-p1'));
        await tester.enterText(
          _key('relation-editor-description'),
          'Сохранённое описание',
        );
      case topDown || bottomUp:
        final prefix = this == topDown ? 'source' : 'action';
        final number = this == topDown ? 1 : 4;
        final row = _key('daily-choice-$prefix-${durabilityUuid(number)}');
        await _tap(
          tester,
          find.descendant(of: row, matching: find.byType(IntentionSummaryView)),
        );
        expect(find.byType(AppNavigationBar), findsNothing);
        await _tap(tester, _key('choice-path-continue-${durabilityUuid(103)}'));
        await _tap(
          tester,
          _key(
            this == topDown
                ? 'choice-path-select-action'
                : 'choice-path-select-source',
          ),
        );
        await _tap(tester, _key('choice-path-open-confirmation'));
        expect(find.byType(AppNavigationBar), findsNothing);
        await tester.enterText(_key('daily-choice-date'), '2026-10-09');
        await tester.enterText(
          _key('daily-choice-description'),
          'Сохранённое описание',
        );
    }
    await tester.pumpAndSettle();
  }

  void expectStored(Map<String, Object?> row) {
    expect(row['description'], 'Сохранённое описание');
    switch (this) {
      case intention:
        expect(row['title'], 'Новое');
      case relation:
        expect(row['source_intention_id'], durabilityUuid(5));
        expect(row['related_intention_id'], durabilityUuid(4));
        expect(row['type'], 'need');
        expect(row['priority'], 1);
      case topDown || bottomUp:
        expect(row['source_intention_id'], durabilityUuid(1));
        expect(row['selected_intention_id'], durabilityUuid(4));
        expect(row['choice_date'], '2026-10-09');
    }
  }
}

final class _App {
  _App(this.router, this.container, this.database, this.observer);
  final AppRouter router;
  final ProviderContainer container;
  final AppDatabase database;
  final _CreationObserver observer;

  AppLocalizations get l10n =>
      AppLocalizations.of(router.navigatorKey.currentContext!);

  Object get catalogs {
    final intentions = container
        .read(intentionCatalogViewModelProvider(const BrowseIntentionCatalog()))
        .requireValue
        .selection;
    final daily = container.read(dailyChoiceCatalogViewModelProvider).selection;
    return (
      intentions.scope,
      intentions.titleFilterText,
      intentions.order,
      intentions.tagFilter,
      daily.date,
      daily.isCompleted,
    );
  }
}

/// Управляет задержкой реального SQL создания, не заменяя команду или граф.
final class _CreationObserver extends LocalDatabaseConnectionObserver {
  String? _table;
  Completer<void>? _gate;
  var attempts = 0;

  void observe(String table, {bool hold = false}) {
    _table = table;
    if (hold) _gate = Completer<void>();
  }

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    final table = _table;
    if (table == null ||
        !statement.statements.any(
          (sql) => RegExp(
            '^\\s*INSERT\\s+INTO\\s+"?$table"?\\s',
            caseSensitive: false,
          ).hasMatch(sql),
        ))
      return;
    attempts++;
    await _gate?.future;
  }
}

Future<_App> _start(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  bool fileBacked = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = fileBacked
      ? await tester.runAsync(LocalDatabaseHarness.fileBacked)
      : LocalDatabaseHarness.inMemory();
  final observer = _CreationObserver();
  final database = await tester.runAsync(
    () => harness!.openReadyDatabase(observer: observer),
  );
  await tester.runAsync(() => seedDurabilityGraph(database!));
  final container = ProviderContainer(
    overrides: [
      personalGraphRepositoryProvider.overrideWithValue(
        durabilityRepository(database!),
      ),
      ControlledDailyChoiceLocalDate(CalendarDate.fromParts(2026, 10, 8))
          .override,
    ],
  );
  final router = AppRouter();
  addTearDown(() async {
    observer.release();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    router.dispose();
    await tester.runAsync(harness!.dispose);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final tabs = router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
  tabs.setActiveIndex(2);
  await tester.pumpAndSettle();
  container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
          .notifier,
    )
    ..changeOrder(IntentionCatalogOrder.createdAtAscending)
    ..changeTitleFilter('Намерение');
  await tester.pumpAndSettle();
  tabs.setActiveIndex(1);
  await tester.pumpAndSettle();
  container.read(dailyChoiceCatalogViewModelProvider.notifier)
    ..selectDate(CalendarDate.fromParts(2026, 10, 7))
    ..selectCompletion(true);
  await tester.pumpAndSettle();
  return _App(router, container, database, observer);
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, _App app, _Flow flow) async {
  await _reveal(tester, _key(flow.submit));
  await tester.tap(_key(flow.submit));
  await _until(tester, () => app.observer.attempts == 1);
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

Future<void> _closeCreation(WidgetTester tester, _App app, _Flow flow) async {
  final ownedRoute = app.router.current.matchId;
  if (flow == _Flow.intention) {
    await tester.tap(_key('intention-editor-close'));
    await _until(
      tester,
      () => _key('intention-editor-close-discard').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(_key('intention-editor-close-discard'));
    await tester.tap(_key('intention-editor-close-discard'));
  } else {
    final label = app.observer.attempts == 0
        ? app.l10n.creationCancelAction
        : app.l10n.creationLeaveAction;
    final button = find.widgetWithText(TextButton, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
  }
  await _until(
    tester,
    () => app.router.stackData.every((route) => route.matchId != ownedRoute),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(condition(), isTrue);
}
