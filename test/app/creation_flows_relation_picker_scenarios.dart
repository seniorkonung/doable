part of 'creation_flows_integration_test.dart';

void _registerRelationPickerIntentionTest() {
  testWidgets('быстро созданное намерение сохраняется после сброса поиска', (
    tester,
  ) async {
    final app = await _start(tester);
    await IntentionCreationOrigin.graph.open(
      tester,
      app.router,
      participantId: durabilityIntention(2),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    unawaited(
      app.router.push<void>(
        IntentionDetailsRoute(intentionId: durabilityIntention(2)),
      ),
    );
    await _until(
      tester,
      () => _key('intention-details-title').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text(app.l10n.detailsRelationsTab).first);
    await _tap(tester, _key('intention-relations-add'));
    Finder row(String title) => find.byWidgetPredicate(
      (widget) => widget is IntentionPickerRow && widget.summary.title == title,
    );
    await _until(tester, () => row('Намерение 4').evaluate().isNotEmpty);
    await _tap(
      tester,
      find.descendant(
        of: row('Намерение 4'),
        matching: find.text('Намерение 4'),
      ),
    );
    await _until(
      tester,
      () => find.text(app.l10n.batchAddCount(1)).evaluate().isNotEmpty,
    );
    await tester.enterText(_key('participant-picker-filter'), 'Намерение 1');
    await _until(tester, () => row('Намерение 1').evaluate().isNotEmpty);
    final pickerHistory = List.of(app.router.stackData);
    await _tap(
      tester,
      find.descendant(
        of: row('Намерение 1'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon &&
              widget.icon == DoableIconData.arrowUpRight,
        ),
      ),
    );
    await _until(
      tester,
      () => app.router.current.name == IntentionDetailsRoute.name,
    );
    final history = List.of(app.router.stackData);
    await _openIntentionEditor(tester, app, IntentionCreationOrigin.graph);
    await _fillIntentionEditor(tester);
    app.observer.observe('intentions');
    await _submit(tester, app);
    await _until(
      tester,
      () => app.router.current.name == IntentionDetailsRoute.name,
    );
    await tester.pumpAndSettle();
    expect(
      app.router.stackData.take(history.length),
      orderedEquals(history.map(same)),
    );
    expect(app.router.stackData, hasLength(history.length + 1));
    final createdId = app.router.current
        .argsAs<IntentionDetailsRouteArgs>()
        .intentionId;
    expect(find.text('Новое'), findsOneWidget);
    expect(app.observer.attempts, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.router.stackData, orderedEquals(history.map(same)));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.router.stackData, orderedEquals(pickerHistory.map(same)));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: _key('participant-picker-filter'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Намерение 1',
    );
    expect(find.text(app.l10n.batchAddCount(1)), findsOneWidget);
    await tester.enterText(_key('participant-picker-filter'), 'Намерение 4');
    await _until(tester, () => row('Намерение 4').evaluate().isNotEmpty);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: row('Намерение 4'),
              matching: find.text('Намерение 4'),
            ),
          )
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    semantics.dispose();
    await _tap(tester, _key('participant-picker-cancel'));
    await _until(
      tester,
      () => find.text(app.l10n.batchDiscardTitle).evaluate().isNotEmpty,
    );
    await _tap(tester, find.text(app.l10n.batchDiscardAction));

    final repository = app.container.read(personalGraphRepositoryProvider);
    final reading = repository.watchIntention(createdId).first;
    var readComplete = false;
    unawaited(reading.then((_) => readComplete = true));
    await _until(tester, () => readComplete);
    final result = await reading;
    final intention = switch (result) {
      ResultSuccess(:final value) => value.value!.intention,
      _ => fail('Чтение созданного намерения не удалось: $result'),
    };
    expect(intention.id, createdId);
    expect(intention.title, 'Новое');
    expect(intention.description, 'Сохранённое описание');
    final relations = await tester.runAsync(
      () => repository.getRelationGroupPage(
        RelationGroupQuery(
          intentionId: durabilityIntention(2),
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
          scope: RelationScope.active,
          pageSize: 10,
        ),
      ),
    );
    expect(relations, isA<RelationGroupPageSuccess>());
    final page =
        (relations as RelationGroupPageSuccess).value as RelationGroupFirstPage;
    expect(page.items, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
