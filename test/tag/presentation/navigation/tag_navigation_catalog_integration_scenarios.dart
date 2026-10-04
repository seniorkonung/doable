part of 'tag_navigation_view_model_test.dart';

void _realTagNavigationCatalogScenarios() {
  for (final scope in TaggedIntentionsScope.values) {
    for (final searchFails in [false, true]) {
      test(
        '${searchFails ? 'отказавший' : 'успешный'} совместный поиск '
        'сохраняет загруженную навигацию и добавляет продолжение: $scope',
        () async {
          final h = await _RealNavigationHarness.open();
          addTearDown(h.dispose);
          final expected =
              (await h.graph.getTaggedIntentionsPage(
                    TaggedIntentionsQuery(
                      tagId: h.tagId,
                      scope: scope,
                      pageSize: 100,
                    ),
                  ) as TaggedIntentionsPageSuccess).value.items
                  .map((item) => item.id)
                  .toList();
          h.model.setScope(scope);
          final first = await h.loaded((state) => state.scope == scope);
          expect(first.items, hasLength(50));
          expect(first.nextCursor, isNotNull);
          h.probe.navigationReads.clear();
          final stateOffset = h.states.length;
          h.probe.failCatalogSearch = searchFails;

          final search = await h.graph.getCatalogPage(
            IntentionCatalogQuery(
              scope: scope == TaggedIntentionsScope.active
                  ? IntentionScope.active
                  : IntentionScope.archived,
              titleFilter: null,
              tagFilter: IntentionTagFilter(
                requiredTagIds: [h.tagId],
                excludedTagIds: [
                  (TagId.decode(tagFixtureId(303)) as TagIdDecodingSuccess).id,
                ],
              ),
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
            ),
          );
          expect(
            search,
            searchFails
                ? isA<ResultFailure<IntentionCatalogPage>>().having(
                    (result) => result.failure,
                    'причина',
                    isA<IntentionUnexpectedFailure>(),
                  )
                : isA<ResultSuccess<IntentionCatalogPage>>(),
          );
          final unchanged = h.subscription.read() as TagNavigationLoaded;
          expect(unchanged.items, first.items);
          expect(unchanged.nextCursor, same(first.nextCursor));
          expect(unchanged.freshness, TagNavigationFreshness.current);
          await h.model.loadMore();
          final loaded = h.subscription.read() as TagNavigationLoaded;
          expect(loaded.items.map((item) => item.id), expected);
          expect(loaded.items.take(first.items.length), first.items);
          expect(
            loaded.items.map((item) => item.id).toSet(),
            hasLength(expected.length),
          );
          expect(loaded.hasReachedEnd, isTrue);
          expect(loaded.freshness, TagNavigationFreshness.current);
          expect(loaded.refreshFailure, isNull);
          expect(
            loaded.revision.compareTo(first.revision),
            GraphRevisionOrder.same,
          );
          expect(h.probe.navigationReads, hasLength(1));
          expect(
            h.probe.navigationReads.single,
            contains('AND a.creation_sequence > ?'),
          );
          expect(
            h.states.skip(stateOffset),
            everyElement(
              isA<TagNavigationLoaded>().having(
                (state) => state.freshness,
                'актуальность',
                TagNavigationFreshness.current,
              ),
            ),
          );
        },
      );
    }
  }

  test('реально устаревший снимок адаптера восстанавливает первую порцию навигации', () async {
    final h = await _RealNavigationHarness.open();
    addTearDown(h.dispose);
    final first = await h.loaded((_) => true);
    h.probe.navigationReads.clear();
    h.raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      'Новое название получателя',
      tagFixtureId(1),
    ]);

    await h.model.loadMore();
    final fresh = await h.loaded(
      (state) => state.items.first.title == 'Новое название получателя',
    );
    expect(fresh.items, hasLength(50));
    expect(
      fresh.items.map((item) => item.id),
      first.items.map((item) => item.id),
    );
    expect(fresh.nextCursor, isNotNull);
    expect(fresh.revision.compareTo(first.revision), GraphRevisionOrder.same);
    // Устаревшее продолжение отклонено до выборки, затем получена первая порция.
    expect(h.probe.navigationReads, hasLength(1));
    expect(
      h.probe.navigationReads.single,
      isNot(contains('AND a.creation_sequence > ?')),
    );
    expect(
      h.states,
      anyElement(
        isA<TagNavigationLoaded>().having(
          (state) => state.freshness,
          'обновление',
          TagNavigationFreshness.refreshing,
        ),
      ),
    );
  });

  for (final scope in TaggedIntentionsScope.values) {
    test('полный пакет настоящего создания обновляет навигацию каждого '
        'начального тега один раз и совпадает с чтением назначений: '
        '$scope', () async {
      final h = await _RealNavigationHarness.open(coordinated: true);
      addTearDown(h.dispose);
      final otherTagId = (TagId.decode(
        tagFixtureId(lastTagNumber),
      ) as TagIdDecodingSuccess).id;
      final otherStates = <TagNavigationState>[];
      final other = h.container.listen(
        tagNavigationViewModelProvider(otherTagId),
        (_, state) => otherStates.add(state),
      );
      addTearDown(other.close);
      h.model.setScope(scope);
      h.container
          .read(tagNavigationViewModelProvider(otherTagId).notifier)
          .setScope(scope);
      final first = await h.loaded((state) => state.scope == scope);
      final otherFirst = await h.loadedFor(
        otherTagId,
        (state) => state.scope == scope,
      );
      for (final loaded in [first, otherFirst]) {
        expect(loaded.items, hasLength(50));
        expect(loaded.nextCursor, isNotNull);
      }
      h.probe.navigationReads.clear();
      final stateOffset = h.states.length;
      otherStates.clear();

      // Одноимённое название подчёркивает, что выдача различает идентичности.
      final completion = await h.create(
        CreateIntention.withInitialState(
          title: 'Одинаковое намерение',
          description: 'Создано сразу с тегами',
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: [otherTagId, h.tagId],
        ),
      );
      final revision = completion.revision!;
      final saved = switch (completion.result) {
        ResultSuccess(value: final IntentionSaved saved) => saved,
        _ => fail('Создание не подтверждено.'),
      };
      final createdId = saved.intention.id;
      final current = await h.loaded(
        (state) =>
            state.revision.compareTo(revision) == GraphRevisionOrder.same,
      );
      final otherCurrent = await h.loadedFor(
        otherTagId,
        (state) =>
            state.revision.compareTo(revision) == GraphRevisionOrder.same,
      );

      // Каждая навигация один раз читает первую порцию прежних тега и охвата;
      // новое назначение стоит в конце порядка, поэтому первая порция прежняя.
      expect(h.probe.navigationReads, hasLength(2));
      expect(
        h.probe.navigationReads,
        everyElement(isNot(contains('AND a.creation_sequence > ?'))),
      );
      for (final (states, before, after, tagId) in [
        (h.states.skip(stateOffset).toList(), first, current, h.tagId),
        (otherStates, otherFirst, otherCurrent, otherTagId),
      ]) {
        expect(after.tagId, tagId);
        expect(after.scope, scope);
        expect(_rowContents(after.items), _rowContents(before.items));
        expect(after.nextCursor, isNotNull);
        // Пакет публикует одно начало актуализации и один полный результат;
        // запоздавшее подтверждение названия тега строк не меняет.
        expect(
          states,
          everyElement(
            isA<TagNavigationLoaded>().having(
              (state) => _rowContents(state.items),
              'строки',
              _rowContents(before.items),
            ),
          ),
        );
        final loadedStates = states.whereType<TagNavigationLoaded>();
        expect(
          loadedStates.where(
            (state) => state.freshness == TagNavigationFreshness.refreshing,
          ),
          hasLength(1),
        );
        expect(
          loadedStates.where(
            (state) =>
                state.revision.compareTo(revision) == GraphRevisionOrder.same,
          ),
          [same(after)],
        );
      }

      for (final (tagId, loaded) in [
        (h.tagId, current),
        (otherTagId, otherCurrent),
      ]) {
        final model = h.container.read(
          tagNavigationViewModelProvider(tagId).notifier,
        );
        await model.loadMore();
        final complete = h.container.read(
          tagNavigationViewModelProvider(tagId),
        ) as TagNavigationLoaded;
        final ids = complete.items.map((item) => item.id).toList();
        expect(complete.hasReachedEnd, isTrue);
        expect(
          _rowContents(complete.items.take(loaded.items.length)),
          _rowContents(loaded.items),
        );
        expect(ids.toSet(), hasLength(ids.length));
        expect(ids, await _wholeTaggedIds(h.graph, tagId, scope));
        if (scope == TaggedIntentionsScope.active) {
          expect(ids.last, createdId);
          expect(complete.items.last.title, 'Одинаковое намерение');
          expect(model.canActOn(createdId), isTrue);
        } else {
          expect(ids, isNot(contains(createdId)));
          expect(model.canActOn(createdId), isFalse);
        }
      }

      // Навигация и чтение назначений описывают один и тот же набор пакета.
      final assignments =
          await h.graph.getTagAssignments(createdId) as TagAssignmentsSuccess;
      expect(
        assignments.value.revision.compareTo(revision),
        GraphRevisionOrder.same,
      );
      expect(_tagContents(assignments.value.items), [
        (h.tagId, 'Дом 🏷️'),
        (otherTagId, 'Работа'),
      ]);
      final created = saved.catalogMutation as IntentionCatalogCreated;
      expect(
        _tagContents(created.entry.summary.tags),
        _tagContents(assignments.value.items),
      );
      expect(
        {
          for (final change in saved.changes)
            if (change case TagAssignmentChangedChange(
              :final assignment,
              state: TagAssignmentState.assigned,
            ))
              (assignment.tagId, assignment.intentionId),
        },
        {(h.tagId, createdId), (otherTagId, createdId)},
      );
    });
  }

  test('чтение назначений созданного намерения показывает весь набор с '
      'актуальными названиями после подтверждённого переименования', () async {
    final h = await _RealNavigationHarness.open(coordinated: true);
    addTearDown(h.dispose);
    await h.loaded((_) => true);
    TagId fixtureTag(int number) =>
        (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;
    final completion = await h.create(
      CreateIntention.withInitialState(
        title: 'Навести порядок',
        description: null,
        readiness: IntentionReadiness.notReady,
        favoriteMark: FavoriteMark.notFavorite,
        tagIds: [fixtureTag(lastTagNumber), h.tagId, fixtureTag(303)],
      ),
    );
    final createdId = switch (completion.result) {
      ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
      _ => fail('Создание не подтверждено.'),
    };
    final provider = tagAssignmentsViewModelProvider(createdId);
    final states = <TagAssignmentsState>[];
    final assignments = h.container.listen(
      provider,
      (_, state) => states.add(state),
      fireImmediately: true,
    );
    addTearDown(assignments.close);

    final loaded = await h.until<TagAssignmentsState>(
      provider,
      (state) =>
          state is TagAssignmentsLoaded &&
          state.canUseCurrentItems &&
          state.revision.compareTo(completion.revision!) ==
              GraphRevisionOrder.same,
    ) as TagAssignmentsLoaded;
    // Весь набор сразу в порядке создания тегов, без частичных публикаций.
    expect(_tagContents(loaded.items), [
      (h.tagId, 'Дом 🏷️'),
      (fixtureTag(303), 'Без назначений'),
      (fixtureTag(lastTagNumber), 'Работа'),
    ]);
    expect(states, [isA<TagAssignmentsInitialLoading>(), same(loaded)]);

    final renamed = await (h.coordinator.acceptTagRename(
      RenameTag(tagId: h.tagId, name: TagName.fromInput('Быт')),
    ) as TagCommandAccepted).future;
    expect(renamed.confirmedResult, isA<TagCommandSucceeded>());
    final current = await h.until<TagAssignmentsState>(
      provider,
      (state) =>
          state is TagAssignmentsLoaded &&
          state.canUseCurrentItems &&
          state.revision.compareTo(renamed.revision!) ==
              GraphRevisionOrder.same,
    ) as TagAssignmentsLoaded;
    final expected = [
      (h.tagId, 'Быт'),
      (fixtureTag(303), 'Без назначений'),
      (fixtureTag(lastTagNumber), 'Работа'),
    ];
    expect(_tagContents(current.items), expected);
    expect(
      _tagContents(
        (await h.graph.getTagAssignments(
          createdId,
        ) as TagAssignmentsSuccess).value.items,
      ),
      expected,
    );
    final navigation = await h.loaded(
      (state) =>
          state.revision.compareTo(renamed.revision!) ==
          GraphRevisionOrder.same,
    );
    expect(navigation.tag.name.value, 'Быт');
    await h.model.loadMore();
    final complete = h.subscription.read() as TagNavigationLoaded;
    expect(complete.items.where((item) => item.id == createdId), hasLength(1));
  });
}

/// Сопоставимое содержимое строк навигации.
List<(IntentionId, String, IntentionArchiveState)> _rowContents(
  Iterable<TaggedIntention> items,
) => [for (final item in items) (item.id, item.title, item.archiveState)];

/// Сопоставимое содержимое тегов: идентичность и название.
List<(TagId, String)> _tagContents(List<Tag> tags) => [
  for (final tag in tags) (tag.id, tag.name.value),
];

/// Читает всю выдачу тега в охвате заново настоящим адаптером.
Future<List<IntentionId>> _wholeTaggedIds(
  DriftPersonalGraphRepository graph,
  TagId tagId,
  TaggedIntentionsScope scope,
) async {
  final ids = <IntentionId>[];
  TaggedIntentionsCursor? cursor;
  do {
    final page = await graph.getTaggedIntentionsPage(
      TaggedIntentionsQuery(tagId: tagId, scope: scope, cursor: cursor),
    ) as TaggedIntentionsPageSuccess;
    ids.addAll(page.value.items.map((item) => item.id));
    cursor = page.value.nextCursor;
  } while (cursor != null);
  return ids;
}

final class _RealNavigationHarness {
  _RealNavigationHarness(
    this.database,
    this.raw,
    this.graph,
    this.probe, {
    required this.coordinated,
  }) {
    container = ProviderContainer(
      // С coordinator модели получают пакеты настоящих завершений команд.
      overrides: coordinated
          ? [personalGraphRepositoryProvider.overrideWithValue(graph)]
          : [
              tagNavigationReaderProvider.overrideWithValue(graph),
              tagNavigationChangesProvider.overrideWithValue(
                const Stream<ConfirmedGraphChangePackage>.empty(),
              ),
            ],
    );
    subscription = container.listen(
      tagNavigationViewModelProvider(tagId),
      (_, state) => states.add(state),
      fireImmediately: true,
    );
    model = container.read(tagNavigationViewModelProvider(tagId).notifier);
  }

  static Future<_RealNavigationHarness> open({bool coordinated = false}) async {
    late sqlite.Database raw;
    final probe = _NavigationCatalogSqlProbe();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    seedTagNavigationFixture(raw, extraPairsPerScope: 51);
    final graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 29),
      InMemoryDiagnosticsSink(),
    );
    return _RealNavigationHarness(
      database,
      raw,
      graph,
      probe,
      coordinated: coordinated,
    );
  }

  final AppDatabase database;
  final sqlite.Database raw;
  final DriftPersonalGraphRepository graph;
  final _NavigationCatalogSqlProbe probe;
  final bool coordinated;
  final tagId =
      (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
  final states = <TagNavigationState>[];
  late final ProviderContainer container;
  late final ProviderSubscription<TagNavigationState> subscription;
  late final TagNavigationViewModel model;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Создаёт намерение настоящим адаптером через coordinator.
  Future<IntentionCommandCompletion> create(CreateIntention command) async {
    final start = coordinator.acceptCreation(
      IntentionCreationFormKey(),
      command,
    );
    final completion = await (start as IntentionCommandAccepted).future;
    expect(completion.isFailure, isFalse);
    return completion;
  }

  Future<TagNavigationLoaded> loaded(
    bool Function(TagNavigationLoaded) matches,
  ) => loadedFor(tagId, matches);

  Future<TagNavigationLoaded> loadedFor(
    TagId tagId,
    bool Function(TagNavigationLoaded) matches,
  ) async => await until(
    tagNavigationViewModelProvider(tagId),
    (state) =>
        state is TagNavigationLoaded &&
        state.canUseCurrentItems &&
        matches(state),
  ) as TagNavigationLoaded;

  /// Ждёт первого состояния [provider], удовлетворяющего [matches].
  Future<T> until<T>(ProviderListenable<T> provider, bool Function(T) matches) {
    final result = Completer<T>();
    void observe(T state) {
      if (!result.isCompleted && matches(state)) result.complete(state);
    }

    final listener = container.listen(provider, (_, state) => observe(state));
    observe(listener.read());
    return result.future.whenComplete(listener.close);
  }

  Future<void> dispose() async {
    if (coordinated) await coordinator.shutdown();
    container.dispose();
    await database.close();
  }
}

final class _NavigationCatalogSqlProbe extends LocalDatabaseConnectionObserver {
  final navigationReads = <String>[];
  var failCatalogSearch = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final sql = statement.statements.single;
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        sql.contains('ORDER BY a.creation_sequence ASC LIMIT')) {
      navigationReads.add(sql);
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final sql = statement.statements.single;
    if (failCatalogSearch &&
        sql.contains('json_each(') &&
        sql.contains('LIMIT')) {
      failCatalogSearch = false;
      throw StateError('CANARY-отказ совместного поиска');
    }
  }
}
