import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

final _action = SelectDailyChoiceAction(session: IntentionSearchSession());

void main() {
  test('готовность и архивирование меняют точное количество, включая незагруженные действия', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_action),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final fourth = testSummary(index: 4, readiness: IntentionReadiness.ready);
    final third = testSummary(index: 3, readiness: IntentionReadiness.ready);
    final second = testSummary(index: 2);
    const cursor = TestCatalogCursor();
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 3,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider(_action).future);

    final readySecond = testSummary(
      index: 2,
      readiness: IntentionReadiness.ready,
    );
    await completeCatalogCommand(
      container,
      repository,
      EnableIntentionReadiness(second.id),
      IntentionSaved(
        testIntention(index: 2),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(second),
          after: TestCatalogEntrySnapshot(readySecond),
        ),
      ),
    );
    var current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.totalCount, 4);

    final renamedThird = testSummary(
      index: 3,
      title: 'Новое имя',
      readiness: IntentionReadiness.ready,
    );
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: third.id, title: 'Новое имя', description: null),
      IntentionSaved(
        testIntention(index: 3, title: 'Новое имя'),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(3),
          before: TestCatalogEntrySnapshot(third),
          after: TestCatalogEntrySnapshot(renamedThird),
        ),
      ),
    );
    current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.last.title, 'Новое имя');
    expect(current.totalCount, 4);

    final archivedThird = testSummary(
      index: 3,
      title: 'Новое имя',
      readiness: IntentionReadiness.ready,
      archiveState: IntentionArchiveState.archived,
    );
    await completeCatalogCommand(
      container,
      repository,
      ArchiveIntention(third.id),
      IntentionSaved(
        testIntention(index: 3),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(4),
          before: TestCatalogEntrySnapshot(renamedThird),
          after: TestCatalogEntrySnapshot(archivedThird),
        ),
      ),
    );
    current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [fourth.id]);
    expect(current.totalCount, 3);

    await completeCatalogCommand(
      container,
      repository,
      DeleteIntention(second.id),
      IntentionDeleted(
        second.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const TestCatalogRevision(5),
          entry: TestCatalogEntrySnapshot(readySecond),
        ),
      ),
    );
    current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [fourth.id]);
    expect(current.totalCount, 2);
    expect(current.nextCursor, same(cursor));

    final notReadyFourth = testSummary(index: 4);
    await completeCatalogCommand(
      container,
      repository,
      DisableIntentionReadiness(fourth.id),
      IntentionSaved(
        testIntention(index: 4),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(6),
          before: TestCatalogEntrySnapshot(fourth),
          after: TestCatalogEntrySnapshot(notReadyFourth),
        ),
      ),
    );
    current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items, isEmpty);
    expect(current.totalCount, 1);
    expect(current.nextCursor, same(cursor));
  });

  test(
    'пакет только с количествами связей продвигает ревизию и сохраняет выдачу',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        intentionCatalogViewModelProvider(_action),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final action = testSummary(index: 1, readiness: IntentionReadiness.ready);
      final neighbour = testSummary(index: 2);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [action],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider(_action).future);

      const revision = TestCatalogRevision(2);
      final relation = testRelation(
        sourceIntentionId: action.id,
        relatedIntentionId: neighbour.id,
      );
      await completeRelationCommand(
        container,
        repository,
        CreateLongTermRelation(
          sourceIntentionId: action.id,
          relatedIntentionId: neighbour.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: null,
        ),
        relationCreationSuccess(
          revision: revision,
          success: LongTermRelationCreated(
            relation: relation,
            description: null,
            changes: [
              IntentionRelationCountsChanged(
                revision: revision,
                intentionId: action.id,
                counts: testRelationCounts(activeNeedOutgoing: 1),
              ),
              IntentionRelationCountsChanged(
                revision: revision,
                intentionId: neighbour.id,
                counts: testRelationCounts(activeNeedIncoming: 1),
              ),
              LongTermRelationCreatedChange(
                revision: revision,
                relation: relation,
              ),
            ],
          ),
        ),
      );

      final current =
          container
                  .read(intentionCatalogViewModelProvider(_action))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single, same(action));
      expect(current.totalCount, 1);
      expect(current.nextCursor, isNull);
      expect(current.revision.compareTo(revision), GraphRevisionOrder.same);
      expect(repository.queries, hasLength(1));
    },
  );

  test('освобождение режима отменяет отложенный фильтр', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_action),
      (_, _) {},
      fireImmediately: true,
    );
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
    await container.read(intentionCatalogViewModelProvider(_action).future);
    container
        .read(intentionCatalogViewModelProvider(_action).notifier)
        .changeTitleFilter('позже');
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repository.queries, hasLength(1));
  });
}
