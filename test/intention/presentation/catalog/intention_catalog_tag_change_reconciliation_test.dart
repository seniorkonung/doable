import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';
import '../../../support/tag_positions.dart';

final _actionSearchPurpose = SelectDailyChoiceAction(
  session: IntentionSearchSession(),
);
final _sourceSearchPurpose = SelectDailyChoiceSource(
  session: IntentionSearchSession(),
);

void main() {
  final health = Tag(
    id: _tagId(1),
    name: TagName.fromInput('Здоровье'),
    color: null,
    position: tagPositionAt(1000),
  );
  final rest = Tag(
    id: _tagId(2),
    name: TagName.fromInput('Отдых'),
    color: null,
    position: tagPositionAt(1001),
  );
  const browse = BrowseIntentionCatalog();

  test('снятие обязательного тега исключает намерение и уменьшает количество на один', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
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
    expect(current.selection.tagFilter, filter);
    expect(current.selection.order, before.selection.order);
    expect(current.selection.scope, before.selection.scope);
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
    _observeConfirmedStates(container, browse);
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
  });

  test('назначение внутри полностью загруженной выдачи ставит намерение на его '
      'позицию и увеличивает количество один раз', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
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
      expect(empty.selection.tagFilter, filter);
    },
  );

  test(
    'назначения поиска согласуют один пакет тега по собственным условиям',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      final action = _actionSearchPurpose;
      final source = _sourceSearchPurpose;
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
  });

  test('изменение только цвета заменяет тег в загруженных строках и '
      'сохраняет условие, состав, количество и продолжение', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
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

    final blueHealth = Tag(
      id: health.id,
      name: health.name,
      color: TagColor.blue,
      position: health.position,
    );
    await _completeTagUpdate(
      container,
      repository,
      before: health,
      after: blueHealth,
      revision: const TestCatalogRevision(2),
    );

    final current = _loaded(container, browse);
    expect(current.items.map((item) => item.id), [fourth.id, third.id]);
    expect(current.items.map(_tagStates), [
      [(health.id, 'Здоровье', TagColor.blue), (rest.id, 'Отдых', null)],
      [(health.id, 'Здоровье', TagColor.blue)],
    ]);
    for (final (index, item) in current.items.indexed) {
      expect(item.createdAt.value, before.items[index].createdAt.value);
      expect(item.updatedAt.value, before.items[index].updatedAt.value);
    }
    expect(current.totalCount, 3);
    expect(current.nextCursor, same(before.nextCursor));
    expect(current.selection.tagFilter, filter);
    expect(repository.queries, hasLength(2));

    final loading = container
        .read(intentionCatalogViewModelProvider(browse).notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(before.nextCursor));
    expect(repository.queryAt(2).tagFilter, filter);
    final second = testSummary(index: 2, tags: [blueHealth]);
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

  test('первая порция, прочитанная до изменения тега, публикуется с новыми '
      'названием и цветом', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    _observeConfirmedStates(container, browse);
    await waitForCatalogQueries(repository, 1);

    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
      color: TagColor.blue,
      position: health.position,
    );
    await _completeTagUpdate(
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
    expect(current.items.map(_tagStates), [
      [(health.id, 'Самочувствие', TagColor.blue)],
    ]);
    expect(current.totalCount, 1);
  });

  test('новый тег с прежним названием не подменяет условие и не меняет '
      'состав и количество', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
    final wellBeing = Tag(
      id: health.id,
      name: TagName.fromInput('Самочувствие'),
      color: health.color,
      position: health.position,
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

    final newHealth = Tag(
      id: _tagId(3),
      name: health.name,
      color: null,
      position: tagPositionAt(1002),
    );
    const revision = TestCatalogRevision(2);
    await completeTagCommand(
      container,
      repository,
      CreateTag(
        name: newHealth.name,
        color: null,
        placement: TagPlacement.first,
      ),
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
    expect(current.selection.tagFilter, filter);
    expect(
      current.selection.tagFilter.requiredTagIds,
      isNot(contains(newHealth.id)),
    );
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
      UpdateTag(tagId: health.id, name: health.name, color: health.color),
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

    final current = _loaded(container, browse);
    expect(current.items, before.items);
    expect(current.totalCount, 1);
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
    _observeConfirmedStates(container, browse);
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
    expect(current.selection.tagFilter, filter);
    expect(current.query.tagFilter.requiredTagIds, [health.id]);
  });

  test('удаление обязательного тега во время продолжения не возвращает '
      'прежние совпадения из запоздалой порции', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
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

    final current = _confirmed(container, browse);
    expect(current, isA<IntentionCatalogEmpty>());
    expect(current.totalCount, 0);
    expect(current.selection.tagFilter, filter);
  });

  test('удаление тега вне условий убирает его из загруженных строк и '
      'сохраняет состав, количество, порядок и продолжение', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
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
    expect(current.selection.tagFilter, filter);
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

    final newHealth = Tag(
      id: _tagId(3),
      name: health.name,
      color: null,
      position: tagPositionAt(1003),
    );
    const created = TestCatalogRevision(3);
    await completeTagCommand(
      container,
      repository,
      CreateTag(
        name: newHealth.name,
        color: null,
        placement: TagPlacement.first,
      ),
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
    expect(current.selection.tagFilter, filter);
    expect(
      current.selection.tagFilter.requiredTagIds,
      isNot(contains(newHealth.id)),
    );
    expect(
      confirmedStates.every((state) => state is IntentionCatalogEmpty),
      isTrue,
    );
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
    expect(
      confirmedStates.take(confirmedStates.length - 1),
      everyElement(isA<IntentionCatalogEmpty>()),
    );
  });

  test('удаление исключённого тега начинает новую выдачу одним чтением '
      'первой порции, и она показывает прежде отсечённые намерения', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 2,
      prefetchRemaining: 0,
    );
    _observeConfirmedStates(container, browse);
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

    await _completeTagDelete(
      container,
      repository,
      tagId: rest.id,
      revision: const TestCatalogRevision(2),
    );
    await waitForCatalogQueries(repository, 3);

    final query = repository.queryAt(2);
    expect(query.tagFilter, filter);
    expect(query.cursor, isNull);
    final eleventh = testSummary(index: 11, tags: [health]);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [eleventh, tenth],
          totalCount: 5,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    final current =
        await container.read(provider.future) as IntentionCatalogLoaded;

    expect(current.items.map((item) => item.id), [eleventh.id, tenth.id]);
    expect(current.totalCount, 5);
    expect(current.selection.tagFilter, filter);
    await Future<void>.delayed(Duration.zero);
    expect(repository.queries, hasLength(3));
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

/// Проводит подтверждённое редактирование тега через coordinator.
Future<void> _completeTagUpdate(
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required Tag before,
  required Tag after,
  required GraphRevision revision,
}) async {
  await completeTagCommand(
    container,
    repository,
    UpdateTag(tagId: before.id, name: after.name, color: after.color),
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: TagUpdated(
          TagUpdatedChange(revision: revision, before: before, after: after),
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

List<(TagId, String, TagColor?)> _tagStates(IntentionSummary summary) => [
  for (final tag in summary.tags) (tag.id, tag.name.value, tag.color),
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
