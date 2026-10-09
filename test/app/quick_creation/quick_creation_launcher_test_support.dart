part of 'quick_creation_launcher_test.dart';

enum _Origin {
  home('Главной', 0, HomePage),
  daily('каталогом дневных выборов', 1, DailyChoiceCatalogPage),
  graph('каталогом намерений', 2, IntentionCatalogPage),
  deep('глубокой страницей', 1, IntentionDetailsPage);

  const _Origin(this.label, this.tabIndex, this.page);
  final String label;
  final int tabIndex;
  final Type page;
}

const _dailyModes = [
  QuickCreationMode.dailyChoiceFromIntention,
  QuickCreationMode.dailyChoiceFromAction,
];

String _label(QuickCreationMode mode) => switch (mode) {
  QuickCreationMode.intention => 'Намерение',
  QuickCreationMode.relation => 'Связь',
  QuickCreationMode.dailyChoiceFromIntention => 'Дневной выбор от намерения',
  QuickCreationMode.dailyChoiceFromAction => 'Дневной выбор от действия',
};

String _firstRoute(QuickCreationMode mode) => switch (mode) {
  QuickCreationMode.intention => IntentionEditorRoute.name,
  QuickCreationMode.relation => RelationEditorRoute.name,
  QuickCreationMode.dailyChoiceFromIntention =>
    DailyChoiceSourcePickerRoute.name,
  QuickCreationMode.dailyChoiceFromAction => DailyChoiceActionPickerRoute.name,
};

ChoicePathDraftDirection _direction(QuickCreationMode mode) =>
    mode == QuickCreationMode.dailyChoiceFromIntention
    ? ChoicePathDraftDirection.topDown
    : ChoicePathDraftDirection.bottomUp;

String _prefix(QuickCreationMode mode) =>
    mode == QuickCreationMode.dailyChoiceFromIntention ? 'source' : 'action';

int _candidate(QuickCreationMode mode) =>
    mode == QuickCreationMode.dailyChoiceFromIntention ? 1 : 3;

Finder _key(String key) => find.byKey(ValueKey(key));
List<LocalKey> _history(RootStackRouter router) => [
  for (final data in router.stackData) data.matchId,
];

Future<void> _choose(WidgetTester tester, QuickCreationMode mode) async {
  await tester.tap(
    find.descendant(
      of: _key(
        'daily-choice-${_prefix(mode)}-${durabilityUuid(_candidate(mode))}',
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

List<FlutterErrorDetails> _captureLaunchErrors() {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'quick creation' ||
        details.library == 'daily choice creation') {
      errors.add(details);
    } else {
      previous?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

final class _FailingRouter extends RootStackRouter {
  _FailingRouter(this.target);
  final String target;
  bool _failed = false;
  @override
  List<AutoRoute> get routes => AppRouter().routes;
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    if (!_failed && route.routeName == target) {
      _failed = true;
      return Future<T?>.error(StateError('Секрет'));
    }
    return super.push<T>(route, onFailure: onFailure);
  }
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
