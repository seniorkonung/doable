import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_test_support.dart'
    as catalog_support;
import '../../support/in_memory_diagnostics_sink.dart';
import '../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart';

/// Контрольная точка согласования: каталог, подробные данные и соседство
/// обслуживаются одним графом, одним coordinator и одним потоком завершений.
void main() {
  test(
    'массовое удаление Drift согласует все открытые представления',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      final ids = [
        for (var index = 1; index <= 4; index++) testIntentionId(index),
      ];
      for (var index = 0; index < ids.length; index++) {
        await database
            .into(database.intentions)
            .insert(
              IntentionsCompanion.insert(
                id: ids[index].toCanonicalString(),
                title: 'Намерение ${index + 1}',
                createdAt: 1000000 + index,
                updatedAt: 2000000 + index,
              ),
            );
      }
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 23),
        InMemoryDiagnosticsSink(),
      );
      Future<LongTermRelationId> create(
        IntentionId source,
        IntentionId related,
        LongTermRelationType type,
      ) async {
        final result = await repository.execute(
          CreateLongTermRelation(
            sourceIntentionId: source,
            relatedIntentionId: related,
            type: type,
            priority: RelationPriority.p2,
            description: null,
          ),
        );
        return ((result as GraphCommandSucceeded).value.value
                as LongTermRelationCreated)
            .relation
            .id;
      }

      final selectedActive = await create(
        ids[0],
        ids[1],
        LongTermRelationType.need,
      );
      final selectedArchived = await create(
        ids[2],
        ids[0],
        LongTermRelationType.can,
      );
      expect(
        await repository.execute(ArchiveLongTermRelation(selectedArchived)),
        isA<GraphCommandSucceeded>(),
      );
      final untouchedOwner = await create(
        ids[0],
        ids[3],
        LongTermRelationType.can,
      );
      final untouchedNeighbor = await create(
        ids[1],
        ids[2],
        LongTermRelationType.need,
      );

      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          catalogPagingPolicyProvider.overrideWithValue(
            CatalogPagingPolicy(
              pageSize: 50,
              prefetchRemaining: 0,
              filterDebounce: Duration.zero,
            ),
          ),
        ],
        retry: (retryCount, error) => null,
      );
      final catalogProvider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final filteredProvider = intentionCatalogViewModelProvider(
        SelectRelationParticipant(
          excludedIntentionId: ids[3],
          selectionContext: RelationParticipantSelectionContext.activeRelation,
        ),
      );
      final catalogUpdates = <IntentionCatalogLoaded>[];
      final subscriptions = [
        container.listen(catalogProvider, (_, next) {
          if (next.value case final IntentionCatalogLoaded loaded) {
            catalogUpdates.add(loaded);
          }
        }, fireImmediately: true),
        container.listen(filteredProvider, (_, _) {}, fireImmediately: true),
        for (final id in ids)
          container.listen(
            intentionDetailsViewModelProvider(id),
            (_, _) {},
            fireImmediately: true,
          ),
        for (final id in [ids[0], ids[1]])
          container.listen(
            relationNeighborhoodViewModelProvider(id),
            (_, _) {},
            fireImmediately: true,
          ),
        for (final id in [selectedActive, untouchedNeighbor])
          container.listen(
            relationDetailsViewModelProvider(id),
            (_, _) {},
            fireImmediately: true,
          ),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
        container.dispose();
      });
      await _settleUntil(
        () =>
            container.read(catalogProvider).value is IntentionCatalogLoaded &&
            container.read(filteredProvider).value is IntentionCatalogLoaded &&
            ids.every(
              (id) =>
                  container.read(intentionDetailsViewModelProvider(id))
                      is IntentionDetailsLoaded,
            ) &&
            [ids[0], ids[1]].every(
              (id) =>
                  container.read(relationNeighborhoodViewModelProvider(id))
                      is RelationGroupLoaded,
            ) &&
            [selectedActive, untouchedNeighbor].every(
              (id) =>
                  container.read(relationDetailsViewModelProvider(id))
                      is RelationDetailsLoaded,
            ),
      );

      final catalogBefore =
          container.read(catalogProvider).requireValue
              as IntentionCatalogLoaded;
      final stableCatalog = [
        for (final item in catalogBefore.items)
          (item.id, item.title, item.createdAt.value, item.updatedAt.value),
      ];
      final intentionsBefore = [
        for (final row
            in await database
                .customSelect('SELECT * FROM intentions ORDER BY id')
                .get())
          row.data,
      ];
      container
          .read(filteredProvider.notifier)
          .changeTitleFilter('Намерение 1');
      await _settleUntil(() {
        final filtered = container.read(filteredProvider).value;
        return filtered is IntentionCatalogLoaded &&
            filtered.selection.titleFilterText == 'Намерение 1' &&
            filtered.items.length == 1;
      });
      catalogUpdates.clear();
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final command = DeleteBlockingRelations(
        intentionId: ids[0],
        relationIds: [selectedActive, selectedArchived],
      );
      final start = coordinator.acceptBlockingRelationsDelete(
        command,
        presentationTitle: 'Намерение 1',
      ) as BlockingRelationsDeleteAccepted;
      final completion = await start.future;
      final confirmed = (completion.result as GraphCommandSucceeded).value;
      expect(confirmed.value, isA<BlockingRelationsDeleted>());
      expect(
        (confirmed.value as BlockingRelationsDeleted).deletedRelations
            .map((relation) => relation.id)
            .toSet(),
        {selectedActive, selectedArchived},
      );
      await _settleUntil(
        () =>
            container.read(relationDetailsViewModelProvider(selectedActive))
                is RelationDetailsDeleted &&
            container.read(relationNeighborhoodViewModelProvider(ids[0]))
                is RelationGroupEmpty &&
            container.read(relationNeighborhoodViewModelProvider(ids[1]))
                is RelationGroupLoaded &&
            container.read(intentionDetailsViewModelProvider(ids[0]))
                is IntentionDetailsLoaded &&
            (container.read(
                  intentionDetailsViewModelProvider(ids[0]),
                ) as IntentionDetailsLoaded).details.relationCounts.total ==
                1,
      );

      final catalogAfter =
          container.read(catalogProvider).requireValue
              as IntentionCatalogLoaded;
      expect(catalogAfter.items.map((item) => item.activeRelationCount), [
        1,
        1,
        1,
        1,
      ]);
      expect(
        catalogAfter.items.map(
          (item) =>
              (item.id, item.title, item.createdAt.value, item.updatedAt.value),
        ),
        stableCatalog,
      );
      expect(catalogAfter.totalCount, catalogBefore.totalCount);
      expect(catalogAfter.nextCursor, catalogBefore.nextCursor);
      expect(catalogUpdates, [same(catalogAfter)]);
      final filteredAfter =
          container.read(filteredProvider).requireValue
              as IntentionCatalogLoaded;
      expect(filteredAfter.selection.titleFilterText, 'Намерение 1');
      expect(filteredAfter.items.single.id, ids[0]);
      expect(filteredAfter.items.single.activeRelationCount, 1);
      expect(filteredAfter.totalCount, 1);
      for (final id in ids) {
        final details = container.read(
          intentionDetailsViewModelProvider(id),
        ) as IntentionDetailsLoaded;
        expect(details.details.relationCounts.active, 1);
        expect(details.intention.title, 'Намерение ${ids.indexOf(id) + 1}');
      }
      final ownerGroup = container.read(
        relationNeighborhoodViewModelProvider(ids[0]),
      ) as RelationGroupEmpty;
      expect(ownerGroup.counts.total, 1);
      expect(ownerGroup.counts.activeCanOutgoing, 1);
      expect(ownerGroup.counts.archivedCanIncoming, 0);
      final neighborGroup = container.read(
        relationNeighborhoodViewModelProvider(ids[1]),
      ) as RelationGroupLoaded;
      expect(neighborGroup.items.single.relation.id, untouchedNeighbor);
      expect(neighborGroup.items.single.source.activeRelationCount, 1);
      expect(neighborGroup.counts.total, 1);
      final remainingDetails = container.read(
        relationDetailsViewModelProvider(untouchedNeighbor),
      ) as RelationDetailsLoaded;
      expect(remainingDetails.details.source.activeRelationCount, 1);
      expect(remainingDetails.details.relation.id, untouchedNeighbor);
      final savedRelations = await database
          .customSelect('SELECT id FROM long_term_relations')
          .get();
      expect([
        for (final row
            in await database
                .customSelect('SELECT * FROM intentions ORDER BY id')
                .get())
          row.data,
      ], intentionsBefore);
      expect(savedRelations.map((row) => row.read<String>('id')).toSet(), {
        untouchedOwner.toCanonicalString(),
        untouchedNeighbor.toCanonicalString(),
      });
      final persistedCounts = (await repository.getRelationCounts(
        ids[0],
      ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
      expect(persistedCounts.value.total, 1);
      expect(
        persistedCounts.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'смешанный поток операций согласованно обновляет все три потребителя',
    () async {
      final repository = _CheckpointGraphRepository();
      final harness = _CheckpointHarness(repository);
      addTearDown(harness.dispose);
      await harness.loadInitialSurfaces();

      final catalogBefore = harness.catalog;
      final detailsBefore = harness.details;

      // Создание связи с ещё не показанным участником.
      await harness.completeRelationCreation(
        relatedIntentionId: testIntentionId(1002),
        relationIndex: 2,
        revision: const TestGraphRevision(9),
        activeCounts: {testIntentionId(1): 2, testIntentionId(1002): 1},
      );
      repository.emitIntention(
        harness.ownerId,
        testNeighborhoodIntention(id: harness.ownerId, title: 'Владелец'),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        revision: const TestGraphRevision(9),
      );
      await pumpEventQueue();

      // Завершение и наблюдение одной ревизии дают одно чтение группы.
      expect(repository.groupQueries, hasLength(2));
      repository.completeGroupPage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 2),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: null,
          revision: const TestGraphRevision(9),
        ),
      );
      await pumpEventQueue();

      expect(harness.catalogCounts, {
        testIntentionId(1002): 1,
        testIntentionId(1001): 1,
        testIntentionId(1): 2,
      });
      expect(harness.catalog.items.map((item) => item.id), [
        testIntentionId(1002),
        testIntentionId(1001),
        testIntentionId(1),
      ]);
      expect(harness.catalog.revision, const TestGraphRevision(9));
      expect(harness.detailsCounts.activeNeedOutgoing, 2);
      expect(harness.neighborhood.items, hasLength(2));
      expect(harness.neighborhood.totalCount, 2);
      expect(harness.neighborhood.revision, const TestGraphRevision(9));
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());
      expect(repository.catalogQueries, hasLength(1));
      expect(catalogBefore, isNot(same(harness.catalog)));
      expect(detailsBefore, isNot(same(harness.details)));
      final ownerObservationsAfterCreation = repository.observationsOf(
        harness.ownerId,
      );

      // Переименование уже загруженного участника той же выдачи.
      await harness.completeParticipantRename(
        participantIndex: 1001,
        title: 'Переименованное',
        activeRelationCount: 1,
        revision: const TestGraphRevision(11),
      );
      expect(repository.groupQueries, hasLength(3));
      repository.completeGroupPage(
        2,
        RelationGroupFirstPage(
          items: testGroupRows(
            ownerId: harness.ownerId,
            from: 1,
            count: 2,
            neighborTitles: const {1: 'Переименованное'},
          ),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: null,
          revision: const TestGraphRevision(11),
        ),
      );
      await pumpEventQueue();

      expect(harness.catalogTitles[testIntentionId(1001)], 'Переименованное');
      expect(harness.catalogCounts[testIntentionId(1001)], 1);
      expect(harness.catalogCounts[testIntentionId(1)], 2);
      expect(harness.catalog.items, hasLength(3));
      expect(harness.catalog.totalCount, 3);
      expect(harness.catalog.revision, const TestGraphRevision(11));
      expect(harness.neighborhood.items.first.related.title, 'Переименованное');
      expect(harness.neighborhood.revision, const TestGraphRevision(11));
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());
      expect(harness.detailsCounts.activeNeedOutgoing, 2);

      // Чужое переименование не перечитывает каталог и подробные данные.
      expect(repository.catalogQueries, hasLength(1));
      expect(
        repository.observationsOf(harness.ownerId),
        ownerObservationsAfterCreation,
      );
      expect(repository.groupQueries, hasLength(3));
      expect(harness.confirmedCatalogStates, hasLength(2));
    },
  );

  test(
    'замена ограничена выбранной группой и загруженным пределом при повторных '
    'ошибках и инвалидированиях',
    () async {
      final repository = _CheckpointGraphRepository();
      final harness = _CheckpointHarness(repository, neighborhoodPageSize: 2);
      addTearDown(harness.dispose);
      await harness.loadInitialSurfaces(
        groupPage: RelationGroupFirstPage(
          items: testGroupRows(ownerId: testIntentionId(1), from: 1, count: 2),
          counts: testRelationCounts(activeNeedOutgoing: 6),
          nextCursor: const TestRelationGroupCursor(2),
          revision: const TestGraphRevision(4),
        ),
      );

      harness.scrollNeighborhoodTo(1);
      await pumpEventQueue();
      repository.completeGroupPage(
        1,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 3, count: 2),
          nextCursor: const TestRelationGroupCursor(4),
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      expect(harness.neighborhood.items, hasLength(4));

      // Изменение непросматриваемой группы запускает замену выбранной.
      repository.emitIntention(
        harness.ownerId,
        testNeighborhoodIntention(id: harness.ownerId, title: 'Владелец'),
        counts: testRelationCounts(activeNeedOutgoing: 6, activeCanIncoming: 1),
        revision: const TestGraphRevision(9),
      );
      await pumpEventQueue();

      expect(repository.groupQueries, hasLength(3));
      expect(repository.groupQueries.last.cursor, isNull);
      repository.failGroupRead(2, const RelationGroupUnavailableFailure());
      await pumpEventQueue();

      expect(harness.neighborhood.items, hasLength(4));
      expect(harness.neighborhood.counts.activeCanIncoming, 0);
      expect(
        harness.neighborhood.summaryStatus,
        isA<RelationSummaryRefreshFailure>(),
      );
      expect(repository.groupQueries, hasLength(3));

      // Повторное инвалидирование запускает ровно одну новую замену.
      repository.emitIntention(
        harness.ownerId,
        testNeighborhoodIntention(id: harness.ownerId, title: 'Владелец'),
        counts: testRelationCounts(activeNeedOutgoing: 6, activeCanIncoming: 1),
        revision: const TestGraphRevision(11),
      );
      repository.emitIntention(
        harness.ownerId,
        testNeighborhoodIntention(id: harness.ownerId, title: 'Владелец'),
        counts: testRelationCounts(activeNeedOutgoing: 6, activeCanIncoming: 1),
        revision: const TestGraphRevision(11),
      );
      await pumpEventQueue();

      expect(repository.groupQueries, hasLength(4));
      repository.completeGroupPage(
        3,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 2),
          counts: testRelationCounts(
            activeNeedOutgoing: 6,
            activeCanIncoming: 1,
          ),
          nextCursor: const TestRelationGroupCursor(2),
          revision: const TestGraphRevision(11),
        ),
      );
      await pumpEventQueue();

      expect(repository.groupQueries, hasLength(5));
      expect(
        repository.groupQueries.last.cursor,
        const TestRelationGroupCursor(2),
      );
      repository.completeGroupPage(
        4,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 3, count: 2),
          nextCursor: const TestRelationGroupCursor(4),
          revision: const TestGraphRevision(11),
        ),
      );
      await pumpEventQueue();

      expect(harness.neighborhood.items, hasLength(4));
      expect(harness.neighborhood.counts.activeCanIncoming, 1);
      expect(harness.neighborhood.revision, const TestGraphRevision(11));
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());

      // Трасса не выходит за выбранную группу и загруженный предел.
      expect(repository.groupQueries, hasLength(5));
      for (final query in repository.groupQueries) {
        expect(query.intentionId, harness.ownerId);
        expect(query.type, LongTermRelationType.need);
        expect(query.direction, RelationDirection.outgoing);
        expect(query.scope, RelationScope.active);
        expect(query.pageSize, 2);
      }
      expect(
        repository.groupQueries.map((query) => query.cursor),
        everyElement(isNot(const TestRelationGroupCursor(4))),
      );
      expect(repository.catalogQueries, hasLength(1));
      expect(repository.observationsOf(harness.ownerId), 2);
    },
  );

  test(
    'перемещение связи согласует каталог и подробные данные всех участников',
    () async {
      final repository = _CheckpointGraphRepository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          catalogPagingPolicyProvider.overrideWithValue(
            CatalogPagingPolicy(
              pageSize: 4,
              prefetchRemaining: 0,
              filterDebounce: Duration.zero,
            ),
          ),
        ],
        retry: (retryCount, error) => null,
      );
      final participantIds = [
        testIntentionId(1),
        testIntentionId(2),
        testIntentionId(3),
        testIntentionId(4),
      ];
      final catalogSubscription = container.listen(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      final detailSubscriptions = [
        for (final id in participantIds)
          container.listen(
            intentionDetailsViewModelProvider(id),
            (_, _) {},
            fireImmediately: true,
          ),
      ];
      addTearDown(() async {
        catalogSubscription.close();
        for (final subscription in detailSubscriptions) {
          subscription.close();
        }
        container.dispose();
        await repository.dispose();
      });

      final summaries = [
        catalog_support.testSummary(
          index: 4,
          title: 'Участник Г',
          activeRelationCount: 0,
        ),
        catalog_support.testSummary(
          index: 3,
          title: 'Участник В',
          activeRelationCount: 0,
        ),
        catalog_support.testSummary(
          index: 2,
          title: 'Участник Б',
          activeRelationCount: 1,
        ),
        catalog_support.testSummary(
          index: 1,
          title: 'Участник А',
          activeRelationCount: 1,
        ),
      ];
      repository.completeCatalogPage(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: summaries,
            totalCount: summaries.length,
            nextCursor: null,
            revision: const TestGraphRevision(4),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );
      for (var index = 0; index < participantIds.length; index++) {
        repository.emitIntention(
          participantIds[index],
          testNeighborhoodIntention(
            id: participantIds[index],
            title: 'Участник ${String.fromCharCode(1040 + index)}',
          ),
          counts: switch (index) {
            0 => testRelationCounts(activeNeedOutgoing: 1),
            1 => testRelationCounts(activeNeedIncoming: 1),
            _ => testRelationCounts(),
          },
          revision: const TestGraphRevision(4),
        );
      }
      await pumpEventQueue();

      final relationBefore = catalog_support.testRelation(
        sourceIntentionId: participantIds[0],
        relatedIntentionId: participantIds[1],
        index: 41,
      );
      final relationAfter = LongTermRelation(
        id: relationBefore.id,
        sourceIntentionId: participantIds[2],
        relatedIntentionId: participantIds[3],
        type: relationBefore.type,
        priority: relationBefore.priority,
        scope: relationBefore.scope,
        creationSequence: relationBefore.creationSequence,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final accepted = coordinator.acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: relationBefore.id,
          patch: LongTermRelationPatch(
            sourceIntentionId: LongTermRelationFieldSet(participantIds[2]),
            relatedIntentionId: LongTermRelationFieldSet(participantIds[3]),
          ),
        ),
      );
      expect(accepted, isA<LongTermRelationCommandAccepted>());
      repository.completeRelationCommand(
        0,
        GraphCommandSucceeded(
          ConfirmedGraphResult(
            revision: const TestGraphRevision(9),
            value: LongTermRelationUpdated(
              before: relationBefore,
              relation: relationAfter,
              description: null,
              changes: [
                IntentionRelationCountsChanged(
                  revision: const TestGraphRevision(9),
                  intentionId: participantIds[0],
                  counts: testRelationCounts(),
                ),
                IntentionRelationCountsChanged(
                  revision: const TestGraphRevision(9),
                  intentionId: participantIds[1],
                  counts: testRelationCounts(),
                ),
                IntentionRelationCountsChanged(
                  revision: const TestGraphRevision(9),
                  intentionId: participantIds[2],
                  counts: testRelationCounts(activeNeedOutgoing: 1),
                ),
                IntentionRelationCountsChanged(
                  revision: const TestGraphRevision(9),
                  intentionId: participantIds[3],
                  counts: testRelationCounts(activeNeedIncoming: 1),
                ),
                LongTermRelationUpdatedChange(
                  revision: const TestGraphRevision(9),
                  before: relationBefore,
                  after: relationAfter,
                ),
              ],
            ),
          ),
        ),
      );
      await (accepted as LongTermRelationCommandAccepted).future;
      await pumpEventQueue();

      IntentionCatalogLoaded catalog() =>
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      int activeCount(IntentionId id) => (container.read(
        intentionDetailsViewModelProvider(id),
      ) as IntentionDetailsLoaded).details.relationCounts.active;
      String title(IntentionId id) => (container.read(
        intentionDetailsViewModelProvider(id),
      ) as IntentionDetailsLoaded).details.intention.title;

      expect(
        {for (final item in catalog().items) item.id: item.activeRelationCount},
        {
          participantIds[3]: 1,
          participantIds[2]: 1,
          participantIds[1]: 0,
          participantIds[0]: 0,
        },
      );
      expect(
        catalog().items.map((item) => item.id),
        summaries.map((item) => item.id),
      );
      expect(catalog().totalCount, 4);
      expect(catalog().revision, const TestGraphRevision(9));

      for (var index = 0; index < participantIds.length; index++) {
        repository.emitIntention(
          participantIds[index],
          testNeighborhoodIntention(
            id: participantIds[index],
            title: 'Устаревший участник',
          ),
          counts: index < 2
              ? testRelationCounts()
              : testRelationCounts(activeNeedOutgoing: 1),
          revision: const TestGraphRevision(7),
        );
      }
      await pumpEventQueue();
      expect([for (final id in participantIds) activeCount(id)], [1, 1, 0, 0]);
      expect(
        [for (final id in participantIds) title(id)],
        ['Участник А', 'Участник Б', 'Участник В', 'Участник Г'],
      );

      for (var index = 0; index < participantIds.length; index++) {
        repository.emitIntention(
          participantIds[index],
          testNeighborhoodIntention(
            id: participantIds[index],
            title: 'Участник ${String.fromCharCode(1040 + index)}',
          ),
          counts: switch (index) {
            0 || 1 => testRelationCounts(),
            2 => testRelationCounts(activeNeedOutgoing: 1),
            3 => testRelationCounts(activeNeedIncoming: 1),
            _ => throw StateError('Неизвестный участник.'),
          },
          revision: const TestGraphRevision(9),
        );
      }
      await pumpEventQueue();

      expect([for (final id in participantIds) activeCount(id)], [0, 0, 1, 1]);
      expect(
        [for (final id in participantIds) title(id)],
        ['Участник А', 'Участник Б', 'Участник В', 'Участник Г'],
      );
      expect(repository.catalogQueries, hasLength(1));
      expect([
        for (final id in participantIds) repository.observationsOf(id),
      ], everyElement(greaterThanOrEqualTo(2)));
    },
  );

  test('каскад заменяет намерение и сводку только цельным снимком', () async {
    final repository = _CheckpointGraphRepository();
    final harness = _CheckpointHarness(repository);
    addTearDown(harness.dispose);
    await harness.loadInitialSurfaces();
    final detailsBefore = harness.details.details;
    final intentionBefore = detailsBefore.intention;
    final intentionAfter = testNeighborhoodIntention(
      id: harness.ownerId,
      title: intentionBefore.title,
      archiveState: IntentionArchiveState.archived,
    );
    final countsAfter = testRelationCounts(archivedNeedOutgoing: 1);
    const revision = TestGraphRevision(9);
    final presentation = harness.coordinator.registerAppPresentation();
    addTearDown(presentation.release);

    harness.archiveOwner();
    expect(repository.intentionCommands, [isA<ArchiveIntention>()]);
    repository.completeIntentionCommand(
      0,
      testNeighborhoodSavedResult(
        before: intentionBefore,
        after: intentionAfter,
        revision: revision,
        additionalChanges: [
          IntentionRelationCountsChanged(
            revision: revision,
            intentionId: harness.ownerId,
            counts: countsAfter,
          ),
        ],
      ),
    );
    await pumpEventQueue();

    expect(harness.details.details, same(detailsBefore));
    expect(
      harness.details.intention.archiveState,
      IntentionArchiveState.active,
    );
    expect(harness.detailsCounts.activeNeedOutgoing, 1);
    expect(harness.detailsCounts.archivedNeedOutgoing, 0);
    expect(repository.observationsOf(harness.ownerId), 3);

    final claim = await presentation.nextClaim();
    expect(claim, isNotNull);
    harness.coordinator.confirmPresentation(claim!);

    repository.emitIntention(
      harness.ownerId,
      intentionAfter,
      counts: countsAfter,
      revision: revision,
    );
    repository.completeGroupPage(
      1,
      RelationGroupFirstPage(
        items: const [],
        counts: countsAfter,
        nextCursor: null,
        revision: revision,
      ),
    );
    await pumpEventQueue();

    expect(harness.details.intention, same(intentionAfter));
    expect(harness.detailsCounts.activeNeedOutgoing, 0);
    expect(harness.detailsCounts.archivedNeedOutgoing, 1);
    expect(repository.intentionCommands, hasLength(1));
    expect(repository.groupQueries, hasLength(2));

    var receivedRepeatedPresentation = false;
    unawaited(
      presentation.nextClaim().then((_) {
        receivedRepeatedPresentation = true;
      }),
    );
    await pumpEventQueue();
    expect(receivedRepeatedPresentation, isFalse);
  });

  test('согласование данных не зависит от предъявления сообщения', () async {
    final repository = _CheckpointGraphRepository();
    final harness = _CheckpointHarness(repository);
    addTearDown(harness.dispose);
    await harness.loadInitialSurfaces();

    final registration = harness.coordinator.registerAppPresentation();
    addTearDown(registration.release);
    GraphAppPresentationClaim? issued;
    unawaited(registration.nextClaim().then((claim) => issued = claim));

    await harness.completeRelationCreation(
      relatedIntentionId: testIntentionId(1002),
      relationIndex: 2,
      revision: const TestGraphRevision(9),
      activeCounts: {testIntentionId(1): 2, testIntentionId(1002): 1},
    );
    repository.completeGroupPage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 2),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();

    // Данные согласованы до подтверждения предъявления.
    expect(issued, isNotNull);
    expect(harness.catalogCounts[testIntentionId(1)], 2);
    expect(harness.neighborhood.items, hasLength(2));
    expect(harness.neighborhood.revision, const TestGraphRevision(9));

    final catalogAfterData = harness.catalog;
    final neighborhoodAfterData = harness.neighborhood;
    final confirmedStatesAfterData = harness.confirmedCatalogStates.length;

    harness.coordinator.confirmPresentation(issued!);
    var hasSecondClaim = false;
    unawaited(registration.nextClaim().then((_) => hasSecondClaim = true));
    await pumpEventQueue();

    // Предъявление не применяет данные повторно и не выдаёт второй claim.
    expect(hasSecondClaim, isFalse);
    expect(harness.catalog, same(catalogAfterData));
    expect(harness.neighborhood, same(neighborhoodAfterData));
    expect(harness.confirmedCatalogStates, hasLength(confirmedStatesAfterData));
    expect(repository.catalogQueries, hasLength(1));
    expect(repository.groupQueries, hasLength(2));
  });
}

Future<void> _settleUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await pumpEventQueue();
  }
  expect(condition(), isTrue);
}

/// Единая среда каталога, подробного просмотра и соседства одного намерения.
final class _CheckpointHarness {
  _CheckpointHarness(
    this.repository, {
    int catalogPageSize = 100,
    int neighborhoodPageSize = 50,
  }) : ownerId = testIntentionId(1) {
    _container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: catalogPageSize,
            prefetchRemaining: 0,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
        relationNeighborhoodPagingPolicyProvider.overrideWithValue(
          RelationNeighborhoodPagingPolicy(
            pageSize: neighborhoodPageSize,
            prefetchRemaining: neighborhoodPageSize - 1,
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    _catalogSubscription = _container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, next) {
        if (next.value case final IntentionCatalogConfirmedState confirmed) {
          confirmedCatalogStates.add(confirmed);
        }
      },
      fireImmediately: true,
    );
    _detailsSubscription = _container.listen(
      intentionDetailsViewModelProvider(ownerId),
      (_, _) {},
      fireImmediately: true,
    );
    _neighborhoodSubscription = _container.listen(
      relationNeighborhoodViewModelProvider(ownerId),
      (_, _) {},
      fireImmediately: true,
    );
  }

  final _CheckpointGraphRepository repository;
  final IntentionId ownerId;
  final confirmedCatalogStates = <IntentionCatalogConfirmedState>[];
  late final ProviderContainer _container;
  late final ProviderSubscription<AsyncValue<IntentionCatalogState>>
  _catalogSubscription;
  late final ProviderSubscription<IntentionDetailsState> _detailsSubscription;
  late final ProviderSubscription<RelationNeighborhoodState>
  _neighborhoodSubscription;

  GraphCommandCoordinator get coordinator =>
      _container.read(graphCommandCoordinatorProvider.notifier);

  IntentionCatalogLoaded get catalog =>
      _container
              .read(
                intentionCatalogViewModelProvider(
                  const BrowseIntentionCatalog(),
                ),
              )
              .requireValue
          as IntentionCatalogLoaded;

  Map<IntentionId, int> get catalogCounts => {
    for (final item in catalog.items) item.id: item.activeRelationCount,
  };

  Map<IntentionId, String> get catalogTitles => {
    for (final item in catalog.items) item.id: item.title,
  };

  IntentionDetailsLoaded get details =>
      _container.read(intentionDetailsViewModelProvider(ownerId))
          as IntentionDetailsLoaded;

  void archiveOwner() => _container
      .read(intentionDetailsViewModelProvider(ownerId).notifier)
      .archive();

  RelationCounts get detailsCounts => details.details.relationCounts;

  RelationGroupLoaded get neighborhood =>
      _container.read(relationNeighborhoodViewModelProvider(ownerId))
          as RelationGroupLoaded;

  void scrollNeighborhoodTo(int visibleIndex) => unawaited(
    _container
        .read(relationNeighborhoodViewModelProvider(ownerId).notifier)
        .loadMoreIfNeeded(visibleIndex: visibleIndex),
  );

  /// Приводит все три поверхности к подтверждённому снимку одной ревизии.
  Future<void> loadInitialSurfaces({RelationGroupFirstPage? groupPage}) async {
    repository.completeCatalogPage(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            catalog_support.testSummary(
              index: 1002,
              title: 'Связанное 2',
              activeRelationCount: 0,
            ),
            catalog_support.testSummary(
              index: 1001,
              title: 'Связанное 1',
              activeRelationCount: 1,
            ),
            catalog_support.testSummary(
              index: 1,
              title: 'Владелец',
              activeRelationCount: 1,
            ),
          ],
          totalCount: 3,
          nextCursor: null,
          revision: const TestGraphRevision(4),
        ),
      ),
    );
    await _container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    repository.emitIntention(
      ownerId,
      testNeighborhoodIntention(id: ownerId, title: 'Владелец'),
      counts: testRelationCounts(activeNeedOutgoing: 1),
      revision: const TestGraphRevision(4),
    );
    repository.completeGroupPage(
      0,
      groupPage ??
          RelationGroupFirstPage(
            items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
            counts: testRelationCounts(activeNeedOutgoing: 1),
            nextCursor: null,
            revision: const TestGraphRevision(4),
          ),
    );
    await pumpEventQueue();
    confirmedCatalogStates.clear();
  }

  /// Проводит создание связи владельца через coordinator до завершения.
  Future<void> completeRelationCreation({
    required IntentionId relatedIntentionId,
    required int relationIndex,
    required GraphRevision revision,
    required Map<IntentionId, int> activeCounts,
  }) async {
    final relation = catalog_support.testRelation(
      sourceIntentionId: ownerId,
      relatedIntentionId: relatedIntentionId,
      index: relationIndex,
    );
    final commandIndex = repository.relationCommands.length;
    final start = coordinator.acceptRelationCreation(
      LongTermRelationCreationFormKey(),
      CreateLongTermRelation(
        sourceIntentionId: ownerId,
        relatedIntentionId: relatedIntentionId,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    expect(start, isA<LongTermRelationCommandAccepted>());
    repository.completeRelationCommand(
      commandIndex,
      GraphCommandSucceeded<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationCreated(
            relation: relation,
            description: null,
            changes: [
              for (final entry in activeCounts.entries)
                IntentionRelationCountsChanged(
                  revision: revision,
                  intentionId: entry.key,
                  counts: testRelationCounts(activeNeedOutgoing: entry.value),
                ),
              LongTermRelationCreatedChange(
                revision: revision,
                relation: relation,
              ),
            ],
          ),
        ),
      ),
    );
    await (start as LongTermRelationCommandAccepted).future;
    await pumpEventQueue();
  }

  /// Переименовывает участника загруженной выдачи через coordinator.
  Future<void> completeParticipantRename({
    required int participantIndex,
    required String title,
    required int activeRelationCount,
    required GraphRevision revision,
  }) async {
    final participantId = testIntentionId(participantIndex);
    final before = catalog_support.testSummary(
      index: participantIndex,
      title: 'Связанное 1',
      activeRelationCount: activeRelationCount,
    );
    final after = catalog_support.testSummary(
      index: participantIndex,
      title: title,
      activeRelationCount: activeRelationCount,
    );
    final commandIndex = repository.intentionCommands.length;
    final start = coordinator.acceptExisting(
      UpdateIntention(id: participantId, title: after.title, description: null),
      presentationTitle: before.title,
    );
    expect(start, isA<IntentionCommandAccepted>());
    repository.completeIntentionCommand(
      commandIndex,
      ResultSuccess(
        IntentionSaved(
          testNeighborhoodIntention(id: participantId, title: title),
          catalogMutation: IntentionCatalogUpdated(
            revision: revision,
            before: catalog_support.TestCatalogEntrySnapshot(before),
            after: catalog_support.TestCatalogEntrySnapshot(after),
          ),
        ),
      ),
    );
    await (start as IntentionCommandAccepted).future;
    await pumpEventQueue();
  }

  void dispose() {
    _catalogSubscription.close();
    _detailsSubscription.close();
    _neighborhoodSubscription.close();
    _container.dispose();
    unawaited(repository.dispose());
  }
}

/// Управляемый граф, обслуживающий все чтения и команды контрольной точки.
final class _CheckpointGraphRepository implements PersonalGraphRepository {
  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  final catalogQueries = <IntentionCatalogQuery>[];
  final _catalogRequests = <Completer<Result<IntentionCatalogPage>>>[];
  final groupQueries = <RelationGroupQuery>[];
  final _groupRequests = <Completer<RelationGroupPageResult>>[];
  final intentionCommands = <IntentionCommand>[];
  final _intentionCommandRequests =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final relationCommands = <LongTermRelationCommand>[];
  final _relationCommandRequests = <Completer<LongTermRelationCommandResult>>[];
  final _observations = <IntentionId, int>{};
  final _intentionControllers =
      <
        IntentionId,
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>
      >{};

  int observationsOf(IntentionId id) => _observations[id] ?? 0;

  void completeCatalogPage(int index, Result<IntentionCatalogPage> result) {
    _catalogRequests[index].complete(result);
  }

  void completeGroupPage(int index, RelationGroupPage page) {
    _groupRequests[index].complete(GraphResultSuccess(page));
  }

  void failGroupRead(int index, RelationGroupReadFailure failure) {
    _groupRequests[index].complete(GraphResultFailure(failure));
  }

  void completeIntentionCommand(
    int index,
    Result<IntentionCommandSuccess> result,
  ) {
    _intentionCommandRequests[index].complete(switch (result) {
      ResultSuccess(:final value) => ResultSuccess(
        ConfirmedGraphResult(
          revision: value.catalogMutation.revision,
          value: value,
        ),
      ),
      ResultFailure(:final failure) => ResultFailure(failure),
    });
  }

  void completeRelationCommand(
    int index,
    LongTermRelationCommandResult result,
  ) {
    _relationCommandRequests[index].complete(result);
  }

  void emitIntention(
    IntentionId id,
    Intention intention, {
    required RelationCounts counts,
    required GraphRevision revision,
  }) {
    _controllerFor(id).add(
      ResultSuccess(
        GraphSnapshot(
          value: IntentionDetails(intention: intention, relationCounts: counts),
          revision: revision,
        ),
      ),
    );
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogQueries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _catalogRequests.add(request);
    return request.future;
  }

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) {
    groupQueries.add(query);
    final request = Completer<RelationGroupPageResult>();
    _groupRequests.add(request);
    return request.future;
  }

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError(
    'Отдельная сводка не читается контрольной точкой.',
  );

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Подробные данные связи не наблюдаются здесь.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    _observations.update(id, (count) => count + 1, ifAbsent: () => 1);
    return _controllerFor(id).stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final IntentionCommand intentionCommand => await _executeIntention(
        intentionCommand,
      ),
      final LongTermRelationCommand relationCommand =>
        await _executeLongTermRelation(relationCommand),
      _ => throw UnsupportedError('Неизвестная команда графа в тесте.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    intentionCommands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _intentionCommandRequests.add(request);
    return request.future;
  }

  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationCommandRequests.add(request);
    return request.future;
  }

  StreamController<Result<GraphSnapshot<IntentionDetails?>>> _controllerFor(
    IntentionId id,
  ) => _intentionControllers.putIfAbsent(
    id,
    () => StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
      sync: true,
    ),
  );

  Future<void> dispose() async {
    for (final controller in _intentionControllers.values) {
      await controller.close();
    }
  }
}
