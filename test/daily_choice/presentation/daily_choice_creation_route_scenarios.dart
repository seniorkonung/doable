part of 'daily_choice_creation_flow_test.dart';

void _registerCreationRouteScenarios() {
  for (final direction in ChoicePathDraftDirection.values) {
    testWidgets(
      'типизированный корень ${direction == ChoicePathDraftDirection.topDown ? 'сверху вниз' : 'снизу вверх'} сохраняет глубокую историю и чужой черновик',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.binding.platformDispatcher.localesTestValue = const [
          Locale('ru'),
        ];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        final harness = (await tester.runAsync(
          LocalDatabaseHarness.fileBacked,
        ))!;
        await tester.runAsync(() => _seed(harness));
        final runtime = AppRuntime(
          quickCreationModeStore: InMemoryQuickCreationModeStore(),
          connectionFactory: () =>
              openFileBackedLocalDatabase(harness.databaseFile),
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.shutdown();
          await harness.dispose();
        });
        await tester.pumpWidget(MainApp(runtime: runtime));
        final ready = await runtime.bootstrap() as AppRuntimeReady;
        final router = ready.container.read(appRouterProvider);
        await openIntentionGraph(
          tester,
          waitFor: _waitFor,
          content: find.text('Основание'),
        );
        await _tap(tester, find.text('Основание').first);
        await _tap(tester, find.text('Связи'));
        final createRelation = find.byKey(
          const ValueKey('intention-relations-add'),
        );
        await _waitFor(tester, createRelation);
        await _tap(tester, createRelation.first);
        final description = find.byKey(
          const ValueKey('relation-editor-description'),
        );
        await _waitFor(tester, description);
        await tester.enterText(description, 'Черновик другой связи');
        unawaited(
          router.push(IntentionDetailsRoute(intentionId: _intention(2))),
        );
        await tester.pumpAndSettle();
        final history = [for (final route in router.stackData) route.matchId];
        expect(history, hasLength(4));
        final startingId = _intention(
          direction == ChoicePathDraftDirection.topDown ? 1 : 3,
        );

        unawaited(
          router.push(
            ChoicePathRoute(
              sourceIntentionId: startingId,
              direction: direction,
            ),
          ),
        );
        await _waitFor(tester, find.byType(ChoicePathPage));
        await tester.pumpAndSettle();
        final rootMatchId = router.current.matchId;
        expect(
          [for (final route in router.stackData) route.matchId],
          [...history, rootMatchId],
        );

        tester.view.physicalSize = const Size(1100, 2300);
        await tester.pumpAndSettle();
        final returned = router.push<void>(
          ChoicePathRoute(sourceIntentionId: startingId, direction: direction),
        );
        await tester.pumpAndSettle();
        expect(router.current.matchId, isNot(rootMatchId));
        expect(
          [for (final route in router.stackData) route.matchId],
          [...history, rootMatchId, router.current.matchId],
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await returned;
        expect(
          [for (final route in router.stackData) route.matchId],
          [...history, rootMatchId],
        );

        for (final relation
            in direction == ChoicePathDraftDirection.topDown
                ? [101, 102]
                : [102, 101]) {
          await _continue(tester, relation);
        }
        final selectEndpoint = find.byKey(
          ValueKey(
            direction == ChoicePathDraftDirection.topDown
                ? 'choice-path-select-action'
                : 'choice-path-select-source',
          ),
        );
        await _tap(tester, selectEndpoint);
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-confirmation')),
        );
        await _waitFor(tester, find.byType(DailyChoiceCreationPage));
        await tester.pumpAndSettle();
        expect(router.current.name, DailyChoiceCreationRoute.name);
        final confirmationMatchId = router.current.matchId;
        expect(confirmationMatchId, isNot(rootMatchId));
        expect(
          [for (final route in router.stackData) route.matchId],
          [...history, rootMatchId, confirmationMatchId],
        );
        final confirmedPath = tester
            .widget<DailyChoiceCreationPage>(
              find.byType(DailyChoiceCreationPage),
            )
            .path;
        expect(confirmedPath.steps.map((step) => step.relationId), [
          _relation(101),
          _relation(102),
        ]);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          [for (final route in router.stackData) route.matchId],
          [...history, rootMatchId],
        );
        await _tap(tester, selectEndpoint);
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-confirmation')),
        );
        await _waitFor(tester, find.byType(DailyChoiceCreationPage));
        await tester.pumpAndSettle();
        expect(router.current.name, DailyChoiceCreationRoute.name);
        expect(router.current.matchId, isNot(confirmationMatchId));
        expect(
          tester
              .widget<DailyChoiceCreationPage>(
                find.byType(DailyChoiceCreationPage),
              )
              .path
              .steps
              .map((step) => step.relationId),
          confirmedPath.steps.map((step) => step.relationId),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect([for (final route in router.stackData) route.matchId], history);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(description).controller!.text,
          'Черновик другой связи',
        );
        expect(_savedIds(harness), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
