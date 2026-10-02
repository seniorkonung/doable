import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  test('применяет пакет каталожных изменений одной ревизии целиком', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
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
    confirmedStates.clear();

    final first = testSummary(index: 1, title: 'Первое');
    final second = testSummary(index: 2, title: 'Второе');
    await completeCatalogCommand(
      container,
      repository,
      const CreateIntention(title: 'Первое', description: null),
      IntentionSaved(
        testIntention(index: 1, title: 'Первое'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(2),
          entry: TestCatalogEntrySnapshot(first),
        ),
        additionalCatalogMutations: [
          IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(second),
          ),
        ],
      ),
    );

    final current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [second.id, first.id]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(2));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(1));
  });

  test('применяет membership transition к префиксу, count и cursor', () async {
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
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
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
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

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
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
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
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          (_, _) {},
          fireImmediately: true,
        );
        final notifier = container.read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .notifier,
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
        await container.read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .future,
        );

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
            container
                    .read(
                      intentionCatalogViewModelProvider(
                        const BrowseIntentionCatalog(),
                      ),
                    )
                    .requireValue
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
            container
                    .read(
                      intentionCatalogViewModelProvider(
                        const BrowseIntentionCatalog(),
                      ),
                    )
                    .requireValue
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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
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
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

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
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.id, summary.id);
      expect(current.totalCount, 1);
      expect(repository.queries, hasLength(2));
    },
  );

  test('согласует данные независимо от владельца предъявления', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
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

    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final created = testSummary(index: 30, title: 'Новое');
    final create = coordinator.acceptCreation(
      IntentionCreationFormKey(),
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
    await create.future;
    await Future<void>.delayed(Duration.zero);

    var current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.single.id, created.id);
    expect(current.totalCount, 1);
    final createClaim = await presenter.nextClaim();
    expect(createClaim!.token, same(create.token));
    coordinator.confirmPresentation(createClaim);
    expect(
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
      same(current),
    );

    final ready = testSummary(
      index: 30,
      title: 'Новое',
      readiness: IntentionReadiness.ready,
    );
    final readiness = coordinator.acceptExisting(
      EnableIntentionReadiness(created.id),
      presentationTitle: created.title,
    ) as IntentionCommandAccepted;
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
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.single.readiness, IntentionReadiness.ready);
    final readinessClaim = await presenter.nextClaim();
    expect(readinessClaim!.token, same(readiness.token));
    coordinator.confirmPresentation(readinessClaim);
    expect(
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
      same(current),
    );

    final beforeFailure = current;
    final failed = coordinator.acceptExisting(
      ArchiveIntention(created.id),
      presentationTitle: created.title,
    ) as IntentionCommandAccepted;
    coordinator.releaseInitiatorPresentation(failed.token);
    repository.completeCommand(
      2,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await failed.future;
    await Future<void>.delayed(Duration.zero);
    expect(
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
      same(beforeFailure),
    );
    final failureClaim = await presenter.nextClaim();
    expect(failureClaim!.token, same(failed.token));
    coordinator.confirmPresentation(failureClaim);
    presenter.release();
    await Future<void>.delayed(Duration.zero);

    expect(
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
      same(beforeFailure),
    );
    expect(repository.queries, hasLength(1));
  });

  group('отметка избранного', () {
    test('отметка и её снятие обновляют загруженную строку на месте во всех '
        'четырёх порядках', () async {
      for (final order in [
        IntentionCatalogOrder.createdAtDescending,
        IntentionCatalogOrder.createdAtAscending,
        IntentionCatalogOrder.updatedAtDescending,
        IntentionCatalogOrder.updatedAtAscending,
      ]) {
        final reason = '${order.field}/${order.direction}';
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 1,
        );
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        final notifier = container.read(provider.notifier);
        if (order != IntentionCatalogOrder.createdAtDescending) {
          notifier.changeOrder(order);
          await waitForCatalogQueries(repository, 2);
        }
        IntentionCatalogLoaded loaded() =>
            container.read(provider).requireValue as IntentionCatalogLoaded;

        // Пять совпадений в действующем порядке: две загруженные порции и
        // одно намерение за границей загруженной части.
        final ordered = [
          for (final index in [5, 4, 3, 2, 1]) testSummary(index: index),
        ]..sort(_compareBy(order));
        final [first, second, third, fourth, outside] = ordered;
        const firstCursor = TestCatalogCursor();
        const secondCursor = TestCatalogCursor();
        repository.complete(
          repository.queries.length - 1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [first, second],
              totalCount: 5,
              nextCursor: firstCursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);
        final continuationIndex = repository.queries.length;
        final load = notifier.loadNextPageIfNeeded(visibleIndex: 1);
        await waitForCatalogQueries(repository, continuationIndex + 1);
        repository.complete(
          continuationIndex,
          ResultSuccess(
            IntentionCatalogContinuationPage(
              items: [third, fourth],
              nextCursor: secondCursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await load;
        final readsBefore = repository.queries.length;
        final before = loaded();
        expect(before.items, [first, second, third, fourth], reason: reason);

        var revision = 1;
        Future<void> confirm(IntentionSummary target, FavoriteMark mark) =>
            completeCatalogCommand(
              container,
              repository,
              switch (mark) {
                FavoriteMark.favorite => MarkIntentionFavorite(target.id),
                FavoriteMark.notFavorite => UnmarkIntentionFavorite(target.id),
              },
              IntentionSaved(
                _intentionOf(target),
                catalogMutation: IntentionCatalogUpdated(
                  revision: TestCatalogRevision(++revision),
                  before: TestCatalogEntrySnapshot(
                    _withMark(target, switch (mark) {
                      FavoriteMark.favorite => FavoriteMark.notFavorite,
                      FavoriteMark.notFavorite => FavoriteMark.favorite,
                    }),
                  ),
                  after: TestCatalogEntrySnapshot(_withMark(target, mark)),
                ),
              ),
            );

        void expectInPlace(Map<IntentionId, FavoriteMark> marks) {
          final current = loaded();
          expect(
            current.items.map((item) => item.id),
            before.items.map((item) => item.id),
            reason: reason,
          );
          for (final (index, item) in current.items.indexed) {
            final unmarked = before.items[index];
            expect(
              item.favoriteMark,
              marks[item.id] ?? FavoriteMark.notFavorite,
              reason: '$reason: ${item.id}',
            );
            expect(item.createdAt, unmarked.createdAt, reason: reason);
            expect(item.updatedAt, unmarked.updatedAt, reason: reason);
            expect(item.title, unmarked.title, reason: reason);
            expect(item.readiness, unmarked.readiness, reason: reason);
            expect(item.archiveState, unmarked.archiveState, reason: reason);
          }
          expect(current.totalCount, 5, reason: reason);
          expect(current.nextCursor, same(secondCursor), reason: reason);
          expect(current.query, same(before.query), reason: reason);
          expect(
            current.continuation,
            isA<IntentionCatalogContinuationIdle>(),
            reason: reason,
          );
          expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
          expect(
            current.revision.compareTo(TestCatalogRevision(revision)),
            GraphRevisionOrder.same,
            reason: reason,
          );
          expect(repository.queries, hasLength(readsBefore), reason: reason);
          expect(repository.reconciliationQueries, isEmpty, reason: reason);
        }

        // Строка первой порции, строка на границе продолжения и строка
        // второй порции обновляются на своих местах.
        await confirm(first, FavoriteMark.favorite);
        expectInPlace({first.id: FavoriteMark.favorite});
        await confirm(fourth, FavoriteMark.favorite);
        expectInPlace({
          first.id: FavoriteMark.favorite,
          fourth.id: FavoriteMark.favorite,
        });
        await confirm(third, FavoriteMark.favorite);
        expectInPlace({
          first.id: FavoriteMark.favorite,
          third.id: FavoriteMark.favorite,
          fourth.id: FavoriteMark.favorite,
        });

        // Намерение вне загруженной части строк не добавляет.
        await confirm(outside, FavoriteMark.favorite);
        expectInPlace({
          first.id: FavoriteMark.favorite,
          third.id: FavoriteMark.favorite,
          fourth.id: FavoriteMark.favorite,
        });
        await confirm(outside, FavoriteMark.notFavorite);

        await confirm(first, FavoriteMark.notFavorite);
        await confirm(fourth, FavoriteMark.notFavorite);
        expectInPlace({third.id: FavoriteMark.favorite});

        subscription.close();
        container.dispose();
      }
    });

    test('повтор отметки и снятия без изменения не меняет выдачу', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 1,
      );
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final published = <IntentionCatalogState>[];
      final subscription = container.listen(provider, (_, next) {
        if (next.value case final state?) {
          published.add(state);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      const cursor = TestCatalogCursor();
      final favorite = testSummary(
        index: 4,
        favoriteMark: FavoriteMark.favorite,
      );
      final plain = testSummary(index: 3);
      final outside = testSummary(index: 1);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [favorite, plain],
            totalCount: 4,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      final before = await container.read(provider.future);
      published.clear();

      // Повтор не продвигает ревизию: снимок до и после один и тот же.
      for (final (command, entry)
          in <(ExistingIntentionCommand, IntentionSummary)>[
            (MarkIntentionFavorite(favorite.id), favorite),
            (UnmarkIntentionFavorite(plain.id), plain),
            (UnmarkIntentionFavorite(outside.id), outside),
          ]) {
        await completeCatalogCommand(
          container,
          repository,
          command,
          IntentionSaved(
            _intentionOf(entry),
            catalogMutation: IntentionCatalogUnchanged(
              revision: const TestCatalogRevision(1),
              entry: TestCatalogEntrySnapshot(entry),
            ),
          ),
        );
      }

      expect(container.read(provider).requireValue, same(before));
      expect(published, isEmpty);
      expect(repository.queries, hasLength(1));
      expect(repository.reconciliationQueries, isEmpty);
    });
  });
}

/// Порядок выдачи фикстур: [testSummary] выводит обе временные метки из
/// номера, поэтому положение намерения задаёт направление порядка.
int Function(IntentionSummary, IntentionSummary) _compareBy(
  IntentionCatalogOrder order,
) => switch (order.direction) {
  IntentionCatalogSortDirection.ascending => (
    left,
    right,
  ) => left.createdAt.value.compareTo(right.createdAt.value),
  IntentionCatalogSortDirection.descending => (
    left,
    right,
  ) => right.createdAt.value.compareTo(left.createdAt.value),
};

/// Краткие данные того же намерения, отличающиеся только отметкой.
IntentionSummary _withMark(IntentionSummary summary, FavoriteMark mark) =>
    IntentionSummary(
      id: summary.id,
      title: summary.title,
      hasDescription: summary.hasDescription,
      readiness: summary.readiness,
      archiveState: summary.archiveState,
      activeRelationCount: summary.activeRelationCount,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      tags: summary.tags,
      favoriteMark: mark,
    );

/// Намерение подтверждённой команды отметки: его поля отметка не меняет.
Intention _intentionOf(IntentionSummary summary) => Intention(
  id: summary.id,
  title: summary.title,
  description: null,
  readiness: summary.readiness,
  archiveState: summary.archiveState,
  createdAt: summary.createdAt,
  updatedAt: summary.updatedAt,
);
