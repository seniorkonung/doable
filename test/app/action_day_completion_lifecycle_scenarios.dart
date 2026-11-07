part of 'action_day_app_lifecycle_test.dart';

void _completionLifecycleScenarios() {
  testWidgets(
    'флажок сохраняет выполнение после закрытия страницы и согласует живой корневой экран дня',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      await _seed(harness, (raw) {
        _seedIntentions(raw);
        seedAction(
          raw,
          id: seedUuid(201),
          path: _longPath,
          description: 'Выбор\nдня',
          date: _pastDate.toCanonicalString(),
        );
      });
      final gate = _ActionSqlGate();
      late _ObservedRepository graph;
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        localDateSource: ControlledLocalDate(_pastDate).read,
        repositoryFactory: (database) =>
            graph = _ObservedRepository(_repository(database)),
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openActions(tester, tap: _tap);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      await _dayResult(
        tester,
        ready.container,
        date: _pastDate,
        completedExpanded: null,
      );
      final rootProvider = openedActionDayProvider(ready.container);
      await _tap(
        tester,
        find.byKey(const ValueKey('action-day-section-incomplete')),
      );
      await showActionDaySection(tester, ActionDaySection.completed);
      final router = ready.container.read(appRouterProvider);
      unawaited(router.push(ActionDayDateRoute(date: _pastDate)));
      final checkbox = find.byKey(
        ValueKey('action-day-completion-${seedUuid(201)}'),
      );
      await _until(tester, () => checkbox.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      gate.arm(fail: false);
      await tester.tap(checkbox);
      await tester.pump();
      await _until(tester, () => gate.hasEntered);
      expect(actionCompletionState(tester, checkbox).completed, isFalse);
      await tester.binding.handlePopRoute();
      await _until(
        tester,
        () => find
            .byType(ActionDayDatePage, skipOffstage: false)
            .evaluate()
            .isEmpty,
      );
      expectActionsRootPage(router);
      gate.release();
      await _until(
        tester,
        () =>
            checkbox.evaluate().isNotEmpty &&
            actionCompletionState(tester, checkbox).completed,
      );
      final loaded = ready.container.read(rootProvider) as ActionDayLoaded;
      expect(loaded.selection.incompleteExpanded, isFalse);
      expect(loaded.selection.completedExpanded, isTrue);
      expect(loaded.incomplete.items, isEmpty);
      expect(loaded.completed.items.single.id, actionIdOf(201));
      expectActionsRootPage(router);
      expect(actionDayDayMark(_pastDate, mark: DayMark.done), findsOneWidget);
      expect(graph.commands, hasLength(1));
      expect((await _read(graph, actionIdOf(201))).action.isCompleted, isTrue);
      final message = find.byKey(const ValueKey('graph-operation-message'));
      await tester.pumpAndSettle();
      expect(message, findsNothing);
      await openHome(tester);
      await openActions(tester, tap: _tap);
      await tester.pumpAndSettle();
      expect(actionCompletionState(tester, checkbox).completed, isTrue);
      expect(message, findsNothing);
      expect(graph.commands, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
