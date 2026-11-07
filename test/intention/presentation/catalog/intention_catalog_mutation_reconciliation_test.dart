import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
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
    final renamed = testSummary(index: 30, title: 'Новое имя');
    final rename = coordinator.acceptExisting(
      UpdateIntention(id: created.id, title: renamed.title, description: null),
      presentationTitle: created.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      1,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: 30, title: 'Новое имя'),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(created),
            after: TestCatalogEntrySnapshot(renamed),
          ),
        ),
      ),
    );
    await rename.future;
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
    expect(current.items.single.title, renamed.title);
    expect(current.totalCount, 1);
    final successClaim = await presenter.nextClaim();
    expect(successClaim, isNotNull);
    // Успех переименования согласует данные, но не предъявляется.
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
    }) => testSummary(index: 9, title: title, tags: tags);

    // Здесь — условия, по-разному сочетающиеся с фактами назначений пакета.
    for (final (name, entry, matches) in <(String, IntentionSummary, bool)>[
      ('подходит названию и тегам', created(tags: [health, rest]), true),
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
          tags: [health],
        );
        final second = testSummary(
          index: 4,
          title: 'Ходить в зал',
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

  group('общее количество поиска для выбора', () {
    test('поправляет количество при создании, смене вида, архивировании '
        'и удалении', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final provider = intentionCatalogViewModelProvider(_participantPurpose());
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final main = testSummary(index: 1);
      final supporting = testSummary(index: 2, kind: IntentionKind.supporting);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [supporting, main],
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
      void expectTotal(int total) {
        // Поиск для выбора считает только общее количество.
        expect(current().counts, isA<IntentionCountsTotalOnly>());
        expect(current().kindCounts, isNull);
        expect(current().totalCount, total);
      }

      expectTotal(2);
      expect(
        repository.queryAt(0).kindFilter,
        IntentionKindFilter.mainAndSupporting,
      );

      final created = testSummary(index: 3, kind: IntentionKind.supporting);
      await completeFullCreation(
        container,
        repository,
        created,
        revision: const TestCatalogRevision(2),
      );
      expectTotal(3);

      // Смена вида не выводит строку из поиска, где виды не различаются.
      await completeCatalogCommand(
        container,
        repository,
        ChangeIntentionKind(main.id, IntentionKind.supporting),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(3),
            before: TestCatalogEntrySnapshot(main),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 1, kind: IntentionKind.supporting),
            ),
          ),
        ),
      );
      expectTotal(3);
      expect(
        (current() as IntentionCatalogLoaded).items.map((item) => item.id),
        [created.id, supporting.id, main.id],
      );

      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(supporting.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(4),
            before: TestCatalogEntrySnapshot(supporting),
            after: TestCatalogEntrySnapshot(
              testSummary(
                index: 2,
                kind: IntentionKind.supporting,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
          ),
        ),
      );
      expectTotal(2);

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
      expectTotal(1);
      expect(
        (current() as IntentionCatalogLoaded).items.map((item) => item.id),
        [main.id],
      );
      expect(repository.queries, hasLength(1));
    });
  });

  group('числа охватов и видов', () {
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );

    IntentionCountsByScopeAndKind matrix(ProviderContainer container) =>
        switch (container.read(provider).requireValue) {
          IntentionCatalogConfirmedState(
            counts: final IntentionCountsByScopeAndKind counts,
          ) =>
            counts,
          final state => fail('Нет матрицы чисел: $state'),
        };

    test('остаются точными в каждой ячейке «архивное состояние × вид» после '
        'создания, изменения, смены вида, архивирования, восстановления '
        'и удаления', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final main = testSummary(index: 1);
      final otherMain = testSummary(index: 2);
      final archivedSupporting = testSummary(
        index: 5,
        kind: IntentionKind.supporting,
        archiveState: IntentionArchiveState.archived,
      );
      // Каталог открывается с видом «Только главные»: строки — активные
      // главные, а числа остальных ячеек приходят только в матрице.
      repository.completeVerbatim(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [otherMain, main],
            totalCount: 2,
            counts: IntentionCountsByScopeAndKind(
              active: IntentionKindCounts(main: 2, supporting: 1),
              archived: IntentionKindCounts(main: 1, supporting: 1),
            ),
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(provider.future);
      void expectCounts({
        required int activeMain,
        required int activeSupporting,
        required int archivedMain,
        required int archivedSupporting,
      }) {
        final counts = matrix(container);
        expect(counts.active.main, activeMain);
        expect(counts.active.supporting, activeSupporting);
        expect(counts.archived.main, archivedMain);
        expect(counts.archived.supporting, archivedSupporting);
        final state = container.read(provider).requireValue;
        expect(
          (state as IntentionCatalogConfirmedState).totalCount,
          activeMain,
        );
      }

      final created = testSummary(index: 6);
      await completeFullCreation(
        container,
        repository,
        created,
        revision: const TestCatalogRevision(2),
      );
      expectCounts(
        activeMain: 3,
        activeSupporting: 1,
        archivedMain: 1,
        archivedSupporting: 1,
      );

      final createdSupporting = testSummary(
        index: 4,
        kind: IntentionKind.supporting,
      );
      await completeFullCreation(
        container,
        repository,
        createdSupporting,
        revision: const TestCatalogRevision(3),
      );
      expectCounts(
        activeMain: 3,
        activeSupporting: 2,
        archivedMain: 1,
        archivedSupporting: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        UpdateIntention(
          id: main.id,
          title: 'Новое название',
          description: null,
        ),
        IntentionSaved(
          testIntention(index: 1, title: 'Новое название'),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(4),
            before: TestCatalogEntrySnapshot(main),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 1, title: 'Новое название'),
            ),
          ),
        ),
      );
      expectCounts(
        activeMain: 3,
        activeSupporting: 2,
        archivedMain: 1,
        archivedSupporting: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        ChangeIntentionKind(main.id, IntentionKind.supporting),
        IntentionSaved(
          testIntention(index: 1),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(5),
            before: TestCatalogEntrySnapshot(main),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 1, kind: IntentionKind.supporting),
            ),
          ),
        ),
      );
      expectCounts(
        activeMain: 2,
        activeSupporting: 3,
        archivedMain: 1,
        archivedSupporting: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        ArchiveIntention(otherMain.id),
        IntentionSaved(
          testIntention(index: 2),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(6),
            before: TestCatalogEntrySnapshot(otherMain),
            after: TestCatalogEntrySnapshot(
              testSummary(
                index: 2,
                archiveState: IntentionArchiveState.archived,
              ),
            ),
          ),
        ),
      );
      expectCounts(
        activeMain: 1,
        activeSupporting: 3,
        archivedMain: 2,
        archivedSupporting: 1,
      );

      await completeCatalogCommand(
        container,
        repository,
        RestoreIntention(archivedSupporting.id),
        IntentionSaved(
          testIntention(index: 5),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(7),
            before: TestCatalogEntrySnapshot(archivedSupporting),
            after: TestCatalogEntrySnapshot(
              testSummary(index: 5, kind: IntentionKind.supporting),
            ),
          ),
        ),
      );
      expectCounts(
        activeMain: 1,
        activeSupporting: 4,
        archivedMain: 2,
        archivedSupporting: 0,
      );

      await completeCatalogCommand(
        container,
        repository,
        DeleteIntention(createdSupporting.id),
        IntentionDeleted(
          createdSupporting.id,
          catalogMutation: IntentionCatalogDeleted(
            revision: const TestCatalogRevision(8),
            entry: TestCatalogEntrySnapshot(createdSupporting),
          ),
        ),
      );
      expectCounts(
        activeMain: 1,
        activeSupporting: 3,
        archivedMain: 2,
        archivedSupporting: 0,
      );
      expect(
        (container.read(provider).requireValue as IntentionCatalogLoaded).items
            .map((item) => item.id),
        [created.id],
      );
      expect(repository.queries, hasLength(1));
    });

    for (final (name, kindFilter, kept) in [
      (
        'выводит строку из каталога «Только главные» и переносит единицу '
            'между видами',
        IntentionKindFilter.mainOnly,
        false,
      ),
      (
        'оставляет строку и количество в каталоге «Главные и вспомогательные»',
        IntentionKindFilter.mainAndSupporting,
        true,
      ),
    ]) {
      test(
        'смена вида намерения с главного на вспомогательное $name',
        () async {
          final repository = ControlledCatalogRepository();
          final container = reconciliationCatalogContainer(repository);
          final subscription = container.listen(
            provider,
            (_, _) {},
            fireImmediately: true,
          );
          addTearDown(subscription.close);
          addTearDown(container.dispose);

          final main = testSummary(index: 1);
          final other = testSummary(index: 2);
          final supporting = testSummary(
            index: 3,
            kind: IntentionKind.supporting,
          );
          // Каталог открывается с видом «Только главные».
          repository.completeVerbatim(
            0,
            ResultSuccess(
              IntentionCatalogFirstPage(
                items: [other, main],
                totalCount: 2,
                counts: IntentionCountsByScopeAndKind(
                  active: IntentionKindCounts(main: 2, supporting: 1),
                  archived: IntentionKindCounts(main: 0, supporting: 0),
                ),
                nextCursor: null,
                revision: const TestCatalogRevision(1),
              ),
            ),
          );
          await container.read(provider.future);
          if (kindFilter != IntentionKindFilter.mainOnly) {
            container.read(provider.notifier).changeKind(kindFilter);
            await waitForCatalogQueries(repository, 2);
            repository.completeVerbatim(
              1,
              ResultSuccess(
                IntentionCatalogFirstPage(
                  items: [supporting, other, main],
                  totalCount: 3,
                  counts: IntentionCountsByScopeAndKind(
                    active: IntentionKindCounts(main: 2, supporting: 1),
                    archived: IntentionKindCounts(main: 0, supporting: 0),
                  ),
                  nextCursor: null,
                  revision: const TestCatalogRevision(1),
                ),
              ),
            );
            await container.read(provider.future);
          }

          await completeCatalogCommand(
            container,
            repository,
            ChangeIntentionKind(main.id, IntentionKind.supporting),
            IntentionSaved(
              testIntention(index: 1),
              catalogMutation: IntentionCatalogUpdated(
                revision: const TestCatalogRevision(2),
                before: TestCatalogEntrySnapshot(main),
                after: TestCatalogEntrySnapshot(
                  testSummary(index: 1, kind: IntentionKind.supporting),
                ),
              ),
            ),
          );

          final state =
              container.read(provider).requireValue as IntentionCatalogLoaded;
          expect(
            state.items.map((item) => item.id),
            kept ? [supporting.id, other.id, main.id] : [other.id],
          );
          expect(state.totalCount, kept ? 3 : 1);
          final counts = matrix(container);
          expect(counts.active.main, 1);
          expect(counts.active.supporting, 2);
          expect(repository.queries, hasLength(kept ? 2 : 1));
        },
      );
    }

    test(
      'считают снимки по условиям выдачи вне текущих охвата и вида',
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
        notifier.changeKind(IntentionKindFilter.supportingOnly);
        await waitForCatalogQueries(repository, 2);
        notifier.changeTitleFilter('ходить');
        await waitForCatalogQueries(repository, 3);
        repository.completeVerbatim(
          2,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: const [],
              totalCount: 0,
              counts: IntentionCountsByScopeAndKind(
                active: IntentionKindCounts(main: 1, supporting: 0),
                archived: IntentionKindCounts(main: 0, supporting: 0),
              ),
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        await container.read(provider.future);

        // Архивированное главное намерение входит в фильтр, а не в текущие
        // охват и вид.
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
        expect(counts.active.main, 1);
        expect(counts.active.supporting, 0);
        expect(counts.archived.main, 1);
        expect(counts.archived.supporting, 0);
        expect(
          (container.read(provider).requireValue as IntentionCatalogEmpty)
              .totalCount,
          0,
        );
        expect(repository.queries, hasLength(3));
      },
    );

    for (final (name, entry) in [
      (
        'отрицательное число главных архивной ячейки',
        testSummary(index: 2, archiveState: IntentionArchiveState.archived),
      ),
      (
        'отрицательное число вспомогательных активной ячейки',
        testSummary(index: 2, kind: IntentionKind.supporting),
      ),
    ]) {
      test('$name начинает выдачу заново с первой порции', () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
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
              items: [testSummary(index: 10)],
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

  group('точное название в поиске участника', () {
    test(
      'учитывает изменения исключённого участника и не перечитывает выдачу',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          filterDebounce: Duration.zero,
        );
        final counterpart = testSummary(index: 9, title: 'Другое');
        final provider = intentionCatalogViewModelProvider(
          SelectRelationParticipant(
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
        container.read(provider.notifier).changeTitleFilter('  Читать  ');
        await waitForCatalogQueries(repository, 2);
        repository.completeVerbatim(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: const [],
              totalCount: 0,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
              pairOccupants: const {},
              exactTitleCount: 0,
            ),
          ),
        );
        await container.read(provider.future);
        IntentionCatalogConfirmedState current() =>
            container.read(provider).requireValue
                as IntentionCatalogConfirmedState;
        expect(current().createTitle, 'Читать');
        final exact = testSummary(index: 9, title: 'ЧИТАТЬ');
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(
            id: counterpart.id,
            title: exact.title,
            description: null,
          ),
          IntentionSaved(
            testIntention(index: 9, title: exact.title),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(counterpart),
              after: TestCatalogEntrySnapshot(exact),
            ),
          ),
        );
        expect(current().exactTitleCount, 1);
        expect(current().createTitle, isNull);
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(
            id: counterpart.id,
            title: counterpart.title,
            description: null,
          ),
          IntentionSaved(
            testIntention(index: 9),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(3),
              before: TestCatalogEntrySnapshot(exact),
              after: TestCatalogEntrySnapshot(counterpart),
            ),
          ),
        );
        expect(current().exactTitleCount, 0);
        expect(current().createTitle, 'Читать');
        expect(current(), isA<IntentionCatalogEmpty>());
        expect(repository.queries, hasLength(2));
      },
    );
    test(
      'совпадения считаются при переименовании, архивировании и удалении',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          filterDebounce: Duration.zero,
        );
        final counterpart = testSummary(index: 9);
        final provider = intentionCatalogViewModelProvider(
          SelectRelationParticipant(
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
        container.read(provider.notifier).changeTitleFilter('Читать');
        await waitForCatalogQueries(repository, 2);
        final longer = testSummary(index: 1, title: 'Читать книгу');
        final exact = testSummary(index: 1, title: 'Читать');
        repository.completeVerbatim(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [longer],
              totalCount: 1,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
              pairOccupants: const {},
              exactTitleCount: 0,
            ),
          ),
        );
        await container.read(provider.future);
        IntentionCatalogConfirmedState current() =>
            container.read(provider).requireValue
                as IntentionCatalogConfirmedState;
        expect(current().createTitle, 'Читать');
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(id: exact.id, title: exact.title, description: null),
          IntentionSaved(
            testIntention(index: 1, title: exact.title),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(longer),
              after: TestCatalogEntrySnapshot(exact),
            ),
          ),
        );
        expect(current().createTitle, isNull);
        final second = testSummary(index: 2, title: 'читать');
        await completeFullCreation(
          container,
          repository,
          second,
          revision: const TestCatalogRevision(3),
        );
        expect(current().exactTitleCount, 2);
        final archived = testSummary(
          index: 1,
          title: 'Читать',
          archiveState: IntentionArchiveState.archived,
        );
        await completeCatalogCommand(
          container,
          repository,
          ArchiveIntention(exact.id),
          IntentionSaved(
            testIntention(index: 1),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(4),
              before: TestCatalogEntrySnapshot(exact),
              after: TestCatalogEntrySnapshot(archived),
            ),
          ),
        );
        expect(current().exactTitleCount, 1);
        expect(current().createTitle, isNull);
        await completeCatalogCommand(
          container,
          repository,
          DeleteIntention(second.id),
          IntentionDeleted(
            second.id,
            catalogMutation: IntentionCatalogDeleted(
              revision: const TestCatalogRevision(5),
              entry: TestCatalogEntrySnapshot(second),
            ),
          ),
        );
        expect(current(), isA<IntentionCatalogEmpty>());
        expect(current().exactTitleCount, 0);
        expect(current().createTitle, 'Читать');
        expect(repository.queries, hasLength(2));
      },
    );

    test('пакет ревизии порции не меняет её число повторно', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        filterDebounce: Duration.zero,
      );
      final counterpart = testSummary(index: 9);
      final provider = intentionCatalogViewModelProvider(
        SelectRelationParticipant(
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
      container.read(provider.notifier).changeTitleFilter('Читать');
      await waitForCatalogQueries(repository, 2);
      final created = testSummary(index: 1, title: 'Читать');
      await completeFullCreation(
        container,
        repository,
        created,
        revision: const TestCatalogRevision(2),
      );
      repository.completeVerbatim(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [created],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(2),
            pairOccupants: const {},
            exactTitleCount: 1,
          ),
        ),
      );
      final current = await container.read(
        provider.future,
      ) as IntentionCatalogConfirmedState;
      expect(current.exactTitleCount, 1);
      expect(current.createTitle, isNull);
      expect(repository.queries, hasLength(2));
    });
    test(
      'поправка сохраняет курсор и число при загрузке продолжения',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          filterDebounce: Duration.zero,
          pageSize: 1,
          prefetchRemaining: 0,
        );
        final counterpart = testSummary(index: 9, title: 'Другое');
        final provider = intentionCatalogViewModelProvider(
          SelectRelationParticipant(
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
        container.read(provider.notifier).changeTitleFilter('Читать');
        await waitForCatalogQueries(repository, 2);
        const cursor = TestCatalogCursor();
        final first = testSummary(index: 2, title: 'Читать первое');
        final second = testSummary(index: 1, title: 'Читать второе');
        repository.completeVerbatim(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [first],
              totalCount: 2,
              nextCursor: cursor,
              revision: const TestCatalogRevision(1),
              pairOccupants: const {},
              exactTitleCount: 0,
            ),
          ),
        );
        await container.read(provider.future);
        final renamed = testSummary(index: 9, title: 'Читать');
        await completeCatalogCommand(
          container,
          repository,
          UpdateIntention(
            id: counterpart.id,
            title: renamed.title,
            description: null,
          ),
          IntentionSaved(
            testIntention(index: 9, title: renamed.title),
            catalogMutation: IntentionCatalogUpdated(
              revision: const TestCatalogRevision(2),
              before: TestCatalogEntrySnapshot(counterpart),
              after: TestCatalogEntrySnapshot(renamed),
            ),
          ),
        );
        var current =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(current.nextCursor, same(cursor));
        expect(current.items.single.id, first.id);
        expect(current.exactTitleCount, 1);
        expect(repository.queries, hasLength(2));
        final continuation = container
            .read(provider.notifier)
            .loadNextPageIfNeeded(visibleIndex: 0);
        repository.completeVerbatim(
          2,
          ResultSuccess(
            IntentionCatalogContinuationPage(
              items: [second],
              nextCursor: null,
              revision: const TestCatalogRevision(2),
              pairOccupants: const {},
            ),
          ),
        );
        await continuation;
        current =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(current.items.map((item) => item.id), [first.id, second.id]);
        expect(current.exactTitleCount, 1);
        expect(current.createTitle, isNull);
      },
    );
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
      priority: RelationPriority.p4,
    );

    PairOccupant occupantOf(LongTermRelation relation) => PairOccupant(
      relationId: relation.id,
      type: relation.type,
      scope: relation.scope,
    );

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
          AddLongTermRelations(
            pageIntentionId: counterpart.id,
            candidateIds: [fourth.id],
            group: (occupyingFourth.type == LongTermRelationType.need
                ? IntentionRelationGroup.needs
                : IntentionRelationGroup.canUse),
          ),
          _relationSuccess(
            const TestCatalogRevision(3),
            LongTermRelationsAdded(
              relations: [occupyingFourth],
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
          priority: relation.priority,
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
          type: occupyingFourth.type,
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

SelectRelationParticipant _participantPurpose() => SelectRelationParticipant(
  session: IntentionSearchSession(),
  pairProbe: RelationPairProbe(
    counterpartId: testSummary(index: 999).id,
    candidateRole: RelationParticipantRole.related,
  ),
);
