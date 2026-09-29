import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  test(
    'поиск только по тегам начинает первую порцию и заменяет прежний префикс',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 1,
        prefetchRemaining: 0,
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
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 1)],
            totalCount: 2,
            nextCursor: const TestCatalogCursor(),
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      final filters = [
        IntentionTagFilter(requiredTagIds: [_tagId(1)]),
        IntentionTagFilter(excludedTagIds: [_tagId(2)]),
        IntentionTagFilter(
          requiredTagIds: [_tagId(1)],
          excludedTagIds: [_tagId(1)],
        ),
      ];
      for (var index = 0; index < filters.length; index++) {
        notifier.changeTagFilter(filters[index]);
        await waitForCatalogQueries(repository, index + 2);
        final query = repository.queryAt(index + 1);
        expect(query.cursor, isNull);
        expect(query.titleFilter, isNull);
        expect(query.tagFilter, filters[index]);
        if (index == 2) {
          _completeEmptyPage(repository, index + 1);
          final empty =
              await container.read(provider.future) as IntentionCatalogEmpty;
          expect(empty.selection.tagFilter, filters[index]);
          expect(empty.totalCount, 0);
          expect(empty.nextCursor, isNull);
        } else {
          final summary = testSummary(index: index + 2);
          repository.complete(
            index + 1,
            ResultSuccess(
              IntentionCatalogFirstPage(
                items: [summary],
                totalCount: 1,
                nextCursor: null,
                revision: const TestCatalogRevision(0),
              ),
            ),
          );
          final loaded =
              await container.read(provider.future) as IntentionCatalogLoaded;
          expect(loaded.items.map((item) => item.id), [summary.id]);
          expect(loaded.totalCount, 1);
          expect(loaded.nextCursor, isNull);
        }
      }
    },
  );

  testWidgets(
    'изменение каждого набора тегов сразу применяет текущий текст и отменяет debounce',
    (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
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
      _completeEmptyPage(repository, 0);
      await tester.pump(Duration.zero);

      final notifier = container.read(provider.notifier);
      notifier.changeTitleFilter('  ходить  ');
      await tester.pump(Duration.zero);
      expect(
        container.read(provider).requireValue,
        isA<IntentionCatalogDebouncing>(),
      );
      expect(repository.queries, hasLength(1));

      final health = _tagId(1);
      final rest = _tagId(2);
      final sport = _tagId(3);
      final filters = [
        IntentionTagFilter(requiredTagIds: [health], excludedTagIds: [sport]),
        IntentionTagFilter(
          requiredTagIds: [health, rest],
          excludedTagIds: [sport],
        ),
        IntentionTagFilter(requiredTagIds: [rest], excludedTagIds: [sport]),
        IntentionTagFilter(requiredTagIds: [rest]),
        IntentionTagFilter(excludedTagIds: [sport]),
        IntentionTagFilter.empty,
      ];
      for (var index = 0; index < filters.length; index++) {
        final filter = filters[index];
        notifier.changeTagFilter(filter);
        expect(notifier.selection.tagFilter, filter);
        await tester.pump(Duration.zero);
        expect(repository.queries, hasLength(index + 2));
        final query = repository.queryAt(index + 1);
        expect(query.tagFilter, filter);
        expect(query.titleFilter?.map((value) => value), 'ходить');
        expect(query.scope, IntentionScope.active);
        expect(query.order, IntentionCatalogOrder.createdAtDescending);
        expect(query.cursor, isNull);
        _completeEmptyPage(repository, index + 1);
        await tester.pump(Duration.zero);
        expect(
          container.read(provider).requireValue.selection.tagFilter,
          filter,
        );
      }
      await tester.pump(const Duration(milliseconds: 251));
      expect(repository.queries, hasLength(filters.length + 1));
      expect(repository.commands, isEmpty);
      expect(repository.relationCommands, isEmpty);
      expect(repository.dailyChoiceCommands, isEmpty);
    },
  );

  testWidgets(
    'равные наборы тегов не перезапускают поиск и сохраняют debounce текста',
    (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
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
      _completeEmptyPage(repository, 0);
      await tester.pump(Duration.zero);
      final notifier = container.read(provider.notifier);
      notifier.changeTagFilter(
        IntentionTagFilter(
          requiredTagIds: [_tagId(1), _tagId(2)],
          excludedTagIds: [_tagId(3)],
        ),
      );
      await tester.pump(Duration.zero);
      _completeEmptyPage(repository, 1);
      await tester.pump(Duration.zero);

      notifier.changeTitleFilter('новое');
      notifier.changeTagFilter(
        IntentionTagFilter(
          requiredTagIds: [_tagId(2), _tagId(1), _tagId(2)],
          excludedTagIds: [_tagId(3)],
        ),
      );
      await tester.pump(Duration.zero);
      expect(repository.queries, hasLength(2));
      expect(
        container.read(provider).requireValue,
        isA<IntentionCatalogDebouncing>(),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(repository.queries, hasLength(3));
      expect(repository.queryAt(2).tagFilter, notifier.selection.tagFilter);
      expect(repository.queryAt(2).titleFilter?.map((value) => value), 'новое');
      _completeEmptyPage(repository, 2);
      await tester.pump(Duration.zero);
    },
  );

  for (final (text, failure) in [
    (
      'нуль\u0000внутри',
      IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
    ),
    (
      String.fromCharCode(0xd800),
      IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
    ),
    (
      List.filled(256, 'я').join(),
      IntentionCatalogFilterValidationFailure.tooLong,
    ),
  ]) {
    testWidgets(
      'изменение тегов сразу отклоняет недопустимый текст длиной ${text.length}',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
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
        _completeEmptyPage(repository, 0);
        await tester.pump(Duration.zero);
        final notifier = container.read(provider.notifier);
        final filter = IntentionTagFilter(
          requiredTagIds: [_tagId(1)],
          excludedTagIds: [_tagId(2)],
        );
        notifier.changeTitleFilter(text);
        notifier.changeTagFilter(filter);
        await tester.pump(Duration.zero);
        final invalid =
            container.read(provider).requireValue
                as IntentionCatalogInvalidFilter;
        expect(invalid.selection.titleFilterText, text);
        expect(invalid.selection.tagFilter, filter);
        expect(invalid.selection.filterValidationFailure, failure);
        await tester.pump(const Duration(milliseconds: 251));
        expect(repository.queries, hasLength(1));

        notifier.changeTitleFilter('верное');
        await tester.pump(const Duration(milliseconds: 250));
        expect(repository.queryAt(1).tagFilter, filter);
        expect(
          repository.queryAt(1).titleFilter?.map((value) => value),
          'верное',
        );
        _completeEmptyPage(repository, 1);
        await tester.pump(Duration.zero);
      },
    );
  }

  test(
    'охват, порядок, текст и повтор первой порции сохраняют оба набора тегов',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        filterDebounce: Duration.zero,
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
      _completeEmptyPage(repository, 0);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(1), _tagId(2)],
        excludedTagIds: [_tagId(3), _tagId(4)],
      );
      notifier.changeTagFilter(filter);
      await waitForCatalogQueries(repository, 2);
      _completeEmptyPage(repository, 1);
      await container.read(provider.future);
      notifier.changeTitleFilter('  ходить  ');
      await waitForCatalogQueries(repository, 3);
      _completeEmptyPage(repository, 2);
      await container.read(provider.future);
      notifier.changeOrder(IntentionCatalogOrder.updatedAtAscending);
      await waitForCatalogQueries(repository, 4);
      _completeEmptyPage(repository, 3);
      await container.read(provider.future);
      notifier.changeScope(IntentionScope.archived);
      await waitForCatalogQueries(repository, 5);
      repository.complete(
        4,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await container.read(provider.future);
      await notifier.retry();
      await waitForCatalogQueries(repository, 6);
      for (final query in repository.queries.skip(1)) {
        expect(query.tagFilter, filter);
        expect(query.cursor, isNull);
      }
      final query = repository.queryAt(5);
      expect(query.scope, IntentionScope.archived);
      expect(query.order, IntentionCatalogOrder.updatedAtAscending);
      expect(query.titleFilter?.map((value) => value), 'ходить');
      expect(notifier.selection.tagFilter, filter);
      _completeEmptyPage(repository, 5);
      await container.read(provider.future);
    },
  );

  test(
    'четыре назначения сохраняют независимые условия тегов и свои ограничения',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      final excluded = testSummary(index: 9).id;
      final purposes = <IntentionCatalogPurpose>[
        const BrowseIntentionCatalog(),
        const SelectDailyChoiceAction(),
        const SelectDailyChoiceSource(),
        SelectRelationParticipant(
          excludedIntentionId: excluded,
          selectionContext: RelationParticipantSelectionContext.activeRelation,
        ),
        SelectRelationParticipant(
          excludedIntentionId: excluded,
          selectionContext:
              RelationParticipantSelectionContext.archivedRelation,
        ),
      ];
      final filters = <IntentionTagFilter>[];
      for (var index = 0; index < purposes.length; index++) {
        final provider = intentionCatalogViewModelProvider(purposes[index]);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        expect(repository.queryAt(index).tagFilter, IntentionTagFilter.empty);
        _completeEmptyPage(repository, index);
        await container.read(provider.future);
        filters.add(
          IntentionTagFilter(
            requiredTagIds: [_tagId(index + 1)],
            excludedTagIds: [_tagId(index + 10)],
          ),
        );
      }
      for (var index = 0; index < purposes.length; index++) {
        final provider = intentionCatalogViewModelProvider(purposes[index]);
        final notifier = container.read(provider.notifier);
        notifier.changeTitleFilter('  свой $index  ');
        notifier.changeTagFilter(filters[index]);
        await waitForCatalogQueries(repository, purposes.length + index + 1);
        final query = repository.queryAt(purposes.length + index);
        expect(query.tagFilter, filters[index]);
        expect(query.titleFilter?.map((value) => value), 'свой $index');
        expect(
          query.scope,
          index == 4 ? IntentionScope.all : IntentionScope.active,
        );
        expect(
          query.readinessFilter,
          index == 1
              ? IntentionReadinessFilter.readyOnly
              : IntentionReadinessFilter.all,
        );
        expect(query.excludedIntentionId, index >= 3 ? excluded : null);
        _completeEmptyPage(repository, purposes.length + index);
        await container.read(provider.future);
      }
      final browse = container.read(
        intentionCatalogViewModelProvider(purposes.first).notifier,
      );
      browse.changeTagFilter(IntentionTagFilter.empty);
      await waitForCatalogQueries(repository, 11);
      _completeEmptyPage(repository, 10);
      await container.read(
        intentionCatalogViewModelProvider(purposes.first).future,
      );
      for (var index = 1; index < purposes.length; index++) {
        final notifier = container.read(
          intentionCatalogViewModelProvider(purposes[index]).notifier,
        );
        expect(notifier.selection.tagFilter, filters[index]);
        expect(notifier.selection.titleFilterText, '  свой $index  ');
        notifier.changeScope(IntentionScope.archived);
        expect(
          notifier.selection.scope,
          index == 4 ? IntentionScope.all : IntentionScope.active,
        );
      }
      expect(repository.queries, hasLength(11));
      expect(repository.commands, isEmpty);
      expect(repository.relationCommands, isEmpty);
      expect(repository.dailyChoiceCommands, isEmpty);
    },
  );

  for (final purpose in <IntentionCatalogPurpose>[
    const BrowseIntentionCatalog(),
    const SelectDailyChoiceAction(),
    const SelectDailyChoiceSource(),
    SelectRelationParticipant(
      excludedIntentionId: testSummary(index: 9).id,
      selectionContext: RelationParticipantSelectionContext.activeRelation,
    ),
    SelectRelationParticipant(
      excludedIntentionId: testSummary(index: 9).id,
      selectionContext: RelationParticipantSelectionContext.archivedRelation,
    ),
  ]) {
    final context = switch (purpose) {
      BrowseIntentionCatalog() => 'каталог',
      SelectDailyChoiceAction() => 'действие',
      SelectDailyChoiceSource() => 'исходное намерение',
      SelectRelationParticipant(
        selectionContext: RelationParticipantSelectionContext.activeRelation,
      ) =>
        'участник активной связи',
      SelectRelationParticipant(
        selectionContext: RelationParticipantSelectionContext.archivedRelation,
      ) =>
        'участник архивной связи',
    };
    test(
      'продолжение, его повтор и восстановление сохраняют совместный запрос: $context',
      () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          pageSize: 1,
          prefetchRemaining: 0,
        );
        final provider = intentionCatalogViewModelProvider(purpose);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        _completeEmptyPage(repository, 0);
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);
        final filter = IntentionTagFilter(
          requiredTagIds: [_tagId(1)],
          excludedTagIds: [_tagId(2)],
        );
        notifier.changeTitleFilter('  ходить  ');
        notifier.changeOrder(IntentionCatalogOrder.updatedAtAscending);
        notifier.changeTagFilter(filter);
        await waitForCatalogQueries(repository, 2);
        const cursor = TestCatalogCursor();
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [testSummary()],
              totalCount: 2,
              nextCursor: cursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        final first =
            await container.read(provider.future) as IntentionCatalogLoaded;
        final continuation = notifier.loadNextPageIfNeeded(visibleIndex: 0);
        repository.complete(
          2,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await continuation;
        final retry = notifier.retryNextPage();
        repository.complete(
          3,
          const ResultFailure(IntentionGenericValidationFailure()),
        );
        await retry;
        final recovery = notifier.recoverFromInvalidCursor();
        repository.complete(
          4,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await recovery;
        final recoveryRetry = notifier.retryRecovery();
        _completeEmptyPage(repository, 5, revision: 1);
        await recoveryRetry;
        for (final query in repository.queries.skip(2)) {
          expect(query.tagFilter, filter);
          expect(query.scope, first.query.scope);
          expect(query.readinessFilter, first.query.readinessFilter);
          expect(
            query.excludedIntentionId,
            purpose is SelectRelationParticipant
                ? purpose.excludedIntentionId
                : null,
          );
          expect(query.titleFilter?.map((value) => value), 'ходить');
          expect(query.order, IntentionCatalogOrder.updatedAtAscending);
          expect(query.pageSize, 1);
        }
        expect(repository.queryAt(2).cursor, same(cursor));
        expect(repository.queryAt(3).cursor, same(cursor));
        expect(repository.queryAt(4).cursor, isNull);
        expect(repository.queryAt(5).cursor, isNull);
        expect(
          container.read(provider).requireValue.selection.tagFilter,
          filter,
        );
      },
    );
  }
}

TagId _tagId(int index) => switch (TagId.decode(
  '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError(
    'Некорректный идентификатор тега в тесте.',
  ),
};

void _completeEmptyPage(
  ControlledCatalogRepository repository,
  int index, {
  int revision = 0,
}) {
  repository.complete(
    index,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: TestCatalogRevision(revision),
      ),
    ),
  );
}
