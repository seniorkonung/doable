import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart';
import 'package:doable/src/intention/presentation/operation/intention_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';

void main() {
  test(
    'запрашивает подтверждённую первую страницу с начальными параметрами',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      expect(
        container.read(intentionCatalogViewModelProvider),
        isA<AsyncLoading<IntentionCatalogState>>(),
      );
      final query = repository.queryAt(0);
      expect(query.scope, IntentionScope.active);
      expect(query.titleFilter, isNull);
      expect(query.order, IntentionCatalogOrder.createdAtDescending);
      expect(query.pageSize, 100);
      expect(query.cursor, isNull);

      const cursor = TestCatalogCursor();
      const revision = TestCatalogRevision(4);
      final summaries = [
        testSummary(index: 1, title: 'Первое'),
        testSummary(index: 2, title: 'Второе'),
      ];
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: summaries,
            totalCount: 7,
            nextCursor: cursor,
            revision: revision,
          ),
        ),
      );

      final state = await container.read(
        intentionCatalogViewModelProvider.future,
      );
      expect(
        state,
        isA<IntentionCatalogLoaded>()
            .having((value) => value.query, 'запрос', same(query))
            .having((value) => value.items, 'элементы', summaries)
            .having((value) => value.totalCount, 'точное количество', 7)
            .having((value) => value.nextCursor, 'курсор', same(cursor))
            .having((value) => value.revision, 'ревизия', same(revision)),
      );
    },
  );

  test('отличает пустой активный каталог от ошибки', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);
    const revision = TestCatalogRevision(0);

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: revision,
        ),
      ),
    );

    final state = await container.read(
      intentionCatalogViewModelProvider.future,
    );
    expect(
      state,
      isA<IntentionCatalogEmpty>()
          .having((value) => value.scope, 'охват', IntentionScope.active)
          .having((value) => value.totalCount, 'точное количество', 0)
          .having((value) => value.nextCursor, 'курсор', isNull)
          .having((value) => value.revision, 'ревизия', same(revision)),
    );
  });

  test('повторяет только устранимый отказ первой страницы', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);
    repository.complete(0, const ResultFailure(IntentionUnavailableFailure()));

    expect(
      await container.read(intentionCatalogViewModelProvider.future),
      isA<IntentionCatalogUnavailable>(),
    );

    final retry = container
        .read(intentionCatalogViewModelProvider.notifier)
        .retry();
    expect(
      container.read(intentionCatalogViewModelProvider),
      isA<AsyncLoading<IntentionCatalogState>>(),
    );
    await _waitForQueries(repository, 2);
    final retryQuery = repository.queryAt(1);
    expect(retryQuery.cursor, isNull);
    const revision = TestCatalogRevision(1);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: revision,
        ),
      ),
    );
    await retry;

    expect(
      container.read(intentionCatalogViewModelProvider).requireValue,
      isA<IntentionCatalogEmpty>(),
    );
    expect(repository.queries, hasLength(2));
  });

  test(
    'не публикует завершение повтора после уничтожения провайдера',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);
      repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final retry = container
          .read(intentionCatalogViewModelProvider.notifier)
          .retry();
      await _waitForQueries(repository, 2);
      subscription.close();
      container.dispose();
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
    },
  );

  test('повреждение и непредвиденная ошибка остаются терминальными', () async {
    final scenarios = <(IntentionFailure, Matcher)>[
      (const IntentionCorruptionFailure(), isA<IntentionCatalogCorruption>()),
      (const IntentionUnexpectedFailure(), isA<IntentionCatalogUnexpected>()),
    ];

    for (final (failure, expectedState) in scenarios) {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);
      repository.complete(0, ResultFailure(failure));

      expect(
        await container.read(intentionCatalogViewModelProvider.future),
        expectedState,
      );
      await container.read(intentionCatalogViewModelProvider.notifier).retry();
      expect(repository.queries, hasLength(1));

      subscription.close();
      container.dispose();
    }
  });

  test('рабочая политика ограничивает первую страницу сотней элементов', () {
    final policy = CatalogPagingPolicy.production;

    expect(policy.pageSize, 100);
    expect(policy.prefetchRemaining, 30);
    expect(policy.filterDebounce, const Duration(milliseconds: 250));
    expect(
      () => CatalogPagingPolicy(
        pageSize: 101,
        prefetchRemaining: 30,
        filterDebounce: const Duration(milliseconds: 250),
      ),
      throwsA(isA<CatalogPagingPolicyValidationException>()),
    );
  });

  test('политика отклоняет недопустимые границы до запроса', () {
    expect(
      CatalogPagingPolicy(
        pageSize: 1,
        prefetchRemaining: 0,
        filterDebounce: Duration.zero,
      ).prefetchRemaining,
      0,
    );
    expect(
      CatalogPagingPolicy(
        pageSize: 100,
        prefetchRemaining: 99,
        filterDebounce: Duration.zero,
      ).pageSize,
      100,
    );

    for (final pageSize in [0, 101]) {
      expect(
        () => CatalogPagingPolicy(
          pageSize: pageSize,
          prefetchRemaining: 0,
          filterDebounce: Duration.zero,
        ),
        throwsA(
          isA<CatalogPagingPolicyValidationException>().having(
            (error) => error.failure,
            'причина',
            CatalogPagingPolicyValidationFailure.pageSizeOutOfRange,
          ),
        ),
      );
    }
    for (final prefetchRemaining in [-1, 3, 4]) {
      expect(
        () => CatalogPagingPolicy(
          pageSize: 3,
          prefetchRemaining: prefetchRemaining,
          filterDebounce: Duration.zero,
        ),
        throwsA(
          isA<CatalogPagingPolicyValidationException>().having(
            (error) => error.failure,
            'причина',
            CatalogPagingPolicyValidationFailure.prefetchRemainingOutOfRange,
          ),
        ),
      );
    }
  });

  test(
    'добавляет порции у порога без дублей и прекращает запросы в конце',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
        repository,
        pageSize: 3,
        prefetchRemaining: 1,
      );
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      const firstCursor = TestCatalogCursor();
      const secondCursor = TestCatalogCursor();
      const revision = TestCatalogRevision(5);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [
              testSummary(index: 1),
              testSummary(index: 2),
              testSummary(index: 3),
            ],
            totalCount: 5,
            nextCursor: firstCursor,
            revision: revision,
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);
      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );

      await notifier.loadNextPageIfNeeded(visibleIndex: 0);
      expect(repository.queries, hasLength(1));

      final firstLoad = notifier.loadNextPageIfNeeded(visibleIndex: 1);
      await _waitForQueries(repository, 2);
      expect(repository.queryAt(1).cursor, same(firstCursor));
      expect(
        container.read(intentionCatalogViewModelProvider).requireValue,
        isA<IntentionCatalogLoaded>().having(
          (state) => state.continuation,
          'состояние продолжения',
          isA<IntentionCatalogContinuationLoading>(),
        ),
      );
      await notifier.loadNextPageIfNeeded(visibleIndex: 2);
      expect(repository.queries, hasLength(2));

      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [testSummary(index: 3), testSummary(index: 4)],
            nextCursor: secondCursor,
            revision: revision,
          ),
        ),
      );
      await firstLoad;

      final afterSecondPage =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(afterSecondPage.items.map((item) => item.id), hasLength(4));
      expect(afterSecondPage.totalCount, 5);
      expect(afterSecondPage.nextCursor, same(secondCursor));
      expect(
        afterSecondPage.continuation,
        isA<IntentionCatalogContinuationIdle>(),
      );

      final secondLoad = notifier.loadNextPageIfNeeded(visibleIndex: 2);
      await _waitForQueries(repository, 3);
      expect(repository.queryAt(2).cursor, same(secondCursor));
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [testSummary(index: 5)],
            nextCursor: null,
            revision: revision,
          ),
        ),
      );
      await secondLoad;

      final complete =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(complete.items.map((item) => item.id).toSet(), hasLength(5));
      expect(complete.totalCount, 5);
      expect(complete.nextCursor, isNull);

      await notifier.loadNextPageIfNeeded(visibleIndex: 4);
      expect(repository.queries, hasLength(3));
    },
  );

  test('повторяет недоступное продолжение с тем же cursor', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(
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
    const revision = TestCatalogRevision(2);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1), testSummary(index: 2)],
          totalCount: 3,
          nextCursor: cursor,
          revision: revision,
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider.future);
    final notifier = container.read(intentionCatalogViewModelProvider.notifier);

    final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
    await _waitForQueries(repository, 2);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await load;

    final failed =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(failed.items, hasLength(2));
    expect(failed.totalCount, 3);
    expect(failed.nextCursor, same(cursor));
    expect(failed.continuation, isA<IntentionCatalogContinuationUnavailable>());

    await notifier.loadNextPageIfNeeded(visibleIndex: 1);
    expect(repository.queries, hasLength(2));

    final retry = notifier.retryNextPage();
    await _waitForQueries(repository, 3);
    expect(repository.queryAt(2).cursor, same(cursor));
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 3)],
          nextCursor: null,
          revision: revision,
        ),
      ),
    );
    await retry;

    final recovered =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(recovered.items, hasLength(3));
    expect(recovered.totalCount, 3);
    expect(recovered.nextCursor, isNull);
    expect(recovered.continuation, isA<IntentionCatalogContinuationIdle>());
  });

  test(
    'восстанавливает validation продолжения только с первой страницы',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
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
            items: [testSummary(index: 1), testSummary(index: 2)],
            totalCount: 4,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);
      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );

      final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
      await _waitForQueries(repository, 2);
      repository.complete(
        1,
        const ResultFailure(IntentionGenericValidationFailure()),
      );
      await load;
      expect(
        (container.read(intentionCatalogViewModelProvider).requireValue
                as IntentionCatalogLoaded)
            .continuation,
        isA<IntentionCatalogContinuationValidation>(),
      );

      final recovery = notifier.recoverFromInvalidCursor();
      await _waitForQueries(repository, 3);
      final recoveryQuery = repository.queryAt(2);
      expect(recoveryQuery.cursor, isNull);
      expect(recoveryQuery.scope, IntentionScope.active);
      final duringRecovery =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(duringRecovery.items, hasLength(2));
      expect(
        duringRecovery.continuation,
        isA<IntentionCatalogContinuationRecovering>(),
      );

      const newCursor = TestCatalogCursor();
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 7)],
            totalCount: 6,
            nextCursor: newCursor,
            revision: const TestCatalogRevision(9),
          ),
        ),
      );
      await recovery;

      final recovered =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(recovered.items.single.id, testSummary(index: 7).id);
      expect(recovered.totalCount, 6);
      expect(recovered.nextCursor, same(newCursor));
      expect(recovered.revision, const TestCatalogRevision(9));
    },
  );

  test(
    'сохраняет префикс при отказе восстановления и повторяет первую страницу',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
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
            items: [testSummary(index: 1), testSummary(index: 2)],
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

      final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
      await _waitForQueries(repository, 2);
      repository.complete(
        1,
        const ResultFailure(IntentionGenericValidationFailure()),
      );
      await load;

      final recovery = notifier.recoverFromInvalidCursor();
      await _waitForQueries(repository, 3);
      repository.complete(
        2,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await recovery;

      final unavailable =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(unavailable.items, hasLength(2));
      expect(unavailable.totalCount, 3);
      expect(unavailable.nextCursor, same(cursor));
      expect(
        unavailable.continuation,
        isA<IntentionCatalogRecoveryUnavailable>(),
      );

      final retry = notifier.retryRecovery();
      await _waitForQueries(repository, 4);
      expect(repository.queryAt(3).cursor, isNull);
      repository.complete(
        3,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 4)],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      await retry;

      final recovered =
          container.read(intentionCatalogViewModelProvider).requireValue
              as IntentionCatalogLoaded;
      expect(recovered.items.single.id, testSummary(index: 4).id);
      expect(recovered.totalCount, 1);
    },
  );

  test('отбрасывает позднее восстановление прежней generation', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(
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

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1), testSummary(index: 2)],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(intentionCatalogViewModelProvider.future);
    final notifier = container.read(intentionCatalogViewModelProvider.notifier);
    final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
    await _waitForQueries(repository, 2);
    repository.complete(
      1,
      const ResultFailure(IntentionGenericValidationFailure()),
    );
    await load;

    final oldRecovery = notifier.recoverFromInvalidCursor();
    await _waitForQueries(repository, 3);
    notifier.changeScope(IntentionScope.archived);
    await _waitForQueries(repository, 4);
    repository.complete(
      3,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 8, title: 'Текущая выдача')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(4),
        ),
      ),
    );
    final current = await container.read(
      intentionCatalogViewModelProvider.future,
    );

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 9, title: 'Прежняя выдача')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(3),
        ),
      ),
    );
    await oldRecovery;

    expect(
      container.read(intentionCatalogViewModelProvider).requireValue,
      same(current),
    );
  });

  test(
    'сохраняет фильтр и порядок при смене охвата и начинает первую страницу',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
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

      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      notifier.changeTitleFilter('  МОЛ  ');
      await _waitForQueries(repository, 2);
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

      notifier.changeOrder(IntentionCatalogOrder.updatedAtAscending);
      await _waitForQueries(repository, 3);
      repository.complete(
        2,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      notifier.changeScope(IntentionScope.archived);
      await _waitForQueries(repository, 4);
      final query = repository.queryAt(3);
      expect(query.scope, IntentionScope.archived);
      expect(query.titleFilter?.map((value) => value), 'МОЛ');
      expect(query.order, IntentionCatalogOrder.updatedAtAscending);
      expect(query.cursor, isNull);
      expect(
        notifier.selection,
        isA<IntentionCatalogSelection>()
            .having(
              (value) => value.titleFilterText,
              'исходный фильтр',
              '  МОЛ  ',
            )
            .having((value) => value.scope, 'охват', IntentionScope.archived)
            .having(
              (value) => value.order,
              'порядок',
              IntentionCatalogOrder.updatedAtAscending,
            ),
      );
    },
  );

  test('не отправляет фильтр до завершения интервала 250 мс', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);

    container
        .read(intentionCatalogViewModelProvider.notifier)
        .changeTitleFilter('молоко');
    await Future<void>.delayed(const Duration(milliseconds: 240));
    expect(repository.queries, hasLength(1));

    await _waitForQueries(repository, 2);
    expect(repository.queryAt(1).titleFilter?.map((value) => value), 'молоко');
  });

  test('отклоняет недопустимый фильтр без обращения к repository', () async {
    final scenarios = <(String, IntentionCatalogFilterValidationFailure)>[
      (
        'нуль\u0000внутри',
        IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
      ),
      (
        List.filled(256, 'я').join(),
        IntentionCatalogFilterValidationFailure.tooLong,
      ),
    ];

    for (final (filter, failure) in scenarios) {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
        repository,
        filterDebounce: Duration.zero,
      );
      final subscription = container.listen(
        intentionCatalogViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      notifier.changeTitleFilter(filter);
      final state = await _waitForState<IntentionCatalogInvalidFilter>(
        container,
      );

      expect(repository.queries, hasLength(1));
      expect(state.selection.titleFilterText, filter);
      expect(state.selection.filterValidationFailure, failure);

      subscription.close();
      container.dispose();
    }
  });

  test('не публикует поздний результат прежней выдачи', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);

    container
        .read(intentionCatalogViewModelProvider.notifier)
        .changeScope(IntentionScope.archived);
    await _waitForQueries(repository, 2);
    final currentSummary = testSummary(index: 2, title: 'Текущий результат');
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [currentSummary],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    final currentState = await container.read(
      intentionCatalogViewModelProvider.future,
    );
    expect(
      currentState,
      isA<IntentionCatalogLoaded>().having(
        (value) => value.items.single.title,
        'название',
        'Текущий результат',
      ),
    );

    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1, title: 'Устаревший результат')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(intentionCatalogViewModelProvider).requireValue,
      same(currentState),
    );
  });

  test('поздний результат прежнего фильтра не заменяет новый', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(
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
    repository.queryAt(0);

    final notifier = container.read(intentionCatalogViewModelProvider.notifier);
    notifier.changeTitleFilter('прежний');
    await _waitForQueries(repository, 2);
    notifier.changeTitleFilter('новый');
    await _waitForQueries(repository, 3);

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 3, title: 'Новый результат')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(3),
        ),
      ),
    );
    final currentState = await container.read(
      intentionCatalogViewModelProvider.future,
    );

    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 2, title: 'Прежний результат')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(2),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(intentionCatalogViewModelProvider).requireValue,
      same(currentState),
    );
  });

  test(
    'после прежней команды перечитывает только текущие параметры и ревизию',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
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
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(3),
          ),
        ),
      );
      await container.read(intentionCatalogViewModelProvider.future);

      final coordinator = container.read(
        intentionCommandCoordinatorProvider.notifier,
      );
      final observedCompletions = <IntentionCommandCompletion>[];
      final completionSubscription = coordinator.completions.listen(
        observedCompletions.add,
      );
      addTearDown(completionSubscription.cancel);
      final start = coordinator.accept(
        const CreateIntention(title: 'Новое', description: null),
      );
      expect(start, isA<IntentionCommandAccepted>());
      final accepted = start as IntentionCommandAccepted;
      expect(repository.commands, hasLength(1));

      final notifier = container.read(
        intentionCatalogViewModelProvider.notifier,
      );
      notifier.changeTitleFilter('архив');
      await _waitForQueries(repository, 2);
      notifier.changeScope(IntentionScope.archived);
      await _waitForQueries(repository, 3);
      notifier.changeOrder(IntentionCatalogOrder.updatedAtDescending);
      await _waitForQueries(repository, 4);

      final intention = testIntention(index: 7, title: 'Новое');
      repository.completeCommand(
        0,
        ResultSuccess(
          IntentionSaved(
            intention,
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(4),
              entry: TestCatalogEntrySnapshot(
                testSummary(index: 7, title: 'Новое'),
              ),
            ),
          ),
        ),
      );
      await accepted.future;
      expect(observedCompletions, hasLength(1));
      await _waitForQueries(repository, 5);

      final refreshedQuery = repository.queryAt(4);
      expect(refreshedQuery.scope, IntentionScope.archived);
      expect(refreshedQuery.titleFilter?.map((value) => value), 'архив');
      expect(refreshedQuery.order, IntentionCatalogOrder.updatedAtDescending);
      expect(refreshedQuery.cursor, isNull);

      repository.complete(
        4,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(4),
          ),
        ),
      );
      final refreshed = await container.read(
        intentionCatalogViewModelProvider.future,
      );
      expect(
        refreshed,
        isA<IntentionCatalogEmpty>().having(
          (value) => value.revision,
          'ревизия',
          const TestCatalogRevision(4),
        ),
      );
    },
  );
}

ProviderContainer _catalogContainer(
  ControlledCatalogRepository repository, {
  Duration filterDebounce = const Duration(milliseconds: 250),
  int pageSize = 100,
  int prefetchRemaining = 30,
}) => ProviderContainer(
  overrides: [
    intentionRepositoryProvider.overrideWithValue(repository),
    catalogPagingPolicyProvider.overrideWithValue(
      CatalogPagingPolicy(
        pageSize: pageSize,
        prefetchRemaining: prefetchRemaining,
        filterDebounce: filterDebounce,
      ),
    ),
  ],
  retry: (retryCount, error) => null,
);

Future<void> _waitForQueries(
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.queries.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count запросов каталога.');
}

Future<T> _waitForState<T extends IntentionCatalogState>(
  ProviderContainer container,
) {
  final completer = Completer<T>();
  late final ProviderSubscription<AsyncValue<IntentionCatalogState>> listener;
  listener = container.listen(intentionCatalogViewModelProvider, (_, next) {
    final value = next.value;
    if (!completer.isCompleted && value is T) {
      completer.complete(value);
      listener.close();
    }
  }, fireImmediately: true);
  return completer.future;
}
