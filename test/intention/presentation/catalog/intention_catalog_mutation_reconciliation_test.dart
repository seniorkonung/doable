import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';
import '../../../support/tag_positions.dart';

void main() {
  test('применяет пакет каталожных изменений одной ревизии целиком', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    final confirmedStates = <IntentionCatalogConfirmedState>[];
    final subscription = container.listen(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      (_, next) {
        if (next.value case final IntentionCatalogConfirmedState confirmed) {
          confirmedStates.add(confirmed);
        }
      },
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
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );
    confirmedStates.clear();

    final first = testSummary(index: 1, title: 'Первое');
    final second = testSummary(index: 2, title: 'Второе');
    await completeCatalogCommand(
      container,
      repository,
      const CreateIntention(title: 'Первое', description: null),
      IntentionSaved(
        testIntention(index: 1, title: 'Первое'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(2),
          entry: TestCatalogEntrySnapshot(first),
        ),
        additionalCatalogMutations: [
          IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(second),
          ),
        ],
      ),
    );

    final current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [second.id, first.id]);
    expect(current.totalCount, 2);
    // Пакет публикуется целиком: ни одно опубликованное состояние не содержит
    // его часть.
    expect(confirmedStates, isNotEmpty);
    expect([
      for (final state in confirmedStates)
        (state as IntentionCatalogLoaded).items.map((item) => item.id),
    ], everyElement([second.id, first.id]));
    expect(repository.queries, hasLength(1));
  });

  test('применяет membership transition к префиксу, count и cursor', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
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
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [fourth, third],
          totalCount: 4,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    final movedAfterBoundary = testSummary(index: 4, createdDay: 1);
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: fourth.id, title: fourth.title, description: null),
      IntentionSaved(
        testIntention(index: 4),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(2),
          before: TestCatalogEntrySnapshot(fourth),
          after: TestCatalogEntrySnapshot(movedAfterBoundary),
        ),
      ),
    );

    final insertedBeforeBoundary = testSummary(index: 5);
    await completeCatalogCommand(
      container,
      repository,
      const CreateIntention(title: 'Новое', description: null),
      IntentionSaved(
        testIntention(index: 5, title: 'Новое'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(3),
          entry: TestCatalogEntrySnapshot(insertedBeforeBoundary),
        ),
      ),
    );

    final archivedThird = testSummary(
      index: 3,
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
          before: TestCatalogEntrySnapshot(third),
          after: TestCatalogEntrySnapshot(archivedThird),
        ),
      ),
    );

    await completeCatalogCommand(
      container,
      repository,
      RestoreIntention(third.id),
      IntentionSaved(
        testIntention(index: 3),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(5),
          before: TestCatalogEntrySnapshot(archivedThird),
          after: TestCatalogEntrySnapshot(third),
        ),
      ),
    );

    await completeCatalogCommand(
      container,
      repository,
      DeleteIntention(insertedBeforeBoundary.id),
      IntentionDeleted(
        insertedBeforeBoundary.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const TestCatalogRevision(6),
          entry: TestCatalogEntrySnapshot(insertedBeforeBoundary),
        ),
      ),
    );

    final current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.map((item) => item.id), [third.id]);
    expect(current.totalCount, 4);
    expect(current.nextCursor, same(cursor));
  });

  test(
    'перемещает изменённое намерение во всём загруженном результате',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
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
      notifier.changeOrder(IntentionCatalogOrder.updatedAtAscending);
      await waitForCatalogQueries(repository, 2);
      final first = testSummary(index: 1, updatedDay: 1);
      final second = testSummary(index: 2, updatedDay: 2);
      final third = testSummary(index: 3, updatedDay: 3);
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [first, second, third],
            totalCount: 3,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

      final moved = testSummary(index: 1, updatedDay: 4);
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(id: first.id, title: first.title, description: null),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(first),
            after: TestCatalogEntrySnapshot(moved),
          ),
        ),
      );

      final current =
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.map((item) => item.id), [
        second.id,
        third.id,
        moved.id,
      ]);
      expect(current.totalCount, 3);
      expect(current.nextCursor, isNull);
    },
  );

  test('сохраняет глобальный порядок и границу во всех порядках', () async {
    final scenarios =
        <
          ({
            IntentionCatalogOrder order,
            int firstPosition,
            int boundaryPosition,
            int remainingPosition,
            int insidePosition,
            int outsidePosition,
            int movedInsidePosition,
            int movedOutsidePosition,
          })
        >[
          (
            order: IntentionCatalogOrder.createdAtAscending,
            firstPosition: 1,
            boundaryPosition: 2,
            remainingPosition: 3,
            insidePosition: 0,
            outsidePosition: 4,
            movedInsidePosition: -1,
            movedOutsidePosition: 5,
          ),
          (
            order: IntentionCatalogOrder.createdAtDescending,
            firstPosition: 5,
            boundaryPosition: 4,
            remainingPosition: 3,
            insidePosition: 6,
            outsidePosition: 2,
            movedInsidePosition: 7,
            movedOutsidePosition: 1,
          ),
          (
            order: IntentionCatalogOrder.updatedAtAscending,
            firstPosition: 1,
            boundaryPosition: 2,
            remainingPosition: 3,
            insidePosition: 0,
            outsidePosition: 4,
            movedInsidePosition: -1,
            movedOutsidePosition: 5,
          ),
          (
            order: IntentionCatalogOrder.updatedAtDescending,
            firstPosition: 5,
            boundaryPosition: 4,
            remainingPosition: 3,
            insidePosition: 6,
            outsidePosition: 2,
            movedInsidePosition: 7,
            movedOutsidePosition: 1,
          ),
          (
            order: IntentionCatalogOrder.titleAscending,
            firstPosition: 1,
            boundaryPosition: 2,
            remainingPosition: 3,
            insidePosition: 0,
            outsidePosition: 4,
            movedInsidePosition: -1,
            movedOutsidePosition: 5,
          ),
          (
            order: IntentionCatalogOrder.titleDescending,
            firstPosition: 5,
            boundaryPosition: 4,
            remainingPosition: 3,
            insidePosition: 6,
            outsidePosition: 2,
            movedInsidePosition: 7,
            movedOutsidePosition: 1,
          ),
        ];
    // Названия по позициям -1…7. Регистр смешан так, что сравнение
    // исходных строк разошлось бы с ключом порядка у границы в обоих
    // направлениях.
    const titlesByPosition = [
      'абрикос',
      'банан',
      'вишня',
      'груша',
      'Дыня',
      'Ежевика',
      'Жимолость',
      'Земляника',
      'Инжир',
    ];

    for (final scenario in scenarios) {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 1,
      );
      final subscription = container.listen(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
        fireImmediately: true,
      );
      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      );
      if (scenario.order != IntentionCatalogOrder.createdAtDescending) {
        notifier.changeOrder(scenario.order);
        await waitForCatalogQueries(repository, 2);
      }
      final firstPageIndex = repository.queries.length - 1;
      const cursor = TestCatalogCursor();
      IntentionSummary atPosition(int index, int position) => testSummary(
        index: index,
        title: scenario.order.field == IntentionCatalogSortField.title
            ? titlesByPosition[position + 1]
            : 'Намерение',
        createdDay: scenario.order.field == IntentionCatalogSortField.createdAt
            ? position
            : index,
        updatedDay: scenario.order.field == IntentionCatalogSortField.updatedAt
            ? position
            : index,
      );

      final first = atPosition(20, scenario.firstPosition);
      final boundary = atPosition(21, scenario.boundaryPosition);
      final remaining = atPosition(22, scenario.remainingPosition);
      final inside = atPosition(23, scenario.insidePosition);
      final outside = atPosition(24, scenario.outsidePosition);
      repository.complete(
        firstPageIndex,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [first, boundary],
            totalCount: 3,
            nextCursor: cursor,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .future,
      );

      await completeCatalogCommand(
        container,
        repository,
        const CreateIntention(title: 'Внутри', description: null),
        IntentionSaved(
          testIntention(index: 23, title: 'Внутри'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(inside),
          ),
        ),
      );
      await completeCatalogCommand(
        container,
        repository,
        const CreateIntention(title: 'Снаружи', description: null),
        IntentionSaved(
          testIntention(index: 24, title: 'Снаружи'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(3),
            entry: TestCatalogEntrySnapshot(outside),
          ),
        ),
      );

      final movedOutside = atPosition(20, scenario.movedOutsidePosition);
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(
          id: first.id,
          title: movedOutside.title,
          description: null,
        ),
        IntentionSaved(
          testIntention(index: 20, title: movedOutside.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(4),
            before: TestCatalogEntrySnapshot(first),
            after: TestCatalogEntrySnapshot(movedOutside),
          ),
        ),
      );
      final movedInside = atPosition(22, scenario.movedInsidePosition);
      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(
          id: remaining.id,
          title: movedInside.title,
          description: null,
        ),
        IntentionSaved(
          testIntention(index: 22, title: movedInside.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(5),
            before: TestCatalogEntrySnapshot(remaining),
            after: TestCatalogEntrySnapshot(movedInside),
          ),
        ),
      );

      final beforeContinuation =
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      expect(beforeContinuation.items.map((item) => item.id), [
        movedInside.id,
        inside.id,
        boundary.id,
      ], reason: '${scenario.order.field}/${scenario.order.direction}');
      expect(beforeContinuation.totalCount, 5);
      expect(beforeContinuation.nextCursor, same(cursor));

      final continuationIndex = repository.queries.length;
      final load = notifier.loadNextPageIfNeeded(visibleIndex: 1);
      await waitForCatalogQueries(repository, continuationIndex + 1);
      expect(repository.queryAt(continuationIndex).cursor, same(cursor));
      repository.complete(
        continuationIndex,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [outside, movedOutside],
            nextCursor: null,
            revision: const TestCatalogRevision(5),
          ),
        ),
      );
      await load;

      final completed =
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      expect(completed.items.map((item) => item.id), [
        movedInside.id,
        inside.id,
        boundary.id,
        outside.id,
        movedOutside.id,
      ], reason: '${scenario.order.field}/${scenario.order.direction}');
      expect(completed.totalCount, 5);
      expect(completed.nextCursor, isNull);

      subscription.close();
      container.dispose();
    }
  });

  test(
    'использует точный historical membership вместо повторного folding',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
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

      final notifier = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      );
      notifier.changeTitleFilter('исторический');
      await waitForCatalogQueries(repository, 2);
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

      final summary = testSummary(index: 6, title: 'Новая проекция');
      await completeCatalogCommand(
        container,
        repository,
        const CreateIntention(title: 'Новая проекция', description: null),
        IntentionSaved(
          testIntention(index: 6, title: 'Новая проекция'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(summary, matchesResult: true),
          ),
        ),
      );

      final current =
          container
                  .read(
                    intentionCatalogViewModelProvider(
                      const BrowseIntentionCatalog(),
                    ),
                  )
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single.id, summary.id);
      expect(current.totalCount, 1);
    },
  );

  test('согласует данные независимо от владельца предъявления', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
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
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()).future,
    );

    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final created = testSummary(index: 30, title: 'Новое');
    final create = coordinator.acceptCreation(
      IntentionCreationFormKey(),
      const CreateIntention(title: 'Новое', description: null),
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      0,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: 30, title: 'Новое'),
          catalogMutation: IntentionCatalogCreated(
            revision: const TestCatalogRevision(2),
            entry: TestCatalogEntrySnapshot(created),
          ),
        ),
      ),
    );
    await create.future;
    await Future<void>.delayed(Duration.zero);

    var current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.single.id, created.id);
    expect(current.totalCount, 1);
    final ready = testSummary(
      index: 30,
      title: 'Новое',
      readiness: IntentionReadiness.ready,
    );
    final readiness = coordinator.acceptExisting(
      EnableIntentionReadiness(created.id),
      presentationTitle: created.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      1,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: 30, title: 'Новое'),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(created),
            after: TestCatalogEntrySnapshot(ready),
          ),
        ),
      ),
    );
    await readiness.future;
    await Future<void>.delayed(Duration.zero);
    current =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(current.items.single.readiness, IntentionReadiness.ready);
    expect(current.totalCount, 1);
    final successClaim = await presenter.nextClaim();
    expect(successClaim, isNotNull);
    // Успех готовности согласует данные, но не предъявляется.
    expect(successClaim!.completions.map((completion) => completion.token), [
      create.token,
    ]);
    coordinator.confirmAppPresentation(
      successClaim,
      successClaim.completions.map((completion) => completion.token),
    );
    expect(_loaded(container).items, current.items);
    expect(_loaded(container).totalCount, current.totalCount);

    final beforeFailure = current;
    final failed = coordinator.acceptExisting(
      ArchiveIntention(created.id),
      presentationTitle: created.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      2,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await failed.future;
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(container).items, beforeFailure.items);
    final failureClaim = await presenter.nextClaim();
    expect(failureClaim, isNotNull);
    expect(failureClaim!.completions.single.token, failed.token);
    coordinator.confirmAppPresentation(
      failureClaim,
      failureClaim.completions.map((completion) => completion.token),
    );
    presenter.release();
    await Future<void>.delayed(Duration.zero);

    expect(_loaded(container).items, beforeFailure.items);
  });

  group('полное создание', () {
    final health = _tag(1);
    final sport = _tag(2);
    final rest = _tag(3);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [sport.id],
    );

    IntentionSummary created({
      String title = 'Ходить в лес',
      required List<Tag> tags,
    }) => testSummary(
      index: 9,
      title: title,
      readiness: IntentionReadiness.ready,
      tags: tags,
    );

    // Готовность при выборе действия проверяет создание через настоящий
    // репозиторий; здесь — условия, по-разному сочетающиеся с фактами
    // назначений пакета.
    for (final (name, entry, matches) in <(String, IntentionSummary, bool)>[
      (
        'подходит названию, готовности и тегам',
        created(tags: [health, rest]),
        true,
      ),
      (
        'не подходит названию',
        created(title: 'Читать в лесу', tags: [health, rest]),
        false,
      ),
      ('без обязательного тега', created(tags: [rest]), false),
      ('с исключённым тегом', created(tags: [health, sport, rest]), false),
    ]) {
      test('принадлежность выдаче задаёт окончательный снимок, а пакет с '
          'фактами назначений применяется одним изменением ревизии: '
          '$name', () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 0,
        );
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        final model = container.read(provider.notifier);
        model.changeTitleFilter('ходить');
        model.changeTagFilter(filter);
        await waitForCatalogQueries(repository, 2);
        const cursor = TestCatalogCursor();
        final first = testSummary(
          index: 5,
          title: 'Ходить в парк',
          readiness: IntentionReadiness.ready,
          tags: [health],
        );
        final second = testSummary(
          index: 4,
          title: 'Ходить в зал',
          readiness: IntentionReadiness.ready,
          tags: [health, rest],
        );
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [first, second],
              totalCount: 3,
              nextCursor: cursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        final before =
            await container.read(provider.future) as IntentionCatalogLoaded;
        expect(before.query.includes(entry), matches);

        final completion = await completeFullCreation(
          container,
          repository,
          entry,
          revision: const TestCatalogRevision(2),
        );

        expect(completion.isFailure, isFalse);
        expect(
          completion.confirmedChange!.changes
              .whereType<IntentionCatalogMutation>(),
          hasLength(1),
        );
        final current =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(
          current.items,
          matches ? [entry, first, second] : [first, second],
        );
        expect(current.totalCount, matches ? 4 : 3);
        expect(current.nextCursor, same(cursor));
        expect(current.selection.titleFilterText, 'ходить');
        expect(current.selection.tagFilter, filter);
      });
    }
  });

  group('числа типов', () {
    test('поправляет оба числа при создании, смене готовности, архивировании '
        'и удалении', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
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

      final intention = testSummary(index: 1);
      final action = testSummary(index: 2, readiness: IntentionReadiness.ready);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [action, intention],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(provider.future);
      IntentionCatalogConfirmedState current() =>
          container.read(provider).requireValue
              as IntentionCatalogConfirmedState;
      void expectCounts({required int all, required int actions}) {
        final state = current();
        expect(state.typeCounts?.all, all);
        expect(state.typeCounts?.actions, actions);
        expect(state.totalCount, all);
      }

      expectCounts(all: 2, actions: 1);

      final created = testSummary(
        index: 3,
        readiness: IntentionReadiness.ready,
      );
      await completeFullCreation(
        container,
        repository,
        created,
        revision: const TestCatalogRevision(2),
      );
      expectCounts(all: 3, actions: 2);

      final intentionAsAction = testSummary(
        index: 1,
        readiness: IntentionReadiness.ready,
      );
      await completeCatalogCommand(
        container,
        repository,
        EnableIntentionReadiness(intention.id),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(intention),
            after: TestCatalogEntrySnapshot(intentionAsAction),
          ),
        ),
      );
      expectCounts(all: 3, actions: 3);

      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(action.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(4),
            before: TestCatalogEntrySnapshot(action),
            after: TestCatalogEntrySnapshot(
              testSummary(
                index: 2,
                readiness: IntentionReadiness.ready,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
          ),
        ),
      );
      expectCounts(all: 2, actions: 2);

      await completeCatalogCommand(
        container,
        repository,
        DeleteIntention(created.id),
        IntentionDeleted(
          created.id,
          catalogMutation: IntentionCatalogDeleted(
            revision: const TestCatalogRevision(5),
            entry: TestCatalogEntrySnapshot(created),
          ),
        ),
      );
      expectCounts(all: 1, actions: 1);
      expect(
        (current() as IntentionCatalogLoaded).items.map((item) => item.id),
        [intention.id],
      );
      expect(repository.queries, hasLength(1));
    });

    test(
      'смена готовности переносит намерение между типами выбранного типа',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
        final provider = intentionCatalogViewModelProvider(
          SelectRelationParticipant(
            selectionContext:
                RelationParticipantSelectionContext.activeRelation,
            session: IntentionSearchSession(),
          ),
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
              items: const [],
              totalCount: 0,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);
        container
            .read(provider.notifier)
            .changeType(IntentionTypeChoice.intentions);
        await waitForCatalogQueries(repository, 2);

        final intention = testSummary(index: 1);
        final action = testSummary(
          index: 2,
          readiness: IntentionReadiness.ready,
        );
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [intention],
              totalCount: 1,
              counts: IntentionCountsByType(
                IntentionTypeCounts(all: 2, actions: 1),
              ),
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);

        await completeCatalogCommand(
          container,
          repository,
          EnableIntentionReadiness(intention.id),
          IntentionSaved(
            testIntention(index: 1),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(intention),
              after: TestCatalogEntrySnapshot(
                testSummary(index: 1, readiness: IntentionReadiness.ready),
              ),
            ),
          ),
        );
        expect(
          container.read(provider).requireValue,
          isA<IntentionCatalogEmpty>()
              .having((state) => state.typeCounts?.all, 'все', 2)
              .having((state) => state.typeCounts?.actions, 'действия', 2),
        );

        final actionAsIntention = testSummary(index: 2);
        await completeCatalogCommand(
          container,
          repository,
          DisableIntentionReadiness(action.id),
          IntentionSaved(
            testIntention(index: 2),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(3),
              before: TestCatalogEntrySnapshot(action),
              after: TestCatalogEntrySnapshot(actionAsIntention),
            ),
          ),
        );
        expect(
          container.read(provider).requireValue,
          isA<IntentionCatalogLoaded>()
              .having((state) => state.items, 'строки', [actionAsIntention])
              .having((state) => state.totalCount, 'количество', 1)
              .having((state) => state.typeCounts?.all, 'все', 2)
              .having((state) => state.typeCounts?.actions, 'действия', 1),
        );
        expect(repository.queries, hasLength(2));
      },
    );
  });

  group('числа охватов и типов', () {
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );

    IntentionCountsByScopeAndType matrix(ProviderContainer container) =>
        switch (container.read(provider).requireValue) {
          IntentionCatalogConfirmedState(
            counts: final IntentionCountsByScopeAndType counts,
          ) =>
            counts,
          final state => fail('Нет матрицы чисел: $state'),
        };

    test('остаются точными после создания, изменения, смены готовности, '
        'архивирования, восстановления и удаления', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final intention = testSummary(index: 1);
      final action = testSummary(index: 2, readiness: IntentionReadiness.ready);
      final archivedIntention = testSummary(
        index: 3,
        archiveState: IntentionArchiveState.archived,
      );
      repository.completeVerbatim(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [action, intention],
            totalCount: 2,
            counts: IntentionCountsByScopeAndType(
              active: IntentionTypeCounts(all: 2, actions: 1),
              archived: IntentionTypeCounts(all: 1, actions: 0),
            ),
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(provider.future);
      void expectCounts({
        required int active,
        required int activeActions,
        required int archived,
        required int archivedActions,
      }) {
        final counts = matrix(container);
        expect(counts.active.all, active);
        expect(counts.active.actions, activeActions);
        expect(counts.archived.all, archived);
        expect(counts.archived.actions, archivedActions);
        final state = container.read(provider).requireValue;
        expect((state as IntentionCatalogConfirmedState).totalCount, active);
      }

      final created = testSummary(
        index: 4,
        readiness: IntentionReadiness.ready,
      );
      await completeFullCreation(
        container,
        repository,
        created,
        revision: const TestCatalogRevision(2),
      );
      expectCounts(
        active: 3,
        activeActions: 2,
        archived: 1,
        archivedActions: 0,
      );

      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(
          id: intention.id,
          title: 'Новое название',
          description: null,
        ),
        IntentionSaved(
          testIntention(index: 1, title: 'Новое название'),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(intention),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 1, title: 'Новое название'),
            ),
          ),
        ),
      );
      expectCounts(
        active: 3,
        activeActions: 2,
        archived: 1,
        archivedActions: 0,
      );

      await completeCatalogCommand(
        container,
        repository,
        EnableIntentionReadiness(intention.id),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(4),
            before: TestCatalogEntrySnapshot(intention),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 1, readiness: IntentionReadiness.ready),
            ),
          ),
        ),
      );
      expectCounts(
        active: 3,
        activeActions: 3,
        archived: 1,
        archivedActions: 0,
      );

      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(action.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(5),
            before: TestCatalogEntrySnapshot(action),
            after: TestCatalogEntrySnapshot(
              testSummary(
                index: 2,
                readiness: IntentionReadiness.ready,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
          ),
        ),
      );
      expectCounts(
        active: 2,
        activeActions: 2,
        archived: 2,
        archivedActions: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        RestoreIntention(archivedIntention.id),
        IntentionSaved(
          testIntention(index: 3),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(6),
            before: TestCatalogEntrySnapshot(archivedIntention),
            after: TestCatalogEntrySnapshot(testSummary(index: 3)),
          ),
        ),
      );
      expectCounts(
        active: 3,
        activeActions: 2,
        archived: 1,
        archivedActions: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        DeleteIntention(created.id),
        IntentionDeleted(
          created.id,
          catalogMutation: IntentionCatalogDeleted(
            revision: const TestCatalogRevision(7),
            entry: TestCatalogEntrySnapshot(created),
          ),
        ),
      );
      expectCounts(
        active: 2,
        activeActions: 1,
        archived: 1,
        archivedActions: 1,
      );
      expect(repository.queries, hasLength(1));
    });

    test(
      'считают снимки по условиям выдачи вне текущих охвата и типа',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          filterDebounce: Duration.zero,
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
              items: const [],
              totalCount: 0,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);
        notifier.changeType(IntentionTypeChoice.actions);
        await waitForCatalogQueries(repository, 2);
        notifier.changeTitleFilter('ходить');
        await waitForCatalogQueries(repository, 3);
        repository.completeVerbatim(
          2,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: const [],
              totalCount: 0,
              counts: IntentionCountsByScopeAndType(
                active: IntentionTypeCounts(all: 1, actions: 0),
                archived: IntentionTypeCounts(all: 0, actions: 0),
              ),
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);

        // Архивированное намерение входит в фильтр, а не в текущий охват.
        final archivedBefore = testSummary(
          index: 1,
          title: 'Гулять',
          archiveState: IntentionArchiveState.archived,
        );
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(
            id: archivedBefore.id,
            title: 'Ходить в парк',
            description: null,
          ),
          IntentionSaved(
            testIntention(index: 1, title: 'Ходить в парк'),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(archivedBefore),
              after: TestCatalogEntrySnapshot(
                testSummary(
                  index: 1,
                  title: 'Ходить в парк',
                  archiveState: IntentionArchiveState.archived,
                ),
              ),
            ),
          ),
        );

        // Намерение вне фильтра не меняет числа.
        final outsideFilter = testSummary(index: 2, title: 'Читать');
        await completeCatalogCommand(
          container,
          repository,
          ArchiveIntention(outsideFilter.id),
          IntentionSaved(
            testIntention(index: 2, title: 'Читать'),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(3),
              before: TestCatalogEntrySnapshot(outsideFilter),
              after: TestCatalogEntrySnapshot(
                testSummary(
                  index: 2,
                  title: 'Читать',
                  archiveState: IntentionArchiveState.archived,
                ),
              ),
            ),
          ),
        );

        final counts = matrix(container);
        expect(counts.active.all, 1);
        expect(counts.archived.all, 1);
        expect(counts.archived.actions, 0);
        expect(
          (container.read(provider).requireValue as IntentionCatalogEmpty)
              .totalCount,
          0,
        );
        expect(repository.queries, hasLength(3));
      },
    );

    for (final (name, counts, entry) in [
      (
        'отрицательные числа',
        IntentionCountsByScopeAndType(
          active: IntentionTypeCounts(all: 1, actions: 0),
          archived: IntentionTypeCounts(all: 0, actions: 0),
        ),
        testSummary(index: 2, archiveState: IntentionArchiveState.archived),
      ),
      (
        'действий больше всех намерений',
        IntentionCountsByScopeAndType(
          active: IntentionTypeCounts(all: 2, actions: 2),
          archived: IntentionTypeCounts(all: 0, actions: 0),
        ),
        testSummary(index: 2),
      ),
    ]) {
      test('$name начинают выдачу заново с первой порции', () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        final total = counts.active.all;
        repository.completeVerbatim(
          0,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [
                for (var index = 0; index < total; index++)
                  testSummary(index: 10 + index),
              ],
              totalCount: total,
              counts: counts,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);

        await completeCatalogCommand(
          container,
          repository,
          DeleteIntention(entry.id),
          IntentionDeleted(
            entry.id,
            catalogMutation: IntentionCatalogDeleted(
              revision: const TestCatalogRevision(2),
              entry: TestCatalogEntrySnapshot(entry),
            ),
          ),
        );

        await waitForCatalogQueries(repository, 2);
        expect(repository.queryAt(1).cursor, isNull);
      });
    }
  });

  group('занимающие связи поиска с пробой пары', () {
    const cursor = TestCatalogCursor();
    final counterpart = testSummary(index: 9);
    final fourth = testSummary(index: 4);
    final third = testSummary(index: 3);
    final later = testSummary(index: 1);
    final occupyingThird = testRelation(
      sourceIntentionId: counterpart.id,
      relatedIntentionId: third.id,
      index: 3,
    );
    final occupyingFourth = testRelation(
      sourceIntentionId: counterpart.id,
      relatedIntentionId: fourth.id,
      index: 4,
    );

    PairOccupant occupantOf(LongTermRelation relation) =>
        PairOccupant(relationId: relation.id, scope: relation.scope);

    /// Открывает поиск с пробой на первой порции [items]: при [nextCursor]
    /// за её границей остаются ещё две строки.
    Future<
      ({
        ProviderContainer container,
        ControlledCatalogRepository repository,
        IntentionCatalogLoaded Function() loaded,
      })
    >
    openSearch({
      required List<IntentionSummary> items,
      IntentionCatalogCursor? nextCursor,
      Map<IntentionId, PairOccupant> pairOccupants = const {},
    }) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 0,
      );
      final provider = intentionCatalogViewModelProvider(
        SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
          pairProbe: RelationPairProbe(
            counterpartId: counterpart.id,
            candidateRole: RelationParticipantRole.related,
          ),
        ),
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
            items: items,
            totalCount: items.length + (nextCursor == null ? 0 : 2),
            nextCursor: nextCursor,
            revision: const TestCatalogRevision(1),
            pairOccupants: pairOccupants,
          ),
        ),
      );
      await container.read(provider.future);
      return (
        container: container,
        repository: repository,
        loaded: () =>
            container.read(provider).requireValue as IntentionCatalogLoaded,
      );
    }

    test(
      'факты связей меняют отметки, не трогая строки, число и курсор',
      () async {
        final search = await openSearch(
          items: [fourth, third],
          nextCursor: cursor,
          pairOccupants: {third.id: occupantOf(occupyingThird)},
        );

        await completeRelationCommand(
          search.container,
          search.repository,
          DeleteLongTermRelation(occupyingThird.id),
          _relationSuccess(
            const TestCatalogRevision(2),
            LongTermRelationDeleted(
              relation: occupyingThird,
              changes: [
                LongTermRelationDeletedChange(
                  revision: const TestCatalogRevision(2),
                  relation: occupyingThird,
                ),
              ],
            ),
          ),
        );

        expect(search.loaded().pairOccupants, isEmpty);

        await completeRelationCommand(
          search.container,
          search.repository,
          CreateLongTermRelation(
            sourceIntentionId: counterpart.id,
            relatedIntentionId: fourth.id,
            type: occupyingFourth.type,
            priority: occupyingFourth.priority,
            description: null,
          ),
          _relationSuccess(
            const TestCatalogRevision(3),
            LongTermRelationCreated(
              relation: occupyingFourth,
              description: null,
              changes: [
                LongTermRelationCreatedChange(
                  revision: const TestCatalogRevision(3),
                  relation: occupyingFourth,
                ),
              ],
            ),
          ),
        );

        final current = search.loaded();
        expect(current.pairOccupants, {fourth.id: occupantOf(occupyingFourth)});
        expect(current.items.map((item) => item.id), [fourth.id, third.id]);
        expect(current.totalCount, 4);
        expect(current.nextCursor, same(cursor));
        expect(search.repository.queries, hasLength(1));
      },
    );

    test(
      'каскадное архивирование участника другой роли архивирует отметки',
      () async {
        final search = await openSearch(
          items: [fourth, third],
          pairOccupants: {
            fourth.id: occupantOf(occupyingFourth),
            third.id: occupantOf(occupyingThird),
          },
        );

        LongTermRelation archived(LongTermRelation relation) => testRelation(
          sourceIntentionId: relation.sourceIntentionId,
          relatedIntentionId: relation.relatedIntentionId,
          index: relation.creationSequence.value,
          scope: RelationScope.archived,
        );
        await completeCatalogCommand(
          search.container,
          search.repository,
          ArchiveIntention(counterpart.id),
          IntentionSaved(
            testIntention(index: 9),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(counterpart),
              after: TestCatalogEntrySnapshot(
                testSummary(
                  index: 9,
                  archiveState: IntentionArchiveState.archived,
                ),
              ),
            ),
            additionalChanges: [
              for (final relation in [occupyingFourth, occupyingThird])
                LongTermRelationUpdatedChange(
                  revision: const TestCatalogRevision(2),
                  before: relation,
                  after: archived(relation),
                ),
            ],
          ),
        );

        expect(search.loaded().pairOccupants, {
          fourth.id: occupantOf(archived(occupyingFourth)),
          third.id: occupantOf(archived(occupyingThird)),
        });
        expect(search.repository.queries, hasLength(1));
      },
    );

    test('оставшаяся строка сохраняет отметку, а ушедшая теряет её', () async {
      final search = await openSearch(
        items: [fourth, third],
        pairOccupants: {
          fourth.id: occupantOf(occupyingFourth),
          third.id: occupantOf(occupyingThird),
        },
      );

      final renamed = testSummary(index: 3, title: 'Новое название');
      await completeCatalogCommand(
        search.container,
        search.repository,
        UpdateIntention(id: third.id, title: renamed.title, description: null),
        IntentionSaved(
          testIntention(index: 3),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(third),
            after: TestCatalogEntrySnapshot(renamed),
          ),
        ),
      );
      await completeCatalogCommand(
        search.container,
        search.repository,
        ArchiveIntention(fourth.id),
        IntentionSaved(
          testIntention(index: 4),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(fourth),
            after: TestCatalogEntrySnapshot(
              testSummary(
                index: 4,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
          ),
        ),
      );

      final current = search.loaded();
      expect(current.items.map((item) => item.id), [third.id]);
      expect(current.pairOccupants, {third.id: occupantOf(occupyingThird)});
      expect(search.repository.queries, hasLength(1));
    });

    test(
      'созданное намерение входит свободным и не сбрасывает выдачу',
      () async {
        final search = await openSearch(
          items: [third],
          pairOccupants: {third.id: occupantOf(occupyingThird)},
        );

        final created = testSummary(index: 5, title: 'Новое');
        await completeCatalogCommand(
          search.container,
          search.repository,
          const CreateIntention(title: 'Новое', description: null),
          IntentionSaved(
            testIntention(index: 5, title: 'Новое'),
            catalogMutation: IntentionCatalogCreated(
              revision: const TestCatalogRevision(2),
              entry: TestCatalogEntrySnapshot(created),
            ),
          ),
        );

        final current = search.loaded();
        expect(current.items.map((item) => item.id), [created.id, third.id]);
        expect(current.pairOccupants, {third.id: occupantOf(occupyingThird)});
        expect(search.repository.queries, hasLength(1));
      },
    );

    test(
      'строка, вошедшая по изменению намерения, начинает выдачу заново',
      () async {
        final search = await openSearch(items: [third]);

        await completeCatalogCommand(
          search.container,
          search.repository,
          RestoreIntention(fourth.id),
          IntentionSaved(
            testIntention(index: 4),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(
                testSummary(
                  index: 4,
                  archiveState: IntentionArchiveState.archived,
                ),
              ),
              after: TestCatalogEntrySnapshot(fourth),
            ),
          ),
        );

        await waitForCatalogQueries(search.repository, 2);
        expect(search.repository.queryAt(1).cursor, isNull);
        final archivedOccupant = PairOccupant(
          relationId: occupyingFourth.id,
          scope: RelationScope.archived,
        );
        search.repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [fourth, third],
              totalCount: 2,
              nextCursor: null,
              revision: const TestCatalogRevision(2),
              pairOccupants: {fourth.id: archivedOccupant},
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final current = search.loaded();
        expect(current.items.map((item) => item.id), [fourth.id, third.id]);
        expect(current.pairOccupants, {fourth.id: archivedOccupant});
      },
    );

    test(
      'строка, перешедшая внутрь загруженной границы, начинает выдачу заново',
      () async {
        final search = await openSearch(
          items: [fourth, third],
          nextCursor: cursor,
        );

        await completeCatalogCommand(
          search.container,
          search.repository,
          UpdateIntention(id: later.id, title: later.title, description: null),
          IntentionSaved(
            testIntention(index: 1),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(later),
              after: TestCatalogEntrySnapshot(
                testSummary(index: 1, createdDay: 10),
              ),
            ),
          ),
        );

        await waitForCatalogQueries(search.repository, 2);
        expect(search.repository.queryAt(1).cursor, isNull);
      },
    );

    test('строка за загруженной границей выдачу не сбрасывает', () async {
      final search = await openSearch(
        items: [fourth, third],
        nextCursor: cursor,
      );

      await completeCatalogCommand(
        search.container,
        search.repository,
        RestoreIntention(later.id),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(2),
            before: TestCatalogEntrySnapshot(
              testSummary(
                index: 1,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
            after: TestCatalogEntrySnapshot(later),
          ),
        ),
      );

      final current = search.loaded();
      expect(current.items.map((item) => item.id), [fourth.id, third.id]);
      expect(current.totalCount, 5);
      expect(search.repository.queries, hasLength(1));
    });
  });
}

LongTermRelationCommandResult _relationSuccess(
  GraphRevision revision,
  LongTermRelationCommandSuccess success,
) =>
    GraphCommandSucceeded<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(ConfirmedGraphResult(revision: revision, value: success));

IntentionCatalogLoaded _loaded(ProviderContainer container) =>
    container
            .read(
              intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
            )
            .requireValue
        as IntentionCatalogLoaded;

Tag _tag(int number) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError('Неверный ID тега.'),
  },
  name: TagName.fromInput('Тег $number'),
  color: null,
  position: tagPositionAt(number),
);
