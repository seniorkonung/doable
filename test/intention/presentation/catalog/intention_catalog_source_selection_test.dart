import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

const _source = SelectDailyChoiceSource();
const _action = SelectDailyChoiceAction();
const _browse = BrowseIntentionCatalog();

void main() {
  test(
    'режим исходного намерения сохраняет свой фильтр и обе готовности',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        filterDebounce: Duration.zero,
        pageSize: 2,
        prefetchRemaining: 1,
      );
      addTearDown(container.dispose);
      for (final purpose in [_source, _action, _browse]) {
        final subscription = container.listen(
          intentionCatalogViewModelProvider(purpose),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
      }
      final participant = SelectRelationParticipant(
        excludedIntentionId: testSummary(index: 9).id,
        selectionContext: RelationParticipantSelectionContext.activeRelation,
      );
      final participantSubscription = container.listen(
        intentionCatalogViewModelProvider(participant),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(participantSubscription.close);

      expect(repository.queryAt(0).scope, IntentionScope.active);
      expect(
        repository.queryAt(0).readinessFilter,
        IntentionReadinessFilter.all,
      );
      expect(repository.queryAt(0).pageSize, 2);
      expect(
        repository.queryAt(1).readinessFilter,
        IntentionReadinessFilter.readyOnly,
      );
      final notReady = testSummary(index: 2, title: 'Одинаковое');
      final ready = testSummary(
        index: 1,
        title: 'Одинаковое',
        readiness: IntentionReadiness.ready,
      );
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [notReady, ready],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      for (var index = 1; index < 4; index++) {
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
      final sourceState = await container.read(
        intentionCatalogViewModelProvider(_source).future,
      ) as IntentionCatalogLoaded;
      expect(sourceState.items.map((item) => item.id), [notReady.id, ready.id]);
      expect(notReady.id, isNot(ready.id));
      expect(repository.commands, isEmpty);
      await container.read(intentionCatalogViewModelProvider(_action).future);
      await container.read(intentionCatalogViewModelProvider(_browse).future);
      await container.read(
        intentionCatalogViewModelProvider(participant).future,
      );

      final notifier = container.read(
        intentionCatalogViewModelProvider(_source).notifier,
      );
      notifier.changeScope(IntentionScope.archived);
      expect(notifier.selection.scope, IntentionScope.active);
      expect(repository.queries, hasLength(4));
      notifier.changeTitleFilter('  Одинаковое  ');
      await waitForCatalogQueries(repository, 5);
      expect(repository.queryAt(4).scope, IntentionScope.active);
      expect(
        repository.queryAt(4).readinessFilter,
        IntentionReadinessFilter.all,
      );
      expect(
        repository.queryAt(4).titleFilter?.map((value) => value),
        'Одинаковое',
      );
      for (final purpose in [_action, _browse, participant]) {
        expect(
          container
              .read(intentionCatalogViewModelProvider(purpose))
              .requireValue
              .selection
              .titleFilterText,
          '',
        );
      }
      repository.complete(
        4,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [notReady, ready],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider(_source).future);
    },
  );

  test(
    'переименование, архивирование и удаление согласуют строки и счётчик',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 1,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        intentionCatalogViewModelProvider(_source),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final third = testSummary(index: 3);
      final second = testSummary(index: 2, readiness: IntentionReadiness.ready);
      final first = testSummary(index: 1);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [third, second],
            totalCount: 3,
            nextCursor: const TestCatalogCursor(),
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider(_source).future);

      final renamed = testSummary(index: 3, title: 'Другое имя');
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(id: third.id, title: renamed.title, description: null),
        IntentionSaved(
          testIntention(index: 3, title: renamed.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(third),
            after: TestCatalogEntrySnapshot(renamed),
          ),
        ),
      );
      var state =
          container
                  .read(intentionCatalogViewModelProvider(_source))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(state.items.first.title, renamed.title);
      expect(state.totalCount, 3);

      final archived = testSummary(
        index: 2,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
      );
      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(second.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(second),
            after: TestCatalogEntrySnapshot(archived),
          ),
        ),
      );
      state =
          container
                  .read(intentionCatalogViewModelProvider(_source))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(state.items.map((item) => item.id), [third.id]);
      expect(state.totalCount, 2);

      await completeCatalogCommand(
        container,
        repository,
        DeleteIntention(first.id),
        IntentionDeleted(
          first.id,
          catalogMutation: IntentionCatalogDeleted(
            revision: const TestCatalogRevision(4),
            entry: TestCatalogEntrySnapshot(first),
          ),
        ),
      );
      state =
          container
                  .read(intentionCatalogViewModelProvider(_source))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(state.items.map((item) => item.id), [third.id]);
      expect(state.totalCount, 1);

      final readyThird = testSummary(
        index: 3,
        title: renamed.title,
        readiness: IntentionReadiness.ready,
      );
      await completeCatalogCommand(
        container,
        repository,
        EnableIntentionReadiness(third.id),
        IntentionSaved(
          testIntention(index: 3, title: renamed.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(5),
            before: TestCatalogEntrySnapshot(renamed),
            after: TestCatalogEntrySnapshot(readyThird),
          ),
        ),
      );
      state =
          container
                  .read(intentionCatalogViewModelProvider(_source))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(state.items.single.id, third.id);
      expect(state.items.single.readiness, IntentionReadiness.ready);
      expect(state.totalCount, 1);
    },
  );

  test('поздняя страница не возвращает архивное намерение', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_source),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    final second = testSummary(index: 2);
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
    await container.read(intentionCatalogViewModelProvider(_source).future);
    final notifier = container.read(
      intentionCatalogViewModelProvider(_source).notifier,
    );
    final loading = notifier.loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);
    expect(repository.queryAt(1).readinessFilter, IntentionReadinessFilter.all);

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
    final state =
        container.read(intentionCatalogViewModelProvider(_source)).requireValue
            as IntentionCatalogLoaded;
    expect(state.items.map((item) => item.id), [fourth.id, third.id]);
    expect(state.totalCount, 2);
    expect(state.nextCursor, isNull);
  });

  test('поздний ответ старого фильтра не заменяет новое основание', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: Duration.zero,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_source),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(
      intentionCatalogViewModelProvider(_source).notifier,
    );
    notifier.changeTitleFilter('новое');
    await waitForCatalogQueries(repository, 2);
    final currentSource = testSummary(index: 2, title: 'Новое');
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [currentSource],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    final current = await container.read(
      intentionCatalogViewModelProvider(_source).future,
    );
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(intentionCatalogViewModelProvider(_source)).requireValue,
      same(current),
    );
    expect(
      (current as IntentionCatalogLoaded).items.single.id,
      currentSource.id,
    );
  });
}
