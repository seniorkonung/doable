part of 'tag_navigation_view_model_test.dart';

void _realTagNavigationCatalogScenarios() {
  for (final scope in TaggedEntitiesScope.values) {
    for (final searchFails in [false, true]) {
      test(
        '${searchFails ? 'отказавший' : 'успешный'} совместный поиск '
        'сохраняет загруженную навигацию и добавляет продолжение: $scope',
        () async {
          final h = await _RealNavigationHarness.open();
          addTearDown(h.dispose);
          final expected =
              (await h.graph.getTaggedEntitiesPage(
                    TaggedEntitiesQuery(
                      tagId: h.tagId,
                      scope: scope,
                      pageSize: 100,
                    ),
                  ) as TaggedEntitiesPageSuccess).value.items
                  .map((item) => item.target)
                  .toList();
          h.model.setScope(scope);
          final first = await h.loaded((state) => state.scope == scope);
          expect(first.items, hasLength(50));
          expect(first.nextCursor, isNotNull);
          h.probe.navigationReads.clear();
          final stateOffset = h.states.length;
          h.probe.failAfterFilterInsert = searchFails;

          final search = await h.graph.getCatalogPage(
            IntentionCatalogQuery(
              scope: scope == TaggedEntitiesScope.active
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
          expect(loaded.items.map((item) => item.target), expected);
          expect(loaded.items.take(first.items.length), first.items);
          expect(
            loaded.items.map((item) => item.target).toSet(),
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
      (state) =>
          (state.items.first as TaggedIntention).title ==
          'Новое название получателя',
    );
    expect(fresh.items, hasLength(50));
    expect(
      fresh.items.map((item) => item.target),
      first.items.map((item) => item.target),
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
}

final class _RealNavigationHarness {
  _RealNavigationHarness(this.database, this.raw, this.graph, this.probe) {
    container = ProviderContainer(
      overrides: [
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

  static Future<_RealNavigationHarness> open() async {
    late sqlite.Database raw;
    final probe = _NavigationCatalogSqlProbe();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    seedTagNavigationFixture(raw, extraPairsPerScope: 26);
    final graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 29),
      InMemoryDiagnosticsSink(),
    );
    return _RealNavigationHarness(database, raw, graph, probe);
  }

  final AppDatabase database;
  final sqlite.Database raw;
  final DriftPersonalGraphRepository graph;
  final _NavigationCatalogSqlProbe probe;
  final tagId =
      (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
  final states = <TagNavigationState>[];
  late final ProviderContainer container;
  late final ProviderSubscription<TagNavigationState> subscription;
  late final TagNavigationViewModel model;

  Future<TagNavigationLoaded> loaded(
    bool Function(TagNavigationLoaded) matches,
  ) {
    final result = Completer<TagNavigationLoaded>();
    void observe(TagNavigationState state) {
      if (!result.isCompleted &&
          state is TagNavigationLoaded &&
          state.canUseCurrentItems &&
          matches(state)) {
        result.complete(state);
      }
    }

    final listener = container.listen(
      tagNavigationViewModelProvider(tagId),
      (_, state) => observe(state),
    );
    observe(listener.read());
    return result.future.whenComplete(listener.close);
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}

final class _NavigationCatalogSqlProbe extends LocalDatabaseConnectionObserver {
  final navigationReads = <String>[];
  var failAfterFilterInsert = false;

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
    if (failAfterFilterInsert &&
        statement.statements.single.startsWith(
          'INSERT INTO temp.doable_catalog_excluded_tags',
        )) {
      failAfterFilterInsert = false;
      throw StateError('CANARY-отказ совместного поиска');
    }
  }
}
