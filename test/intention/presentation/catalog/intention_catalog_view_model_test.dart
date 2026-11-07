import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      expect(
        container.read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        ),
        isA<AsyncLoading<IntentionCatalogState>>(),
      );
      final query = repository.queryAt(0);
      expect(query.scope, IntentionScope.active);
      expect(query.titleFilter, isNull);
      expect(query.order, IntentionCatalogOrder.createdAtDescending);
      expect(query.pageSize, 100);
      expect(query.cursor, isNull);

      const cursor = TestCatalogCursor();
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
            revision: const TestCatalogRevision(4),
          ),
        ),
      );

      final state = await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );
      expect(
        state,
        isA<IntentionCatalogLoaded>()
            .having((value) => value.items, 'элементы', summaries)
            .having((value) => value.totalCount, 'точное количество', 7)
            .having((value) => value.nextCursor, 'курсор', same(cursor)),
      );
    },
  );

  test('повторяет только устранимый отказ первой страницы', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);
    repository.complete(0, const ResultFailure(IntentionUnavailableFailure()));

    expect(
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      ),
      isA<IntentionCatalogUnavailable>(),
    );

    final retry = container
        .read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .notifier,
        )
        .retry();
    expect(
      container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      ),
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
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);
      repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

      final retry = container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
                .notifier,
          )
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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);
      repository.complete(0, ResultFailure(failure));

      expect(
        await container.read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .future,
        ),
        expectedState,
      );
      await container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
                .notifier,
          )
          .retry();
      expect(repository.queries, hasLength(1));

      subscription.close();
      container.dispose();
    }
  });

  test('рабочая политика ограничивает первую страницу сотней элементов', () {
    final policy = CatalogPagingPolicy.production;

    expect(policy.pageSize, 100);
    expect(policy.prefetchRemaining, 30);
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
    for (final prefetchRemaining in [-1, 3]) {
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

  test('добавляет порции, повторяет после нескольких и завершается', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(
      repository,
      pageSize: 3,
      prefetchRemaining: 1,
    );
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
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
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );
    final notifier = container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
          .notifier,
    );

    await notifier.loadNextPageIfNeeded(visibleIndex: 0);
    expect(repository.queries, hasLength(1));

    final firstLoad = notifier.loadNextPageIfNeeded(visibleIndex: 1);
    await _waitForQueries(repository, 2);
    expect(repository.queryAt(1).cursor, same(firstCursor));
    expect(
      container
          .read(
            intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
          )
          .requireValue,
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
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
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
    repository.complete(2, const ResultFailure(IntentionUnavailableFailure()));
    await secondLoad;

    final failedAfterSeveralPages =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(failedAfterSeveralPages.items, hasLength(4));
    expect(failedAfterSeveralPages.totalCount, 5);
    expect(failedAfterSeveralPages.nextCursor, same(secondCursor));
    expect(
      failedAfterSeveralPages.continuation,
      isA<IntentionCatalogContinuationUnavailable>(),
    );

    final finalLoad = notifier.retryNextPage();
    await _waitForQueries(repository, 4);
    expect(repository.queryAt(3).cursor, same(secondCursor));
    repository.complete(
      3,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 5)],
          nextCursor: null,
          revision: revision,
        ),
      ),
    );
    await finalLoad;

    final complete =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(complete.items.map((item) => item.id).toSet(), hasLength(5));
    expect(complete.totalCount, 5);
    expect(complete.nextCursor, isNull);

    await notifier.loadNextPageIfNeeded(visibleIndex: 4);
    expect(repository.queries, hasLength(4));
  });

  test('повторяет недоступное продолжение с тем же cursor', () async {
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(
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
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );
    final notifier = container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
          .notifier,
    );

    final load = notifier.loadNextPageIfNeeded(visibleIndex: 0);
    await _waitForQueries(repository, 2);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await load;

    final failed =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
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
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(recovered.items, hasLength(3));
    expect(recovered.totalCount, 3);
    expect(recovered.nextCursor, isNull);
    expect(recovered.continuation, isA<IntentionCatalogContinuationIdle>());
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
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
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
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

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
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

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
            .having(
              (value) => value.show,
              'параметры показа',
              const IntentionShowChosen(
                scope: IntentionScope.archived,
                kind: IntentionKindFilter.mainOnly,
              ),
            )
            .having(
              (value) => value.order,
              'порядок',
              IntentionCatalogOrder.updatedAtAscending,
            ),
      );
    },
  );

  test(
    'снятие фильтра названия сразу читает первую порцию без паузы ввода',
    () async {
      final repository = ControlledCatalogRepository();
      // Пауза ввода длиннее теста: запрос без неё возможен только сразу.
      final container = _catalogContainer(
        repository,
        filterDebounce: const Duration(hours: 1),
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
      repository.queryAt(0);
      notifier
        ..changeTitleFilter('бег')
        ..changeOrder(IntentionCatalogOrder.updatedAtAscending);
      await _waitForQueries(repository, 2);
      expect(repository.queryAt(1).titleFilter?.map((value) => value), 'бег');
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
      await _waitForState<IntentionCatalogEmpty>(container);

      notifier.clearTitleFilter();
      await _waitForQueries(repository, 3);

      final query = repository.queryAt(2);
      expect(query.titleFilter, isNull);
      expect(query.order, IntentionCatalogOrder.updatedAtAscending);
      expect(query.cursor, isNull);
      expect(notifier.selection.titleFilterText, isEmpty);
    },
  );

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
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      repository.queryAt(0);

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
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
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    repository.queryAt(0);

    container
        .read(
          intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
              .notifier,
        )
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
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
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

    final state =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(state.items.single.title, 'Текущий результат');
  });

  test(
    'согласует completion только с текущими параметрами без повторного чтения',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
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
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final start = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(title: 'Новое', description: null),
      );
      expect(start, isA<IntentionCommandAccepted>());
      final accepted = start as IntentionCommandAccepted;

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
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
      repository.complete(
        3,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(3),
          ),
        ),
      );
      final reconciled = await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );
      expect(reconciled, isA<IntentionCatalogEmpty>());
      expect(repository.queries, hasLength(4));
    },
  );

  group('вид намерения', () {
    test(
      'назначение задаёт параметры показа, условие вида и просьбу чисел',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final cases =
            <
              (
                IntentionCatalogPurpose,
                IntentionShowParameters,
                IntentionKindFilter,
                IntentionCatalogCounting,
              )
            >[
              (
                const BrowseIntentionCatalog(),
                const IntentionShowChosen(
                  scope: IntentionScope.active,
                  kind: IntentionKindFilter.mainOnly,
                ),
                IntentionKindFilter.mainOnly,
                IntentionCatalogCounting.byScopeAndKind,
              ),
              (
                _participantPurpose(),
                const IntentionShowFixed(),
                IntentionKindFilter.mainAndSupporting,
                IntentionCatalogCounting.totalOnly,
              ),
              (
                SelectPathStart(session: IntentionSearchSession()),
                const IntentionShowFixed(),
                IntentionKindFilter.mainAndSupporting,
                IntentionCatalogCounting.totalOnly,
              ),
            ];

        for (final (index, (purpose, show, kindFilter, counting))
            in cases.indexed) {
          final provider = intentionCatalogViewModelProvider(purpose);
          final subscription = container.listen(
            provider,
            (_, _) {},
            fireImmediately: true,
          );
          addTearDown(subscription.close);
          final selection = container.read(provider.notifier).selection;

          expect(selection.show, show);
          final query = repository.queryAt(index);
          expect(query.scope, IntentionScope.active);
          expect(query.kindFilter, kindFilter);
          expect(query.counting, counting);
          repository.complete(
            index,
            ResultSuccess(
              IntentionCatalogFirstPage(
                items: [testSummary(index: index + 1)],
                totalCount: 1,
                nextCursor: null,
                revision: const TestCatalogRevision(1),
              ),
            ),
          );
          final state = await container.read(provider.future);
          expect(
            state,
            isA<IntentionCatalogLoaded>()
                .having(
                  (value) => value.kindCounts,
                  'числа видов',
                  purpose is BrowseIntentionCatalog ? isNotNull : isNull,
                )
                .having(
                  (value) => value.scopeCounts,
                  'числа охватов',
                  purpose is BrowseIntentionCatalog ? isNotNull : isNull,
                ),
          );
        }
      },
    );

    test('смена вида каталога читает первую порцию с новым видом и сохраняет '
        'охват, порядок и фильтры, а тот же вид ничего не меняет', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
        repository,
        filterDebounce: const Duration(milliseconds: 1),
      );
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      final notifier = container.read(provider.notifier);
      final tagFilter = IntentionTagFilter(requiredTagIds: [_tagId(1)]);

      await _completeEmptyFirstPage(container, repository, 0);
      notifier
        ..changeScope(IntentionScope.archived)
        ..changeOrder(IntentionCatalogOrder.titleAscending)
        ..changeTitleFilter('бег')
        ..changeTagFilter(tagFilter);
      await _waitForQueries(repository, 2);
      await _completeEmptyFirstPage(container, repository, 1);

      notifier.changeKind(IntentionKindFilter.supportingOnly);
      await _waitForQueries(repository, 3);
      final kindQuery = repository.queryAt(2);
      expect(kindQuery.kindFilter, IntentionKindFilter.supportingOnly);
      expect(kindQuery.counting, IntentionCatalogCounting.byScopeAndKind);
      expect(kindQuery.cursor, isNull);
      expect(kindQuery.scope, IntentionScope.archived);
      expect(kindQuery.order, IntentionCatalogOrder.titleAscending);
      expect(kindQuery.titleFilter?.map((value) => value), 'бег');
      expect(kindQuery.tagFilter, tagFilter);
      await _completeEmptyFirstPage(container, repository, 2);

      notifier.changeKind(IntentionKindFilter.supportingOnly);
      await pumpEventQueue();
      expect(repository.queries, hasLength(3));

      notifier.changeScope(IntentionScope.all);
      await _waitForQueries(repository, 4);
      expect(
        repository.queryAt(3).kindFilter,
        IntentionKindFilter.supportingOnly,
      );
      expect(
        notifier.selection.show,
        const IntentionShowChosen(
          scope: IntentionScope.all,
          kind: IntentionKindFilter.supportingOnly,
        ),
      );
    });

    test('смена вида в поиске выбора ничего не меняет', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      final provider = intentionCatalogViewModelProvider(_participantPurpose());
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 1)],
            totalCount: 3,
            nextCursor: const TestCatalogCursor(),
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);

      for (final kind in IntentionKindFilter.values) {
        notifier.changeKind(kind);
      }
      await pumpEventQueue();

      expect(repository.queries, hasLength(1));
      expect(notifier.selection.show, const IntentionShowFixed());
      expect(notifier.canResetShowParameters, isFalse);
    });

    test(
      'числа вида, которых экран выбора не просил, нарушают контракт порции',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final provider = intentionCatalogViewModelProvider(
          _participantPurpose(),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        repository.completeVerbatim(
          0,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [testSummary(index: 1)],
              totalCount: 1,
              counts: IntentionCountsByScopeAndKind(
                active: IntentionKindCounts(main: 1, supporting: 0),
                archived: IntentionKindCounts(main: 0, supporting: 0),
              ),
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );

        expect(
          await container.read(provider.future),
          isA<IntentionCatalogUnexpected>(),
        );
      },
    );

    test(
      'подтверждённая выдача каталога даёт числа текущего охвата и вида',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        final matrix = IntentionCountsByScopeAndKind(
          active: IntentionKindCounts(main: 5, supporting: 4),
          archived: IntentionKindCounts(main: 3, supporting: 2),
        );
        IntentionCatalogFirstPage page(int totalCount) =>
            IntentionCatalogFirstPage(
              items: [testSummary(index: 1)],
              totalCount: totalCount,
              counts: matrix,
              nextCursor: totalCount > 1 ? const TestCatalogCursor() : null,
              revision: const TestCatalogRevision(1),
            );

        repository.completeVerbatim(0, ResultSuccess(page(5)));
        final active = await container.read(provider.future);
        expect(
          active,
          isA<IntentionCatalogConfirmedState>()
              .having((state) => state.totalCount, 'количество', 5)
              .having((state) => state.kindCounts?.main, 'главные', 5)
              .having(
                (state) => state.kindCounts?.supporting,
                'вспомогательные',
                4,
              )
              .having((state) => state.kindCounts?.all, 'оба вида', 9)
              .having((state) => state.scopeCounts?.active, 'активные', 5)
              .having((state) => state.scopeCounts?.archived, 'архивные', 3)
              .having((state) => state.scopeCounts?.all, 'все охваты', 8),
        );

        final notifier = container.read(provider.notifier);
        notifier.changeScope(IntentionScope.all);
        notifier.changeKind(IntentionKindFilter.supportingOnly);
        await _waitForQueries(repository, 2);
        repository.completeVerbatim(1, ResultSuccess(page(6)));
        expect(
          await container.read(provider.future),
          isA<IntentionCatalogConfirmedState>()
              .having((state) => state.totalCount, 'количество', 6)
              .having((state) => state.kindCounts?.main, 'главные', 8)
              .having(
                (state) => state.kindCounts?.supporting,
                'вспомогательные',
                6,
              )
              .having((state) => state.kindCounts?.all, 'оба вида', 14)
              .having((state) => state.scopeCounts?.active, 'активные', 4)
              .having((state) => state.scopeCounts?.archived, 'архивные', 2)
              .having((state) => state.scopeCounts?.all, 'все охваты', 6),
        );
      },
    );

    test('числа без матрицы или с числом выбранного вида, расходящимся с общим '
        'количеством, нарушают контракт порции', () async {
      final pages = [
        // Главных в активном охвате три, а общее количество — только строка
        // порции.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          counts: IntentionCountsByScopeAndKind(
            active: IntentionKindCounts(main: 3, supporting: 0),
            archived: IntentionKindCounts(main: 0, supporting: 0),
          ),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
        // Общее количество совпадает с числом другого вида, а не выбранного.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          counts: IntentionCountsByScopeAndKind(
            active: IntentionKindCounts(main: 0, supporting: 1),
            archived: IntentionKindCounts(main: 0, supporting: 0),
          ),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
        // Чисел видов нет, хотя каталог их просил.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ];

      for (final page in pages) {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        repository.completeVerbatim(0, ResultSuccess(page));

        expect(
          await container.read(provider.future),
          isA<IntentionCatalogUnexpected>(),
        );
      }
    });
  });

  group('сброс параметров показа', () {
    test('каталог возвращает охват, вид и порядок одной выдачей, сохраняя '
        'фильтр названия и условие по тегу, а в начальном состоянии ничего '
        'не делает', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
        repository,
        filterDebounce: const Duration(milliseconds: 1),
      );
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      final notifier = container.read(provider.notifier);
      final tagFilter = IntentionTagFilter(requiredTagIds: [_tagId(1)]);

      await _completeEmptyFirstPage(container, repository, 0);
      expect(notifier.canResetShowParameters, isFalse);
      notifier.resetShowParameters();
      await pumpEventQueue();
      expect(repository.queries, hasLength(1));

      notifier
        ..changeScope(IntentionScope.all)
        ..changeKind(IntentionKindFilter.supportingOnly)
        ..changeOrder(IntentionCatalogOrder.titleAscending)
        ..changeTitleFilter('бег')
        ..changeTagFilter(tagFilter);
      await _waitForQueries(repository, 2);
      await _completeEmptyFirstPage(container, repository, 1);
      expect(notifier.canResetShowParameters, isTrue);

      notifier.resetShowParameters();
      await _waitForQueries(repository, 3);
      await pumpEventQueue();

      expect(repository.queries, hasLength(3));
      final query = repository.queryAt(2);
      expect(query.scope, IntentionScope.active);
      expect(query.kindFilter, IntentionKindFilter.mainOnly);
      expect(query.order, IntentionCatalogOrder.createdAtDescending);
      expect(query.titleFilter?.map((value) => value), 'бег');
      expect(query.tagFilter, tagFilter);
      expect(query.cursor, isNull);
      await _completeEmptyFirstPage(container, repository, 2);
      expect(notifier.canResetShowParameters, isFalse);
      expect(
        notifier.selection.show,
        const IntentionShowChosen(
          scope: IntentionScope.active,
          kind: IntentionKindFilter.mainOnly,
        ),
      );

      notifier.resetShowParameters();
      await pumpEventQueue();
      expect(repository.queries, hasLength(3));
    });

    test(
      'смена одного вида делает сброс доступным и возвращает главные',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        final notifier = container.read(provider.notifier);

        await _completeEmptyFirstPage(container, repository, 0);
        notifier.changeKind(IntentionKindFilter.mainAndSupporting);
        await _waitForQueries(repository, 2);
        await _completeEmptyFirstPage(container, repository, 1);
        expect(notifier.canResetShowParameters, isTrue);

        notifier.resetShowParameters();
        await _waitForQueries(repository, 3);

        expect(repository.queryAt(2).kindFilter, IntentionKindFilter.mainOnly);
        await _completeEmptyFirstPage(container, repository, 2);
        expect(notifier.canResetShowParameters, isFalse);
      },
    );

    test('смена поколения графа возвращает начальный выбор и запрос, '
        'включая фильтры', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(
        repository,
        filterDebounce: const Duration(milliseconds: 1),
      );
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      final notifier = container.read(provider.notifier);

      await _completeEmptyFirstPage(container, repository, 0);
      notifier
        ..changeScope(IntentionScope.all)
        ..changeKind(IntentionKindFilter.supportingOnly)
        ..changeOrder(IntentionCatalogOrder.titleAscending)
        ..changeTitleFilter('бег');
      await _waitForQueries(repository, 2);
      await _completeEmptyFirstPage(container, repository, 1);
      expect(repository.queryAt(1).titleFilter?.map((value) => value), 'бег');

      final accepted =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptBackupRestore(
                    (exclusive) => exclusive.replace(
                      () async => ConfirmedGraphReplacement(
                        const TestCatalogRevision(0, epoch: 1),
                      ),
                    ),
                  )
              as GraphBackupRestoreAccepted;
      await accepted.future;
      await _waitForQueries(repository, 3);
      await pumpEventQueue();

      expect(repository.queries, hasLength(3));
      final query = repository.queryAt(2);
      expect(query.scope, IntentionScope.active);
      expect(query.kindFilter, IntentionKindFilter.mainOnly);
      expect(query.order, IntentionCatalogOrder.createdAtDescending);
      expect(query.titleFilter, isNull);
      expect(query.tagFilter, IntentionTagFilter.empty);
      final selection = notifier.selection;
      expect(
        selection.show,
        const IntentionShowChosen(
          scope: IntentionScope.active,
          kind: IntentionKindFilter.mainOnly,
        ),
      );
      expect(selection.order, IntentionCatalogOrder.createdAtDescending);
      expect(selection.titleFilterText, isEmpty);
    });
  });

  group('занимающие связи строк поиска участника', () {
    final purpose = SelectRelationParticipant(
      session: IntentionSearchSession(),
      pairProbe: RelationPairProbe(
        counterpartId: testSummary(index: 9).id,
        candidateRole: RelationParticipantRole.related,
      ),
    );
    final provider = intentionCatalogViewModelProvider(purpose);

    PairOccupant occupant(int rowIndex, RelationScope scope) => PairOccupant(
      relationId: testRelation(
        sourceIntentionId: testSummary(index: 9).id,
        relatedIntentionId: testSummary(index: rowIndex).id,
        index: rowIndex,
      ).id,
      type: LongTermRelationType.need,
      scope: scope,
    );

    test(
      'выдача несёт занимающие связи строк первой порции и продолжений',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 1,
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);

        repository.complete(
          0,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [testSummary(index: 4), testSummary(index: 3)],
              totalCount: 4,
              nextCursor: const TestCatalogCursor(),
              revision: const TestCatalogRevision(1),
              pairOccupants: {
                testSummary(index: 3).id: occupant(3, RelationScope.archived),
              },
            ),
          ),
        );
        final first = await container.read(provider.future);
        expect(
          first,
          isA<IntentionCatalogLoaded>().having(
            (loaded) => loaded.pairOccupants,
            'занимающие связи',
            {testSummary(index: 3).id: occupant(3, RelationScope.archived)},
          ),
        );

        final load = container
            .read(provider.notifier)
            .loadNextPageIfNeeded(visibleIndex: 0);
        await _waitForQueries(repository, 2);
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogContinuationPage(
              items: [testSummary(index: 2), testSummary(index: 1)],
              nextCursor: null,
              revision: const TestCatalogRevision(1),
              pairOccupants: {
                testSummary(index: 1).id: occupant(1, RelationScope.active),
              },
            ),
          ),
        );
        await load;

        expect(
          container.read(provider).requireValue,
          isA<IntentionCatalogLoaded>()
              .having((loaded) => loaded.items, 'строки', hasLength(4))
              .having((loaded) => loaded.pairOccupants, 'занимающие связи', {
                testSummary(index: 3).id: occupant(3, RelationScope.archived),
                testSummary(index: 1).id: occupant(1, RelationScope.active),
              }),
        );
      },
    );

    test(
      'первая порция без занимающих связей нарушает контракт выдачи',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);

        repository.completeVerbatim(
          0,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [testSummary(index: 4)],
              totalCount: 1,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );

        expect(
          await container.read(provider.future),
          isA<IntentionCatalogUnexpected>(),
        );
      },
    );

    test(
      'продолжение без занимающих связей нарушает контракт продолжения',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 1,
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);

        repository.complete(
          0,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [testSummary(index: 4), testSummary(index: 3)],
              totalCount: 4,
              nextCursor: const TestCatalogCursor(),
              revision: const TestCatalogRevision(1),
              pairOccupants: {
                testSummary(index: 3).id: occupant(3, RelationScope.active),
              },
            ),
          ),
        );
        await container.read(provider.future);
        final load = container
            .read(provider.notifier)
            .loadNextPageIfNeeded(visibleIndex: 0);
        await _waitForQueries(repository, 2);
        repository.completeVerbatim(
          1,
          ResultSuccess(
            IntentionCatalogContinuationPage(
              items: [testSummary(index: 2), testSummary(index: 1)],
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await load;

        expect(
          container.read(provider).requireValue,
          isA<IntentionCatalogLoaded>()
              .having((loaded) => loaded.items, 'строки', hasLength(2))
              .having((loaded) => loaded.pairOccupants, 'занимающие связи', {
                testSummary(index: 3).id: occupant(3, RelationScope.active),
              })
              .having(
                (loaded) => loaded.continuation,
                'продолжение',
                isA<IntentionCatalogContinuationUnexpected>(),
              ),
        );
      },
    );
  });

  test('не забирает у оболочки право предъявить completion', () async {
    final intention = testIntention(index: 90, title: 'Изменённое намерение');
    final repository = ControlledCatalogRepository();
    final container = _catalogContainer(repository);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, _) {},
      fireImmediately: true,
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final started = coordinator.acceptExisting(
      UpdateIntention(
        id: intention.id,
        title: intention.title,
        description: intention.description,
      ),
      presentationTitle: intention.title,
    ) as IntentionCommandAccepted;
    coordinator.releaseInitiatorPresentation(started.token);
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await started.future;

    final claim = await presenter.nextClaim();
    expect(claim, isNotNull);
    expect(
      claim!.completions.single,
      isA<IntentionCommandCompletion>().having(
        (completion) => completion.presentationTitle,
        'название намерения',
        intention.title,
      ),
    );
    coordinator.confirmAppPresentation(
      claim,
      claim.completions.map((completion) => completion.token),
    );

    subscription.close();
    container.dispose();
  });
}

ProviderContainer _catalogContainer(
  ControlledCatalogRepository repository, {
  Duration filterDebounce = const Duration(milliseconds: 250),
  int pageSize = 100,
  int prefetchRemaining = 30,
}) => ProviderContainer(
  overrides: [
    personalGraphRepositoryProvider.overrideWithValue(repository),
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

Future<IntentionCatalogState> _completeEmptyFirstPage(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  int index,
) {
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
  return container.read(
    intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
  );
}

TagId _tagId(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Future<T> _waitForState<T extends IntentionCatalogState>(
  ProviderContainer container,
) {
  final completer = Completer<T>();
  late final ProviderSubscription<AsyncValue<IntentionCatalogState>> listener;
  listener = container.listen(
    intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
    (_, next) {
      final value = next.value;
      if (!completer.isCompleted && value is T) {
        completer.complete(value);
        listener.close();
      }
    },
    fireImmediately: true,
  );
  return completer.future;
}

SelectRelationParticipant _participantPurpose() => SelectRelationParticipant(
  session: IntentionSearchSession(),
  pairProbe: RelationPairProbe(
    counterpartId: testSummary(index: 999).id,
    candidateRole: RelationParticipantRole.related,
  ),
);
