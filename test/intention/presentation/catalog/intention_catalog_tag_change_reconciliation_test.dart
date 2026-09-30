import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  final health = Tag(id: _tagId(1), name: TagName.fromInput('Здоровье'));
  final rest = Tag(id: _tagId(2), name: TagName.fromInput('Отдых'));
  const browse = BrowseIntentionCatalog();

  test('снятие обязательного тега исключает намерение и уменьшает количество на один', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final fourth = testSummary(index: 4, title: 'Бегать', tags: [health]);
    final third = testSummary(index: 3, title: 'Спать', tags: [health, rest]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [fourth, third],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    final thirdWithoutHealth = testSummary(
      index: 3,
      title: 'Спать',
      tags: [rest],
    );
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: third,
      after: thirdWithoutHealth,
      revision: const TestCatalogRevision(2),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [fourth.id]);
    expect(current.totalCount, 2);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(current.selection.order, before.selection.order);
    expect(current.selection.scope, before.selection.scope);
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test('назначение намерению вне загруженной части увеличивает количество и '
      'доступно в продолжении без пропуска и повтора', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final fifth = testSummary(index: 5, tags: [rest]);
    final fourth = testSummary(index: 4, tags: [rest]);
    final second = testSummary(index: 2, tags: [rest]);
    final filter = IntentionTagFilter(requiredTagIds: [rest.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [fifth, fourth],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    final unloaded = testSummary(index: 1, tags: [health]);
    final unloadedWithRest = testSummary(index: 1, tags: [health, rest]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: rest.id,
      before: unloaded,
      after: unloadedWithRest,
      revision: const TestCatalogRevision(2),
    );

    final reconciled = _loaded(container, browse);
    expect(reconciled.items.map((item) => item.id), [fifth.id, fourth.id]);
    expect(reconciled.totalCount, 4);
    expect(reconciled.nextCursor, same(before.nextCursor));
    expect(reconciled.query, same(before.query));
    expect(reconciled.revision, const TestCatalogRevision(2));
    expect(confirmedStates, [same(reconciled)]);
    expect(repository.queries, hasLength(2));

    final loading = container
        .read(intentionCatalogViewModelProvider(browse).notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(before.nextCursor));
    expect(repository.queryAt(2).tagFilter, filter);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [second, unloadedWithRest],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await loading;

    final completed = _loaded(container, browse);
    expect(completed.items.map((item) => item.id), [
      fifth.id,
      fourth.id,
      second.id,
      unloaded.id,
    ]);
    expect(completed.items.last.tags.map((tag) => tag.id), [
      health.id,
      rest.id,
    ]);
    expect(completed.totalCount, 4);
    expect(completed.nextCursor, isNull);
    expect(completed.continuation, isA<IntentionCatalogContinuationIdle>());
  });

  test('назначение внутри полностью загруженной выдачи ставит намерение на его '
      'позицию и увеличивает количество один раз', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final third = testSummary(index: 3, tags: [rest]);
    final first = testSummary(index: 1, tags: [rest]);
    final filter = IntentionTagFilter(requiredTagIds: [rest.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [third, first],
        totalCount: 2,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    final second = testSummary(index: 2);
    final secondWithRest = testSummary(index: 2, tags: [rest]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: rest.id,
      before: second,
      after: secondWithRest,
      revision: const TestCatalogRevision(2),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      third.id,
      second.id,
      first.id,
    ]);
    expect(current.items[1].tags.map((tag) => tag.id), [rest.id]);
    expect(current.items[1].createdAt.value, second.createdAt.value);
    expect(current.items[1].updatedAt.value, second.updatedAt.value);
    expect(current.totalCount, 3);
    expect(current.nextCursor, isNull);
    expect(current.query, same(before.query));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test(
    'снятие последнего совпадения даёт успешный пустой результат без сброса',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      _observeConfirmedStates(container, browse);
      final only = testSummary(index: 1, tags: [health]);
      final filter = IntentionTagFilter(requiredTagIds: [health.id]);
      await _loadFiltered(
        container,
        repository,
        browse,
        filter,
        IntentionCatalogFirstPage(
          items: [only],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      );
      final before = _loaded(container, browse);

      await completeIntentionTagAssignment(
        container,
        repository,
        state: TagAssignmentState.absent,
        tagId: health.id,
        before: only,
        after: testSummary(index: 1),
        revision: const TestCatalogRevision(2),
      );

      final empty =
          container.read(intentionCatalogViewModelProvider(browse)).requireValue
              as IntentionCatalogEmpty;
      expect(empty.totalCount, 0);
      expect(empty.nextCursor, isNull);
      expect(empty.revision, const TestCatalogRevision(2));
      expect(empty.query, same(before.query));
      expect(empty.selection.tagFilter, filter);
      expect(repository.queries, hasLength(2));
    },
  );

  test(
    'назначения поиска согласуют один пакет тега по собственным условиям',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      const action = SelectDailyChoiceAction();
      const source = SelectDailyChoiceSource();
      for (final purpose in [browse, action, source]) {
        final subscription = container.listen(
          intentionCatalogViewModelProvider(purpose),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
      }
      await waitForCatalogQueries(repository, 3);
      final ready = testSummary(
        index: 2,
        readiness: IntentionReadiness.ready,
        tags: [health],
      );
      final other = testSummary(
        index: 1,
        readiness: IntentionReadiness.ready,
        tags: [health],
      );
      for (var index = 0; index < 3; index++) {
        repository.complete(
          index,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [ready, other],
              totalCount: 2,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
      }
      for (final purpose in [browse, action, source]) {
        await container.read(intentionCatalogViewModelProvider(purpose).future);
      }
      final healthFilter = IntentionTagFilter(requiredTagIds: [health.id]);
      final withoutHealth = IntentionTagFilter(excludedTagIds: [health.id]);
      container
          .read(intentionCatalogViewModelProvider(browse).notifier)
          .changeTagFilter(healthFilter);
      container
          .read(intentionCatalogViewModelProvider(source).notifier)
          .changeTagFilter(withoutHealth);
      await waitForCatalogQueries(repository, 5);
      repository.complete(
        3,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [ready, other],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      repository.complete(4, _emptyPage(1));
      await container.read(intentionCatalogViewModelProvider(browse).future);
      await container.read(intentionCatalogViewModelProvider(source).future);
      final queriesBefore = {
        for (final purpose in [browse, action, source])
          purpose: _confirmed(container, purpose).query,
      };

      final readyWithoutHealth = testSummary(
        index: 2,
        readiness: IntentionReadiness.ready,
      );
      await completeIntentionTagAssignment(
        container,
        repository,
        state: TagAssignmentState.absent,
        tagId: health.id,
        before: ready,
        after: readyWithoutHealth,
        revision: const TestCatalogRevision(2),
      );

      final browseState = _loaded(container, browse);
      expect(browseState.items.map((item) => item.id), [other.id]);
      expect(browseState.totalCount, 1);
      expect(browseState.selection.tagFilter, healthFilter);

      final actionState = _loaded(container, action);
      expect(actionState.items.map((item) => item.id), [ready.id, other.id]);
      expect(actionState.items.first.tags, isEmpty);
      expect(actionState.totalCount, 2);
      expect(actionState.selection.tagFilter, IntentionTagFilter.empty);

      final sourceState = _loaded(container, source);
      expect(sourceState.items.map((item) => item.id), [ready.id]);
      expect(sourceState.totalCount, 1);
      expect(sourceState.selection.tagFilter, withoutHealth);

      for (final purpose in [browse, action, source]) {
        final state = _confirmed(container, purpose);
        expect(state.query, same(queriesBefore[purpose]));
        expect(state.revision, const TestCatalogRevision(2));
      }
      expect(repository.queries, hasLength(5));
    },
  );

  test(
    'ожидающее продолжение новой ревизии разрешается пакетом назначения',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 0,
      );
      _observeConfirmedStates(container, browse);
      final fourth = testSummary(index: 4, tags: [rest]);
      final third = testSummary(index: 3, tags: [rest]);
      final second = testSummary(index: 2, tags: [rest]);
      final filter = IntentionTagFilter(requiredTagIds: [rest.id]);
      await _loadFiltered(
        container,
        repository,
        browse,
        filter,
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      );

      final loading = container
          .read(intentionCatalogViewModelProvider(browse).notifier)
          .loadNextPageIfNeeded(visibleIndex: 1);
      await waitForCatalogQueries(repository, 3);
      final firstWithRest = testSummary(index: 1, tags: [rest]);
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [second, firstWithRest],
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      await loading;
      final waiting = _loaded(container, browse);
      expect(waiting.items.map((item) => item.id), [fourth.id, third.id]);
      expect(waiting.continuation, isA<IntentionCatalogContinuationLoading>());

      await completeIntentionTagAssignment(
        container,
        repository,
        state: TagAssignmentState.assigned,
        tagId: rest.id,
        before: testSummary(index: 1),
        after: firstWithRest,
        revision: const TestCatalogRevision(2),
      );

      final current = _loaded(container, browse);
      expect(current.items.map((item) => item.id), [
        fourth.id,
        third.id,
        second.id,
        firstWithRest.id,
      ]);
      expect(current.totalCount, 4);
      expect(current.nextCursor, isNull);
      expect(current.revision, const TestCatalogRevision(2));
      expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
      expect(repository.queries, hasLength(3));
    },
  );

  test('пакет назначения, уже учтённый первой порцией, не меняет количество повторно', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    await waitForCatalogQueries(repository, 1);
    final filter = IntentionTagFilter(requiredTagIds: [rest.id]);
    container
        .read(intentionCatalogViewModelProvider(browse).notifier)
        .changeTagFilter(filter);
    await waitForCatalogQueries(repository, 2);
    repository.complete(0, _emptyPage(1));

    final withRest = testSummary(index: 1, tags: [rest]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: rest.id,
      before: testSummary(index: 1),
      after: withRest,
      revision: const TestCatalogRevision(2),
    );
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [withRest],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(3),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider(browse).future);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [withRest.id]);
    expect(current.totalCount, 1);
    expect(current.revision, const TestCatalogRevision(3));
    expect(repository.queries, hasLength(2));
  });

  test('пакет назначения другой эпохи не применяется к содержимому', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    final only = testSummary(index: 1, tags: [health]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [only],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );

    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: only,
      after: testSummary(index: 1),
      revision: const TestCatalogRevision(2, epoch: 1),
    );

    await waitForCatalogQueries(repository, 3);
    final restart = repository.queryAt(2);
    expect(restart.cursor, isNull);
    expect(restart.tagFilter, filter);
  });

  test('факт назначения намерению без каталожного снимка не продвигает '
      'выдачу молча, а перечитывает её', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    final only = testSummary(index: 1, tags: [health]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [only],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );

    const revision = TestCatalogRevision(2);
    final target = IntentionTagTarget(only.id);
    await completeTagCommand(
      container,
      repository,
      RemoveTagAssignment(tagId: health.id, target: target),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagAssignmentChanged(
            TagAssignmentChangedChange(
              revision: revision,
              assignment: TagAssignment(tagId: health.id, target: target),
              state: TagAssignmentState.absent,
            ),
          ),
        ),
      ),
    );

    await waitForCatalogQueries(repository, 3);
    final restart = repository.queryAt(2);
    expect(restart.cursor, isNull);
    expect(restart.tagFilter, filter);
  });

  test('назначение долговременной связи не меняет выдачу намерений', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final only = testSummary(index: 1, tags: [health]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [only],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    const revision = TestCatalogRevision(2);
    final target = LongTermRelationTagTarget(_relationId(1));
    await completeTagCommand(
      container,
      repository,
      AssignTag(tagId: health.id, target: target),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagAssignmentChanged(
            TagAssignmentChangedChange(
              revision: revision,
              assignment: TagAssignment(tagId: health.id, target: target),
              state: TagAssignmentState.assigned,
            ),
          ),
        ),
      ),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [only.id]);
    expect(current.items.single.tags.map((tag) => tag.id), [health.id]);
    expect(confirmedStates, [same(current)]);
    expect(current.totalCount, 1);
    expect(current.query, same(before.query));
    expect(current.revision, revision);
    expect(repository.queries, hasLength(2));
  });

  test('переименование обновляет названия загруженных строк и сохраняет '
      'условие, состав, количество и продолжение', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final fourth = testSummary(index: 4, tags: [health, rest]);
    final third = testSummary(index: 3, tags: [health]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [fourth, third],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
    );
    await _completeTagRename(
      container,
      repository,
      before: health,
      after: wellBeing,
      revision: const TestCatalogRevision(2),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.items.map(_tagNames), [
      ['Самочувствие', 'Отдых'],
      ['Самочувствие'],
    ]);
    expect(current.items.map(_tagIds), [
      [health.id, rest.id],
      [health.id],
    ]);
    for (final (index, item) in current.items.indexed) {
      expect(item.createdAt.value, before.items[index].createdAt.value);
      expect(item.updatedAt.value, before.items[index].updatedAt.value);
    }
    expect(current.totalCount, 3);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));

    final loading = container
        .read(intentionCatalogViewModelProvider(browse).notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(before.nextCursor));
    expect(repository.queryAt(2).tagFilter, filter);
    final second = testSummary(index: 2, tags: [wellBeing]);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [second],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await loading;

    final completed = _loaded(container, browse);
    expect(completed.items.map((item) => item.id), [
      fourth.id,
      third.id,
      second.id,
    ]);
    expect(completed.totalCount, 3);
    expect(completed.nextCursor, isNull);
  });

  test('переименование согласует пять назначений поиска по их собственным '
      'условиям без новых чтений', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final excluded = testSummary(index: 9).id;
    final withHealth = testSummary(
      index: 2,
      readiness: IntentionReadiness.ready,
      tags: [health],
    );
    final withBoth = testSummary(
      index: 3,
      readiness: IntentionReadiness.ready,
      tags: [health, rest],
    );
    final untagged = testSummary(index: 1, readiness: IntentionReadiness.ready);
    final searches =
        <(IntentionCatalogPurpose, IntentionTagFilter, List<IntentionSummary>)>[
          (
            browse,
            IntentionTagFilter(requiredTagIds: [health.id]),
            [withBoth, withHealth],
          ),
          (
            const SelectDailyChoiceAction(),
            IntentionTagFilter(requiredTagIds: [health.id, rest.id]),
            [withBoth],
          ),
          (
            const SelectDailyChoiceSource(),
            IntentionTagFilter(excludedTagIds: [rest.id]),
            [withHealth, untagged],
          ),
          (
            SelectRelationParticipant(
              excludedIntentionId: excluded,
              selectionContext:
                  RelationParticipantSelectionContext.activeRelation,
            ),
            IntentionTagFilter(
              requiredTagIds: [health.id],
              excludedTagIds: [rest.id],
            ),
            [withHealth],
          ),
          (
            SelectRelationParticipant(
              excludedIntentionId: excluded,
              selectionContext:
                  RelationParticipantSelectionContext.archivedRelation,
            ),
            IntentionTagFilter.empty,
            [withBoth, withHealth, untagged],
          ),
        ];
    for (final (purpose, filter, items) in searches) {
      final provider = intentionCatalogViewModelProvider(purpose);
      final initial = repository.queries.length;
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final page = ResultSuccess<IntentionCatalogPage>(
        IntentionCatalogFirstPage(
          items: items,
          totalCount: items.length,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      );
      await waitForCatalogQueries(repository, initial + 1);
      if (filter == IntentionTagFilter.empty) {
        repository.complete(initial, page);
      } else {
        repository.complete(initial, _emptyPage(1));
        await container.read(provider.future);
        container.read(provider.notifier).changeTagFilter(filter);
        await waitForCatalogQueries(repository, initial + 2);
        repository.complete(initial + 1, page);
      }
      await container.read(provider.future);
    }
    final before = {
      for (final (purpose, _, _) in searches)
        purpose: _loaded(container, purpose),
    };
    final queriesBefore = repository.queries.length;

    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
    );
    await _completeTagRename(
      container,
      repository,
      before: health,
      after: wellBeing,
      revision: const TestCatalogRevision(2),
    );

    for (final (purpose, filter, items) in searches) {
      final current = _loaded(container, purpose);
      expect(
        current.items.map((item) => item.id),
        items.map((item) => item.id),
      );
      for (final item in current.items) {
        expect(
          item.tags.map((tag) => tag.name.value),
          isNot(contains('Здоровье')),
        );
        expect(
          _tagIds(item),
          _tagIds(items.firstWhere((i) => i.id == item.id)),
        );
      }
      expect(current.totalCount, items.length);
      expect(current.selection.tagFilter, filter);
      expect(current.query, same(before[purpose]!.query));
      expect(current.revision, const TestCatalogRevision(2));
    }
    expect(_loaded(container, browse).items.map(_tagNames), [
      ['Самочувствие', 'Отдых'],
      ['Самочувствие'],
    ]);
    expect(repository.queries, hasLength(queriesBefore));
  });

  test('первая порция, прочитанная до переименования, публикуется с новым '
      'названием', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    await waitForCatalogQueries(repository, 1);

    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
    );
    await _completeTagRename(
      container,
      repository,
      before: health,
      after: wellBeing,
      revision: const TestCatalogRevision(2),
    );
    final only = testSummary(index: 1, tags: [health]);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [only],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider(browse).future);

    final current = _loaded(container, browse);
    expect(current.items.map(_tagNames), [
      ['Самочувствие'],
    ]);
    expect(current.totalCount, 1);
    expect(current.revision, const TestCatalogRevision(2));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(1));
  });

  test('новый тег с прежним названием не подменяет условие и не меняет '
      'состав и количество', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
    );
    final fourth = testSummary(index: 4, tags: [wellBeing]);
    final third = testSummary(index: 3, tags: [wellBeing, rest]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [fourth, third],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    final newHealth = Tag(id: _tagId(3), name: health.name);
    const revision = TestCatalogRevision(2);
    await completeTagCommand(
      container,
      repository,
      CreateTag(newHealth.name),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagCreated(
            TagCreatedChange(revision: revision, after: newHealth),
          ),
        ),
      ),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.items.map(_tagIds), [
      [health.id],
      [health.id, rest.id],
    ]);
    expect(current.items.map(_tagNames), [
      ['Самочувствие'],
      ['Самочувствие', 'Отдых'],
    ]);
    expect(current.totalCount, 3);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.revision, revision);
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(
      current.selection.tagFilter.requiredTagIds,
      isNot(contains(newHealth.id)),
    );
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test('подтверждения без изменения тега и назначения не меняют выдачу и '
      'количество', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final only = testSummary(index: 1, tags: [health]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [only],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    const revision = TestCatalogRevision(1);
    await completeTagCommand(
      container,
      repository,
      RenameTag(tagId: health.id, name: health.name),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagUnchanged(
            TagUnchangedChange(revision: revision, tag: health),
          ),
        ),
      ),
    );
    final target = IntentionTagTarget(only.id);
    await completeTagCommand(
      container,
      repository,
      AssignTag(tagId: health.id, target: target),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagAssignmentUnchanged(
            TagAssignmentUnchangedChange(
              revision: revision,
              assignment: TagAssignment(tagId: health.id, target: target),
              state: TagAssignmentState.assigned,
            ),
          ),
        ),
      ),
    );

    expect(_loaded(container, browse), same(before));
    expect(confirmedStates, isEmpty);
    expect(repository.queries, hasLength(2));
  });
}

Result<IntentionCatalogPage> _emptyPage(int revision) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: const [],
    totalCount: 0,
    nextCursor: null,
    revision: TestCatalogRevision(revision),
  ),
);

/// Загружает первую порцию назначения с заданными условиями по тегам.
Future<void> _loadFiltered(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionCatalogPurpose purpose,
  IntentionTagFilter filter,
  IntentionCatalogFirstPage page,
) async {
  final provider = intentionCatalogViewModelProvider(purpose);
  await waitForCatalogQueries(repository, 1);
  repository.complete(0, _emptyPage(0));
  await container.read(provider.future);
  container.read(provider.notifier).changeTagFilter(filter);
  await waitForCatalogQueries(repository, 2);
  expect(repository.queryAt(1).tagFilter, filter);
  repository.complete(1, ResultSuccess(page));
  await container.read(provider.future);
}

List<IntentionCatalogConfirmedState> _observeConfirmedStates(
  ProviderContainer container,
  IntentionCatalogPurpose purpose,
) {
  final confirmedStates = <IntentionCatalogConfirmedState>[];
  final subscription = container.listen(
    intentionCatalogViewModelProvider(purpose),
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

IntentionCatalogConfirmedState _confirmed(
  ProviderContainer container,
  IntentionCatalogPurpose purpose,
) =>
    container.read(intentionCatalogViewModelProvider(purpose)).requireValue
        as IntentionCatalogConfirmedState;

/// Проводит подтверждённое переименование тега через coordinator.
Future<void> _completeTagRename(
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required Tag before,
  required Tag after,
  required GraphRevision revision,
}) async {
  await completeTagCommand(
    container,
    repository,
    RenameTag(tagId: before.id, name: after.name),
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: TagRenamed(
          TagRenamedChange(revision: revision, before: before, after: after),
        ),
      ),
    ),
  );
}

List<TagId> _tagIds(IntentionSummary summary) => [
  for (final tag in summary.tags) tag.id,
];

List<String> _tagNames(IntentionSummary summary) => [
  for (final tag in summary.tags) tag.name.value,
];

IntentionCatalogLoaded _loaded(
  ProviderContainer container,
  IntentionCatalogPurpose purpose,
) => _confirmed(container, purpose) as IntentionCatalogLoaded;

TagId _tagId(int index) => switch (TagId.decode(
  '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError(
    'Некорректный идентификатор тега в тесте.',
  ),
};

LongTermRelationId _relationId(int index) => switch (LongTermRelationId.decode(
  '018f0001-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный идентификатор связи в тесте.',
  ),
};
