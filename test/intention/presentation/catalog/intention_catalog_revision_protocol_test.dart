import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  test('применяет completion новее первой страницы', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final created = testSummary(index: 8, title: 'Новое');
    await completeCatalogCommand(
      container,
      repository,
      const CreateIntention(title: 'Новое', description: null),
      IntentionSaved(
        testIntention(index: 8, title: 'Новое'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(2),
          entry: TestCatalogEntrySnapshot(created),
        ),
      ),
    );
    expect(repository.queries, hasLength(1));

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

    final current = await container.read(
      intentionCatalogViewModelProvider.future,
    );
    expect(
      current,
      isA<IntentionCatalogLoaded>()
          .having((value) => value.items.single.id, 'ID', created.id)
          .having((value) => value.totalCount, 'count', 1)
          .having(
            (value) => value.revision,
            'ревизия',
            const TestCatalogRevision(2),
          ),
    );
  });

  test('не применяет повторно mutation, уже вошедую в страницу', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final accepted = coordinator.acceptCreation(
      IntentionCreationFormKey(),
      const CreateIntention(title: 'Новое', description: null),
    ) as IntentionCommandAccepted;
    final created = testSummary(index: 9, title: 'Новое');
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [created],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider.future);

    repository.completeCommand(
      0,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: 9, title: 'Новое'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(created),
          ),
        ),
      ),
    );
    final completion = await accepted.future;
    final claim = coordinator.claimInitiator(completion.token);
    coordinator.confirmPresentation(claim!);
    await Future<void>.delayed(Duration.zero);

    final current =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [created.id]);
    expect(current.totalCount, 1);
    expect(repository.queries, hasLength(1));
  });

  test(
    'после completion другой epoch начинает с первой страницы без replay',
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

      final created = testSummary(index: 10, title: 'Новая epoch');
      await completeCatalogCommand(
        container,
        repository,
        const CreateIntention(title: 'Новая epoch', description: null),
        IntentionSaved(
          testIntention(index: 10, title: 'Новая epoch'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(1, epoch: 2),
            entry: TestCatalogEntrySnapshot(created),
          ),
        ),
      );
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(5, epoch: 1),
          ),
        ),
      );

      await waitForCatalogQueries(repository, 2);
      expect(repository.queryAt(1).cursor, isNull);
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [created],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(1, epoch: 2),
          ),
        ),
      );

      final current = await container.read(
        intentionCatalogViewModelProvider.future,
      );
      expect(
        current,
        isA<IntentionCatalogLoaded>()
            .having((value) => value.items.map((item) => item.id), 'ID', [
              created.id,
            ])
            .having((value) => value.totalCount, 'count', 1)
            .having(
              (value) => value.revision,
              'ревизия',
              const TestCatalogRevision(1, epoch: 2),
            ),
      );
      expect(repository.queries, hasLength(2));
    },
  );

  test('повторяет только устаревшую continuation с тем же cursor', () async {
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
    final fourth = testSummary(index: 4, title: 'Прежнее');
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, testSummary(index: 3)],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider.future);

    final notifier = container.read(intentionCatalogViewModelProvider.notifier);
    final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
    await waitForCatalogQueries(repository, 2);
    final updated = testSummary(index: 4, title: 'Изменённое');
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: fourth.id, title: updated.title, description: null),
      IntentionSaved(
        testIntention(index: 4, title: updated.title),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(fourth),
          after: TestCatalogEntrySnapshot(updated),
        ),
      ),
    );

    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 2), testSummary(index: 1)],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(cursor));
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 2), testSummary(index: 1)],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await load;

    final current =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [
      updated.id,
      testSummary(index: 3).id,
      testSummary(index: 2).id,
      testSummary(index: 1).id,
    ]);
    expect(current.items.first.title, 'Изменённое');
    expect(current.totalCount, 4);
    expect(current.nextCursor, isNull);
  });

  test('исключение continuation сохраняет применённый completion', () async {
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
    final original = testSummary(index: 4, title: 'Прежнее');
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [original, testSummary(index: 3)],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider.future);

    final notifier = container.read(intentionCatalogViewModelProvider.notifier);
    final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
    await waitForCatalogQueries(repository, 2);
    final updated = testSummary(index: 4, title: 'Подтверждённое');
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: original.id, title: updated.title, description: null),
      IntentionSaved(
        testIntention(index: 4, title: updated.title),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(original),
          after: TestCatalogEntrySnapshot(updated),
        ),
      ),
    );
    repository.failPage(1, StateError('Ошибка continuation'));
    await load;

    final current =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.first.title, 'Подтверждённое');
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.totalCount, 4);
    expect(current.nextCursor, same(cursor));
    expect(current.continuation, isA<IntentionCatalogContinuationUnexpected>());
  });

  test(
    'удерживает новую continuation до всех предшествующих completions',
    () async {
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
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 4), testSummary(index: 3)],
            totalCount: 4,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final firstAccepted = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(title: 'Новое 1', description: null),
      ) as IntentionCommandAccepted;
      final secondAccepted = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(title: 'Новое 2', description: null),
      ) as IntentionCommandAccepted;
      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
      await waitForCatalogQueries(repository, 2);
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [testSummary(index: 2), testSummary(index: 1)],
            nextCursor: null,
            revision: const TestCatalogRevision(3),
          ),
        ),
      );
      await load;

      final waiting =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(waiting.items, hasLength(2));
      expect(waiting.continuation, isA<IntentionCatalogContinuationLoading>());

      final firstCreated = testSummary(index: 6, title: 'Новое 1');
      repository.completeCommand(
        0,
        ResultSuccess(
          IntentionSaved(
            testIntention(index: 6, title: 'Новое 1'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(2),
              entry: TestCatalogEntrySnapshot(firstCreated),
            ),
          ),
        ),
      );
      final firstCompletion = await firstAccepted.future;
      final firstClaim = coordinator.claimInitiator(firstCompletion.token);
      coordinator.confirmPresentation(firstClaim!);
      await Future<void>.delayed(Duration.zero);

      final afterFirst =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(afterFirst.items, hasLength(3));
      expect(afterFirst.totalCount, 5);
      expect(afterFirst.nextCursor, same(cursor));
      expect(
        afterFirst.continuation,
        isA<IntentionCatalogContinuationLoading>(),
      );

      final secondCreated = testSummary(index: 5, title: 'Новое 2');
      repository.completeCommand(
        1,
        ResultSuccess(
          IntentionSaved(
            testIntention(index: 5, title: 'Новое 2'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(3),
              entry: TestCatalogEntrySnapshot(secondCreated),
            ),
          ),
        ),
      );
      final secondCompletion = await secondAccepted.future;
      final secondClaim = coordinator.claimInitiator(secondCompletion.token);
      coordinator.confirmPresentation(secondClaim!);
      await Future<void>.delayed(Duration.zero);

      final current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.map((item) => item.id), [
        firstCreated.id,
        secondCreated.id,
        testSummary(index: 4).id,
        testSummary(index: 3).id,
        testSummary(index: 2).id,
        testSummary(index: 1).id,
      ]);
      expect(current.totalCount, 6);
      expect(current.nextCursor, isNull);
      expect(repository.queries, hasLength(2));
    },
  );

  test(
    'повторяет старую recovery-страницу после применённого completion',
    () async {
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
      final original = testSummary(index: 4, title: 'Прежнее');
      final second = testSummary(index: 3);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [original, second],
            totalCount: 3,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      final continuation = notifier.loadNextPageIfNeeded(visibleIndex: 0);
      await waitForCatalogQueries(repository, 2);
      repository.complete(
        1,
        const ResultFailure(IntentionGenericValidationFailure()),
      );
      await continuation;

      final recovery = notifier.recoverFromInvalidCursor();
      await waitForCatalogQueries(repository, 3);
      expect(repository.queryAt(2).cursor, isNull);
      final updated = testSummary(index: 4, title: 'Подтверждённое');
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(
          id: original.id,
          title: updated.title,
          description: null,
        ),
        IntentionSaved(
          testIntention(index: 4, title: updated.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(original),
            after: TestCatalogEntrySnapshot(updated),
          ),
        ),
      );
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [original, second],
            totalCount: 3,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );

      await waitForCatalogQueries(repository, 4);
      expect(repository.queryAt(3).cursor, isNull);
      repository.complete(
        3,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [updated, second],
            totalCount: 3,
            nextCursor: cursor,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      await recovery;

      final current =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(current.items.first.title, 'Подтверждённое');
      expect(current.revision, const TestCatalogRevision(2));
      expect(current.nextCursor, same(cursor));
      expect(repository.queries, hasLength(4));
    },
  );
}
