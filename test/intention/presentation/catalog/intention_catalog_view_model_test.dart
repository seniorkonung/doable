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
}) => ProviderContainer(
  overrides: [
    intentionRepositoryProvider.overrideWithValue(repository),
    catalogPagingPolicyProvider.overrideWithValue(
      CatalogPagingPolicy(
        pageSize: 100,
        prefetchRemaining: 30,
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
