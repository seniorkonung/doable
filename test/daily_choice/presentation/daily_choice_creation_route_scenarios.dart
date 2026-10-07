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
        final createRelation = find.byKey(
          const ValueKey('relation-neighborhood-create-relation'),
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
        final page = tester.widget<ChoicePathPage>(find.byType(ChoicePathPage));
        final state = tester.state<ChoicePathPageState>(
          find.byType(ChoicePathPage),
        );
        final session = state.creationSession!;
        expect(page.direction, direction);
        expect(page.sourceIntentionId, startingId);
        expect(session.rootMatchId, router.current.matchId);
        expect(session.originalHistory, history);
        expect(session.state, isA<DailyChoiceCreationFlowEditing>());

        tester.view.physicalSize = const Size(1100, 2300);
        await tester.pumpAndSettle();
        expect(state.creationSession, same(session));
        final returned = router.push<void>(
          ChoicePathRoute(sourceIntentionId: startingId, direction: direction),
        );
        await tester.pumpAndSettle();
        final second = tester
            .state<ChoicePathPageState>(find.byType(ChoicePathPage))
            .creationSession!;
        expect(second.flowId, isNot(same(session.flowId)));
        expect(second.rootMatchId, isNot(session.rootMatchId));
        expect(second.originalHistory, [...history, session.rootMatchId]);
        await tester.binding.handlePopRoute();
        expect(second.canContinue, isFalse);
        await tester.pumpAndSettle();
        await returned;
        expect(second.state, isA<DailyChoiceCreationFlowLeft>());
        expect(state.creationSession, same(session));
        expect(session.canContinue, isTrue);

        await tester.binding.handlePopRoute();
        expect(session.canContinue, isFalse);
        await tester.pumpAndSettle();
        expect(session.state, isA<DailyChoiceCreationFlowLeft>());
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
