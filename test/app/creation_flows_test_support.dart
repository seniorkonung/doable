part of 'creation_flows_integration_test.dart';

/// Граф с тридцатью выполненными действиями 7 октября по пути 1 → 2.
Future<void> _seedActionsForReturn(AppDatabase database) async {
  await seedDurabilityGraph(database);
  await seedGraph(database, () async {
    for (var index = 0; index < 30; index++) {
      final id = seedUuid(200 + index);
      await database.customStatement(
        'INSERT INTO actions (id, title, date, priority, is_completed, '
        'created_at, updated_at) VALUES (?, ?, ?, 4, 1, 1, 1)',
        [id, 'Действие ${index + 1}', '2026-10-07'],
      );
      for (final (position, intention) in [1, 2].indexed) {
        await database.customStatement(insertActionPathItem, [
          id,
          position,
          seedUuid(intention),
          position == 0 ? null : seedUuid(1),
          actionPathRole(position, 2),
        ]);
      }
    }
  });
}

ScrollPosition _actionDayScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('action-day')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Таблица и число строк намерений в графе до создания.
const _intentionsTable = 'intentions';
const _initialIntentionRows = 5;
const _intentionSubmit = 'intention-editor-submit';

/// Открывает форму намерения двойным нажатием общей кнопки: запуск один.
Future<void> _openIntentionEditor(
  WidgetTester tester,
  _App app,
  IntentionCreationOrigin origin,
) async {
  await _until(
    tester,
    () => quickCreationAction().hitTestable().evaluate().isNotEmpty,
  );
  final history = [for (final route in app.router.stackData) route.matchId];
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: _key('intention-editor-title'),
    wait: (tester, finder) =>
        _until(tester, () => finder.evaluate().isNotEmpty),
    activate: (tester, button) async {
      final position = tester.getCenter(button);
      await tester.tapAt(position);
      await tester.tapAt(position);
    },
  );
  expect(app.router.stackData, hasLength(history.length + 1));
  expect(
    app.router.stackData.take(history.length).map((route) => route.matchId),
    orderedEquals(history),
  );
  expect(app.router.current.name, IntentionEditorRoute.name);
  // Под модальной панелью намерения исходная панель видна, но недоступна.
  expect(find.byType(AppNavigationBar).hitTestable(), findsNothing);
}

Future<void> _fillIntentionEditor(WidgetTester tester) async {
  await tester.enterText(_key('intention-editor-title'), 'Новое');
  await tester.enterText(
    _key('intention-editor-description'),
    'Сохранённое описание',
  );
  await tester.pumpAndSettle();
}

void _expectIntentionStored(Map<String, Object?> row) {
  expect(row['description'], 'Сохранённое описание');
  expect(row['title'], 'Новое');
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
    final daily = container.read(openedActionDayProvider(container)).selection;
    return (
      intentions.show,
      intentions.titleFilterText,
      intentions.order,
      intentions.tagFilter,
      daily.date,
      daily.completedExpanded,
    );
  }
}

/// Управляет задержкой реального SQL создания, не заменяя команду или граф.
final class _CreationObserver extends LocalDatabaseConnectionObserver {
  String? _table;
  Completer<void>? _gate;
  var attempts = 0;
  var _fail = false;

  void observe(String table, {bool hold = false, bool fail = false}) {
    _table = table;
    _fail = fail;
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
        )) {
      return;
    }
    attempts++;
    await _gate?.future;
    if (_fail) throw StateError('Управляемый отказ записи.');
  }
}

Future<_App> _start(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  bool fileBacked = false,
  Future<void> Function(AppDatabase) seed = seedDurabilityGraph,
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
  await tester.runAsync(() => seed(database!));
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      personalGraphRepositoryProvider.overrideWithValue(
        durabilityRepository(database!),
      ),
      ControlledLocalDate(CalendarDate.fromParts(2026, 10, 8)).override,
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
        theme: doableTheme(Brightness.light),
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
  container.read(openedActionDayProvider(container).notifier)
    ..selectDate(CalendarDate.fromParts(2026, 10, 7))
    ..toggleSection(ActionDaySection.incomplete);
  await tester.pumpAndSettle();
  return _App(router, container, database, observer);
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, _App app) async {
  await _reveal(tester, _key(_intentionSubmit));
  await tester.tap(_key(_intentionSubmit));
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

Future<void> _closeCreation(WidgetTester tester, _App app) async {
  final ownedRoute = app.router.current.matchId;
  await tester.tap(_key('intention-editor-close'));
  await _until(
    tester,
    () => _key('intention-editor-close-discard').evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(_key('intention-editor-close-discard'));
  await tester.tap(_key('intention-editor-close-discard'));
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
