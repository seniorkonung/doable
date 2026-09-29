part of 'drift_tagged_entities_read_test.dart';

void _taggedEntitiesCatalogStorageScenarios(
  Future<
    ({
      AppDatabase database,
      sqlite.Database raw,
      DriftPersonalGraphRepository graph,
      _ReadProbe probe,
      File file,
    })
  >
  Function()
  open,
) {
  for (final external in [false, true]) {
    for (final writeBeforeSearch in [false, true]) {
      for (final corrupt in [false, true]) {
        for (final searchFails in [false, true]) {
          test('${corrupt ? 'повреждение ссылки' : 'сырая запись'} '
              'на ${external ? 'другом' : 'том же'} соединении '
              '${writeBeforeSearch ? 'до' : 'после'} '
              '${searchFails ? 'отказавшего' : 'успешного'} поиска '
              'лишает курсор действительности без новой ревизии', () async {
            final h = await open();
            late sqlite.Database otherRaw;
            final other = AppDatabase(
              openFileBackedLocalDatabase(h.file, setup: (db) => otherRaw = db),
            );
            addTearDown(other.close);
            await other.open();
            expect(identical(h.raw, otherRaw), isFalse);
            final otherGraph = _storageScenarioRepository(other);
            final first = await _storageScenarioPage(h.graph);
            final otherFirst = await _storageScenarioPage(otherGraph);
            expect(first.nextCursor, isNotNull);
            expect(otherFirst.nextCursor, isNotNull);
            final writer = external ? otherRaw : h.raw;
            void write() {
              if (corrupt) {
                writer.execute('PRAGMA foreign_keys = OFF');
                writer.execute(
                  'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
                  [tagFixtureId(firstTagNumber), tagFixtureId(999)],
                );
              } else {
                writer.execute('UPDATE intentions SET title = ? WHERE id = ?', [
                  'Подтверждённое сырое изменение',
                  tagFixtureId(1),
                ]);
              }
            }

            if (writeBeforeSearch) write();
            h.probe.failAfter = searchFails ? _isCatalogRows : null;
            final search = await h.graph.getCatalogPage(
              _storageScenarioQuery(),
            );
            expect(
              search,
              searchFails
                  ? isA<ResultFailure<IntentionCatalogPage>>().having(
                      (result) => result.failure,
                      'отказ поиска',
                      isA<IntentionUnexpectedFailure>(),
                    )
                  : isA<ResultSuccess<IntentionCatalogPage>>(),
            );
            if (!writeBeforeSearch) write();

            for (final (repository, previous) in [
              (h.graph, first),
              (otherGraph, otherFirst),
            ]) {
              expect(
                await repository.getTaggedEntitiesPage(
                  _storageScenarioNavigation(cursor: previous.nextCursor),
                ),
                isA<TaggedEntitiesPageError>().having(
                  (result) => result.failure,
                  'старый снимок',
                  isA<TaggedEntitiesSnapshotExpired>(),
                ),
              );
              final fresh = await repository.getTaggedEntitiesPage(
                _storageScenarioNavigation(),
              );
              if (corrupt) {
                expect(
                  fresh,
                  isA<TaggedEntitiesPageError>().having(
                    (result) => result.failure,
                    'повреждённая ссылка',
                    isA<TaggedEntitiesCorruptionFailure>(),
                  ),
                );
                // Ревизия проверяется независимым предметным чтением:
                // успешную неполную навигацию при повреждении не допускаем.
                final catalog = (await repository.getCatalogPage(
                  _storageScenarioQuery(),
                ) as ResultSuccess<IntentionCatalogPage>).value;
                expect(
                  catalog.revision.compareTo(previous.revision),
                  GraphRevisionOrder.same,
                );
              } else {
                final page = (fresh as TaggedEntitiesPageSuccess).value;
                expect(
                  page.revision.compareTo(previous.revision),
                  GraphRevisionOrder.same,
                );
                expect(
                  (page.items.single as TaggedIntention).title,
                  'Подтверждённое сырое изменение',
                );
              }
            }
          });
        }
      }
    }
  }

  test('поиски на двух соединениях сохраняют курсоры обоих, предметная команда устаревает курсоры обоих', () async {
    final h = await open();
    final other = AppDatabase(openFileBackedLocalDatabase(h.file));
    addTearDown(other.close);
    await other.open();
    final otherGraph = _storageScenarioRepository(other);
    final first = await _storageScenarioPage(h.graph);
    final otherFirst = await _storageScenarioPage(otherGraph);
    for (var index = 0; index < 3; index++) {
      h.probe.failAfter = index.isEven ? _isCatalogRows : null;
      await h.graph.getCatalogPage(_storageScenarioQuery());
      expect(
        await otherGraph.getCatalogPage(_storageScenarioQuery()),
        isA<ResultSuccess<IntentionCatalogPage>>(),
      );
      for (final (repository, previous) in [
        (h.graph, first),
        (otherGraph, otherFirst),
      ]) {
        final next = (await repository.getTaggedEntitiesPage(
          _storageScenarioNavigation(cursor: previous.nextCursor),
        ) as TaggedEntitiesPageSuccess).value;
        expect(
          next.revision.compareTo(previous.revision),
          GraphRevisionOrder.same,
        );
        expect(
          next.items.single.target,
          LongTermRelationTagTarget(_relation(101)),
        );
      }
    }
    expect(
      await h.graph.execute(DisableIntentionReadiness(_intention(1))),
      isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    );
    for (final (repository, previous) in [
      (h.graph, first),
      (otherGraph, otherFirst),
    ]) {
      expect(
        await repository.getTaggedEntitiesPage(
          _storageScenarioNavigation(cursor: previous.nextCursor),
        ),
        isA<TaggedEntitiesPageError>().having(
          (result) => result.failure,
          'старый снимок',
          isA<TaggedEntitiesSnapshotExpired>(),
        ),
      );
      final fresh = await _storageScenarioPage(repository);
      expect(
        fresh.revision.compareTo(previous.revision),
        identical(repository, h.graph)
            ? GraphRevisionOrder.newer
            : GraphRevisionOrder.same,
      );
    }
  });
}

DriftPersonalGraphRepository _storageScenarioRepository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 29),
      InMemoryDiagnosticsSink(),
    );

IntentionCatalogQuery _storageScenarioQuery() => IntentionCatalogQuery(
  scope: IntentionScope.active,
  titleFilter: null,
  tagFilter: IntentionTagFilter(
    requiredTagIds: [_tag(firstTagNumber)],
    excludedTagIds: [_tag(lastTagNumber)],
  ),
  order: IntentionCatalogOrder.createdAtAscending,
  pageSize: 1,
);

TaggedEntitiesQuery _storageScenarioNavigation({
  TaggedEntitiesCursor? cursor,
}) => TaggedEntitiesQuery(
  tagId: _tag(firstTagNumber),
  scope: TaggedEntitiesScope.active,
  pageSize: 1,
  cursor: cursor,
);

Future<TaggedEntitiesPage> _storageScenarioPage(
  DriftPersonalGraphRepository graph,
) async => (await graph.getTaggedEntitiesPage(
  _storageScenarioNavigation(),
) as TaggedEntitiesPageSuccess).value;
