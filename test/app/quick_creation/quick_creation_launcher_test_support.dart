part of 'quick_creation_launcher_test.dart';

enum _Origin {
  home('Главной', 0, HomePage),
  deep('глубокой страницей', 1, IntentionDetailsPage);

  const _Origin(this.label, this.tabIndex, this.page);
  final String label;
  final int tabIndex;
  final Type page;
}

Finder _key(String key) => find.byKey(ValueKey(key));
List<LocalKey> _history(RootStackRouter router) => [
  for (final data in router.stackData) data.matchId,
];

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
      router.push(IntentionDetailsRoute(intentionId: durabilityIntention(2))),
    );
    await tester.pumpAndSettle();
  }
  return tester.element(find.byType(origin.page));
}

Future<RootStackRouter> _openApp(
  WidgetTester tester, {
  CalendarDate? today,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase(openInMemoryLocalDatabase());
  await seedDurabilityGraph(database);
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      if (today != null) ControlledLocalDate(today).override,
      personalGraphRepositoryProvider.overrideWithValue(
        durabilityRepository(database),
      ),
    ],
  );
  final appRouter = AppRouter();
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
