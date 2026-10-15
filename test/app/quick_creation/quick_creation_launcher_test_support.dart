part of 'quick_creation_launcher_test.dart';

enum _Origin {
  home('Главной', 0, HomePage),
  daily('каталогом дневных выборов', 1, DailyChoiceCatalogPage),
  deep('глубокой страницей', 1, IntentionDetailsPage);

  const _Origin(this.label, this.tabIndex, this.page);
  final String label;
  final int tabIndex;
  final Type page;
}

String _label(QuickCreationMode mode, ChoicePathDraftDirection? direction) =>
    switch (mode) {
      QuickCreationMode.intention => 'Намерение',
      QuickCreationMode.relation => 'Связь',
      QuickCreationMode.dailyChoice =>
        'Дневной выбор: ${_directionLabel(direction!)}',
    };

String _directionLabel(ChoicePathDraftDirection direction) =>
    switch (direction) {
      ChoicePathDraftDirection.topDown => 'от намерения',
      ChoicePathDraftDirection.bottomUp => 'от действия',
    };

String _firstRoute(
  QuickCreationMode mode,
  ChoicePathDraftDirection? direction,
) => switch (mode) {
  QuickCreationMode.intention => IntentionEditorRoute.name,
  QuickCreationMode.relation => RelationEditorRoute.name,
  QuickCreationMode.dailyChoice => switch (direction!) {
    ChoicePathDraftDirection.topDown => DailyChoiceSourcePickerRoute.name,
    ChoicePathDraftDirection.bottomUp => DailyChoiceActionPickerRoute.name,
  },
};

String _prefix(ChoicePathDraftDirection direction) => switch (direction) {
  ChoicePathDraftDirection.topDown => 'source',
  ChoicePathDraftDirection.bottomUp => 'action',
};

int _candidate(ChoicePathDraftDirection direction) => switch (direction) {
  ChoicePathDraftDirection.topDown => 1,
  ChoicePathDraftDirection.bottomUp => 3,
};

Future<void> _selectStart(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
) => chooseQuickCreationDailyChoiceStart(
  tester,
  direction,
  openedPage: _key('daily-choice-${_prefix(direction)}-filter'),
);

Finder _key(String key) => find.byKey(ValueKey(key));
List<LocalKey> _history(RootStackRouter router) => [
  for (final data in router.stackData) data.matchId,
];

Future<void> _choose(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
) async {
  await tester.tap(
    find.descendant(
      of: _key(
        'daily-choice-${_prefix(direction)}-${durabilityUuid(_candidate(direction))}',
      ),
      matching: find.byType(IntentionSummaryView),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _cancel(WidgetTester tester, QuickCreationMode mode) async {
  await tester.tap(
    mode == QuickCreationMode.intention
        ? _key('intention-editor-close')
        : find.text('Отменить создание'),
  );
  await tester.pumpAndSettle();
}

Future<BuildContext> _source(
  WidgetTester tester,
  RootStackRouter router,
  _Origin origin,
) async {
  router
      .innerRouterOf<TabsRouter>(AppShellRoute.name)!
      .setActiveIndex(origin.tabIndex);
  await tester.pumpAndSettle();
  if (origin == _Origin.deep) {
    unawaited(
      router.push(
        RelationEditorRoute(
          editorContext: const RelationBlankCreationContext(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      _key('relation-editor-description'),
      'Чужой черновик',
    );
    unawaited(
      router.push(IntentionDetailsRoute(intentionId: durabilityIntention(2))),
    );
    await tester.pumpAndSettle();
    await tester.tap(_key('intention-details-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _key('intention-details-edit-title'),
      'Несохранённое название',
    );
  }
  return tester.element(find.byType(origin.page));
}

Future<RootStackRouter> _openApp(
  WidgetTester tester, {
  RootStackRouter? router,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase(openInMemoryLocalDatabase());
  await seedDurabilityGraph(database);
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      personalGraphRepositoryProvider.overrideWithValue(
        durabilityRepository(database),
      ),
    ],
  );
  final appRouter = router ?? AppRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    appRouter.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: appRouter.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return appRouter;
}

/// Настоящий поиск закрывается сразу, а его ID доставляется после сброса.
final class _DelayedPickerRouter extends RootStackRouter {
  final _gate = Completer<void>();
  bool _hold = true;
  void release() => _gate.complete();
  @override
  List<AutoRoute> get routes => AppRouter().routes;
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    final hold =
        _hold &&
        (route.routeName == DailyChoiceSourcePickerRoute.name ||
            route.routeName == DailyChoiceActionPickerRoute.name);
    if (hold) _hold = false;
    final result = await super.push<T>(route, onFailure: onFailure);
    if (hold) await _gate.future;
    return result;
  }
}
