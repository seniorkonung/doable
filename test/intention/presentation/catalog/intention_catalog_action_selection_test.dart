import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

const _action = SelectDailyChoiceAction();
const _browse = BrowseIntentionCatalog();

void main() {
  test('режим действия читает только активные готовые намерения и хранит свой фильтр', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: Duration.zero,
    );
    addTearDown(container.dispose);
    final actionSubscription = container.listen(
      intentionCatalogViewModelProvider(_action),
      (_, _) {},
      fireImmediately: true,
    );
    final browseSubscription = container.listen(
      intentionCatalogViewModelProvider(_browse),
      (_, _) {},
      fireImmediately: true,
    );
    final participant = SelectRelationParticipant(
      excludedIntentionId: testSummary(index: 9).id,
      selectionContext: RelationParticipantSelectionContext.activeRelation,
    );
    final participantSubscription = container.listen(
      intentionCatalogViewModelProvider(participant),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(actionSubscription.close);
    addTearDown(browseSubscription.close);
    addTearDown(participantSubscription.close);

    expect(repository.queryAt(0).scope, IntentionScope.active);
    expect(
      repository.queryAt(0).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
    expect(repository.queryAt(1).readinessFilter, IntentionReadinessFilter.all);
    expect(repository.queryAt(2).readinessFilter, IntentionReadinessFilter.all);
    for (var index = 0; index < 3; index++) {
      repository.complete(
        index,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
    }
    await container.read(intentionCatalogViewModelProvider(_action).future);
    await container.read(intentionCatalogViewModelProvider(_browse).future);
    await container.read(intentionCatalogViewModelProvider(participant).future);

    final notifier = container.read(
      intentionCatalogViewModelProvider(_action).notifier,
    );
    notifier.changeScope(IntentionScope.archived);
    expect(notifier.selection.scope, IntentionScope.active);
    expect(repository.queries, hasLength(3));
    notifier.changeTitleFilter('  прогулка  ');
    await waitForCatalogQueries(repository, 4);
    expect(repository.queryAt(3).scope, IntentionScope.active);
    expect(
      repository.queryAt(3).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
    expect(
      repository.queryAt(3).titleFilter?.map((value) => value),
      'прогулка',
    );
    expect(
      container
          .read(intentionCatalogViewModelProvider(_browse))
          .requireValue
          .selection
          .titleFilterText,
      '',
    );
    expect(
      container
          .read(intentionCatalogViewModelProvider(participant))
          .requireValue
          .selection
          .titleFilterText,
      '',
    );
  });

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
    'изменение только счётчика сохраняет принадлежность действия каталогу',
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

      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(id: action.id, title: action.title, description: null),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUnchanged(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(action),
          ),
          additionalChanges: [
            IntentionRelationCountsChanged(
              revision: const TestCatalogRevision(2),
              intentionId: action.id,
              counts: testRelationCounts(activeNeedOutgoing: 2),
            ),
          ],
        ),
      );
      final current =
          container
                  .read(intentionCatalogViewModelProvider(_action))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.id, action.id);
      expect(current.items.single.activeRelationCount, 2);
      expect(current.totalCount, 1);
      expect(current.revision, const TestCatalogRevision(2));
    },
  );

  test('поздняя страница прежней ревизии не возвращает утратившее готовность действие', () async {
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
    final second = testSummary(index: 2, readiness: IntentionReadiness.ready);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider(_action).future);
    final notifier = container.read(
      intentionCatalogViewModelProvider(_action).notifier,
    );
    final loading = notifier.loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);
    expect(
      repository.queryAt(1).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );

    final notReadySecond = testSummary(index: 2);
    await completeCatalogCommand(
      container,
      repository,
      DisableIntentionReadiness(second.id),
      IntentionSaved(
        testIntention(index: 2),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(second),
          after: TestCatalogEntrySnapshot(notReadySecond),
        ),
      ),
    );
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [second],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await waitForCatalogQueries(repository, 3);
    expect(
      repository.queryAt(2).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: const [],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await loading;

    final current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.totalCount, 2);
    expect(current.nextCursor, isNull);
  });

  test('восстановление после недействительного курсора сохраняет фильтр готовности', () async {
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
    final first = testSummary(index: 2, readiness: IntentionReadiness.ready);
    final second = testSummary(index: 1, readiness: IntentionReadiness.ready);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [first, second],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider(_action).future);
    final notifier = container.read(
      intentionCatalogViewModelProvider(_action).notifier,
    );
    final loading = notifier.loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);
    repository.complete(
      1,
      const ResultFailure(IntentionGenericValidationFailure()),
    );
    await loading;

    final recovery = notifier.recoverFromInvalidCursor();
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).scope, IntentionScope.active);
    expect(
      repository.queryAt(2).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
    expect(repository.queryAt(2).cursor, isNull);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [first],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await recovery;
    final current =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogLoaded;
    expect(current.items.single.id, first.id);
    expect(current.totalCount, 1);
  });

  test('недопустимый фильтр и временный отказ сохраняют отдельные состояния режима действия', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: Duration.zero,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_action),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    repository.complete(0, const ResultFailure(IntentionUnavailableFailure()));
    expect(
      await container.read(intentionCatalogViewModelProvider(_action).future),
      isA<IntentionCatalogUnavailable>(),
    );
    final notifier = container.read(
      intentionCatalogViewModelProvider(_action).notifier,
    );
    final retry = notifier.retry();
    await waitForCatalogQueries(repository, 2);
    expect(
      repository.queryAt(1).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
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
    await retry;
    expect(
      container.read(intentionCatalogViewModelProvider(_action)).requireValue,
      isA<IntentionCatalogEmpty>(),
    );

    notifier.changeTitleFilter('неверный\u0000фильтр');
    for (var attempt = 0; attempt < 100; attempt++) {
      if (container.read(intentionCatalogViewModelProvider(_action)).value
          is IntentionCatalogInvalidFilter) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final invalid =
        container.read(intentionCatalogViewModelProvider(_action)).requireValue
            as IntentionCatalogInvalidFilter;
    expect(
      invalid.selection.filterValidationFailure,
      IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
    );
    expect(repository.queries, hasLength(2));
  });

  test(
    'смена фильтра во время загрузки отвергает позднюю прежнюю выдачу',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        filterDebounce: Duration.zero,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        intentionCatalogViewModelProvider(_action),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(
        intentionCatalogViewModelProvider(_action).notifier,
      );
      notifier.changeTitleFilter('новое');
      await waitForCatalogQueries(repository, 2);
      final currentAction = testSummary(
        index: 2,
        title: 'Новое',
        readiness: IntentionReadiness.ready,
      );
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [currentAction],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      final current = await container.read(
        intentionCatalogViewModelProvider(_action).future,
      );
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 1, readiness: IntentionReadiness.ready)],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(intentionCatalogViewModelProvider(_action)).requireValue,
        same(current),
      );
      expect(
        (current as IntentionCatalogLoaded).items.single.id,
        currentAction.id,
      );
      expect(current.query.readinessFilter, IntentionReadinessFilter.readyOnly);
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
