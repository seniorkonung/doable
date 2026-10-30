import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
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
            .having((value) => value.scope, 'охват', IntentionScope.archived)
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

  group('тип намерения', () {
    test(
      'назначение задаёт доступность типа, готовность запроса и просьбу чисел',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final cases =
            <
              (
                IntentionCatalogPurpose,
                IntentionTypeAvailability,
                IntentionReadinessFilter,
              )
            >[
              (
                const BrowseIntentionCatalog(),
                const IntentionTypeNotOffered(),
                IntentionReadinessFilter.all,
              ),
              (
                SelectDailyChoiceAction(session: IntentionSearchSession()),
                const IntentionTypePinnedToActions(),
                IntentionReadinessFilter.readyOnly,
              ),
              (
                SelectDailyChoiceSource(session: IntentionSearchSession()),
                const IntentionTypeOpen(IntentionTypeChoice.all),
                IntentionReadinessFilter.all,
              ),
              (
                SelectRelationParticipant(
                  selectionContext:
                      RelationParticipantSelectionContext.activeRelation,
                  session: IntentionSearchSession(),
                ),
                const IntentionTypeOpen(IntentionTypeChoice.all),
                IntentionReadinessFilter.all,
              ),
            ];

        for (final (index, (purpose, type, readiness)) in cases.indexed) {
          final provider = intentionCatalogViewModelProvider(purpose);
          final subscription = container.listen(
            provider,
            (_, _) {},
            fireImmediately: true,
          );
          addTearDown(subscription.close);
          final isOpen = type is IntentionTypeOpen;

          expect(container.read(provider.notifier).selection.type, type);
          final query = repository.queryAt(index);
          expect(query.readinessFilter, readiness);
          expect(
            query.counting,
            isOpen
                ? IntentionCatalogCounting.byType
                : IntentionCatalogCounting.totalOnly,
          );

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
            isA<IntentionCatalogLoaded>().having(
              (value) => value.typeCounts,
              'числа типов',
              isOpen ? isNotNull : isNull,
            ),
          );
        }
      },
    );

    test(
      'смена открытого типа начинает новую выдачу с первой порции',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        final provider = intentionCatalogViewModelProvider(
          SelectDailyChoiceSource(session: IntentionSearchSession()),
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
              items: [testSummary(index: 1)],
              totalCount: 3,
              nextCursor: const TestCatalogCursor(),
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);

        for (final (index, (type, readiness)) in [
          (
            IntentionTypeChoice.intentions,
            IntentionReadinessFilter.notReadyOnly,
          ),
          (IntentionTypeChoice.actions, IntentionReadinessFilter.readyOnly),
          (IntentionTypeChoice.all, IntentionReadinessFilter.all),
        ].indexed) {
          notifier.changeType(type);
          await _waitForQueries(repository, index + 2);

          expect(notifier.selection.type, IntentionTypeOpen(type));
          final query = repository.queryAt(index + 1);
          expect(query.readinessFilter, readiness);
          expect(query.counting, IntentionCatalogCounting.byType);
          expect(query.cursor, isNull);
        }

        notifier.changeType(IntentionTypeChoice.all);
        await Future<void>.delayed(Duration.zero);
        expect(repository.queries, hasLength(4));
      },
    );

    test('без открытого типа смена типа не начинает новую выдачу', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      addTearDown(container.dispose);
      final purposes = <IntentionCatalogPurpose>[
        const BrowseIntentionCatalog(),
        SelectDailyChoiceAction(session: IntentionSearchSession()),
      ];

      for (final (index, purpose) in purposes.indexed) {
        final provider = intentionCatalogViewModelProvider(purpose);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
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
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);
        final type = notifier.selection.type;

        notifier.changeType(IntentionTypeChoice.intentions);
        await Future<void>.delayed(Duration.zero);

        expect(notifier.selection.type, type);
        expect(repository.queries, hasLength(index + 1));
      }
    });

    test(
      'числа типов при закреплённом типе нарушают контракт порции',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _catalogContainer(repository);
        addTearDown(container.dispose);
        final provider = intentionCatalogViewModelProvider(
          SelectDailyChoiceAction(session: IntentionSearchSession()),
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
              counts: IntentionCountsByType(
                IntentionTypeCounts(all: 1, actions: 0),
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

    test('пропущенные, чужого вида или противоречивые числа типов нарушают контракт порции', () async {
      final repository = ControlledCatalogRepository();
      final container = _catalogContainer(repository);
      addTearDown(container.dispose);
      final pages = [
        // Запрошенных чисел нет.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
        // Общее количество типа «Все» расходится с числом всех.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1), testSummary(index: 2)],
          totalCount: 2,
          counts: IntentionCountsByType(
            IntentionTypeCounts(all: 3, actions: 1),
          ),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
        // Подсчёт по охватам и типам модель не просила.
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          counts: IntentionCountsByScopeAndType(
            active: IntentionTypeCounts(all: 1, actions: 0),
            archived: IntentionTypeCounts(all: 0, actions: 0),
          ),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ];

      for (final (index, page) in pages.indexed) {
        final provider = intentionCatalogViewModelProvider(
          SelectDailyChoiceSource(session: IntentionSearchSession()),
        );
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        repository.completeVerbatim(index, ResultSuccess(page));

        expect(
          await container.read(provider.future),
          isA<IntentionCatalogUnexpected>(),
        );
      }
    });
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
