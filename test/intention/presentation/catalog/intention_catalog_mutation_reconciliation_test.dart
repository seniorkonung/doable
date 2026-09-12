import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  test('применяет membership transition к префиксу, count и cursor', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
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
    await container.read(intentionCatalogViewModelProvider.future);

    final movedAfterBoundary = testSummary(index: 4, createdDay: 1);
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: fourth.id, title: fourth.title, description: null),
      IntentionSaved(
        testIntention(index: 4),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(fourth),
          after: TestCatalogEntrySnapshot(movedAfterBoundary),
        ),
      ),
    );

    final insertedBeforeBoundary = testSummary(index: 5);
    await completeCatalogCommand(
      container,
      repository,
      const CreateIntention(title: 'Новое', description: null),
      IntentionSaved(
        testIntention(index: 5, title: 'Новое'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(3),
          entry: TestCatalogEntrySnapshot(insertedBeforeBoundary),
        ),
      ),
    );

    final archivedThird = testSummary(
      index: 3,
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
          before: TestCatalogEntrySnapshot(third),
          after: TestCatalogEntrySnapshot(archivedThird),
        ),
      ),
    );

    await completeCatalogCommand(
      container,
      repository,
      RestoreIntention(third.id),
      IntentionSaved(
        testIntention(index: 3),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(5),
          before: TestCatalogEntrySnapshot(archivedThird),
          after: TestCatalogEntrySnapshot(third),
        ),
      ),
    );

    await completeCatalogCommand(
      container,
      repository,
      DeleteIntention(insertedBeforeBoundary.id),
      IntentionDeleted(
        insertedBeforeBoundary.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const TestCatalogRevision(6),
          entry: TestCatalogEntrySnapshot(insertedBeforeBoundary),
        ),
      ),
    );

    final current =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [third.id]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, same(cursor));
    expect(current.revision, const TestCatalogRevision(6));
    expect(repository.queries, hasLength(1));
  });

  test(
    'перемещает изменённое намерение во всём загруженном результате',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      notifier.changeOrder(IntentionCatalogOrder.updatedAtAscending);
      await waitForCatalogQueries(repository, 2);
      final first = testSummary(index: 1, updatedDay: 1);
      final second = testSummary(index: 2, updatedDay: 2);
      final third = testSummary(index: 3, updatedDay: 3);
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [first, second, third],
            totalCount: 3,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final moved = testSummary(index: 1, updatedDay: 4);
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(id: first.id, title: first.title, description: null),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(first),
            after: TestCatalogEntrySnapshot(moved),
          ),
        ),
      );

      final current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.map((item) => item.id), [
        second.id,
        third.id,
        moved.id,
      ]);
      expect(current.totalCount, 3);
      expect(current.nextCursor, isNull);
      expect(current.revision, const TestCatalogRevision(2));
      expect(repository.queries, hasLength(2));
    },
  );

  test(
    'сохраняет глобальный порядок и границу во всех четырёх порядках',
    () async {
      final scenarios =
          <
            ({
              IntentionCatalogOrder order,
              int firstPosition,
              int boundaryPosition,
              int remainingPosition,
              int insidePosition,
              int outsidePosition,
              int movedInsidePosition,
              int movedOutsidePosition,
            })
          >[
            (
              order: IntentionCatalogOrder.createdAtAscending,
              firstPosition: 1,
              boundaryPosition: 2,
              remainingPosition: 3,
              insidePosition: 0,
              outsidePosition: 4,
              movedInsidePosition: -1,
              movedOutsidePosition: 5,
            ),
            (
              order: IntentionCatalogOrder.createdAtDescending,
              firstPosition: 5,
              boundaryPosition: 4,
              remainingPosition: 3,
              insidePosition: 6,
              outsidePosition: 2,
              movedInsidePosition: 7,
              movedOutsidePosition: 1,
            ),
            (
              order: IntentionCatalogOrder.updatedAtAscending,
              firstPosition: 1,
              boundaryPosition: 2,
              remainingPosition: 3,
              insidePosition: 0,
              outsidePosition: 4,
              movedInsidePosition: -1,
              movedOutsidePosition: 5,
            ),
            (
              order: IntentionCatalogOrder.updatedAtDescending,
              firstPosition: 5,
              boundaryPosition: 4,
              remainingPosition: 3,
              insidePosition: 6,
              outsidePosition: 2,
              movedInsidePosition: 7,
              movedOutsidePosition: 1,
            ),
          ];

      for (final scenario in scenarios) {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 1,
        );
        final subscription = container.listen(
          intentionCatalogViewModelProvider,
          (_, _) {},
          fireImmediately: true,
        );
        final notifier = container.read(
          intentionCatalogViewModelProvider.notifier,
        );
        if (scenario.order != IntentionCatalogOrder.createdAtDescending) {
          notifier.changeOrder(scenario.order);
          await waitForCatalogQueries(repository, 2);
        }
        final firstPageIndex = repository.queries.length - 1;
        const cursor = TestCatalogCursor();
        IntentionSummary atPosition(int index, int position) => testSummary(
          index: index,
          createdDay:
              scenario.order.field == IntentionCatalogSortField.createdAt
              ? position
              : index,
          updatedDay:
              scenario.order.field == IntentionCatalogSortField.updatedAt
              ? position
              : index,
        );

        final first = atPosition(20, scenario.firstPosition);
        final boundary = atPosition(21, scenario.boundaryPosition);
        final remaining = atPosition(22, scenario.remainingPosition);
        final inside = atPosition(23, scenario.insidePosition);
        final outside = atPosition(24, scenario.outsidePosition);
        repository.complete(
          firstPageIndex,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [first, boundary],
              totalCount: 3,
              nextCursor: cursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(intentionCatalogViewModelProvider.future);

        await completeCatalogCommand(
          container,
          repository,
          const CreateIntention(title: 'Внутри', description: null),
          IntentionSaved(
            testIntention(index: 23, title: 'Внутри'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(2),
              entry: TestCatalogEntrySnapshot(inside),
            ),
          ),
        );
        await completeCatalogCommand(
          container,
          repository,
          const CreateIntention(title: 'Снаружи', description: null),
          IntentionSaved(
            testIntention(index: 24, title: 'Снаружи'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(3),
              entry: TestCatalogEntrySnapshot(outside),
            ),
          ),
        );

        final movedOutside = atPosition(20, scenario.movedOutsidePosition);
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(id: first.id, title: first.title, description: null),
          IntentionSaved(
            testIntention(index: 20),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(4),
              before: TestCatalogEntrySnapshot(first),
              after: TestCatalogEntrySnapshot(movedOutside),
            ),
          ),
        );
        final movedInside = atPosition(22, scenario.movedInsidePosition);
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(
            id: remaining.id,
            title: remaining.title,
            description: null,
          ),
          IntentionSaved(
            testIntention(index: 22),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(5),
              before: TestCatalogEntrySnapshot(remaining),
              after: TestCatalogEntrySnapshot(movedInside),
            ),
          ),
        );

        final beforeContinuation =
            container.read(intentionCatalogViewModelProvider).requireValue
                as IntentionCatalogLoaded;
        expect(beforeContinuation.items.map((item) => item.id), [
          movedInside.id,
          inside.id,
          boundary.id,
        ], reason: '${scenario.order.field}/${scenario.order.direction}');
        expect(beforeContinuation.totalCount, 5);
        expect(beforeContinuation.nextCursor, same(cursor));

        final continuationIndex = repository.queries.length;
        final load = notifier.loadNextPageIfNeeded(visibleIndex: 1);
        await waitForCatalogQueries(repository, continuationIndex + 1);
        expect(repository.queryAt(continuationIndex).cursor, same(cursor));
        repository.complete(
          continuationIndex,
          ResultSuccess(
            IntentionCatalogContinuationPage(
              items: [outside, movedOutside],
              nextCursor: null,
              revision: const TestCatalogRevision(5),
            ),
          ),
        );
        await load;

        final completed =
            container.read(intentionCatalogViewModelProvider).requireValue
                as IntentionCatalogLoaded;
        expect(completed.items.map((item) => item.id), [
          movedInside.id,
          inside.id,
          boundary.id,
          outside.id,
          movedOutside.id,
        ], reason: '${scenario.order.field}/${scenario.order.direction}');
        expect(completed.totalCount, 5);
        expect(completed.nextCursor, isNull);

        subscription.close();
        container.dispose();
      }
    },
  );

  test(
    'использует точный historical membership вместо повторного folding',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        filterDebounce: Duration.zero,
      );
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      notifier.changeTitleFilter('исторический');
      await waitForCatalogQueries(repository, 2);
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final summary = testSummary(index: 6, title: 'Новая проекция');
      await completeCatalogCommand(
        container,
        repository,
        const CreateIntention(title: 'Новая проекция', description: null),
        IntentionSaved(
          testIntention(index: 6, title: 'Новая проекция'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(summary, matchesResult: true),
          ),
        ),
      );

      final current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.id, summary.id);
      expect(current.totalCount, 1);
      expect(repository.queries, hasLength(2));
    },
  );

  test(
    'согласует данные для обоих owners, но сообщает только fallback',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
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
      await container.read(intentionCatalogViewModelProvider.future);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      final events = <IntentionCatalogPresentationEvent>[];
      notifier.addPresentationListener(events.add);
      final coordinator = container.read(
        intentionCommandCoordinatorProvider.notifier,
      );
      final created = testSummary(index: 30, title: 'Новое');
      final create = coordinator.accept(
        const CreateIntention(title: 'Новое', description: null),
      ) as IntentionCommandAccepted;
      repository.completeCommand(
        0,
        ResultSuccess(
          IntentionSaved(
            testIntention(index: 30, title: 'Новое'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(2),
              entry: TestCatalogEntrySnapshot(created),
            ),
          ),
        ),
      );
      final createCompletion = await create.future;
      final initiatorClaim = coordinator.claimInitiator(createCompletion.token);
      coordinator.confirmPresentation(initiatorClaim!);
      await Future<void>.delayed(Duration.zero);

      var current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.id, created.id);
      expect(current.totalCount, 1);
      expect(events, isEmpty);

      final ready = testSummary(
        index: 30,
        title: 'Новое',
        readiness: IntentionReadiness.ready,
      );
      final readiness = coordinator.accept(
        EnableIntentionReadiness(created.id),
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(readiness.token);
      repository.completeCommand(
        1,
        ResultSuccess(
          IntentionSaved(
            testIntention(index: 30, title: 'Новое'),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(3),
              before: TestCatalogEntrySnapshot(created),
              after: TestCatalogEntrySnapshot(ready),
            ),
          ),
        ),
      );
      await readiness.future;
      await Future<void>.delayed(Duration.zero);

      current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.readiness, IntentionReadiness.ready);
      expect(events, [
        isA<IntentionCatalogUpdatePresentationEvent>().having(
          (event) => event.outcome,
          'outcome',
          IntentionCatalogUpdateOutcome.succeeded,
        ),
      ]);

      final beforeFailure = current;
      final failed = coordinator.accept(
        ArchiveIntention(created.id),
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(failed.token);
      repository.completeCommand(
        2,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await failed.future;
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(intentionCatalogViewModelProvider).requireValue,
        same(beforeFailure),
      );
      expect(
        events.last,
        isA<IntentionCatalogUpdatePresentationEvent>().having(
          (event) => event.outcome,
          'outcome',
          IntentionCatalogUpdateOutcome.unavailable,
        ),
      );
      expect(events, hasLength(2));
      expect(repository.queries, hasLength(1));
    },
  );
}
