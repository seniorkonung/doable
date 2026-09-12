import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
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
      repository.queryAt(1);
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
}

ProviderContainer _catalogContainer(ControlledCatalogRepository repository) =>
    ProviderContainer(
      overrides: [
        intentionRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy.production,
        ),
      ],
      retry: (retryCount, error) => null,
    );
