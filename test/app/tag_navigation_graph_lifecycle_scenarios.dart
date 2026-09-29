part of 'tag_navigation_app_flow_test.dart';

void _testTaggedGraphLifecycle(String locale) {
  testWidgets(
    'открытая навигация обновляет поля и порядок назначений на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      final coordinator = app.runtime.commandCoordinator;
      final before = _snapshot(app.raw);
      final targets = _lifecycleActiveTargets();
      await _expectTargets(tester, app.router, targets);

      await _changed(
        tester,
        (coordinator.acceptExisting(
          UpdateIntention(
            id: _intentionId(1),
            title: 'Обновлённое намерение',
            description: 'Описание 1',
          ),
          presentationTitle: 'Одинаковое намерение',
        ) as IntentionCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, targets);
      _expectRowText(tester, _intentionId(1), 'Обновлённое намерение');
      expect(find.textContaining('Чтобы'), findsNothing);

      for (final command in [
        DisableIntentionReadiness(_intentionId(1)),
        EnableIntentionReadiness(_intentionId(1)),
      ]) {
        await _changed(
          tester,
          (coordinator.acceptExisting(
            command,
            presentationTitle: 'Обновлённое намерение',
          ) as IntentionCommandAccepted).future,
        );
        await _expectTargets(tester, app.router, targets);
        expect(
          _row(app.raw, 'intentions', 1)['is_action_ready'],
          command is EnableIntentionReadiness ? 1 : 0,
        );
      }

      await _changed(
        tester,
        (coordinator.acceptExisting(
          UpdateIntention(
            id: _intentionId(3),
            title: 'Новое имя соседа',
            description: 'Описание 3',
          ),
          presentationTitle: 'Непомеченный сосед',
        ) as IntentionCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, targets);
      expect(find.textContaining('Чтобы'), findsNothing);
      expect(_snapshot(app.raw)['tag_assignments'], before['tag_assignments']);
      final freeRelationBefore = _row(app.raw, 'long_term_relations', 103);
      await _changed(
        tester,
        (coordinator.acceptRelationRestore(
          RestoreLongTermRelation(_relationId(103)),
        ) as LongTermRelationCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, targets);
      await _changed(
        tester,
        (coordinator.acceptRelationUpdate(
          UpdateLongTermRelation(
            relationId: _relationId(103),
            patch: LongTermRelationPatch(
              type: const LongTermRelationFieldSet(LongTermRelationType.need),
              priority: const LongTermRelationFieldSet(RelationPriority.p1),
              sourceIntentionId: LongTermRelationFieldSet(_intentionId(3)),
              relatedIntentionId: LongTermRelationFieldSet(_intentionId(5)),
            ),
          ),
        ) as LongTermRelationCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, targets);
      expect(find.textContaining('Чтобы'), findsNothing);
      expect(_row(app.raw, 'long_term_relations', 103), {
        ...freeRelationBefore,
        'source_intention_id': tagFixtureId(3),
        'related_intention_id': tagFixtureId(5),
        'type': 'need',
        'priority': 1,
        'is_archived': 0,
      });
      expect(_snapshot(app.raw)['tag_assignments'], before['tag_assignments']);

      final graphAfterEdits = retainedTagFixtureGraph(app.raw);
      for (final target in [_intentionId(3)]) {
        await _changeAssignment(tester, coordinator, target, assigned: true);
        targets.add(target);
        await _expectTargets(tester, app.router, targets);
        expect(retainedTagFixtureGraph(app.raw), graphAfterEdits);
      }
      for (final target in [_intentionId(1), _intentionId(5)]) {
        await _changeAssignment(tester, coordinator, target, assigned: false);
        targets.remove(target);
        await _expectTargets(tester, app.router, targets);
        expect(retainedTagFixtureGraph(app.raw), graphAfterEdits);
        await _changeAssignment(tester, coordinator, target, assigned: true);
        targets.add(target);
        await _expectTargets(tester, app.router, targets);
        expect(retainedTagFixtureGraph(app.raw), graphAfterEdits);
      }
      await _selectScope(tester, TaggedIntentionsScope.archived);
      final archivedTargets = [_intentionId(2)];
      await _expectTargets(
        tester,
        app.router,
        archivedTargets,
        scope: TaggedIntentionsScope.archived,
      );
      for (final target in List<IntentionId>.of(archivedTargets)) {
        await _changeAssignment(tester, coordinator, target, assigned: false);
        archivedTargets.remove(target);
        await _expectTargets(
          tester,
          app.router,
          archivedTargets,
          scope: TaggedIntentionsScope.archived,
        );
        await _changeAssignment(tester, coordinator, target, assigned: true);
        archivedTargets.add(target);
        await _expectTargets(
          tester,
          app.router,
          archivedTargets,
          scope: TaggedIntentionsScope.archived,
        );
        expect(retainedTagFixtureGraph(app.raw), graphAfterEdits);
      }
      await _selectScope(tester, TaggedIntentionsScope.active);
      await _expectTargets(tester, app.router, targets);
      expect(
        app.raw
            .select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
              tagFixtureId(lastTagNumber),
            ])
            .map((row) => row.values.toList()),
        before['tag_assignments']!.where(
          (row) => row.contains(tagFixtureId(lastTagNumber)),
        ),
      );
      expect(_snapshot(app.raw)['daily_choices'], before['daily_choices']);
      expect(
        _snapshot(app.raw)['daily_choice_path_steps'],
        before['daily_choice_path_steps'],
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'каскад и отдельное восстановление меняют собственные охваты на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      await _loaded(tester, firstTagNumber);
      final before = _snapshot(app.raw);
      final neighbors = [
        for (final id in [2, 3, 4, 5]) _row(app.raw, 'intentions', id),
      ];
      final unrelatedRelations = [
        for (final id in [105, 106]) _row(app.raw, 'long_term_relations', id),
      ];
      final coordinator = app.runtime.commandCoordinator;

      await _changed(
        tester,
        (coordinator.acceptExisting(
          ArchiveIntention(_intentionId(1)),
          presentationTitle: 'Одинаковое намерение',
        ) as IntentionCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, [
        _intentionId(4),
        _intentionId(5),
      ]);
      final archived = [_intentionId(1), _intentionId(2)];
      await _selectScope(tester, TaggedIntentionsScope.archived);
      await _expectTargets(
        tester,
        app.router,
        archived,
        scope: TaggedIntentionsScope.archived,
      );
      expect([
        for (final id in [101, 102, 103, 104])
          _row(app.raw, 'long_term_relations', id)['is_archived'],
      ], everyElement(1));
      expect([
        for (final id in [2, 3, 4, 5]) _row(app.raw, 'intentions', id),
      ], neighbors);
      expect([
        for (final id in [105, 106]) _row(app.raw, 'long_term_relations', id),
      ], unrelatedRelations);

      await _changed(
        tester,
        (coordinator.acceptExisting(
          RestoreIntention(_intentionId(1)),
          presentationTitle: 'Одинаковое намерение',
        ) as IntentionCommandAccepted).future,
      );
      archived.remove(_intentionId(1));
      await _expectTargets(
        tester,
        app.router,
        archived,
        scope: TaggedIntentionsScope.archived,
      );
      expect([
        for (final id in [101, 102, 103, 104])
          _row(app.raw, 'long_term_relations', id)['is_archived'],
      ], everyElement(1));
      await _selectScope(tester, TaggedIntentionsScope.active);
      await _expectTargets(tester, app.router, [
        _intentionId(1),
        _intentionId(4),
        _intentionId(5),
      ]);
      await _selectScope(tester, TaggedIntentionsScope.archived);

      for (final (number, archive) in [
        (101, false),
        (104, false),
        (106, true),
        (106, false),
      ]) {
        final start = archive
            ? coordinator.acceptRelationArchive(
                ArchiveLongTermRelation(_relationId(number)),
              )
            : coordinator.acceptRelationRestore(
                RestoreLongTermRelation(_relationId(number)),
              );
        await _changed(
          tester,
          (start as LongTermRelationCommandAccepted).future,
        );
        await _expectTargets(
          tester,
          app.router,
          archived,
          scope: TaggedIntentionsScope.archived,
        );
        expect(
          _row(app.raw, 'long_term_relations', number)['is_archived'],
          archive ? 1 : 0,
        );
      }
      await _selectScope(tester, TaggedIntentionsScope.active);
      await _expectTargets(tester, app.router, _lifecycleActiveTargets());
      final after = _snapshot(app.raw);
      for (final table in [
        'tags',
        'tag_assignments',
        'daily_choices',
        'daily_choice_path_steps',
      ]) {
        expect(after[table], before[table], reason: table);
      }
      expect([
        for (final id in [2, 3, 4, 5]) _row(app.raw, 'intentions', id),
      ], neighbors);
      expect([
        for (final id in [105, 106]) _row(app.raw, 'long_term_relations', id),
      ], unrelatedRelations);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'одиночное и массовое удаление убирают только получателей на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      await _loaded(tester, firstTagNumber);
      final before = _snapshot(app.raw);
      final coordinator = app.runtime.commandCoordinator;
      final targets = _lifecycleActiveTargets();

      await _changed(
        tester,
        (coordinator.acceptExisting(
          DeleteIntention(_intentionId(5)),
          presentationTitle: 'Отдельное намерение',
        ) as IntentionCommandAccepted).future,
      );
      targets.remove(_intentionId(5));
      await _expectTargets(tester, app.router, targets);
      _expectOnlyDeleted(app.raw, before, intentions: [5]);
      await _changed(
        tester,
        (coordinator.acceptRelationDelete(
          DeleteLongTermRelation(_relationId(106)),
        ) as LongTermRelationCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, targets);
      _expectOnlyDeleted(app.raw, before, intentions: [5], relations: [106]);

      await _selectScope(tester, TaggedIntentionsScope.archived);
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      await _changed(
        tester,
        (coordinator.acceptBlockingRelationsDelete(
          DeleteBlockingRelations.longTerm(
            intentionId: _intentionId(1),
            relationIds: [_relationId(102), _relationId(103)],
          ),
          presentationTitle: 'Одинаковое намерение',
        ) as BlockingRelationsDeleteAccepted).future,
      );
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      _expectOnlyDeleted(
        app.raw,
        before,
        intentions: [5],
        relations: [102, 103, 106],
      );
      await _selectScope(tester, TaggedIntentionsScope.active);
      await _expectTargets(tester, app.router, targets);
      expect(app.raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'отмена и зависимость дневного пути сохраняют навигацию и назначения на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      final initial = await _loaded(tester, firstTagNumber);
      final before = _snapshot(app.raw);
      final cancel = _l10n(tester).detailsCancelEditAction;
      for (final (relation, number, deleteKey) in [
        (false, 5, 'intention-details-delete'),
        (true, 106, 'relation-details-delete-relation'),
      ]) {
        if (relation) {
          unawaited(
            app.router.push(
              RelationDetailsRoute(relationId: _relationId(number)),
            ),
          );
          await _until(
            tester,
            find.byKey(const ValueKey('relation-details-phrase')),
          );
          expect(app.router.current.name, RelationDetailsRoute.name);
          expect(
            app.router.current.argsAs<RelationDetailsRouteArgs>().relationId,
            _relationId(number),
          );
        } else {
          await _tap(tester, find.byKey(ValueKey(_intentionId(number))));
          _expectDetailsRoute(app.router, _intentionId(number));
        }
        await _tap(tester, find.byKey(ValueKey(deleteKey)));
        await _until(tester, find.byType(AlertDialog));
        await _tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, cancel),
          ),
        );
        app.router.pop();
        await _expectUnchangedNavigation(
          tester,
          app.router,
          initial,
          app.raw,
          before,
        );
      }

      await _scrollToTop(tester);
      await _tap(tester, find.byKey(ValueKey<IntentionId>(_intentionId(1))));
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('intention-details-state-change-failure')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-show-blocking-relations')),
      );
      await _scrollAndTap(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await _scrollAndTap(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          ValueKey('relation-neighborhood-select-${tagFixtureId(104)}'),
        ),
      );
      await _scrollAndTap(
        tester,
        find.byKey(const ValueKey('blocking-relations-review')),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('blocking-relations-confirm-list')),
      );
      expect(
        find.byKey(
          ValueKey('blocking-relations-confirm-row-${tagFixtureId(104)}'),
        ),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('blocking-relations-cancel')),
      );
      app.router.pop();
      await _expectUnchangedNavigation(
        tester,
        app.router,
        initial,
        app.raw,
        before,
      );

      final coordinator = app.runtime.commandCoordinator;
      final blocked = await _completed(
        tester,
        (coordinator.acceptRelationDelete(
          DeleteLongTermRelation(_relationId(101)),
        ) as LongTermRelationCommandAccepted).future,
      );
      expect(blocked.isFailure, isTrue);
      expect(
        (blocked.confirmedResult as GraphCommandFailed).failure,
        isA<LongTermRelationReferencedByDailyPathFailure>(),
      );
      await _expectUnchangedNavigation(
        tester,
        app.router,
        initial,
        app.raw,
        before,
      );
      final massBlocked = await _completed(
        tester,
        (coordinator.acceptBlockingRelationsDelete(
          DeleteBlockingRelations(
            intentionId: _intentionId(1),
            references: [
              LongTermBlockingRelationReference(_relationId(101)),
              LongTermBlockingRelationReference(_relationId(102)),
              LongTermBlockingRelationReference(_relationId(103)),
              DailyChoiceBlockingRelationReference(
                (DailyChoiceId.decode(
                  tagFixtureId(201),
                ) as DailyChoiceIdDecodingSuccess).id,
              ),
            ],
          ),
          presentationTitle: 'Одинаковое намерение',
        ) as BlockingRelationsDeleteAccepted).future,
      );
      expect(massBlocked.isFailure, isTrue);
      expect(
        (massBlocked.result as GraphCommandFailed).failure,
        isA<DeleteBlockingRelationsSelectionConflictFailure>().having(
          (failure) => failure.reason,
          'причина конфликта',
          BlockingRelationConflictReason.deletionProhibited,
        ),
      );
      await _expectUnchangedNavigation(
        tester,
        app.router,
        initial,
        app.raw,
        before,
      );
      await _selectScope(tester, TaggedIntentionsScope.archived);
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'отказ записи откатывает одиночное, массовое и общее удаление на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      final initial = await _loaded(tester, firstTagNumber);
      final before = _snapshot(app.raw);
      final coordinator = app.runtime.commandCoordinator;
      app.raw.execute('''
        CREATE TEMP TRIGGER fail_navigation_assignment_cascade
        AFTER DELETE ON tag_assignments
        WHEN OLD.intention_id = '${tagFixtureId(5)}'
          OR OLD.long_term_relation_id IN ('${tagFixtureId(103)}', '${tagFixtureId(106)}')
        BEGIN
          SELECT RAISE(ABORT, 'navigation assignment cascade');
        END
      ''');
      final attempts = <Future<GraphCommandCompletion> Function()>[
        () => (coordinator.acceptExisting(
          DeleteIntention(_intentionId(5)),
          presentationTitle: 'Отдельное намерение',
        ) as IntentionCommandAccepted).future,
        () => (coordinator.acceptRelationDelete(
          DeleteLongTermRelation(_relationId(106)),
        ) as LongTermRelationCommandAccepted).future,
        () => (coordinator.acceptBlockingRelationsDelete(
          DeleteBlockingRelations.longTerm(
            intentionId: _intentionId(1),
            relationIds: [_relationId(102), _relationId(103)],
          ),
          presentationTitle: 'Одинаковое намерение',
        ) as BlockingRelationsDeleteAccepted).future,
        () => (coordinator.acceptTagDelete(
          DeleteTag(_tagId(firstTagNumber)),
        ) as TagCommandAccepted).future,
      ];
      for (final attempt in attempts) {
        final completion = await _completed(tester, attempt());
        expect(completion.isFailure, isTrue);
        expect(completion.confirmedChange, isNull);
        expect(_failure(completion).category, GraphFailureCategory.unexpected);
        await _expectUnchangedNavigation(
          tester,
          app.router,
          initial,
          app.raw,
          before,
        );
      }
      await _selectScope(tester, TaggedIntentionsScope.archived);
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      final archived = await _loaded(tester, firstTagNumber);
      final failedDelete = await _completed(tester, attempts.last());
      expect(failedDelete.isFailure, isTrue);
      await _expectUnchangedNavigation(
        tester,
        app.router,
        archived,
        app.raw,
        before,
      );

      app.raw.execute('DROP TRIGGER fail_navigation_assignment_cascade');
      for (final attempt in attempts.take(3)) {
        await _changed(tester, attempt());
      }
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      _expectOnlyDeleted(
        app.raw,
        before,
        intentions: [5],
        relations: [102, 103, 106],
      );
      await _selectScope(tester, TaggedIntentionsScope.active);
      await _expectTargets(tester, app.router, [
        _intentionId(1),
        _intentionId(4),
      ]);
      expect(app.raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'удаление общего тега сохраняет граф и не подменяет выбор одноимённым на $locale',
    (tester) async {
      final app = await _pumpApp(
        tester,
        locale,
        seed: seedTagNavigationLifecycleFixture,
      );
      await _openCatalogTag(tester, firstTagNumber);
      await _loaded(tester, firstTagNumber);
      await _selectScope(tester, TaggedIntentionsScope.archived);
      final before = _snapshot(app.raw);
      final graph = retainedTagFixtureGraph(app.raw);
      final coordinator = app.runtime.commandCoordinator;
      const name = 'Общее новое название';
      await _changed(
        tester,
        (coordinator.acceptTagRename(
          RenameTag(
            tagId: _tagId(firstTagNumber),
            name: TagName.fromInput(name),
          ),
        ) as TagCommandAccepted).future,
      );
      await _expectTargets(tester, app.router, [
        _intentionId(2),
      ], scope: TaggedIntentionsScope.archived);
      expect(find.text(_l10n(tester).tagNavigationTag(name)), findsOneWidget);
      expect(_snapshot(app.raw)['tag_assignments'], before['tag_assignments']);
      final deleted = await _completed(
        tester,
        (coordinator.acceptTagDelete(
          DeleteTag(_tagId(firstTagNumber)),
        ) as TagCommandAccepted).future,
      );
      expect(deleted.isFailure, isFalse);
      await _expectMissing(tester, app.router, TaggedIntentionsScope.archived);
      expect(retainedTagFixtureGraph(app.raw), graph);
      expect(
        _snapshot(app.raw)['tags'],
        before['tags']!.where(
          (row) => !row.contains(tagFixtureId(firstTagNumber)),
        ),
      );
      final retainedAssignments = before['tag_assignments']!
          .where((row) => !row.contains(tagFixtureId(firstTagNumber)))
          .toList();
      expect(_snapshot(app.raw)['tag_assignments'], retainedAssignments);

      final created = await _completed(
        tester,
        (coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(TagName.fromInput(name)),
        ) as TagCommandAccepted).future,
      );
      expect(created.isFailure, isFalse);
      final newTag =
          ((created.confirmedResult as TagCommandSucceeded).value.value
                  as TagCreated)
              .tag;
      expect(newTag.id, isNot(_tagId(firstTagNumber)));
      expect(newTag.name.value, name);
      expect(_snapshot(app.raw)['tag_assignments'], retainedAssignments);
      await _expectMissing(tester, app.router, TaggedIntentionsScope.archived);
      final assigned = await _completed(
        tester,
        (coordinator.acceptTagAssign(
          AssignTag(tagId: newTag.id, intentionId: _intentionId(1)),
        ) as TagCommandAccepted).future,
      );
      expect(assigned.isFailure, isFalse);
      await _expectMissing(tester, app.router, TaggedIntentionsScope.archived);
      expect(retainedTagFixtureGraph(app.raw), graph);
      expect(
        app.raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
          tagFixtureId(firstTagNumber),
        ]),
        isEmpty,
      );
      expect(app.raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

GraphCommandFailure _failure(
  GraphCommandCompletion completion,
) => switch (completion) {
  IntentionCommandCompletion(result: ResultFailure(:final failure)) => failure,
  LongTermRelationCommandCompletion(
    confirmedResult: GraphResultFailure(:final failure),
  ) =>
    failure,
  BlockingRelationsDeleteCompletion(
    result: GraphResultFailure(:final failure),
  ) =>
    failure,
  TagCommandCompletion(confirmedResult: GraphResultFailure(:final failure)) =>
    failure,
  _ => throw StateError('Ожидался отказ команды'),
};

Future<void> _expectMissing(
  WidgetTester tester,
  AppRouter router,
  TaggedIntentionsScope scope,
) async {
  await _waitFor(
    tester,
    () => _state(tester, firstTagNumber) is TagNavigationTagMissing,
  );
  await tester.pumpAndSettle();
  expect(_state(tester, firstTagNumber).tagId, _tagId(firstTagNumber));
  expect(_state(tester, firstTagNumber).scope, scope);
  expect(router.current.name, TagNavigationRoute.name);
  expect(
    router.current.argsAs<TagNavigationRouteArgs>().tagId,
    _tagId(firstTagNumber),
  );
  expect(find.text(_l10n(tester).tagNotFound), findsOneWidget);
  expect(find.byType(ListTile), findsNothing);
}

Future<void> _expectUnchangedNavigation(
  WidgetTester tester,
  AppRouter router,
  TagNavigationLoaded initial,
  sqlite.Database raw,
  Map<String, List<List<Object?>>> before,
) async {
  final state = await _expectTargets(
    tester,
    router,
    initial.items.map((item) => item.id).toList(),
    scope: initial.scope,
  );
  expect(state.revision.compareTo(initial.revision), GraphRevisionOrder.same);
  expect(_snapshot(raw), before);
}

void _expectOnlyDeleted(
  sqlite.Database raw,
  Map<String, List<List<Object?>>> before, {
  List<int> intentions = const [],
  List<int> relations = const [],
}) {
  final intentionIds = intentions.map(tagFixtureId).toSet();
  final relationIds = relations.map(tagFixtureId).toSet();
  final remainingIntentions = before['intentions']!
      .where((row) => !row.any(intentionIds.contains))
      .toList();
  expect(_snapshot(raw), {
    for (final entry in before.entries)
      entry.key: entry.key == 'intention_titles_fts'
          ? [
              for (final row in remainingIntentions) [row[2]],
            ]
          : entry.value
                .where(
                  (row) => switch (entry.key) {
                    'intentions' => !row.any(intentionIds.contains),
                    'long_term_relations' => !row.any(relationIds.contains),
                    'tag_assignments' => !row.any(
                      {...intentionIds, ...relationIds}.contains,
                    ),
                    _ => true,
                  },
                )
                .toList(),
  });
}

List<IntentionId> _lifecycleActiveTargets() => [
  _intentionId(1),
  _intentionId(4),
  _intentionId(5),
];

Future<TagNavigationLoaded> _changed(
  WidgetTester tester,
  Future<GraphCommandCompletion> future,
) async {
  final completion = await _completed(tester, future);
  expect(completion.isFailure, isFalse);
  expect(completion.revision, isNotNull);
  await _waitFor(tester, () {
    final state = _state(tester, firstTagNumber);
    return state is TagNavigationLoaded &&
        state.canUseCurrentItems &&
        state.revision.compareTo(completion.revision!) ==
            GraphRevisionOrder.same;
  });
  return _loaded(tester, firstTagNumber);
}

Future<T> _completed<T extends GraphCommandCompletion>(
  WidgetTester tester,
  Future<T> future,
) async {
  T? outcome;
  unawaited(future.then((completion) => outcome = completion));
  await _waitFor(tester, () => outcome != null);
  return outcome!;
}

Future<void> _changeAssignment(
  WidgetTester tester,
  GraphCommandCoordinator coordinator,
  IntentionId target, {
  required bool assigned,
}) async {
  final id = _tagId(firstTagNumber);
  final start = assigned
      ? coordinator.acceptTagAssign(AssignTag(tagId: id, intentionId: target))
      : coordinator.acceptTagRemoveAssignment(
          RemoveTagAssignment(tagId: id, intentionId: target),
        );
  await _changed(tester, (start as TagCommandAccepted).future);
}

Future<TagNavigationLoaded> _expectTargets(
  WidgetTester tester,
  AppRouter router,
  List<IntentionId> targets, {
  TaggedIntentionsScope scope = TaggedIntentionsScope.active,
}) async {
  final state = await _loaded(tester, firstTagNumber);
  expect(router.current.name, TagNavigationRoute.name);
  expect(
    router.current.argsAs<TagNavigationRouteArgs>().tagId,
    _tagId(firstTagNumber),
  );
  expect(state.tagId, _tagId(firstTagNumber));
  expect(state.scope, scope);
  expect(state.items.map((item) => item.id), targets);
  expect(state.hasReachedEnd, isTrue);
  for (final target in [
    for (final number in [1, 2, 3, 4, 5]) _intentionId(number),
  ]) {
    expect(
      find.byKey(ValueKey(target)),
      targets.contains(target) ? findsOneWidget : findsNothing,
    );
  }
  expect(
    tester.widget<ChoiceChip>(find.byKey(ValueKey(scope))).selected,
    isTrue,
  );
  return state;
}

void _expectRowText(WidgetTester tester, IntentionId target, String text) =>
    expect(
      find.descendant(
        of: find.byKey(ValueKey(target)),
        matching: find.text(text),
      ),
      findsOneWidget,
    );

Map<String, Object?> _row(sqlite.Database raw, String table, int number) =>
    Map.of(
      raw.select('SELECT * FROM $table WHERE id = ?', [
        tagFixtureId(number),
      ]).single,
    );

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await _tap(tester, finder);
}
