part of 'daily_choice_app_lifecycle_test.dart';

void _completionLifecycleScenarios() {
  testWidgets(
    'флажок сохраняет выполнение после закрытия страницы и согласует живой корневой каталог',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      final seeded = await harness.openReadyDatabase();
      await seedDurabilityGraph(seeded);
      expect(
        await durabilityRepository(seeded)
            .execute(durabilityCreate(completed: false)),
        isA<GraphCommandSucceeded>(),
      );
      await harness.closePersistenceObjectGraph();
      final gate = _ChoiceSqlGate();
      late _ObservedRepository graph;
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(
          durabilityChoiceDate,
        ).read,
        repositoryFactory: (database) =>
            graph = _ObservedRepository(durabilityRepository(database)),
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openDailyChoices(tester, tap: _tap);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      await _catalogResult(
        tester,
        ready.container,
        date: durabilityChoiceDate,
        isCompleted: null,
      );
      final rootProvider = openedDailyChoiceCatalogProvider(ready.container);
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-section-false')),
      );
      await showDailyChoiceCatalogSection(tester, true);
      final router = ready.container.read(appRouterProvider);
      unawaited(
        router.push(DailyChoiceDateCatalogRoute(date: durabilityChoiceDate)),
      );
      final checkbox = find.byKey(
        ValueKey('daily-choice-completion-${durabilityUuid(201)}'),
      );
      await _until(tester, () => checkbox.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      gate.arm(fail: false);
      await tester.tap(checkbox);
      await tester.pump();
      await _until(tester, () => gate.hasEntered);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.binding.handlePopRoute();
      await _until(
        tester,
        () => find
            .byType(DailyChoiceDateCatalogPage, skipOffstage: false)
            .evaluate()
            .isEmpty,
      );
      expectDailyChoicesRootPage(router);
      gate.release();
      await _until(
        tester,
        () =>
            checkbox.evaluate().isNotEmpty &&
            tester.widget<Checkbox>(checkbox).value == true,
      );
      final loaded =
          ready.container.read(rootProvider) as DailyChoiceCatalogLoaded;
      expect(loaded.selection.incompleteExpanded, isFalse);
      expect(loaded.selection.completedExpanded, isTrue);
      expect(loaded.incomplete.items, isEmpty);
      expect(loaded.completed.items.single.id, durabilityChoice(201));
      expectDailyChoicesRootPage(router);
      expect(
        dailyChoiceCatalogDayMark(durabilityChoiceDate, mark: DayMark.done),
        findsOneWidget,
      );
      expect(graph.commands, hasLength(1));
      final result = await graph.getDailyChoice(durabilityChoice(201));
      expect(
        (result
                as GraphResultSuccess<
                  GraphSnapshot<DailyChoiceDetails?>,
                  DailyChoiceReadFailure
                >)
            .value
            .value!
            .choice
            .isCompleted,
        isTrue,
      );
      final message = find.byKey(const ValueKey('graph-operation-message'));
      await _until(tester, () => message.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(tester.element(message.first)).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await openHome(tester);
      await openDailyChoices(tester, tap: _tap);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(message, findsNothing);
      expect(graph.commands, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
