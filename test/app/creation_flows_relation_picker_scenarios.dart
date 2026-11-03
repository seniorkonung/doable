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
    await _Flow.intention.open(tester, app, IntentionCreationOrigin.graph);
    await _Flow.intention.fill(tester);
    app.observer.observe('intentions');
    await _submit(tester, app, _Flow.intention);
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

void _registerRelationPickerDailyChoiceTests() {
  for (final quick in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'дневной выбор ${quick ? 'быстрым созданием' : 'со вкладки'}: '
        '${cancel ? 'отмена' : 'успех'} сохраняет первоначальный поиск',
        (tester) async {
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
            (widget) =>
                widget is IntentionPickerRow && widget.summary.title == title,
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
          await tester.enterText(
            _key('participant-picker-filter'),
            'Намерение 1',
          );
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
          if (quick) {
            await _Flow.topDown.open(
              tester,
              app,
              IntentionCreationOrigin.graph,
            );
            await _Flow.topDown.fill(tester);
          } else {
            await _tap(tester, find.text(app.l10n.detailsChoicesTab).first);
            await _tap(tester, _key('intention-choices-add'));
            await _tap(
              tester,
              _key('choice-path-continue-${durabilityUuid(103)}'),
            );
            await _tap(tester, _key('choice-path-select-action'));
            await _tap(tester, _key('choice-path-open-confirmation'));
            await tester.enterText(_key('daily-choice-date'), '2026-10-09');
            await tester.enterText(
              _key('daily-choice-description'),
              'Сохранённое описание',
            );
          }
          app.observer.observe('daily_choices');
          if (cancel) {
            await _closeCreation(tester, app, _Flow.topDown);
            expect(app.router.stackData, orderedEquals(history.map(same)));
          } else {
            await _submit(tester, app, _Flow.topDown);
            await _until(
              tester,
              () => app.router.current.name == DailyChoiceDetailsRoute.name,
            );
            expect(
              app.router.stackData.take(history.length),
              orderedEquals(history.map(same)),
            );
            expect(app.router.stackData, hasLength(history.length + 1));
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(app.router.stackData, orderedEquals(history.map(same)));
          }
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
          await tester.enterText(
            _key('participant-picker-filter'),
            'Намерение 4',
          );
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
          final result = await tester.runAsync(
            () => app.container
                .read(personalGraphRepositoryProvider)
                .getDailyChoice(durabilityChoice(201)),
          );
          expect(result, isA<DailyChoiceReadSuccess>());
          final choice = (result as DailyChoiceReadSuccess).value.value;
          if (cancel) {
            expect(choice, isNull);
          } else {
            expect(choice, isNotNull);
            expect(choice!.choice.sourceIntentionId, durabilityIntention(1));
            expect(choice.choice.selectedIntentionId, durabilityIntention(4));
            expect(choice.choice.date, CalendarDate.fromParts(2026, 10, 9));
            expect(choice.path.map((step) => step.relation.id), [
              durabilityRelation(103),
            ]);
          }
          final relations = await tester.runAsync(
            () => app.container
                .read(personalGraphRepositoryProvider)
                .getRelationGroupPage(
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
              (relations as RelationGroupPageSuccess).value
                  as RelationGroupFirstPage;
          expect(page.items, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
