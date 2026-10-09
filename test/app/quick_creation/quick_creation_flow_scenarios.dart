part of '../creation_flows_integration_test.dart';

void _registerQuickCreationFlowTests() {
  for (final flow in _Flow.values) {
    testWidgets(
      '${flow.label}: обычное назад сохраняет предыдущий шаг и ввод',
      (tester) async {
        final app = await _start(tester);
        const origin = IntentionCreationOrigin.deep;
        final history = await origin.open(
          tester,
          app.router,
          participantId: durabilityIntention(2),
          waitFor: (tester, finder) =>
              _until(tester, () => finder.evaluate().isNotEmpty),
        );
        await flow.open(tester, app, origin);
        await flow.fill(tester);
        app.observer.observe(flow.table);
        final previous = List.of(app.router.stackData);
        switch (flow) {
          case _Flow.intention:
            await _tap(tester, _key('intention-editor-choose-tags'));
          case _Flow.relation:
            await _reveal(tester, _key('relation-editor-change-source'));
            await _tap(tester, _key('relation-editor-change-source'));
          case _Flow.topDown || _Flow.bottomUp:
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(
              app.router.current.matchId,
              previous[previous.length - 2].matchId,
            );
            await _tap(
              tester,
              _key(
                flow == _Flow.topDown
                    ? 'choice-path-select-action'
                    : 'choice-path-select-source',
              ),
            );
            await _reveal(tester, _key('choice-path-open-confirmation'));
            await _tap(tester, _key('choice-path-open-confirmation'));
            expect(app.router.current.name, DailyChoiceCreationRoute.name);
            expect(app.router.current.matchId, isNot(previous.last.matchId));
            final before = previous.last.argsAs<DailyChoiceCreationRouteArgs>();
            final after = app.router.current
                .argsAs<DailyChoiceCreationRouteArgs>();
            expect(after.session, same(before.session));
            expect(after.path.steps, orderedEquals(before.path.steps));
            expect(
              app.router.stackData.take(previous.length - 1),
              orderedEquals(previous.take(previous.length - 1).map(same)),
            );
        }
        if (flow == _Flow.intention || flow == _Flow.relation) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(app.router.stackData, orderedEquals(previous.map(same)));
          expect(
            tester
                .widget<TextField>(
                  _key(
                    flow == _Flow.intention
                        ? 'intention-editor-description'
                        : 'relation-editor-description',
                  ),
                )
                .controller!
                .text,
            'Сохранённое описание',
          );
        }
        history.expectPrefix(app.router);
        expect(app.observer.attempts, 0);
        await _closeCreation(tester, app, flow);
        history.expectRestored(tester, app.router);
        await history.expectUnderlyingDraft(tester, app.router);
        expect(tester.takeException(), isNull);
      },
    );

    for (final fail in [false, true]) {
      testWidgets('${flow.label}: поздний ${fail ? 'отказ' : 'успех'} '
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
        await flow.open(tester, app, origin);
        await flow.fill(tester);
        app.observer.observe(flow.table, hold: true, fail: fail);
        await _submit(tester, app, flow);
        await _closeCreation(tester, app, flow);
        history.expectRestored(tester, app.router);
        await _Flow.intention.open(tester, app, origin);
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
          () => durabilityRows(app.database, flow.table),
        ))!;
        expect(rows, hasLength(flow.initialRows + (fail ? 0 : 1)));
        expect(app.observer.attempts, 1);
        if (!fail) flow.expectStored(rows.last);
        await _closeCreation(tester, app, _Flow.intention);
        history.expectRestored(tester, app.router);
        await _until(
          tester,
          () =>
              _key('graph-operation-message')
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 300));
        final message = _key('graph-operation-message');
        expect(message.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(message).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(AppNavigationBar)).top),
        );
        await tester.drag(find.byType(SnackBar), const Offset(0, 400));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(message, findsNothing);
        expect(completions, hasLength(1));
        history.expectRestored(tester, app.router);
        await history.expectUnderlyingDraft(tester, app.router);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      '${flow.label}: пустой граф оставляет режим доступным без записи',
      (tester) async {
        final app = await _start(tester, seed: (_) async {});
        const origin = IntentionCreationOrigin.home;
        final history = await origin.open(
          tester,
          app.router,
          participantId: durabilityIntention(2),
          waitFor: (tester, finder) =>
              _until(tester, () => finder.evaluate().isNotEmpty),
        );
        await flow.open(tester, app, origin);
        switch (flow) {
          case _Flow.intention:
            expect(
              tester
                  .widget<TextField>(_key('intention-editor-title'))
                  .controller!
                  .text,
              isEmpty,
            );
            await _tap(tester, _key(flow.submit));
            expect(app.router.current.name, IntentionEditorRoute.name);
            expect(find.text(app.l10n.editorTitleEmpty), findsOneWidget);
            await _tap(tester, _key('intention-editor-close'));
          case _Flow.relation:
            expect(
              tester.widget<FilledButton>(_key(flow.submit)).onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<TextField>(_key('relation-editor-description'))
                  .controller!
                  .text,
              isEmpty,
            );
            for (final role in ['source', 'related']) {
              await _tap(tester, _key('relation-editor-select-$role'));
              expect(find.byType(IntentionSummaryView), findsNothing);
              expect(
                find.text(app.l10n.participantPickerEmpty),
                findsOneWidget,
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }
            await _tap(tester, find.text(app.l10n.creationCancelAction));
          case _Flow.topDown || _Flow.bottomUp:
            expect(find.byType(IntentionSummaryView), findsNothing);
            expect(
              find.text(
                flow == _Flow.topDown
                    ? app.l10n.sourcePickerEmpty
                    : app.l10n.actionPickerEmpty,
              ),
              findsOneWidget,
            );
            await _tap(tester, find.text(app.l10n.creationCancelAction));
        }
        history.expectRestored(tester, app.router);
        for (final table in [
          'intentions',
          'long_term_relations',
          'daily_choices',
          'daily_choice_path_steps',
        ]) {
          expect(
            await tester.runAsync(() => durabilityRows(app.database, table)),
            isEmpty,
          );
        }
        expect(app.observer.attempts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _registerNestedQuickCreationTests() {
  for (final flow in [_Flow.relation, _Flow.topDown, _Flow.bottomUp]) {
    testWidgets('${flow.label}: вложенный запуск изолирует фильтры, теги, '
        'порции и прокрутку обоих поисков', (tester) async {
      final app = await _start(tester, seed: _seedSearchGraph);
      const origin = IntentionCreationOrigin.home;
      final history = await origin.open(
        tester,
        app.router,
        participantId: durabilityIntention(2),
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      final before = await tester.runAsync(() => durabilityState(app.database));
      final filterKey = switch (flow) {
        _Flow.relation => 'participant-picker-filter-field',
        _Flow.topDown => 'daily-choice-source-filter',
        _Flow.bottomUp => 'daily-choice-action-filter',
        _Flow.intention => throw StateError(
          'У намерения нет начального поиска.',
        ),
      };
      final listKey = switch (flow) {
        _Flow.relation => 'participant-picker-list',
        _Flow.topDown => 'daily-choice-source-list',
        _Flow.bottomUp => 'daily-choice-action-list',
        _Flow.intention => throw StateError(
          'У намерения нет начального поиска.',
        ),
      };
      Future<void> openSearch() async {
        await flow.open(tester, app, origin);
        if (flow == _Flow.relation) {
          await _tap(tester, _key('relation-editor-select-source'));
        }
      }

      IntentionCatalogPurpose purpose() => tester
          .widget<IntentionTagConditionsSection>(
            find.byType(IntentionTagConditionsSection),
          )
          .purpose;
      IntentionCatalogLoaded loaded(IntentionCatalogPurpose purpose) =>
          app.container
                  .read(intentionCatalogViewModelProvider(purpose))
                  .requireValue
              as IntentionCatalogLoaded;
      Finder list() => find.byKey(PageStorageKey<String>(listKey));
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: list(), matching: find.byType(Scrollable)),
          )
          .position;

      await openSearch();
      final firstRoute = app.router.current.matchId;
      final first = purpose();
      await tester.enterText(_key(filterKey), 'Поиск');
      await tester.pumpAndSettle();
      await _addSearchTag(tester, 900, present: true);
      await _addSearchTag(tester, 901, present: false);
      expect(loaded(first).totalCount, 80);
      // Реальные жесты прокручивают выдачу, загруженную больше одной порции.
      for (var i = 0; i < 12; i++) {
        await tester.drag(list(), const Offset(0, -1200));
        await tester.pumpAndSettle();
        if (loaded(first).items.length == 80) break;
      }
      final firstState = loaded(first);
      expect(firstState.items, hasLength(80));
      expect(firstState.nextCursor, isNull);
      expect(
        firstState.selection.tagFilter.requiredTagIds.map(
          (id) => id.toCanonicalString(),
        ),
        [durabilityUuid(900)],
      );
      expect(
        firstState.selection.tagFilter.excludedTagIds.map(
          (id) => id.toCanonicalString(),
        ),
        [durabilityUuid(901)],
      );
      final firstOffset = position().pixels;
      expect(firstOffset, greaterThan(0));
      final originalPickerHistory = List.of(app.router.stackData);
      final details = find.byIcon(Icons.info_outline).hitTestable().first;
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(app.router.current.name, IntentionDetailsRoute.name);
      final ordinary = app.router.current.matchId;
      await openSearch();
      final second = purpose();
      expect(second, isNot(first));
      expect(
        tester.widget<TextField>(_key(filterKey)).controller!.text,
        isEmpty,
      );
      expect(loaded(second).selection.tagFilter, IntentionTagFilter.empty);
      expect(position().pixels, 0);
      await tester.enterText(_key(filterKey), 'Поиск B');
      await tester.pumpAndSettle();
      await _addSearchTag(tester, 901, present: true);
      await _addSearchTag(tester, 900, present: false);
      expect(
        loaded(second).selection.tagFilter.requiredTagIds
            .map((id) => id.toCanonicalString()),
        [durabilityUuid(901)],
      );
      expect(
        loaded(second).selection.tagFilter.excludedTagIds
            .map((id) => id.toCanonicalString()),
        [durabilityUuid(900)],
      );
      await tester.drag(list(), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(position().pixels, greaterThan(0));
      expect(
        loaded(second).items.every((item) => item.title.startsWith('Поиск B')),
        isTrue,
      );
      expect(loaded(first), same(firstState));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (flow == _Flow.relation) {
        await _tap(tester, find.text(app.l10n.creationCancelAction));
      }
      expect(app.router.current.matchId, ordinary);
      expect(
        app.container.exists(intentionCatalogViewModelProvider(second)),
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.router.current.matchId, firstRoute);
      expect(
        app.router.stackData,
        orderedEquals(originalPickerHistory.map(same)),
      );
      expect(purpose(), same(first));
      expect(
        tester.widget<TextField>(_key(filterKey)).controller!.text,
        'Поиск',
      );
      expect(loaded(first), same(firstState));
      expect(position().pixels, firstOffset);
      expect(
        _key('intention-tag-condition-${durabilityUuid(900)}'),
        findsOneWidget,
      );
      expect(
        _key('intention-tag-condition-${durabilityUuid(901)}'),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (flow == _Flow.relation) {
        await _tap(tester, find.text(app.l10n.creationCancelAction));
      }
      history.expectRestored(tester, app.router);
      expect(
        await tester.runAsync(() => durabilityState(app.database)),
        before,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _addSearchTag(
  WidgetTester tester,
  int number, {
  required bool present,
}) async {
  await _tap(tester, _key('intention-tag-conditions-add'));
  await _tap(
    tester,
    _key(
      'tag-condition-picker-${present ? 'mustBePresent' : 'mustBeAbsent'}-${durabilityUuid(number)}',
    ),
  );
}

Future<void> _seedSearchGraph(AppDatabase database) async {
  await seedDurabilityGraph(database);
  for (final (number, name) in [
    (900, 'Первая группа'),
    (901, 'Вторая группа'),
  ]) {
    await database.customStatement(
      'INSERT INTO tags (id, name) VALUES (?, ?)',
      [durabilityUuid(number), name],
    );
  }
  for (var i = 0; i < 160; i++) {
    final id = durabilityUuid(1000 + i);
    await database.customStatement(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) '
      'VALUES (?, ?, 1, 0, 1, 1)',
      [
        id,
        'Поиск ${i.isEven ? 'A' : 'B'} ${(i ~/ 2).toString().padLeft(3, '0')}',
      ],
    );
    await database.customStatement(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [durabilityUuid(i.isEven ? 900 : 901), id],
    );
  }
}
