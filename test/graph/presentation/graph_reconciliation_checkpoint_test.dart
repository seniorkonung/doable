import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_instance.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';

import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation, TagAssignment;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
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
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart' as tag_domain;
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../intention/presentation/catalog/catalog_test_support.dart'
    as catalog_support;
import '../../support/daily_choice_durability_fixture.dart';
import '../../support/daily_choice_local_date.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart';
import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/statistics_read_contract_test_fallback.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/tag_positions.dart';

/// Контрольная точка согласования: каталог, подробные данные и соседство
/// обслуживаются одним графом, одним coordinator и одним потоком завершений.
void main() {
  group('согласование выдачи с условием по тегу с настоящим хранилищем', () {
    late AppDatabase database;
    late sqlite.Database raw;
    late DriftPersonalGraphRepository repository;
    late ProviderContainer container;
    late GraphCommandCoordinator coordinator;
    late TagId tagId;
    late IntentionId ownerId;

    const browse = BrowseIntentionCatalog();
    IntentionCatalogLoaded? loadedCatalog() =>
        switch (container.read(intentionCatalogViewModelProvider(browse))) {
          AsyncData(value: final IntentionCatalogLoaded catalog) => catalog,
          _ => null,
        };
    IntentionCatalogLoaded catalog() => loadedCatalog()!;
    RelationGroupLoaded neighborhood() =>
        container.read(relationNeighborhoodViewModelProvider(ownerId))
            as RelationGroupLoaded;
    IntentionDetailsLoaded details() =>
        container.read(intentionDetailsViewModelProvider(ownerId))
            as IntentionDetailsLoaded;

    // Активные получатели общего тега в порядке выдачи — от созданного
    // последним; архивные получатели в активный охват не входят.
    final expected = [
      for (var index = _taggedRecipients - 1; index >= 0; index--)
        if (index.isEven)
          (IntentionId.decode(
            tagFixtureId(10000 + index),
          ) as IntentionIdDecodingSuccess).id,
    ];

    /// Дожидается выдачи на ревизии [revision] и дочитывает её до конца.
    Future<void> settle(GraphRevision revision) async {
      await _settleUntil(
        () =>
            loadedCatalog()?.revision.compareTo(revision) ==
            GraphRevisionOrder.same,
        diagnostics: () =>
            'Каталог: ${container.read(intentionCatalogViewModelProvider(browse))}.',
      );
      while (catalog().nextCursor != null) {
        final countBefore = catalog().items.length;
        await container
            .read(intentionCatalogViewModelProvider(browse).notifier)
            .loadNextPageIfNeeded(visibleIndex: countBefore - 1);
        await _settleUntil(
          () =>
              catalog().items.length > countBefore &&
              catalog().continuation is IntentionCatalogContinuationIdle,
        );
      }
    }

    setUp(() async {
      database = AppDatabase(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
      );
      await database.open();
      seedWidelyAssignedTagFixture(raw, recipients: _taggedRecipients);
      repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 28),
        InMemoryDiagnosticsSink(),
      );
      tagId = (TagId.decode(tagFixtureId(9000)) as TagIdDecodingSuccess).id;
      ownerId = (IntentionId.decode(
        tagFixtureId(1),
      ) as IntentionIdDecodingSuccess).id;
      container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          catalogPagingPolicyProvider.overrideWithValue(
            CatalogPagingPolicy(
              pageSize: 10,
              prefetchRemaining: 0,
              filterDebounce: const Duration(milliseconds: 250),
            ),
          ),
          relationNeighborhoodPagingPolicyProvider.overrideWithValue(
            RelationNeighborhoodPagingPolicy(
              pageSize: 10,
              prefetchRemaining: 0,
            ),
          ),
        ],
        retry: (retryCount, error) => null,
      );
      coordinator = container.read(graphCommandCoordinatorProvider.notifier);
      container.listen(intentionCatalogViewModelProvider(browse), (_, _) {});
      container.listen(intentionDetailsViewModelProvider(ownerId), (_, _) {});
      container.listen(
        relationNeighborhoodViewModelProvider(ownerId),
        (_, _) {},
      );
      await _settleUntil(() => loadedCatalog() != null);
      container
          .read(intentionCatalogViewModelProvider(browse).notifier)
          .changeTagFilter(IntentionTagFilter(requiredTagIds: [tagId]));
      await _settleUntil(
        () =>
            loadedCatalog()?.selection.tagFilter.requiredTagIds.contains(
                  tagId,
                ) ==
                true &&
            container.read(relationNeighborhoodViewModelProvider(ownerId))
                is RelationGroupLoaded &&
            container.read(intentionDetailsViewModelProvider(ownerId))
                is IntentionDetailsLoaded,
      );
    });

    tearDown(() async {
      await coordinator.shutdown();
      container.dispose();
      await database.close();
    });

    test('команды тегов обновляют выдачу с условием по тегу и сохраняют '
        'счётчики связей', () async {
      final initialRevision = catalog().revision;
      expect(catalog().items.map((item) => item.id), expected.take(10));
      await settle(initialRevision);
      final countsBefore = neighborhood().counts;
      final detailsCountsBefore = details().details.relationCounts;
      expect(catalog().items.map((item) => item.id), expected);
      expect(catalog().totalCount, expected.length);

      for (final target in expected.take(2).toList()) {
        final removed = await (coordinator.acceptTagRemoveAssignment(
          RemoveTagAssignment(tagId: tagId, intentionId: target),
        ) as TagCommandAccepted).future;
        expect(removed.confirmedResult, isA<TagCommandSucceeded>());
        final remaining = [...expected]..remove(target);
        await settle(removed.revision!);
        expect(catalog().items.map((item) => item.id), remaining);
        expect(catalog().totalCount, remaining.length);

        if (neighborhood().nextCursor != null) {
          final countBefore = neighborhood().items.length;
          await container
              .read(relationNeighborhoodViewModelProvider(ownerId).notifier)
              .loadMoreIfNeeded(visibleIndex: countBefore - 1);
          await _settleUntil(() => neighborhood().items.length > countBefore);
          expect(neighborhood().counts, countsBefore);
        }

        final assigned = await (coordinator.acceptTagAssign(
          AssignTag(tagId: tagId, intentionId: target),
        ) as TagCommandAccepted).future;
        expect(assigned.confirmedResult, isA<TagCommandSucceeded>());
        await settle(assigned.revision!);
        expect(catalog().items.map((item) => item.id), expected);
        expect(catalog().totalCount, expected.length);
      }

      final renamed = await (coordinator.acceptTagUpdate(
        UpdateTag(tagId: tagId, name: TagName.fromInput('Быт'), color: null),
      ) as TagCommandAccepted).future;
      await settle(renamed.revision!);
      expect(catalog().selection.tagFilter.requiredTagIds, {tagId});
      expect(catalog().items.map((item) => item.id), expected);
      for (final item in catalog().items) {
        expect(
          item.tags.singleWhere((tag) => tag.id == tagId).name.value,
          'Быт',
        );
      }

      final edited = await (coordinator.acceptExisting(
        UpdateIntention(
          id: ownerId,
          title: 'Новое исходное намерение',
          description: null,
        ),
        presentationTitle: 'Исходное намерение',
      ) as IntentionCommandAccepted).future;
      await settle(edited.revision!);
      expect(catalog().items.map((item) => item.id), expected);
      expect(
        catalog().items.map((item) => item.title),
        expected.map(
          (id) => raw.select('SELECT title FROM intentions WHERE id = ?', [
            id.toCanonicalString(),
          ]).single['title'],
        ),
      );
      expect(catalog().items.any((item) => item.id == ownerId), isFalse);
      expect(neighborhood().counts, countsBefore);
      expect(details().details.relationCounts, detailsCountsBefore);
      expect(catalog().totalCount, expected.length);
    });
  });

  test(
    'повтор и замена согласуют открытые представления одной ревизией',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      await seedDurabilityGraph(database);
      await seedGraph(
        database,
        () => database.customStatement(
          '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id,
          type, priority, is_archived)
         VALUES (?, ?, ?, 'need', 2, 0)''',
          [durabilityUuid(105), durabilityUuid(5), durabilityUuid(4)],
        ),
      );
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 23),
        InMemoryDiagnosticsSink(),
        dailyChoiceIdGenerator: _CheckpointChoiceIds(),
      );
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      final firstId = durabilityChoice(201);
      final repeatId = durabilityChoice(202);
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          ControlledDailyChoiceLocalDate(durabilityChoiceDate).override,
        ],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final catalogProvider = dailyChoiceCatalogViewModelProvider(
        DailyChoiceCatalogInstance(initialDate: durabilityChoiceDate),
      );
      final subscriptions = [
        container.listen(catalogProvider, (_, _) {}, fireImmediately: true),
        for (final number in [1, 2, 3, 4, 5])
          container.listen(
            intentionDetailsViewModelProvider(durabilityIntention(number)),
            (_, _) {},
            fireImmediately: true,
          ),
        for (final number in [1, 3, 4, 5])
          container.listen(
            relationNeighborhoodViewModelProvider(durabilityIntention(number)),
            (_, _) {},
            fireImmediately: true,
          ),
        for (final number in [101, 102, 105])
          container.listen(
            relationDetailsViewModelProvider(durabilityRelation(number)),
            (_, _) {},
            fireImmediately: true,
          ),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      // Каталог показывает день повторяемого выбора независимо от
      // первоначального охвата.
      container.read(catalogProvider.notifier).selectDate(durabilityChoiceDate);
      final details = DailyChoiceDetailsViewModel(repository, firstId);
      addTearDown(details.dispose);

      for (final number in [1, 3, 4, 5]) {
        container
            .read(
              relationNeighborhoodViewModelProvider(durabilityIntention(number))
                  .notifier,
            )
            .selectDailyGroup(
              number == 3 || number == 4
                  ? DailyChoiceRelationRole.selected
                  : DailyChoiceRelationRole.source,
            );
      }
      DailyChoiceCatalogLoaded catalog() =>
          container.read(catalogProvider) as DailyChoiceCatalogLoaded;
      DailyChoiceGroupLoaded group(int number) => container.read(
        relationNeighborhoodViewModelProvider(durabilityIntention(number)),
      ) as DailyChoiceGroupLoaded;
      IntentionDetailsLoaded intention(int number) => container.read(
        intentionDetailsViewModelProvider(durabilityIntention(number)),
      ) as IntentionDetailsLoaded;
      RelationDetailsLoaded relation(int number) => container.read(
        relationDetailsViewModelProvider(durabilityRelation(number)),
      ) as RelationDetailsLoaded;
      await _settleUntil(
        () =>
            container.read(catalogProvider) is DailyChoiceCatalogLoaded &&
            details.state is DailyChoiceDetailsLoaded &&
            [1, 3].every(
              (number) => container.read(
                relationNeighborhoodViewModelProvider(
                  durabilityIntention(number),
                ),
              ) is DailyChoiceGroupLoaded,
            ) &&
            [4, 5].every(
              (number) => container.read(
                relationNeighborhoodViewModelProvider(
                  durabilityIntention(number),
                ),
              ) is RelationGroupEmpty,
            ) &&
            [1, 2, 3, 4, 5].every(
              (number) => container.read(
                intentionDetailsViewModelProvider(durabilityIntention(number)),
              ) is IntentionDetailsLoaded,
            ) &&
            [101, 102, 105].every(
              (number) => container.read(
                relationDetailsViewModelProvider(durabilityRelation(number)),
              ) is RelationDetailsLoaded,
            ),
        diagnostics: () => [
          container.read(catalogProvider).runtimeType,
          details.state.runtimeType,
          for (final number in [1, 3, 4, 5])
            container
                .read(
                  relationNeighborhoodViewModelProvider(
                    durabilityIntention(number),
                  ),
                )
                .runtimeType,
          for (final number in [1, 2, 3, 4, 5])
            container
                .read(
                  intentionDetailsViewModelProvider(
                    durabilityIntention(number),
                  ),
                )
                .runtimeType,
        ].join(', '),
      );
      final initialIntentions = {
        for (final number in [1, 2, 3, 4, 5])
          number: intention(number).intention,
      };
      expect(catalog().selection.date, durabilityChoiceDate);
      expect(catalog().items.map((item) => item.id), [firstId]);
      expect(group(1).items.map((item) => item.id), [firstId]);
      expect(group(3).items.map((item) => item.id), [firstId]);
      expect(relation(101).permissions.canDelete, isFalse);
      expect(relation(102).permissions.canDelete, isFalse);
      expect(relation(105).permissions.canDelete, isTrue);
      expect(
        (container.read(
          relationNeighborhoodViewModelProvider(durabilityIntention(4)),
        ) as RelationGroupEmpty).counts.dailySelected,
        0,
      );
      expect(
        (container.read(
          relationNeighborhoodViewModelProvider(durabilityIntention(5)),
        ) as RelationGroupEmpty).counts.dailySource,
        0,
      );

      final repeat = coordinator.acceptDailyChoiceCreation(
        DailyChoiceCreationFormKey(),
        durabilityCreate(),
      );
      expect(repeat, isA<DailyChoiceCommandAccepted>());
      final repeated = await (repeat as DailyChoiceCommandAccepted).future;
      expect(repeated.isFailure, isFalse);
      final repeatRevision = repeated.revision!;
      await _settleUntil(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().revision.compareTo(repeatRevision) ==
                GraphRevisionOrder.same &&
            catalog().totalCount == 2 &&
            group(1).items.length == 2 &&
            group(3).items.length == 2,
      );
      expect(catalog().items.map((item) => item.id).toSet(), {
        firstId,
        repeatId,
      });
      expect(group(1).counts.dailySource, 2);
      expect(group(3).counts.dailySelected, 2);
      expect(relation(101).permissions.canDelete, isFalse);
      expect(relation(105).permissions.canDelete, isTrue);
      expect(intention(2).details.relationCounts.dailySource, 0);
      expect(intention(2).details.relationCounts.dailySelected, 0);

      final replacement = coordinator.acceptDailyChoiceReplace(
        ReplaceDailyChoicePath(
          choiceId: firstId,
          sourceIntentionId: durabilityIntention(5),
          selectedIntentionId: durabilityIntention(4),
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: durabilityRelation(105),
              sourceIntentionId: durabilityIntention(5),
              type: LongTermRelationType.need,
              relatedIntentionId: durabilityIntention(4),
            ),
          ]),
        ),
      );
      expect(replacement, isA<DailyChoiceCommandAccepted>());
      final replaced = await (replacement as DailyChoiceCommandAccepted).future;
      expect(replaced.isFailure, isFalse);
      final replacementRevision = replaced.revision!;
      await _settleUntil(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().revision.compareTo(replacementRevision) ==
                GraphRevisionOrder.same &&
            (details.state is DailyChoiceDetailsLoaded) &&
            (details.state as DailyChoiceDetailsLoaded).revision.compareTo(
                  replacementRevision,
                ) ==
                GraphRevisionOrder.same &&
            [1, 3, 4, 5].every(
              (number) =>
                  group(number).revision.compareTo(replacementRevision) ==
                  GraphRevisionOrder.same,
            ),
      );
      final opened = (details.state as DailyChoiceDetailsLoaded).details;
      expect(opened.source.id, durabilityIntention(5));
      expect(opened.selected.id, durabilityIntention(4));
      expect(opened.path.map((step) => step.relation.id), [
        durabilityRelation(105),
      ]);
      expect(
        catalog().items.singleWhere((item) => item.id == firstId).source.id,
        durabilityIntention(5),
      );
      expect(group(1).items.map((item) => item.id), [repeatId]);
      expect(group(3).items.map((item) => item.id), [repeatId]);
      expect(group(4).items.map((item) => item.id), [firstId]);
      expect(group(5).items.map((item) => item.id), [firstId]);
      expect(
        [
          group(1).counts.dailySource,
          group(3).counts.dailySelected,
          group(4).counts.dailySelected,
          group(5).counts.dailySource,
        ],
        [1, 1, 1, 1],
      );
      expect(relation(101).permissions.canDelete, isFalse);
      expect(relation(102).permissions.canDelete, isFalse);
      expect(relation(105).permissions.canDelete, isFalse);
      expect(intention(2).details.relationCounts.dailySource, 0);
      expect(intention(2).details.relationCounts.dailySelected, 0);
      for (final number in [1, 2, 3, 4, 5]) {
        final before = initialIntentions[number]!;
        final after = intention(number).intention;
        expect(after.title, before.title);
        expect(after.readiness, before.readiness);
        expect(after.archiveState, before.archiveState);
        expect(after.updatedAt, before.updatedAt);
      }

      final deletion = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(repeatId),
      );
      expect(deletion, isA<DailyChoiceCommandAccepted>());
      final deleted = await (deletion as DailyChoiceCommandAccepted).future;
      expect(deleted.isFailure, isFalse);
      final deletionRevision = deleted.revision!;
      await _settleUntil(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().revision.compareTo(deletionRevision) ==
                GraphRevisionOrder.same &&
            catalog().totalCount == 1 &&
            container.read(
              relationNeighborhoodViewModelProvider(durabilityIntention(1)),
            ) is RelationGroupEmpty &&
            container.read(
              relationNeighborhoodViewModelProvider(durabilityIntention(3)),
            ) is RelationGroupEmpty &&
            relation(101).permissionRevision.compareTo(deletionRevision) ==
                GraphRevisionOrder.same &&
            relation(105).permissions.canDelete == false,
      );
      expect(catalog().items.single.id, firstId);
      expect(relation(101).permissions.canDelete, isTrue);
      expect(relation(102).permissions.canDelete, isTrue);
      expect(relation(105).permissions.canDelete, isFalse);
      expect(
        (details.state as DailyChoiceDetailsLoaded)
            .details
            .path
            .single
            .relation
            .id,
        durabilityRelation(105),
      );
    },
  );

  test(
    'одиночные удаления связей Drift согласуют все открытые представления',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      final ids = [
        for (var index = 1; index <= 4; index++) testIntentionId(index),
      ];
      await seedGraph(database, () async {
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
      });
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
          session: IntentionSearchSession(),
          excludedIntentionId: ids[3],
          selectionContext: RelationParticipantSelectionContext.activeRelation,
        ),
      );
      final subscriptions = [
        container.listen(catalogProvider, (_, _) {}, fireImmediately: true),
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
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      late ConfirmedGraphResult<LongTermRelationCommandSuccess> confirmed;
      for (final relationId in [selectedActive, selectedArchived]) {
        final start = coordinator.acceptRelationDelete(
          DeleteLongTermRelation(relationId),
        ) as LongTermRelationCommandAccepted;
        final completion = await start.future;
        confirmed =
            (completion.confirmedResult
                    as GraphCommandSucceeded<
                      LongTermRelationCommandSuccess,
                      LongTermRelationCommandFailure
                    >)
                .value;
        expect(confirmed.value, isA<LongTermRelationDeleted>());
        expect(
          (confirmed.value as LongTermRelationDeleted).relation.id,
          relationId,
        );
      }
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
      expect(
        catalogAfter.items.map(
          (item) =>
              (item.id, item.title, item.createdAt.value, item.updatedAt.value),
        ),
        stableCatalog,
      );
      expect(catalogAfter.totalCount, catalogBefore.totalCount);
      expect(catalogAfter.nextCursor, catalogBefore.nextCursor);
      final filteredAfter =
          container.read(filteredProvider).requireValue
              as IntentionCatalogLoaded;
      expect(filteredAfter.selection.titleFilterText, 'Намерение 1');
      expect(filteredAfter.items.single.id, ids[0]);
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
      expect(neighborGroup.counts.total, 1);
      final remainingDetails = container.read(
        relationDetailsViewModelProvider(untouchedNeighbor),
      ) as RelationDetailsLoaded;
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

      expect(
        harness.catalog.revision.compareTo(const TestGraphRevision(9)),
        GraphRevisionOrder.same,
      );
      expect(harness.catalog.items.map((item) => item.id), [
        testIntentionId(1002),
        testIntentionId(1001),
        testIntentionId(1),
      ]);
      expect(harness.detailsCounts.activeNeedOutgoing, 2);
      expect(harness.neighborhood.items, hasLength(2));
      expect(harness.neighborhood.totalCount, 2);
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());

      // Переименование уже загруженного участника той же выдачи.
      await harness.completeParticipantRename(
        participantIndex: 1001,
        title: 'Переименованное',
        revision: const TestGraphRevision(11),
      );
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
      expect(harness.catalog.items, hasLength(3));
      expect(harness.catalog.totalCount, 3);
      expect(harness.neighborhood.items.first.related.title, 'Переименованное');
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());
      expect(harness.detailsCounts.activeNeedOutgoing, 2);
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

      expect(repository.groupQueries.last.cursor, isNull);
      repository.failGroupRead(2, const RelationGroupUnavailableFailure());
      await pumpEventQueue();

      expect(harness.neighborhood.items, hasLength(4));
      expect(harness.neighborhood.counts.activeCanIncoming, 0);
      expect(
        harness.neighborhood.summaryStatus,
        isA<RelationSummaryRefreshFailure>(),
      );

      // Повторное инвалидирование запускает новую замену.
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
      expect(harness.neighborhood.progress, isA<RelationGroupIdle>());

      // Трасса не выходит за выбранную группу и загруженный предел.
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
    },
  );

  test('перемещение связи продвигает ревизию каталога без замены строк и '
      'согласует подробные данные всех участников', () async {
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
      catalog_support.testSummary(index: 4, title: 'Участник Г'),
      catalog_support.testSummary(index: 3, title: 'Участник В'),
      catalog_support.testSummary(index: 2, title: 'Участник Б'),
      catalog_support.testSummary(index: 1, title: 'Участник А'),
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
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
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

    expect(catalog().items, summaries);
    expect(catalog().totalCount, 4);
    expect(
      catalog().revision.compareTo(const TestGraphRevision(9)),
      GraphRevisionOrder.same,
    );

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
  });

  test(
    'пакет только тега сохраняет каталог и обновляет группу перед продолжением',
    () async {
      final repository = _CheckpointGraphRepository();
      final harness = _CheckpointHarness(repository, neighborhoodPageSize: 1);
      addTearDown(harness.dispose);
      await harness.loadInitialSurfaces(
        groupPage: RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(4),
        ),
      );

      final beforeCatalog = harness.catalog;
      final beforeGroup = harness.neighborhood;
      final accepted = harness.coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(
          name: TagName.fromInput('Дом'),
          color: null,
          placement: TagPlacement.first,
        ),
      ) as TagCommandAccepted;
      const revision = TestGraphRevision(5);
      final tag = tag_domain.Tag(
        id: switch (TagId.decode('018f0000-0000-7000-8000-000000000001')) {
          TagIdDecodingSuccess(:final id) => id,
          InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
        },
        name: TagName.fromInput('Дом'),
        color: null,
        position: tagPositionAt(1000),
      );
      repository.completeTagCommand(
        0,
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: revision,
            value: TagCreated(TagCreatedChange(revision: revision, after: tag)),
          ),
        ),
      );
      await accepted.future;
      await pumpEventQueue();

      expect(harness.catalog.items, beforeCatalog.items);
      expect(harness.catalog.totalCount, beforeCatalog.totalCount);
      expect(harness.neighborhood.items, beforeGroup.items);
      expect(harness.neighborhood.counts, beforeGroup.counts);
      expect(repository.catalogQueries, hasLength(1));

      harness.scrollNeighborhoodTo(0);
      await pumpEventQueue();
      expect(repository.groupQueries[1].cursor, isNull);
      repository.completeGroupPage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: revision,
        ),
      );
      await pumpEventQueue();
      repository.completeGroupPage(
        2,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 2, count: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await pumpEventQueue();
      expect(harness.neighborhood.items, hasLength(2));
      expect(harness.neighborhood.counts.activeNeedOutgoing, 2);

      final currentCatalog = harness.catalog;
      final currentGroup = harness.neighborhood;
      final unchanged = harness.coordinator.acceptTagUpdate(
        UpdateTag(tagId: tag.id, name: tag.name, color: tag.color),
      ) as TagCommandAccepted;
      repository.completeTagCommand(
        1,
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: revision,
            value: TagUnchanged(
              TagUnchangedChange(revision: revision, tag: tag),
            ),
          ),
        ),
      );
      await unchanged.future;
      await pumpEventQueue();
      expect(harness.catalog.items, currentCatalog.items);
      expect(harness.catalog.totalCount, currentCatalog.totalCount);
      expect(harness.neighborhood.items, currentGroup.items);
      expect(harness.neighborhood.counts, currentGroup.counts);
    },
  );

  test('позднее продолжение группы не смешивается с пакетом тега', () async {
    final repository = _CheckpointGraphRepository();
    final harness = _CheckpointHarness(repository, neighborhoodPageSize: 1);
    addTearDown(harness.dispose);
    await harness.loadInitialSurfaces(
      groupPage: RelationGroupFirstPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        nextCursor: const TestRelationGroupCursor(1),
        revision: const TestGraphRevision(4),
      ),
    );
    harness.scrollNeighborhoodTo(0);
    expect(repository.groupQueries[1].cursor, isNotNull);

    final tagId = switch (TagId.decode(
      '018f0000-0000-7000-8000-000000000001',
    )) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
    };
    const revision = TestGraphRevision(5);
    final accepted = harness.coordinator.acceptTagDelete(
      DeleteTag(tagId),
    ) as TagCommandAccepted;
    repository.completeTagCommand(
      0,
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagDeleted(TagDeletedChange(revision: revision, tagId: tagId)),
        ),
      ),
    );
    await accepted.future;
    await pumpEventQueue();
    expect(repository.groupQueries[2].cursor, isNull);

    repository.completeGroupPage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 2, count: 1),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    expect(harness.neighborhood.items, hasLength(1));

    repository.completeGroupPage(
      2,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        nextCursor: const TestRelationGroupCursor(1),
        revision: revision,
      ),
    );
    await pumpEventQueue();
    repository.completeGroupPage(
      3,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 2, count: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await pumpEventQueue();
    expect(harness.neighborhood.items, hasLength(2));
  });

  test(
    'пакет назначения сохраняет счётчики и не смешивает продолжения группы',
    () async {
      final repository = _CheckpointGraphRepository();
      final harness = _CheckpointHarness(repository, neighborhoodPageSize: 1);
      addTearDown(harness.dispose);
      await harness.loadInitialSurfaces(
        groupPage: RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(4),
        ),
      );
      final detailsBefore = harness.detailsCounts;
      harness.scrollNeighborhoodTo(0);
      expect(repository.groupQueries[1].cursor, isNotNull);

      final tagId = switch (TagId.decode(
        '018f0000-0000-7000-8000-000000000001',
      )) {
        TagIdDecodingSuccess(:final id) => id,
        InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
      };
      final target = harness.ownerId;
      const revision = TestGraphRevision(5);
      final ownerBefore = catalog_support.testSummary(
        index: 1,
        title: 'Владелец',
      );
      final ownerAfter = catalog_support.testSummary(
        index: 1,
        title: 'Владелец',
        tags: [
          tag_domain.Tag(
            id: tagId,
            name: TagName.fromInput('Здоровье'),
            color: null,
            position: tagPositionAt(1001),
          ),
        ],
      );
      final accepted = harness.coordinator.acceptTagAssign(
        AssignTag(tagId: tagId, intentionId: target),
      ) as TagCommandAccepted;
      repository.completeTagCommand(
        0,
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: revision,
            value: TagAssignmentChanged(
              TagAssignmentChangedChange(
                revision: revision,
                assignment: TagAssignment(tagId: tagId, intentionId: target),
                state: TagAssignmentState.assigned,
              ),
              catalogMutation: IntentionCatalogUpdated(
                revision: revision,
                before: catalog_support.TestCatalogEntrySnapshot(ownerBefore),
                after: catalog_support.TestCatalogEntrySnapshot(ownerAfter),
              ),
            ),
          ),
        ),
      );
      final completion = await accepted.future;
      expect(completion.confirmedChange!.changes, [
        isA<TagAssignmentChangedChange>(),
        isA<IntentionCatalogUpdated>(),
      ]);
      await pumpEventQueue();
      expect(repository.groupQueries[2].cursor, isNull);

      repository.completeGroupPage(
        1,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 2, count: 1),
          nextCursor: null,
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      expect(harness.neighborhood.items, hasLength(1));

      repository.completeGroupPage(
        2,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: revision,
        ),
      );
      await pumpEventQueue();
      repository.completeGroupPage(
        3,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 2, count: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await pumpEventQueue();
      expect(harness.neighborhood.items, hasLength(2));
      expect(
        harness.neighborhood.counts,
        testRelationCounts(activeNeedOutgoing: 2),
      );
      expect(
        harness.catalog.items
            .singleWhere((item) => item.id == harness.ownerId)
            .tags
            .map((tag) => tag.id),
        [tagId],
      );
      expect(harness.detailsCounts, detailsBefore);
    },
  );
}

/// Получатели общего тега: активные из них занимают две порции каталога.
const _taggedRecipients = 24;

Future<void> _settleUntil(
  bool Function() condition, {
  String Function()? diagnostics,
}) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await pumpEventQueue();
  }
  expect(condition(), isTrue, reason: diagnostics?.call());
}

final class _CheckpointChoiceIds implements DailyChoiceIdGenerator {
  var _next = 201;

  @override
  DailyChoiceId generate() => durabilityChoice(_next++);
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
      (_, _) {},
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

  Map<IntentionId, String> get catalogTitles => {
    for (final item in catalog.items) item.id: item.title,
  };

  IntentionDetailsLoaded get details =>
      _container.read(intentionDetailsViewModelProvider(ownerId))
          as IntentionDetailsLoaded;

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
            catalog_support.testSummary(index: 1002, title: 'Связанное 2'),
            catalog_support.testSummary(index: 1001, title: 'Связанное 1'),
            catalog_support.testSummary(index: 1, title: 'Владелец'),
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
    required GraphRevision revision,
  }) async {
    final participantId = testIntentionId(participantIndex);
    final before = catalog_support.testSummary(
      index: participantIndex,
      title: 'Связанное 1',
    );
    final after = catalog_support.testSummary(
      index: participantIndex,
      title: title,
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
final class _CheckpointGraphRepository
    with StatisticsReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => throw UnsupportedError(
    'Чтение состояний дней не используется в этом тесте.',
  );

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

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
  final _tagCommandRequests = <Completer<TagCommandResult>>[];
  final _intentionControllers =
      <
        IntentionId,
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>
      >{};

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

  void completeTagCommand(int index, TagCommandResult result) {
    _tagCommandRequests[index].complete(result);
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
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) {
    groupQueries.add(query as RelationGroupQuery);
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
      final TagCommand tagCommand => await _executeTag(tagCommand),
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

  Future<TagCommandResult> _executeTag(TagCommand command) {
    final request = Completer<TagCommandResult>();
    _tagCommandRequests.add(request);
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
