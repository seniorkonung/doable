import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  test(
    'создание связи обновляет количества участников без изменения состава',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final confirmedStates = _observeConfirmedStates(container);

      final second = testSummary(index: 2, title: 'Второе');
      final first = testSummary(index: 1, title: 'Первое');
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [second, first],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );
      confirmedStates.clear();

      await completeRelationCommand(
        container,
        repository,
        _createRelation(first.id, second.id),
        relationCreationSuccess(
          revision: const TestCatalogRevision(2),
          success: _relationCreated(
            sourceIntentionId: first.id,
            relatedIntentionId: second.id,
            revision: const TestCatalogRevision(2),
            activeCounts: {first.id: 1, second.id: 1},
          ),
        ),
      );

      final current = _loaded(container);
      expect(current.items.map((item) => item.id), [second.id, first.id]);
      expect(current.items.map((item) => item.activeRelationCount), [1, 1]);
      expect(current.items.map((item) => item.title), ['Второе', 'Первое']);
      expect(current.items.map((item) => item.createdAt.value), [
        second.createdAt.value,
        first.createdAt.value,
      ]);
      expect(current.items.map((item) => item.updatedAt.value), [
        second.updatedAt.value,
        first.updatedAt.value,
      ]);
      expect(current.totalCount, 2);
      expect(current.nextCursor, isNull);
      expect(current.revision, const TestCatalogRevision(2));
      expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
      expect(confirmedStates, [same(current)]);
      expect(repository.queries, hasLength(1));
    },
  );

  test('количество вне загруженной выдачи не меняет каталог', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container);

    const cursor = TestCatalogCursor();
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );
    confirmedStates.clear();

    final unloaded = testSummary(index: 1);
    final neighbour = testSummary(index: 9);
    await completeRelationCommand(
      container,
      repository,
      _createRelation(unloaded.id, neighbour.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: unloaded.id,
          relatedIntentionId: neighbour.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {unloaded.id: 1, neighbour.id: 1},
        ),
      ),
    );

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.items.map((item) => item.activeRelationCount), [0, 0]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, same(cursor));
    expect(current.revision, const TestCatalogRevision(2));
    expect(repository.queries, hasLength(1));
  });

  test('фильтр сохраняет число совпадений при обновлении количества', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: Duration.zero,
    );
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    container
        .read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .notifier,
        )
        .changeTitleFilter('Альфа');
    await waitForCatalogQueries(repository, 2);
    final matching = testSummary(index: 1, title: 'Альфа');
    final hidden = testSummary(index: 2, title: 'Бета');
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [matching],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    await completeRelationCommand(
      container,
      repository,
      _createRelation(matching.id, hidden.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: matching.id,
          relatedIntentionId: hidden.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {matching.id: 1, hidden.id: 3},
        ),
      ),
    );

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [matching.id]);
    expect(current.items.single.activeRelationCount, 1);
    expect(current.totalCount, 1);
    expect(current.revision, const TestCatalogRevision(2));
    expect(repository.queries, hasLength(2));
  });

  test(
    'каскадное архивирование применяет членство и количества вместе',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final confirmedStates = _observeConfirmedStates(container);

      final second = testSummary(index: 2, activeRelationCount: 1);
      final first = testSummary(index: 1, activeRelationCount: 1);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [second, first],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );
      confirmedStates.clear();

      final archived = testSummary(
        index: 2,
        archiveState: IntentionArchiveState.archived,
      );
      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(second.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(second),
            after: TestCatalogEntrySnapshot(archived),
          ),
          additionalChanges: [
            _countsChanged(second.id, const TestCatalogRevision(2), 0),
            _countsChanged(first.id, const TestCatalogRevision(2), 0),
          ],
        ),
      );

      final current = _loaded(container);
      expect(current.items.map((item) => item.id), [first.id]);
      expect(current.items.single.activeRelationCount, 0);
      expect(current.totalCount, 1);
      expect(current.revision, const TestCatalogRevision(2));
      expect(confirmedStates, [same(current)]);
    },
  );

  test('пакет до первой страницы применяет количество один раз', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container);

    final first = testSummary(index: 1);
    final second = testSummary(index: 2);
    await completeRelationCommand(
      container,
      repository,
      _createRelation(first.id, second.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: first.id,
          relatedIntentionId: second.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {first.id: 1, second.id: 1},
        ),
      ),
    );

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(index: 2, activeRelationCount: 1),
            testSummary(index: 1, activeRelationCount: 1),
          ],
          totalCount: 2,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    final current = _loaded(container);
    expect(current.items.map((item) => item.activeRelationCount), [1, 1]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(2));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(1));
  });

  test('страница прежней ревизии дополняется новым количеством', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container);

    final first = testSummary(index: 1);
    final second = testSummary(index: 2);
    await completeRelationCommand(
      container,
      repository,
      _createRelation(first.id, second.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: first.id,
          relatedIntentionId: second.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {first.id: 1, second.id: 1},
        ),
      ),
    );

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [second, first],
          totalCount: 2,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [second.id, first.id]);
    expect(current.items.map((item) => item.activeRelationCount), [1, 1]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(2));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(1));
  });

  test('устаревшее продолжение не возвращает прежнее количество', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    const cursor = TestCatalogCursor();
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    unawaitedLoad(container, visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);

    final second = testSummary(index: 2);
    await completeRelationCommand(
      container,
      repository,
      _createRelation(fourth.id, second.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: fourth.id,
          relatedIntentionId: second.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {fourth.id: 1, second.id: 1},
        ),
      ),
    );
    expect(_loaded(container).items.first.activeRelationCount, 1);

    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [second, testSummary(index: 1)],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await waitForCatalogQueries(repository, 3);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [
            testSummary(index: 2, activeRelationCount: 1),
            testSummary(index: 1),
          ],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [
      fourth.id,
      third.id,
      second.id,
      testSummary(index: 1).id,
    ]);
    expect(current.items.map((item) => item.activeRelationCount), [1, 0, 1, 0]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
  });

  test('количества обновляются во всех загруженных порциях', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    const cursor = TestCatalogCursor();
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    final second = testSummary(index: 2);
    final first = testSummary(index: 1);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    unawaitedLoad(container, visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [second, first],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(container).items, hasLength(4));

    await completeRelationCommand(
      container,
      repository,
      _createRelation(fourth.id, first.id),
      relationCreationSuccess(
        revision: const TestCatalogRevision(2),
        success: _relationCreated(
          sourceIntentionId: fourth.id,
          relatedIntentionId: first.id,
          revision: const TestCatalogRevision(2),
          activeCounts: {fourth.id: 1, first.id: 1},
        ),
      ),
    );

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [
      fourth.id,
      third.id,
      second.id,
      first.id,
    ]);
    expect(current.items.map((item) => item.activeRelationCount), [1, 0, 0, 1]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(repository.queries, hasLength(2));
  });

  test('отказ создания связи сохраняет подтверждённые количества', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container);

    final first = testSummary(index: 1, activeRelationCount: 2);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [first],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );
    final loadedBefore = _loaded(container);
    confirmedStates.clear();

    await completeRelationCommand(
      container,
      repository,
      _createRelation(first.id, testSummary(index: 2).id),
      const GraphCommandFailed<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(LongTermRelationUnavailableFailure()),
    );

    expect(_loaded(container), same(loadedBefore));
    expect(loadedBefore.items.single.activeRelationCount, 2);
    expect(loadedBefore.revision, const TestCatalogRevision(1));
    expect(confirmedStates, isEmpty);
    expect(repository.queries, hasLength(1));
  });
}

List<IntentionCatalogConfirmedState> _observeConfirmedStates(
  ProviderContainer container,
) {
  final confirmedStates = <IntentionCatalogConfirmedState>[];
  final subscription = container.listen(
    intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
    (_, next) {
      if (next.value case final IntentionCatalogConfirmedState confirmed) {
        confirmedStates.add(confirmed);
      }
    },
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  addTearDown(container.dispose);
  return confirmedStates;
}

IntentionCatalogLoaded _loaded(ProviderContainer container) =>
    container
            .read(
              intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
            )
            .requireValue
        as IntentionCatalogLoaded;

void unawaitedLoad(ProviderContainer container, {required int visibleIndex}) {
  container
      .read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      )
      .loadNextPageIfNeeded(visibleIndex: visibleIndex)
      .ignore();
}

CreateLongTermRelation _createRelation(
  IntentionId sourceIntentionId,
  IntentionId relatedIntentionId,
) => CreateLongTermRelation(
  sourceIntentionId: sourceIntentionId,
  relatedIntentionId: relatedIntentionId,
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: null,
);

LongTermRelationCreated _relationCreated({
  required IntentionId sourceIntentionId,
  required IntentionId relatedIntentionId,
  required GraphRevision revision,
  required Map<IntentionId, int> activeCounts,
}) => LongTermRelationCreated(
  relation: testRelation(
    sourceIntentionId: sourceIntentionId,
    relatedIntentionId: relatedIntentionId,
  ),
  description: null,
  changes: [
    for (final entry in activeCounts.entries)
      _countsChanged(entry.key, revision, entry.value),
    LongTermRelationCreatedChange(
      revision: revision,
      relation: testRelation(
        sourceIntentionId: sourceIntentionId,
        relatedIntentionId: relatedIntentionId,
      ),
    ),
  ],
);

IntentionRelationCountsChanged _countsChanged(
  IntentionId intentionId,
  GraphRevision revision,
  int activeCount,
) => IntentionRelationCountsChanged(
  revision: revision,
  intentionId: intentionId,
  counts: testRelationCounts(activeNeedOutgoing: activeCount),
);
