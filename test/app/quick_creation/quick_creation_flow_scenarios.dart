part of '../creation_flows_integration_test.dart';

void _registerQuickCreationFlowTests() {
  testWidgets('намерение: обычное назад сохраняет предыдущий шаг и ввод', (
    tester,
  ) async {
    final app = await _start(tester);
    const origin = IntentionCreationOrigin.deep;
    final history = await origin.open(
      tester,
      app.router,
      participantId: durabilityIntention(2),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await _openIntentionEditor(tester, app, origin);
    await _fillIntentionEditor(tester);
    final previous = List.of(app.router.stackData);
    // Выбор тегов — панель над формой, а не следующий маршрут.
    await _tap(tester, _key('intention-editor-choose-tags'));
    expect(find.byType(Sheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(
      [for (final route in app.router.stackData) route.matchId],
      [for (final route in previous) route.matchId],
    );
    expect(
      tester
          .widget<TextField>(_key('intention-editor-description'))
          .controller!
          .text,
      'Сохранённое описание',
    );
    history.expectPrefix(app.router);
    await _closeCreation(tester, app);
    history.expectRestored(tester, app.router);
    await history.expectUnderlyingTask(tester, app.router);
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('намерение: поздний ${fail ? 'отказ' : 'успех'} '
        'сохраняет новую сессию и предъявляется один раз', (tester) async {
      final app = await _start(tester);
      const origin = IntentionCreationOrigin.deep;
      final history = await origin.open(
        tester,
        app.router,
        participantId: durabilityIntention(2),
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      final completions = <GraphCommandCompletion>[];
      final subscription = app.container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen(completions.add);
      addTearDown(subscription.cancel);
      await _openIntentionEditor(tester, app, origin);
      await _fillIntentionEditor(tester);
      app.observer.observe(_intentionsTable, hold: true, fail: fail);
      await _submit(tester, app);
      await _closeCreation(tester, app);
      history.expectRestored(tester, app.router);
      await _openIntentionEditor(tester, app, origin);
      final newSession = app.router.current.matchId;
      await tester.enterText(
        _key('intention-editor-title'),
        'Новый независимый черновик',
      );
      app.observer.release();
      await _until(tester, () => completions.length == 1);
      await tester.pumpAndSettle();
      expect(app.router.current.matchId, newSession);
      expect(
        tester
            .widget<TextField>(_key('intention-editor-title'))
            .controller!
            .text,
        'Новый независимый черновик',
      );
      history.expectPrefix(app.router);
      final rows = (await tester.runAsync(
        () => durabilityRows(app.database, _intentionsTable),
      ))!;
      expect(rows, hasLength(_initialIntentionRows + (fail ? 0 : 1)));
      expect(app.observer.attempts, 1);
      if (!fail) _expectIntentionStored(rows.last);
      await _closeCreation(tester, app);
      history.expectRestored(tester, app.router);
      await _until(
        tester,
        () =>
            _key('graph-operation-message').hitTestable().evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final message = _key('graph-operation-message');
      expect(message.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(message).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AppNavigationBar)).top),
      );
      await tester.drag(find.byType(SnackBar), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(message, findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(message, findsNothing);
      expect(completions, hasLength(1));
      history.expectRestored(tester, app.router);
      await history.expectUnderlyingTask(tester, app.router);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('намерение: пустой граф оставляет режим доступным без записи', (
    tester,
  ) async {
    final app = await _start(tester, seed: (_) async {});
    const origin = IntentionCreationOrigin.home;
    final history = await origin.open(
      tester,
      app.router,
      participantId: durabilityIntention(2),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await _openIntentionEditor(tester, app, origin);
    expect(
      tester.widget<TextField>(_key('intention-editor-title')).controller!.text,
      isEmpty,
    );
    await _tap(tester, _key(_intentionSubmit));
    expect(app.router.current.name, IntentionEditorRoute.name);
    expect(find.text(app.l10n.editorTitleEmpty), findsOneWidget);
    await _tap(tester, _key('intention-editor-close'));
    history.expectRestored(tester, app.router);
    for (final table in [
      'intentions',
      'long_term_relations',
      'actions',
      'action_path_items',
    ]) {
      expect(
        await tester.runAsync(() => durabilityRows(app.database, table)),
        isEmpty,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
