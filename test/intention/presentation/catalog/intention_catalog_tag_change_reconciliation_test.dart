import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

  test('переименование выбранных обязательного и исключённого тегов '
      'сохраняет выбор по идентификаторам и меняет только названия '
      'в загруженных сводках', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final focus = Tag(id: _tagId(3), name: TagName.fromInput('Фокус'));
    final withHealthAndFocus = testSummary(
      index: 2,
      readiness: IntentionReadiness.ready,
      tags: [health, focus],
    );
    final withHealth = testSummary(
      index: 1,
      readiness: IntentionReadiness.ready,
      tags: [health],
    );
    final items = [withHealthAndFocus, withHealth];
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    final excluded = testSummary(index: 9).id;
    final purposes = <IntentionCatalogPurpose>[
      browse,
      const SelectDailyChoiceAction(),
      const SelectDailyChoiceSource(),
      SelectRelationParticipant(
        excludedIntentionId: excluded,
        selectionContext: RelationParticipantSelectionContext.activeRelation,
      ),
      SelectRelationParticipant(
        excludedIntentionId: excluded,
        selectionContext: RelationParticipantSelectionContext.archivedRelation,
      ),
    ];
    for (final purpose in purposes) {
      final provider = intentionCatalogViewModelProvider(purpose);
      final initial = repository.queries.length;
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForCatalogQueries(repository, initial + 1);
      repository.complete(initial, _emptyPage(1));
      await container.read(provider.future);
      container.read(provider.notifier).changeTagFilter(filter);
      await waitForCatalogQueries(repository, initial + 2);
      expect(repository.queryAt(initial + 1).tagFilter, filter);
      repository.complete(
        initial + 1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: items,
            totalCount: items.length,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(provider.future);
    }
    final before = {
      for (final purpose in purposes) purpose: _loaded(container, purpose),
    };
    final loadingStates = {
      for (final purpose in purposes)
        purpose: _observeLoadingStates(container, purpose),
    };
    final queriesBefore = repository.queries.length;

    await _completeTagRename(
      container,
      repository,
      before: health,
      after: Tag(id: health.id, name: TagName.fromInput('Самочувствие')),
      revision: const TestCatalogRevision(2),
    );
    await _completeTagRename(
      container,
      repository,
      before: rest,
      after: Tag(id: rest.id, name: TagName.fromInput('Покой')),
      revision: const TestCatalogRevision(3),
    );

    for (final purpose in purposes) {
      final previous = before[purpose]!;
      final current = _loaded(container, purpose);
      expect(current.selection, same(previous.selection));
      expect(current.selection.tagFilter, same(previous.selection.tagFilter));
      expect(current.selection.tagFilter.requiredTagIds, {health.id});
      expect(current.selection.tagFilter.excludedTagIds, {rest.id});
      expect(current.query, same(previous.query));
      expect(current.query.tagFilter, filter);
      expect(
        current.items.map((item) => item.id),
        items.map((item) => item.id),
      );
      expect(current.items.map(_tagIds), items.map(_tagIds));
      expect(current.items.map(_tagNames), [
        ['Самочувствие', 'Фокус'],
        ['Самочувствие'],
      ]);
      expect(current.totalCount, items.length);
      expect(current.nextCursor, isNull);
      expect(current.revision, const TestCatalogRevision(3));
      expect(loadingStates[purpose], isEmpty);
    }
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
    await completeTagCommand(
      container,
      repository,
      AssignTag(tagId: health.id, intentionId: only.id),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagAssignmentUnchanged(
            TagAssignmentUnchangedChange(
              revision: revision,
              assignment: TagAssignment(tagId: health.id, intentionId: only.id),
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

  test('удаление обязательного тега сохраняет условие и даёт успешный пустой '
      'результат без продолжения', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final fourth = testSummary(index: 4, tags: [health]);
    final third = testSummary(index: 3, tags: [health, rest]);
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

    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.totalCount, 0);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(current.query.tagFilter.requiredTagIds, [health.id]);
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test('удаление обязательного тега во время продолжения не возвращает '
      'прежние совпадения из запоздалой порции', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final fourth = testSummary(index: 4, tags: [health]);
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
    final loading = container
        .read(intentionCatalogViewModelProvider(browse).notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 3);
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );
    final emptied = _confirmed(container, browse);
    expect(emptied, isA<IntentionCatalogEmpty>());

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [
            testSummary(index: 2, tags: [health]),
          ],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await loading;
    await Future<void>.delayed(Duration.zero);

    expect(_confirmed(container, browse), same(emptied));
    expect(emptied.totalCount, 0);
    expect(emptied.selection.tagFilter, filter);
    expect(confirmedStates, [same(emptied)]);
    expect(repository.queries, hasLength(3));
  });

  test('первая порция, прочитанная до удаления обязательного тега, '
      'публикуется пустой', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    await waitForCatalogQueries(repository, 1);
    repository.complete(0, _emptyPage(0));
    await container.read(provider.future);
    final filter = IntentionTagFilter(requiredTagIds: [health.id]);
    container.read(provider.notifier).changeTagFilter(filter);
    await waitForCatalogQueries(repository, 2);
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(index: 1, tags: [health]),
          ],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(provider.future);

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test('удаление тега вне условий убирает его из загруженных строк и '
      'сохраняет состав, количество, порядок и продолжение', () async {
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

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.items.map(_tagIds), [
      [health.id],
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
    final second = testSummary(index: 2, tags: [health]);
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

  test('удаление тега согласует пять назначений поиска по их собственным '
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
    final withRest = testSummary(
      index: 4,
      readiness: IntentionReadiness.ready,
      tags: [rest],
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
            IntentionTagFilter.empty,
            [withRest, withBoth, withHealth, untagged],
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
            IntentionTagFilter(requiredTagIds: [rest.id]),
            [withRest, withBoth],
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

    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );

    for (final (purpose, filter, _) in searches) {
      final current = _confirmed(container, purpose);
      expect(current.selection.tagFilter, filter);
      expect(current.query, same(before[purpose]!.query));
      expect(current.revision, const TestCatalogRevision(2));
    }
    for (final purpose in [
      browse,
      const SelectDailyChoiceAction(),
      searches[3].$1,
    ]) {
      final current = _confirmed(container, purpose);
      expect(current, isA<IntentionCatalogEmpty>());
      expect(current.totalCount, 0);
      expect(current.nextCursor, isNull);
    }
    final source = _loaded(container, const SelectDailyChoiceSource());
    expect(source.items.map((item) => item.id), [
      withRest.id,
      withBoth.id,
      withHealth.id,
      untagged.id,
    ]);
    expect(source.items.map(_tagIds), [
      [rest.id],
      [rest.id],
      <TagId>[],
      <TagId>[],
    ]);
    expect(source.totalCount, 4);
    final archived = _loaded(container, searches[4].$1);
    expect(archived.items.map((item) => item.id), [withRest.id, withBoth.id]);
    expect(archived.items.map(_tagIds), [
      [rest.id],
      [rest.id],
    ]);
    expect(archived.totalCount, 2);
    expect(repository.queries, hasLength(queriesBefore));
  });

  test('новый одноимённый тег, назначенный после удаления обязательного, '
      'не восстанавливает соответствие условию', () async {
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
    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );
    confirmedStates.clear();

    final newHealth = Tag(id: _tagId(3), name: health.name);
    const created = TestCatalogRevision(3);
    await completeTagCommand(
      container,
      repository,
      CreateTag(newHealth.name),
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: created,
          value: TagCreated(
            TagCreatedChange(revision: created, after: newHealth),
          ),
        ),
      ),
    );
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: newHealth.id,
      before: testSummary(index: 1),
      after: testSummary(index: 1, tags: [newHealth]),
      revision: const TestCatalogRevision(4),
    );

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.totalCount, 0);
    expect(current.revision, const TestCatalogRevision(4));
    expect(current.selection.tagFilter, filter);
    expect(
      current.selection.tagFilter.requiredTagIds,
      isNot(contains(newHealth.id)),
    );
    expect(
      confirmedStates.every((state) => state is IntentionCatalogEmpty),
      isTrue,
    );
    expect(repository.queries, hasLength(2));
  });

  test('явное снятие условия по удалённому тегу сразу применяет оставшиеся '
      'условия', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: const Duration(hours: 1),
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final withBoth = testSummary(index: 2, tags: [health, rest]);
    final filter = IntentionTagFilter(requiredTagIds: [health.id, rest.id]);
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [withBoth],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    await _completeTagDelete(
      container,
      repository,
      tagId: health.id,
      revision: const TestCatalogRevision(2),
    );
    final emptied = _confirmed(container, browse);
    expect(emptied, isA<IntentionCatalogEmpty>());
    confirmedStates.clear();

    final remaining = IntentionTagFilter(requiredTagIds: [rest.id]);
    container.read(provider.notifier).changeTagFilter(remaining);
    await waitForCatalogQueries(repository, 3);
    final query = repository.queryAt(2);
    expect(query.tagFilter, remaining);
    expect(query.cursor, isNull);
    final withRest = testSummary(index: 2, tags: [rest]);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [withRest],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await container.read(provider.future);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [withRest.id]);
    expect(current.totalCount, 1);
    expect(current.selection.tagFilter, remaining);
    expect(current.query, same(query));
    expect(confirmedStates.last, same(current));
    expect(
      confirmedStates.take(confirmedStates.length - 1),
      everyElement(same(emptied)),
    );
  });

  test('удаление исключённого тега достраивает частично загруженный префикс '
      'без перечитывания порций и сохраняет границу продолжения', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();
    final loadingStates = _observeLoadingStates(container, browse);

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);

    final first = repository.reconciliationQueryAt(0);
    expect(first.catalogQuery, same(before.query));
    expect(
      first.boundary,
      isA<IntentionCatalogPartialPrefixBoundary>().having(
        (boundary) => boundary.continuation,
        'continuation',
        same(before.nextCursor),
      ),
    );
    expect(first.window.storedIntentionIds, [tenth.id, eighth.id]);
    expect(first.cursor, isNull);
    await container
        .read(provider.notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    expect(repository.queries, hasLength(2));

    final twelfth = testSummary(index: 12, tags: [health]);
    final eleventh = testSummary(index: 11, tags: [health]);
    final ninth = testSummary(index: 9, tags: [health]);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        [twelfth, eleventh],
        totalCount: 6,
        nextCursor: const TestReconciliationCursor(),
        revision: 2,
      ),
    );
    await waitForReconciliationQueries(repository, 2);

    final continuation = repository.reconciliationQueryAt(1);
    expect(continuation.catalogQuery, same(before.query));
    expect(continuation.boundary, same(first.boundary));
    expect(
      continuation.window.storedIntentionIds,
      first.window.storedIntentionIds,
    );
    expect(continuation.cursor, isA<TestReconciliationCursor>());
    expect(confirmedStates, isEmpty);
    expect(container.read(provider).requireValue, same(before));

    repository.completeReconciliation(
      1,
      reconciliationContinuationPortion([ninth], revision: 2),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      twelfth.id,
      eleventh.id,
      tenth.id,
      ninth.id,
      eighth.id,
    ]);
    expect(current.totalCount, 6);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(loadingStates, isEmpty);
    expect(repository.queries, hasLength(2));
    expect(repository.reconciliationQueries, hasLength(2));
    expect(repository.tagCommands, hasLength(1));

    final nextRequest = container
        .read(provider.notifier)
        .loadNextPageIfNeeded(visibleIndex: 4);
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(before.nextCursor));
    final fifth = testSummary(index: 5, tags: [health]);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [fifth],
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await nextRequest;

    final completed = _loaded(container, browse);
    expect(completed.items.map((item) => item.id), [
      twelfth.id,
      eleventh.id,
      tenth.id,
      ninth.id,
      eighth.id,
      fifth.id,
    ]);
    expect(completed.totalCount, 6);
    expect(completed.nextCursor, isNull);
  });

  test('удаление исключённого тега дочитывает ранее завершённую выдачу до '
      'нового конца ограниченными порциями', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 2,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();
    final loadingStates = _observeLoadingStates(container, browse);

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);

    final first = repository.reconciliationQueryAt(0);
    expect(first.catalogQuery, same(before.query));
    expect(first.boundary, isA<IntentionCatalogCompletedBoundary>());
    expect(first.window.storedIntentionIds, [tenth.id, eighth.id]);
    final twelfth = testSummary(index: 12, tags: [health]);
    final ninth = testSummary(index: 9, tags: [health]);
    final third = testSummary(index: 3, tags: [health]);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        [twelfth, ninth],
        totalCount: 5,
        nextCursor: const TestReconciliationCursor(),
        revision: 2,
      ),
    );
    await waitForReconciliationQueries(repository, 2);
    expect(confirmedStates, isEmpty);
    repository.completeReconciliation(
      1,
      reconciliationContinuationPortion([third], revision: 2),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      twelfth.id,
      tenth.id,
      ninth.id,
      eighth.id,
      third.id,
    ]);
    expect(current.totalCount, 5);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(loadingStates, isEmpty);
    expect(repository.queries, hasLength(2));
  });

  for (final (name, missing) in [
    (
      'открывает совпадения',
      [
        testSummary(index: 4, tags: [health]),
      ],
    ),
    ('оставляет выдачу пустой', <IntentionSummary>[]),
  ]) {
    test('удаление исключённого тега в пустой выдаче $name', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final confirmedStates = _observeConfirmedStates(container, browse);
      final filter = IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      );
      await _loadFiltered(
        container,
        repository,
        browse,
        filter,
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      );
      final before = _confirmed(container, browse) as IntentionCatalogEmpty;
      confirmedStates.clear();

      await _completeTagDelete(
        container,
        repository,
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      );
      await waitForReconciliationQueries(repository, 1);

      final query = repository.reconciliationQueryAt(0);
      expect(query.catalogQuery, same(before.query));
      expect(query.boundary, isA<IntentionCatalogCompletedBoundary>());
      expect(query.window.storedIntentionIds, isEmpty);
      expect(confirmedStates, isEmpty);
      repository.completeReconciliation(
        0,
        reconciliationFirstPortion(
          missing,
          totalCount: missing.length,
          revision: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _confirmed(container, browse);
      expect(current.query, same(before.query));
      expect(current.selection.tagFilter, filter);
      expect(current.totalCount, missing.length);
      expect(current.nextCursor, isNull);
      expect(current.revision, const TestCatalogRevision(2));
      expect(switch (current) {
        IntentionCatalogLoaded(:final items) => items.map((item) => item.id),
        IntentionCatalogEmpty() => <IntentionId>[],
      }, missing.map((item) => item.id));
      expect(
        current,
        missing.isEmpty
            ? isA<IntentionCatalogEmpty>()
            : isA<IntentionCatalogLoaded>(),
      );
      expect(confirmedStates, [same(current)]);
      expect(repository.queries, hasLength(2));
    });
  }

  test('удаление тега из обоих наборов оставляет успешный пустой результат '
      'без чтения согласования', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final filter = IntentionTagFilter(
      requiredTagIds: [rest.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _confirmed(container, browse);
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.totalCount, 0);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(repository.reconciliationQueries, isEmpty);
    expect(repository.queries, hasLength(2));
  });

  test('пакеты, подтверждённые во время согласования, объединяются и '
      'применяются последовательно к согласованному содержимому', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final sport = Tag(id: _tagId(3), name: TagName.fromInput('Спорт'));
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id, sport.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 2,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: tenth,
      after: testSummary(index: 10),
      revision: const TestCatalogRevision(3),
    );
    await _completeTagDelete(
      container,
      repository,
      tagId: sport.id,
      revision: const TestCatalogRevision(4),
    );
    expect(repository.reconciliationQueries, hasLength(1));
    expect(confirmedStates, isEmpty);

    final ninth = testSummary(index: 9, tags: [health]);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion([ninth], totalCount: 3, revision: 2),
    );
    await waitForReconciliationQueries(repository, 2);

    final merged = repository.reconciliationQueryAt(1);
    expect(merged.catalogQuery, same(before.query));
    expect(merged.boundary, isA<IntentionCatalogCompletedBoundary>());
    expect(merged.window.storedIntentionIds, [ninth.id, eighth.id]);
    expect(merged.cursor, isNull);
    expect(confirmedStates, isEmpty);
    final seventh = testSummary(index: 7, tags: [health]);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion([seventh], totalCount: 3, revision: 4),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      ninth.id,
      eighth.id,
      seventh.id,
    ]);
    expect(current.totalCount, 3);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(4));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test('чтение согласования более новой ревизии ждёт её пакет и повторяется '
      'для обновлённого содержимого', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final tenth = testSummary(index: 10, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [tenth],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    final renamed = Tag(id: health.id, name: TagName.fromInput('Самочувствие'));
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        [
          testSummary(index: 9, tags: [renamed]),
        ],
        totalCount: 2,
        revision: 3,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(repository.reconciliationQueries, hasLength(1));
    expect(confirmedStates, isEmpty);

    await _completeTagRename(
      container,
      repository,
      before: health,
      after: renamed,
      revision: const TestCatalogRevision(3),
    );
    await waitForReconciliationQueries(repository, 2);

    final repeated = repository.reconciliationQueryAt(1);
    expect(repeated.catalogQuery, same(before.query));
    expect(repeated.window.storedIntentionIds, [tenth.id]);
    expect(repeated.cursor, isNull);
    expect(confirmedStates, isEmpty);
    final ninth = testSummary(index: 9, tags: [renamed]);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion([ninth], totalCount: 2, revision: 3),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [tenth.id, ninth.id]);
    expect(current.items.map(_tagNames), [
      ['Самочувствие'],
      ['Самочувствие'],
    ]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(3));
    expect(current.query, same(before.query));
    expect(confirmedStates, [same(current)]);
  });

  test('первая порция, прочитанная до удаления исключённого тега, '
      'достраивается чтением согласования', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await waitForCatalogQueries(repository, 1);
    repository.complete(0, _emptyPage(0));
    await container.read(provider.future);
    container.read(provider.notifier).changeTagFilter(filter);
    await waitForCatalogQueries(repository, 2);
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    final tenth = testSummary(index: 10, tags: [health]);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [tenth],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    final first =
        await container.read(provider.future) as IntentionCatalogLoaded;
    expect(first.revision, const TestCatalogRevision(1));
    await waitForReconciliationQueries(repository, 1);
    confirmedStates.clear();

    final query = repository.reconciliationQueryAt(0);
    expect(query.catalogQuery, same(first.query));
    expect(query.boundary, isA<IntentionCatalogCompletedBoundary>());
    expect(query.window.storedIntentionIds, [tenth.id]);
    final ninth = testSummary(index: 9, tags: [health]);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion([ninth], totalCount: 2, revision: 2),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [tenth.id, ninth.id]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(first.query));
    expect(confirmedStates, [same(current)]);
    expect(repository.queries, hasLength(2));
  });

  test(
    'смена условий во время согласования отбрасывает его позднее чтение',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final confirmedStates = _observeConfirmedStates(container, browse);
      final provider = intentionCatalogViewModelProvider(browse);
      final tenth = testSummary(index: 10, tags: [health]);
      await _loadFiltered(
        container,
        repository,
        browse,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [rest.id],
        ),
        IntentionCatalogFirstPage(
          items: [tenth],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      );
      await _completeTagDelete(
        container,
        repository,
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      );
      await waitForReconciliationQueries(repository, 1);

      final replacement = IntentionTagFilter(requiredTagIds: [health.id]);
      container.read(provider.notifier).changeTagFilter(replacement);
      await waitForCatalogQueries(repository, 3);
      final ninth = testSummary(index: 9, tags: [health]);
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [tenth],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      final replaced =
          await container.read(provider.future) as IntentionCatalogLoaded;
      confirmedStates.clear();
      repository.completeReconciliation(
        0,
        reconciliationFirstPortion([ninth], totalCount: 2, revision: 2),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(provider).requireValue, same(replaced));
      expect(replaced.selection.tagFilter, replacement);
      expect(confirmedStates, isEmpty);
      expect(repository.reconciliationQueries, hasLength(1));
    },
  );

  for (final (name, failRead, refresh)
      in <
        (String, void Function(ControlledCatalogRepository repository), Matcher)
      >[
        (
          'недоступность хранилища',
          (repository) => repository.completeReconciliation(
            0,
            const ResultFailure(IntentionUnavailableFailure()),
          ),
          isA<IntentionCatalogRefreshUnavailable>(),
        ),
        (
          'повреждение данных',
          (repository) => repository.completeReconciliation(
            0,
            const ResultFailure(IntentionCorruptionFailure()),
          ),
          isA<IntentionCatalogRefreshCorruption>(),
        ),
        (
          'недопустимый ввод',
          (repository) => repository.completeReconciliation(
            0,
            const ResultFailure(IntentionGenericValidationFailure()),
          ),
          isA<IntentionCatalogRefreshUnexpected>(),
        ),
        (
          'исключение',
          (repository) => repository.failReconciliation(
            0,
            StateError('Контролируемый отказ согласования.'),
          ),
          isA<IntentionCatalogRefreshUnexpected>(),
        ),
        (
          'порция больше размера порции запроса',
          (repository) => repository.completeReconciliation(
            0,
            reconciliationFirstPortion(
              [
                testSummary(index: 13, tags: [health]),
                testSummary(index: 12, tags: [health]),
                testSummary(index: 11, tags: [health]),
              ],
              totalCount: 6,
              revision: 2,
            ),
          ),
          isA<IntentionCatalogRefreshUnexpected>(),
        ),
      ]) {
    test('отказ чтения согласования ($name) сохраняет загруженный префикс с '
        'явным отказом обновления, а следующий подтверждённый пакет сам '
        'повторяет чтение на актуальной ревизии', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 0,
      );
      final confirmedStates = _observeConfirmedStates(container, browse);
      final provider = intentionCatalogViewModelProvider(browse);
      final model = container.read(provider.notifier);
      final tenth = testSummary(index: 10, tags: [health]);
      final eighth = testSummary(index: 8, tags: [health]);
      final filter = IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      );
      await _loadFiltered(
        container,
        repository,
        browse,
        filter,
        IntentionCatalogFirstPage(
          items: [tenth, eighth],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      );
      final before = _loaded(container, browse);
      expect(before.refresh, isA<IntentionCatalogRefreshIdle>());
      confirmedStates.clear();
      final loadingStates = _observeLoadingStates(container, browse);

      await _completeTagDelete(
        container,
        repository,
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      );
      await waitForReconciliationQueries(repository, 1);
      failRead(repository);
      await Future<void>.delayed(Duration.zero);

      final failed = _loaded(container, browse);
      expect(failed.items, before.items);
      expect(failed.totalCount, 3);
      expect(failed.nextCursor, same(before.nextCursor));
      expect(failed.revision, const TestCatalogRevision(1));
      expect(failed.query, same(before.query));
      expect(failed.selection.tagFilter, filter);
      expect(failed.continuation, isA<IntentionCatalogContinuationIdle>());
      expect(failed.refresh, refresh);
      expect(confirmedStates, [same(failed)]);
      expect(loadingStates, isEmpty);
      expect(repository.queries, hasLength(2));
      expect(repository.reconciliationQueries, hasLength(1));

      // Граница не сдвигается, пока область не согласована.
      await model.loadNextPageIfNeeded(visibleIndex: 1);
      expect(repository.queries, hasLength(2));

      // Подтверждённый после отказа пакет применяется к сохранённому
      // содержимому и сам запускает одно новое чтение той же области.
      final renamed = Tag(
        id: health.id,
        name: TagName.fromInput('Самочувствие'),
      );
      await _completeTagRename(
        container,
        repository,
        before: health,
        after: renamed,
        revision: const TestCatalogRevision(3),
      );
      await waitForReconciliationQueries(repository, 2);
      final retrying = _loaded(container, browse);
      expect(retrying.refresh, isA<IntentionCatalogRefreshIdle>());
      expect(retrying.items, before.items);
      expect(retrying.revision, const TestCatalogRevision(1));
      expect(retrying.query, same(before.query));
      await model.retryRefresh();
      expect(repository.reconciliationQueries, hasLength(2));

      final repeated = repository.reconciliationQueryAt(1);
      expect(repeated.catalogQuery, same(before.query));
      expect(
        repeated.boundary,
        isA<IntentionCatalogPartialPrefixBoundary>().having(
          (boundary) => boundary.continuation,
          'continuation',
          same(before.nextCursor),
        ),
      );
      expect(repeated.window.storedIntentionIds, [tenth.id, eighth.id]);
      expect(repeated.cursor, isNull);
      final ninth = testSummary(index: 9, tags: [renamed]);
      repository.completeReconciliation(
        1,
        reconciliationFirstPortion([ninth], totalCount: 4, revision: 3),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _loaded(container, browse);
      expect(current.items.map((item) => item.id), [
        tenth.id,
        ninth.id,
        eighth.id,
      ]);
      expect(current.items.map(_tagNames), [
        ['Самочувствие'],
        ['Самочувствие'],
        ['Самочувствие'],
      ]);
      expect(current.totalCount, 4);
      expect(current.nextCursor, same(before.nextCursor));
      expect(current.revision, const TestCatalogRevision(3));
      expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
      expect(current.query, same(before.query));
      expect(current.selection.tagFilter, filter);
      expect(confirmedStates, [same(failed), same(retrying), same(current)]);
      expect(loadingStates, isEmpty);
      expect(repository.queries, hasLength(2));

      unawaited(model.loadNextPageIfNeeded(visibleIndex: 2));
      await waitForCatalogQueries(repository, 3);
      expect(repository.queryAt(2).cursor, same(before.nextCursor));
    });
  }

  test('отказ согласования пустой выдачи не выдаётся за успешную пустоту '
      'и не снимает условие', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = _observeConfirmedStates(container, browse);
    final model = container.read(
      intentionCatalogViewModelProvider(browse).notifier,
    );
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _confirmed(container, browse) as IntentionCatalogEmpty;
    confirmedStates.clear();

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);

    final failed = _confirmed(container, browse);
    expect(failed, isA<IntentionCatalogEmpty>());
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());
    expect(failed.revision, const TestCatalogRevision(1));
    expect(failed.query, same(before.query));
    expect(failed.selection.tagFilter, filter);
    expect(confirmedStates, [same(failed)]);

    final retry = model.retryRefresh();
    await waitForReconciliationQueries(repository, 2);
    expect(
      repository.reconciliationQueryAt(1).catalogQuery,
      same(before.query),
    );
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(const [], totalCount: 0, revision: 2),
    );
    await retry;

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(repository.queries, hasLength(2));
  });

  test('смена условий после отказа согласования отменяет его повтор', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final model = container.read(provider.notifier);
    final tenth = testSummary(index: 10, tags: [health]);
    await _loadFiltered(
      container,
      repository,
      browse,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
      IntentionCatalogFirstPage(
        items: [tenth],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);

    final replacement = IntentionTagFilter(requiredTagIds: [health.id]);
    model.changeTagFilter(replacement);
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).tagFilter, replacement);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [tenth],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    final replaced =
        await container.read(provider.future) as IntentionCatalogLoaded;
    expect(replaced.refresh, isA<IntentionCatalogRefreshIdle>());

    await model.retryRefresh();
    expect(repository.reconciliationQueries, hasLength(1));
    expect(container.read(provider).requireValue, same(replaced));
  });

  test('без нового пакета отказ согласования не повторяет чтение, а явный '
      'повтор запускает то же чтение области', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final model = container.read(provider.notifier);
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    await _loadFiltered(
      container,
      repository,
      browse,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);
    final failed = _loaded(container, browse);
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());

    // Повтора по таймеру нет: без пакета и явного повтора чтений нет.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repository.reconciliationQueries, hasLength(1));
    expect(container.read(provider).requireValue, same(failed));

    final retry = model.retryRefresh();
    await waitForReconciliationQueries(repository, 2);
    final repeated = repository.reconciliationQueryAt(1);
    expect(repeated.catalogQuery, same(before.query));
    expect(repeated.window.storedIntentionIds, [tenth.id, eighth.id]);
    expect(repeated.cursor, isNull);
    final eleventh = testSummary(index: 11, tags: [health]);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion([eleventh], totalCount: 4, revision: 2),
    );
    await retry;

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      eleventh.id,
      tenth.id,
      eighth.id,
    ]);
    expect(current.totalCount, 4);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(current.query, same(before.query));
    expect(repository.reconciliationQueries, hasLength(2));
  });

  test('подтверждённое назначение после отказа согласования само повторяет '
      'чтение области, а пакеты во время повтора ждут очереди без '
      'параллельных чтений', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final model = container.read(provider.notifier);
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();
    final loadingStates = _observeLoadingStates(container, browse);
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);
    final failed = _loaded(container, browse);
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());

    // Назначение вне загруженной части увеличивает количество области и
    // сразу запускает одно новое чтение на ревизии этого пакета.
    final seventh = testSummary(index: 7, tags: [health]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: health.id,
      before: testSummary(index: 7),
      after: seventh,
      revision: const TestCatalogRevision(3),
    );
    await waitForReconciliationQueries(repository, 2);
    final retrying = _loaded(container, browse);
    expect(retrying.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(retrying.items, before.items);
    expect(retrying.totalCount, 3);
    expect(retrying.revision, const TestCatalogRevision(1));
    expect(retrying.query, same(before.query));
    final repeated = repository.reconciliationQueryAt(1);
    expect(repeated.catalogQuery, same(before.query));
    expect(
      repeated.boundary,
      isA<IntentionCatalogPartialPrefixBoundary>().having(
        (boundary) => boundary.continuation,
        'continuation',
        same(before.nextCursor),
      ),
    );
    expect(repeated.window.storedIntentionIds, [tenth.id, eighth.id]);

    // Пакет, подтверждённый во время повтора, ставится в очередь.
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: eighth,
      after: testSummary(index: 8),
      revision: const TestCatalogRevision(4),
    );
    await model.retryRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(repository.reconciliationQueries, hasLength(2));
    expect(container.read(provider).requireValue, same(retrying));

    final eleventh = testSummary(index: 11, tags: [health]);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion([eleventh], totalCount: 5, revision: 3),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [eleventh.id, tenth.id]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.revision, const TestCatalogRevision(4));
    expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
    expect(current.query, same(before.query));
    expect(current.selection.tagFilter, filter);
    expect(confirmedStates, [same(failed), same(retrying), same(current)]);
    expect(loadingStates, isEmpty);
    expect(repository.reconciliationQueries, hasLength(2));
    expect(repository.queries, hasLength(2));

    // После согласования снова доступно обычное продолжение.
    unawaited(model.loadNextPageIfNeeded(visibleIndex: 1));
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(before.nextCursor));
  });

  test('очередной отказ автоматического повтора публикует отказ поверх того '
      'же содержимого, а следующий пакет снова повторяет чтение', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final model = container.read(provider.notifier);
    final tenth = testSummary(index: 10, tags: [health]);
    final eighth = testSummary(index: 8, tags: [health]);
    await _loadFiltered(
      container,
      repository,
      browse,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
      IntentionCatalogFirstPage(
        items: [tenth, eighth],
        totalCount: 3,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final before = _loaded(container, browse);
    confirmedStates.clear();
    final loadingStates = _observeLoadingStates(container, browse);
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);
    final failed = _loaded(container, browse);

    final renamed = Tag(id: health.id, name: TagName.fromInput('Самочувствие'));
    await _completeTagRename(
      container,
      repository,
      before: health,
      after: renamed,
      revision: const TestCatalogRevision(3),
    );
    await waitForReconciliationQueries(repository, 2);
    final retrying = _loaded(container, browse);
    expect(retrying.refresh, isA<IntentionCatalogRefreshIdle>());
    repository.completeReconciliation(
      1,
      const ResultFailure(IntentionCorruptionFailure()),
    );
    await Future<void>.delayed(Duration.zero);

    final failedAgain = _loaded(container, browse);
    expect(failedAgain.refresh, isA<IntentionCatalogRefreshCorruption>());
    expect(failedAgain.items, before.items);
    expect(failedAgain.totalCount, 3);
    expect(failedAgain.nextCursor, same(before.nextCursor));
    expect(failedAgain.revision, const TestCatalogRevision(1));
    expect(failedAgain.query, same(before.query));
    expect(confirmedStates, [same(failed), same(retrying), same(failedAgain)]);
    await model.loadNextPageIfNeeded(visibleIndex: 1);
    expect(repository.queries, hasLength(2));
    expect(repository.reconciliationQueries, hasLength(2));

    final seventh = testSummary(index: 7, tags: [renamed]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: health.id,
      before: testSummary(index: 7),
      after: seventh,
      revision: const TestCatalogRevision(4),
    );
    await waitForReconciliationQueries(repository, 3);
    expect(repository.reconciliationQueryAt(2).window.storedIntentionIds, [
      tenth.id,
      eighth.id,
    ]);
    final eleventh = testSummary(index: 11, tags: [renamed]);
    repository.completeReconciliation(
      2,
      reconciliationFirstPortion([eleventh], totalCount: 5, revision: 4),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      eleventh.id,
      tenth.id,
      eighth.id,
    ]);
    expect(current.items.map(_tagNames), [
      ['Самочувствие'],
      ['Самочувствие'],
      ['Самочувствие'],
    ]);
    expect(current.totalCount, 5);
    expect(current.revision, const TestCatalogRevision(4));
    expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(current.query, same(before.query));
    expect(loadingStates, isEmpty);
    expect(repository.reconciliationQueries, hasLength(3));
  });

  test('смена условий во время автоматического повтора отменяет его, а '
      'последующие пакеты согласуются без чтения прежней области', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    final provider = intentionCatalogViewModelProvider(browse);
    final model = container.read(provider.notifier);
    final tenth = testSummary(index: 10, tags: [health]);
    await _loadFiltered(
      container,
      repository,
      browse,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
      IntentionCatalogFirstPage(
        items: [tenth],
        totalCount: 1,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForReconciliationQueries(repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await Future<void>.delayed(Duration.zero);
    final renamed = Tag(id: health.id, name: TagName.fromInput('Самочувствие'));
    await _completeTagRename(
      container,
      repository,
      before: health,
      after: renamed,
      revision: const TestCatalogRevision(3),
    );
    await waitForReconciliationQueries(repository, 2);

    final replacement = IntentionTagFilter(requiredTagIds: [health.id]);
    model.changeTagFilter(replacement);
    await waitForCatalogQueries(repository, 3);
    final renamedTenth = testSummary(index: 10, tags: [renamed]);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [renamedTenth],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(3),
        ),
      ),
    );
    final replaced =
        await container.read(provider.future) as IntentionCatalogLoaded;
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(
        [
          testSummary(index: 11, tags: [renamed]),
        ],
        totalCount: 2,
        revision: 3,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).requireValue, same(replaced));
    expect(replaced.selection.tagFilter, replacement);
    expect(replaced.refresh, isA<IntentionCatalogRefreshIdle>());

    final ninth = testSummary(index: 9, tags: [renamed]);
    await completeIntentionTagAssignment(
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: health.id,
      before: testSummary(index: 9),
      after: ninth,
      revision: const TestCatalogRevision(4),
    );
    await model.retryRefresh();

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [tenth.id, ninth.id]);
    expect(current.totalCount, 2);
    expect(current.revision, const TestCatalogRevision(4));
    expect(current.query, same(replaced.query));
    expect(repository.reconciliationQueries, hasLength(2));
    expect(repository.queries, hasLength(3));
  });

  /// Загружает выдачу с условиями по тегам до конца порциями по две строки.
  Future<IntentionCatalogLoaded> loadCompletedArea(
    ProviderContainer container,
    ControlledCatalogRepository repository,
    IntentionTagFilter filter,
    List<List<IntentionSummary>> pages,
  ) async {
    await _loadFiltered(
      container,
      repository,
      browse,
      filter,
      IntentionCatalogFirstPage(
        items: pages.first,
        totalCount: pages.expand((page) => page).length,
        nextCursor: const TestCatalogCursor(),
        revision: const TestCatalogRevision(1),
      ),
    );
    final model = container.read(
      intentionCatalogViewModelProvider(browse).notifier,
    );
    for (var index = 1; index < pages.length; index++) {
      final loaded = _loaded(container, browse);
      final request = model.loadNextPageIfNeeded(
        visibleIndex: loaded.items.length - 1,
      );
      await waitForCatalogQueries(repository, index + 2);
      repository.complete(
        index + 1,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: pages[index],
            nextCursor: index == pages.length - 1
                ? null
                : const TestCatalogCursor(),
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await request;
    }
    return _loaded(container, browse);
  }

  test('удаление исключённого тега сдвигает окно сохранённых строк не больше '
      'порции по ранее завершённой выдаче в несколько окон', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    final confirmedStates = _observeConfirmedStates(container, browse);
    IntentionSummary row(int index) =>
        testSummary(index: index, tags: [health]);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    final before = await loadCompletedArea(container, repository, filter, [
      [row(10), row(8)],
      [row(6), row(4)],
      [row(2)],
    ]);
    expect(before.nextCursor, isNull);
    confirmedStates.clear();
    final loadingStates = _observeLoadingStates(container, browse);
    final catalogReads = repository.queries.length;
    const cursors = [_WindowCursor(1), _WindowCursor(2), _WindowCursor(3)];

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );

    // Внутреннее окно: заполненная порция перед его краем и строка перед
    // первой сохранённой строкой.
    await waitForReconciliationQueries(repository, 1);
    final first = repository.reconciliationQueryAt(0);
    expect(first.catalogQuery, same(before.query));
    expect(first.boundary, isA<IntentionCatalogCompletedBoundary>());
    expect(first.window, isA<IntentionCatalogInnerReconciliationWindow>());
    expect(first.window.storedIntentionIds, [row(10).id, row(8).id]);
    expect(first.cursor, isNull);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        [row(11), row(9)],
        totalCount: 11,
        nextCursor: cursors[0],
        revision: 2,
      ),
    );

    // После заполненной порции окно начинается с сохранённых строк после её
    // последней строки; незаполненная порция доходит до края окна.
    await waitForReconciliationQueries(repository, 2);
    final second = repository.reconciliationQueryAt(1);
    expect(second.window, isA<IntentionCatalogInnerReconciliationWindow>());
    expect(second.window.storedIntentionIds, [row(8).id, row(6).id]);
    expect(second.cursor, same(cursors[0]));
    repository.completeReconciliation(
      1,
      reconciliationContinuationPortion(
        [row(7)],
        nextCursor: cursors[1],
        revision: 2,
      ),
    );

    // Совпадение сразу после края прежнего окна читает следующее окно,
    // содержащее последнюю сохранённую строку области.
    await waitForReconciliationQueries(repository, 3);
    final third = repository.reconciliationQueryAt(2);
    expect(third.window, isA<IntentionCatalogFinalReconciliationWindow>());
    expect(third.window.storedIntentionIds, [row(4).id, row(2).id]);
    expect(third.cursor, same(cursors[1]));
    repository.completeReconciliation(
      2,
      reconciliationContinuationPortion(
        [row(5), row(3)],
        nextCursor: cursors[2],
        revision: 2,
      ),
    );

    await waitForReconciliationQueries(repository, 4);
    final fourth = repository.reconciliationQueryAt(3);
    expect(fourth.window, isA<IntentionCatalogFinalReconciliationWindow>());
    expect(fourth.window.storedIntentionIds, [row(2).id]);
    expect(fourth.cursor, same(cursors[2]));
    expect(confirmedStates, isEmpty);
    repository.completeReconciliation(
      3,
      reconciliationContinuationPortion([row(1)], revision: 2),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [
      for (var index = 11; index >= 1; index--) row(index).id,
    ]);
    expect(current.totalCount, 11);
    expect(current.nextCursor, isNull);
    expect(current.revision, const TestCatalogRevision(2));
    expect(current.query, same(before.query));
    expect(confirmedStates, [same(current)]);
    expect(loadingStates, isEmpty);
    expect(repository.reconciliationQueries, hasLength(4));
    expect(
      repository.reconciliationQueries.map(
        (query) => query.window.storedRows.length,
      ),
      everyElement(lessThanOrEqualTo(2)),
    );
    expect(repository.queries, hasLength(catalogReads));
  });

  for (final (name, portion) in [
    (
      'за верхним краем внутреннего окна',
      (IntentionSummary Function(int) row) => [row(7)],
    ),
    (
      'не по возрастанию в действующем порядке',
      (IntentionSummary Function(int) row) => [row(9), row(11)],
    ),
  ]) {
    test('порция согласования $name — непредвиденный отказ обновления '
        'без замены подтверждённого содержимого', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 0,
      );
      final confirmedStates = _observeConfirmedStates(container, browse);
      IntentionSummary row(int index) =>
          testSummary(index: index, tags: [health]);
      final filter = IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      );
      final before = await loadCompletedArea(container, repository, filter, [
        [row(10), row(8)],
        [row(6)],
      ]);
      confirmedStates.clear();

      await _completeTagDelete(
        container,
        repository,
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      );
      await waitForReconciliationQueries(repository, 1);
      expect(
        repository.reconciliationQueryAt(0).window,
        isA<IntentionCatalogInnerReconciliationWindow>(),
      );
      repository.completeReconciliation(
        0,
        reconciliationFirstPortion(
          portion(row),
          totalCount: 5,
          nextCursor: const _WindowCursor(1),
          revision: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _loaded(container, browse);
      expect(current.items, before.items);
      expect(current.totalCount, before.totalCount);
      expect(current.revision, before.revision);
      expect(current.query, same(before.query));
      expect(current.refresh, isA<IntentionCatalogRefreshUnexpected>());
      expect(repository.reconciliationQueries, hasLength(1));
    });
  }
}

/// Собирает состояния загрузки, которые сбросили бы позицию просмотра.
List<AsyncValue<IntentionCatalogState>> _observeLoadingStates(
  ProviderContainer container,
  IntentionCatalogPurpose purpose,
) {
  final loadingStates = <AsyncValue<IntentionCatalogState>>[];
  final subscription = container.listen(
    intentionCatalogViewModelProvider(purpose),
    (_, next) {
      if (next.isLoading) {
        loadingStates.add(next);
      }
    },
  );
  addTearDown(subscription.close);
  return loadingStates;
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

/// Проводит подтверждённое физическое удаление тега через coordinator.
Future<void> _completeTagDelete(
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required TagId tagId,
  required GraphRevision revision,
}) async {
  await completeTagCommand(
    container,
    repository,
    DeleteTag(tagId),
    tagDeletionSuccess(tagId: tagId, revision: revision),
  );
}

final class _WindowCursor implements IntentionCatalogReconciliationCursor {
  const _WindowCursor(this.number);

  final int number;
}
