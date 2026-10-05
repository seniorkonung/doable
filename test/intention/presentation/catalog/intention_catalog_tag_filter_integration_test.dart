import 'dart:convert';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart' as tag_domain;
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';
import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late DriftPersonalGraphRepository repository;
  late _CatalogReadFault fault;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    fault = _CatalogReadFault();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        fault,
      ),
    );
    await database.open();
    await _seedCatalog(database);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 29),
      diagnostics,
    );
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 2,
            prefetchRemaining: 0,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  for (final (name, purpose, expectedIds)
      in <(String, IntentionCatalogPurpose, List<int>)>[
        ('каталог', const BrowseIntentionCatalog(), [10, 2, 1]),
        ('действие', const SelectDailyChoiceAction(), [10, 1]),
        ('исходное намерение', const SelectDailyChoiceSource(), [10, 2, 1]),
        (
          'участник активной связи',
          SelectRelationParticipant(
            excludedIntentionId: _intentionId(2),
            selectionContext:
                RelationParticipantSelectionContext.activeRelation,
          ),
          [10, 1],
        ),
        (
          'участник архивной связи',
          SelectRelationParticipant(
            excludedIntentionId: _intentionId(2),
            selectionContext:
                RelationParticipantSelectionContext.archivedRelation,
          ),
          [10, 9, 3, 1],
        ),
      ]) {
    test('реальный совместный поиск сохраняет ограничения: $name', () async {
      final provider = intentionCatalogViewModelProvider(purpose);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final model = container.read(provider.notifier);

      model.changeTitleFilter('  ХОДИТЬ  ');
      model.changeTagFilter(
        IntentionTagFilter(
          requiredTagIds: [_tagId(301)],
          excludedTagIds: [_tagId(304)],
        ),
      );
      final previous =
          await container.read(provider.future) as IntentionCatalogLoaded;
      expect(previous.totalCount, greaterThan(expectedIds.length));
      expect(previous.nextCursor, isNotNull);

      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(301), _tagId(303)],
        excludedTagIds: [_tagId(302)],
      );
      model.changeTagFilter(filter);
      final first =
          await container.read(provider.future) as IntentionCatalogLoaded;
      expect(first.query.cursor, isNull);
      expect(first.query.titleFilter?.map((text) => text), 'ХОДИТЬ');
      expect(first.query.tagFilter, filter);
      expect(first.selection.tagFilter, filter);
      expect(first.items.map((item) => item.id), [
        for (final number in expectedIds.take(2)) _intentionId(number),
      ]);
      expect(first.totalCount, expectedIds.length);
      expect(first.items.length, lessThanOrEqualTo(first.query.pageSize));

      var loaded = first;
      for (var page = 1; page < expectedIds.length; page++) {
        if (loaded.nextCursor == null) break;
        await model.loadNextPageIfNeeded(visibleIndex: loaded.items.length - 1);
        loaded =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(loaded.totalCount, expectedIds.length);
        expect(loaded.query.tagFilter, filter);
      }
      expect(loaded.nextCursor, isNull);
      expect(loaded.items.map((item) => item.id), [
        for (final number in expectedIds) _intentionId(number),
      ]);
      for (final item in loaded.items) {
        expect(item.title, 'Ходить в парк');
        expect(item.tags.map((tag) => (tag.id, tag.name.value)), [
          (_tagId(301), 'Здоровье'),
          (_tagId(303), 'Отдых'),
        ]);
      }
      expect(loaded.continuation, isA<IntentionCatalogContinuationIdle>());
    });
  }

  for (final (name, filter, expectedIds) in [
    (
      'обязательные',
      IntentionTagFilter(
        requiredTagIds: [_tagId(301), _tagId(303)],
        excludedTagIds: [_tagId(304)],
      ),
      [10, 4, 2, 1],
    ),
    (
      'исключённые',
      IntentionTagFilter(
        requiredTagIds: [_tagId(301)],
        excludedTagIds: [_tagId(302)],
      ),
      [10, 5, 2, 1],
    ),
  ]) {
    test(
      'поздние реальные порции не смешиваются после замены условий: $name',
      () async {
        // Контур задерживает только передачу ответа. Каждый ответ целиком
        // вычисляется настоящим адаптером по запросу модели, включая курсор.
        final delayedReads = ControlledCatalogRepository();
        final delayedContainer = reconciliationCatalogContainer(
          delayedReads,
          pageSize: 2,
          prefetchRemaining: 0,
        );
        addTearDown(delayedContainer.dispose);
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final subscription = delayedContainer.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final oldFirst = await repository.getCatalogPage(
          delayedReads.queryAt(0),
        );
        final model = delayedContainer.read(provider.notifier);
        model.changeTitleFilter('ходить');
        model.changeTagFilter(
          IntentionTagFilter(
            requiredTagIds: [_tagId(301)],
            excludedTagIds: [_tagId(304)],
          ),
        );
        await waitForCatalogQueries(delayedReads, 2);
        delayedReads.complete(
          1,
          await repository.getCatalogPage(delayedReads.queryAt(1)),
        );
        final previous = await delayedContainer.read(
          provider.future,
        ) as IntentionCatalogLoaded;
        expect(previous.totalCount, 5);
        expect(previous.items.map((item) => item.id), [
          _intentionId(10),
          _intentionId(5),
        ]);
        delayedReads.complete(0, oldFirst);
        await Future<void>.delayed(Duration.zero);
        expect(delayedContainer.read(provider).requireValue, same(previous));

        final oldRequest = model.loadNextPageIfNeeded(visibleIndex: 1);
        final oldContinuation = await repository.getCatalogPage(
          delayedReads.queryAt(2),
        );
        model.changeTagFilter(filter);
        await waitForCatalogQueries(delayedReads, 4);
        delayedReads.complete(
          3,
          await repository.getCatalogPage(delayedReads.queryAt(3)),
        );
        final current = await delayedContainer.read(
          provider.future,
        ) as IntentionCatalogLoaded;
        expect(current.query.tagFilter, filter);
        expect(current.totalCount, 4);
        expect(current.items.map((item) => item.id), [
          for (final number in expectedIds.take(2)) _intentionId(number),
        ]);
        delayedReads.complete(2, oldContinuation);
        await oldRequest;
        expect(delayedContainer.read(provider).requireValue, same(current));

        final newRequest = model.loadNextPageIfNeeded(visibleIndex: 1);
        delayedReads.complete(
          4,
          await repository.getCatalogPage(delayedReads.queryAt(4)),
        );
        await newRequest;
        final loaded =
            delayedContainer.read(provider).requireValue
                as IntentionCatalogLoaded;
        expect(loaded.items.map((item) => item.id), [
          for (final number in expectedIds) _intentionId(number),
        ]);
        expect(loaded.totalCount, 4);
        expect(loaded.nextCursor, isNull);
        for (final item in loaded.items) {
          expect(
            filter.matches(item.tags.map((tag) => tag.id).toSet()),
            isTrue,
          );
        }
        expect(delayedReads.queries, hasLength(5));
      },
    );
  }

  test('смена охвата сохраняет реальный совместный фильтр и порядок', () async {
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301), _tagId(303)],
      excludedTagIds: [_tagId(302)],
    );
    model.changeTitleFilter('ходить');
    model.changeOrder(IntentionCatalogOrder.createdAtAscending);
    model.changeTagFilter(filter);
    final active =
        await container.read(provider.future) as IntentionCatalogLoaded;
    expect(active.items.map((item) => item.id), [
      _intentionId(1),
      _intentionId(2),
    ]);
    expect(active.totalCount, 3);

    model.changeScope(IntentionScope.archived);
    final archived =
        await container.read(provider.future) as IntentionCatalogLoaded;
    expect(archived.query.scope, IntentionScope.archived);
    expect(archived.query.order, IntentionCatalogOrder.createdAtAscending);
    expect(archived.query.titleFilter?.map((text) => text), 'ходить');
    expect(archived.query.tagFilter, filter);
    expect(archived.query.cursor, isNull);
    expect(archived.items.map((item) => item.id), [
      _intentionId(3),
      _intentionId(9),
    ]);
    expect(archived.totalCount, 2);
    expect(archived.nextCursor, isNull);
    for (final item in archived.items) {
      expect(item.tags.map((tag) => tag.id), [_tagId(301), _tagId(303)]);
    }
  });

  test(
    'пустая выдача, недопустимый ввод и отказ настоящего чтения различаются',
    () async {
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final model = container.read(provider.notifier);

      for (final filter in [
        IntentionTagFilter(requiredTagIds: [_tagId(999)]),
        IntentionTagFilter(
          requiredTagIds: [_tagId(301)],
          excludedTagIds: [_tagId(301)],
        ),
      ]) {
        model.changeTagFilter(filter);
        final empty =
            await container.read(provider.future) as IntentionCatalogEmpty;
        expect(empty.query.tagFilter, filter);
        expect(empty.selection.tagFilter, filter);
        expect(empty.totalCount, 0);
        expect(empty.nextCursor, isNull);
      }

      final readsBeforeInvalidInput = fault.selects;
      for (final (text, failure, tagNumber) in [
        (
          'ходить\u0000',
          IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
          302,
        ),
        ('я' * 256, IntentionCatalogFilterValidationFailure.tooLong, 303),
      ]) {
        final filter = IntentionTagFilter(requiredTagIds: [_tagId(tagNumber)]);
        model.changeTitleFilter(text);
        model.changeTagFilter(filter);
        final invalid = await container.read(
          provider.future,
        ) as IntentionCatalogInvalidFilter;
        expect(invalid.selection.titleFilterText, text);
        expect(invalid.selection.tagFilter, filter);
        expect(invalid.selection.filterValidationFailure, failure);
        expect(fault.selects, readsBeforeInvalidInput);
      }

      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(301), _tagId(303)],
        excludedTagIds: [_tagId(302)],
      );
      fault.failNextSelect = true;
      model.changeTitleFilter('ходить');
      model.changeTagFilter(filter);
      final unavailable =
          await container.read(provider.future) as IntentionCatalogUnavailable;
      expect(unavailable.query.tagFilter, filter);
      expect(unavailable.query.titleFilter?.map((text) => text), 'ходить');
      expect(unavailable.selection.filterValidationFailure, isNull);

      await model.retry();
      final recovered =
          await container.read(provider.future) as IntentionCatalogLoaded;
      expect(recovered.query.tagFilter, filter);
      expect(recovered.query.titleFilter?.map((text) => text), 'ходить');
      expect(recovered.query.cursor, isNull);
      expect(recovered.items.map((item) => item.id), [
        _intentionId(10),
        _intentionId(2),
      ]);
      expect(recovered.totalCount, 3);
      expect(recovered.nextCursor, isNotNull);
    },
  );

  for (final (name, loadAll, expectedBefore, expectedAfter, hasNext) in [
    (
      'частично загруженный префикс',
      false,
      [10, 6, 5, 2],
      [13, 12, 11, 10, 6, 5, 4, 2],
      true,
    ),
    (
      'полностью загруженная выдача',
      true,
      [10, 6, 5, 2, 1],
      [13, 12, 11, 10, 6, 5, 4, 2, 1],
      false,
    ),
  ]) {
    test('удаление исключённого тега достраивает загруженную область через '
        'настоящий репозиторий: $name', () async {
      await _seedExcludedMatches(database);
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final model = container.read(provider.notifier);
      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(301)],
        excludedTagIds: [_tagId(302)],
      );
      model.changeTagFilter(filter);
      var loaded =
          await container.read(provider.future) as IntentionCatalogLoaded;
      while (loaded.items.length < expectedBefore.length) {
        await model.loadNextPageIfNeeded(visibleIndex: loaded.items.length - 1);
        loaded =
            container.read(provider).requireValue as IntentionCatalogLoaded;
      }
      expect(loaded.items.map((item) => item.id), [
        for (final number in expectedBefore) _intentionId(number),
      ]);
      expect(loaded.totalCount, 5);
      expect(loaded.nextCursor == null, loadAll);
      final pageReadsBefore = _catalogPageReads(diagnostics);
      final states = <AsyncValue<IntentionCatalogState>>[];
      final observer = container.listen(
        provider,
        (_, next) => states.add(next),
      );
      addTearDown(observer.close);

      await _deleteTag(container, _tagId(302));
      final current = await _awaitRevisionAfter(container, provider, loaded);

      expect(current, isA<IntentionCatalogLoaded>());
      final reconciled = current as IntentionCatalogLoaded;
      expect(reconciled.items.map((item) => item.id), [
        for (final number in expectedAfter) _intentionId(number),
      ]);
      expect(reconciled.totalCount, 9);
      expect(reconciled.nextCursor, same(loaded.nextCursor));
      expect(reconciled.query, same(loaded.query));
      expect(reconciled.selection.tagFilter, filter);
      for (final item in reconciled.items) {
        expect(item.tags.map((tag) => tag.id), contains(_tagId(301)));
        expect(item.tags.map((tag) => tag.id), isNot(contains(_tagId(302))));
      }
      expect(states.where((state) => state.isLoading), isEmpty);
      expect(states.map((state) => state.requireValue), [same(reconciled)]);
      expect(_catalogPageReads(diagnostics), pageReadsBefore);

      if (hasNext) {
        await model.loadNextPageIfNeeded(
          visibleIndex: reconciled.items.length - 1,
        );
        final completed =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(completed.items.map((item) => item.id), [
          for (final number in [...expectedAfter, 1]) _intentionId(number),
        ]);
        expect(completed.totalCount, 9);
        expect(completed.nextCursor, isNull);
      }
    });
  }

  test('удаление исключённого тега открывает совпадение в пустой выдаче через '
      'настоящий репозиторий', () async {
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301)],
      excludedTagIds: [_tagId(302)],
    );
    model.changeTitleFilter('зал');
    model.changeTagFilter(filter);
    final empty =
        await container.read(provider.future) as IntentionCatalogEmpty;
    final pageReadsBefore = _catalogPageReads(diagnostics);
    final states = <AsyncValue<IntentionCatalogState>>[];
    final observer = container.listen(provider, (_, next) => states.add(next));
    addTearDown(observer.close);

    await _deleteTag(container, _tagId(302));
    final current = await _awaitRevisionAfter(container, provider, empty);

    expect(current, isA<IntentionCatalogLoaded>());
    final reconciled = current as IntentionCatalogLoaded;
    expect(reconciled.items.map((item) => item.id), [_intentionId(4)]);
    expect(reconciled.items.single.tags.map((tag) => tag.id), [
      _tagId(301),
      _tagId(303),
    ]);
    expect(reconciled.totalCount, 1);
    expect(reconciled.nextCursor, isNull);
    expect(reconciled.query, same(empty.query));
    expect(reconciled.selection.tagFilter, filter);
    expect(states.where((state) => state.isLoading), isEmpty);
    expect(states.map((state) => state.requireValue), [same(reconciled)]);
    expect(_catalogPageReads(diagnostics), pageReadsBefore);
  });

  test('отказ SQLite при чтении согласования сохраняет выдачу с явным '
      'отказом обновления, а повтор достраивает её через настоящий '
      'репозиторий', () async {
    await _seedExcludedMatches(database);
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301)],
      excludedTagIds: [_tagId(302)],
    );
    model.changeTagFilter(filter);
    final loaded =
        await container.read(provider.future) as IntentionCatalogLoaded;
    expect(loaded.items.map((item) => item.id), [
      _intentionId(10),
      _intentionId(6),
    ]);
    expect(loaded.totalCount, 5);
    final pageReadsBefore = _catalogPageReads(diagnostics);
    final eventsBefore = diagnostics.events.length;
    final states = <AsyncValue<IntentionCatalogState>>[];
    final observer = container.listen(provider, (_, next) => states.add(next));
    addTearDown(observer.close);

    fault.failNextFilteredSelect = true;
    await _deleteTag(container, _tagId(302));
    final failed = await _awaitRefreshFailure(container, provider);

    expect(failed, isA<IntentionCatalogLoaded>());
    expect((failed as IntentionCatalogLoaded).items, loaded.items);
    expect(failed.totalCount, 5);
    expect(failed.nextCursor, same(loaded.nextCursor));
    expect(failed.revision, same(loaded.revision));
    expect(failed.query, same(loaded.query));
    expect(failed.selection.tagFilter, filter);
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());
    expect(fault.failNextFilteredSelect, isFalse);
    expect(states.where((state) => state.isLoading), isEmpty);
    expect(_catalogPageReads(diagnostics), pageReadsBefore);
    // Отказ не сбрасывает выдачу: кроме событий самой команды удаления,
    // диагностика получает только начало и безопасный отказ чтения
    // согласования, но не события повторного чтения каталога.
    expect(
      diagnostics.events
          .skip(eventsBefore)
          .where((event) => event is! TagCommandDiagnosticsEvent),
      [
        _reconciliationRead(isA<DiagnosticsStarted>()),
        _reconciliationRead(
          isA<DiagnosticsFailed>().having(
            (status) => status.code,
            'категория',
            DiagnosticsFailureCode.unavailable,
          ),
        ),
      ],
    );

    await model.retryRefresh();

    final reconciled =
        container.read(provider).requireValue as IntentionCatalogLoaded;
    expect(reconciled.items.map((item) => item.id), [
      for (final number in [13, 12, 11, 10, 6]) _intentionId(number),
    ]);
    expect(reconciled.totalCount, 9);
    expect(reconciled.nextCursor, same(loaded.nextCursor));
    expect(reconciled.query, same(loaded.query));
    expect(reconciled.refresh, isA<IntentionCatalogRefreshIdle>());
    for (final item in reconciled.items) {
      expect(item.tags.map((tag) => tag.id), isNot(contains(_tagId(302))));
    }
    expect(states.where((state) => state.isLoading), isEmpty);
    expect(_catalogPageReads(diagnostics), pageReadsBefore);
  });

  test('после отказа SQLite при чтении согласования следующее подтверждённое '
      'назначение тега само повторяет чтение через настоящий репозиторий и '
      'записывает его диагностику', () async {
    await _seedExcludedMatches(database);
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301)],
      excludedTagIds: [_tagId(302)],
    );
    model.changeTagFilter(filter);
    final loaded =
        await container.read(provider.future) as IntentionCatalogLoaded;
    final pageReadsBefore = _catalogPageReads(diagnostics);
    final states = <AsyncValue<IntentionCatalogState>>[];
    final observer = container.listen(provider, (_, next) => states.add(next));
    addTearDown(observer.close);

    fault.failNextFilteredSelect = true;
    await _deleteTag(container, _tagId(302));
    final failed = await _awaitRefreshFailure(container, provider);
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());
    final eventsAfterFailure = diagnostics.events.length;

    // «Ходить без тегов» получает «Здоровье» и становится совпадением.
    await _assignTag(container, _tagId(301), _intentionId(7));
    final current = await _awaitRevisionAfter(container, provider, failed);

    expect(current, isA<IntentionCatalogLoaded>());
    final reconciled = current as IntentionCatalogLoaded;
    expect(reconciled.items.map((item) => item.id), [
      for (final number in [13, 12, 11, 10, 7, 6]) _intentionId(number),
    ]);
    expect(
      reconciled.items
          .singleWhere((item) => item.id == _intentionId(7))
          .tags
          .map((tag) => tag.id),
      [_tagId(301)],
    );
    expect(reconciled.totalCount, 10);
    expect(reconciled.nextCursor, same(loaded.nextCursor));
    expect(reconciled.query, same(loaded.query));
    expect(reconciled.selection.tagFilter, filter);
    expect(reconciled.refresh, isA<IntentionCatalogRefreshIdle>());
    expect(states.where((state) => state.isLoading), isEmpty);
    expect(_catalogPageReads(diagnostics), pageReadsBefore);
    // Автоматический повтор записывает обычные события чтения согласования.
    final retryEvents = diagnostics.events
        .skip(eventsAfterFailure)
        .where((event) => event is! TagCommandDiagnosticsEvent)
        .toList();
    final reads = retryEvents.length ~/ 2;
    expect(reads, greaterThan(0));
    expect(retryEvents, [
      for (var read = 0; read < reads; read++) ...[
        _reconciliationRead(isA<DiagnosticsStarted>()),
        _reconciliationRead(
          isA<DiagnosticsSucceeded>(),
          completion: CatalogReconciliationReadCompletion.portion,
        ),
      ],
    ]);
  });

  test('отказ диагностического приёмника не меняет согласование после '
      'удаления исключённого тега', () async {
    await _seedExcludedMatches(database);
    final throwingContainer = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 29),
            _ThrowingDiagnosticsSink(),
          ),
        ),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 2,
            prefetchRemaining: 0,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(throwingContainer.dispose);
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = throwingContainer.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await throwingContainer.read(provider.future);
    throwingContainer
        .read(provider.notifier)
        .changeTagFilter(
          IntentionTagFilter(
            requiredTagIds: [_tagId(301)],
            excludedTagIds: [_tagId(302)],
          ),
        );
    final loaded =
        await throwingContainer.read(provider.future) as IntentionCatalogLoaded;

    await _deleteTag(throwingContainer, _tagId(302));
    final current = await _awaitRevisionAfter(
      throwingContainer,
      provider,
      loaded,
    );

    expect(current, isA<IntentionCatalogLoaded>());
    final reconciled = current as IntentionCatalogLoaded;
    expect(reconciled.items.map((item) => item.id), [
      for (final number in [13, 12, 11, 10, 6]) _intentionId(number),
    ]);
    expect(reconciled.totalCount, 9);
    expect(reconciled.refresh, isA<IntentionCatalogRefreshIdle>());
  });
  test('ранее полностью загруженная выдача в несколько окон согласуется '
      'через настоящий репозиторий окнами не больше порции', () async {
    await _seedWindowedArea(database);
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301)],
      excludedTagIds: [_tagId(302)],
    );
    model.changeTagFilter(filter);
    var loaded =
        await container.read(provider.future) as IntentionCatalogLoaded;
    while (loaded.nextCursor != null) {
      await model.loadNextPageIfNeeded(visibleIndex: loaded.items.length - 1);
      loaded = container.read(provider).requireValue as IntentionCatalogLoaded;
    }
    final storedBefore = [
      for (var number = 38; number >= 20; number -= 2) number,
      10,
      6,
      5,
      2,
      1,
    ];
    expect(loaded.items.map((item) => item.id), [
      for (final number in storedBefore) _intentionId(number),
    ]);
    expect(loaded.totalCount, storedBefore.length);
    final pageReadsBefore = _catalogPageReads(diagnostics);
    final eventsBefore = diagnostics.events.length;
    final states = <AsyncValue<IntentionCatalogState>>[];
    final observer = container.listen(provider, (_, next) => states.add(next));
    addTearDown(observer.close);
    fault.boundedReads.clear();

    await _deleteTag(container, _tagId(302));
    final current = await _awaitRevisionAfter(container, provider, loaded);

    // Совпадения лежат перед первой сохранённой строкой, внутри окон и сразу
    // после их краёв; итог равен сравнению со всей сохранённой областью.
    const expectedAfter = [
      39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, //
      22, 21, 20, 10, 6, 5, 4, 2, 1,
    ];
    expect(current, isA<IntentionCatalogLoaded>());
    final reconciled = current as IntentionCatalogLoaded;
    expect(reconciled.items.map((item) => item.id), [
      for (final number in expectedAfter) _intentionId(number),
    ]);
    expect(reconciled.totalCount, expectedAfter.length);
    expect(reconciled.nextCursor, isNull);
    expect(reconciled.query, same(loaded.query));
    for (final item in reconciled.items) {
      expect(item.tags.map((tag) => tag.id), contains(_tagId(301)));
      expect(item.tags.map((tag) => tag.id), isNot(contains(_tagId(302))));
    }
    expect(states.where((state) => state.isLoading), isEmpty);
    expect(states.map((state) => state.requireValue), [same(reconciled)]);
    expect(_catalogPageReads(diagnostics), pageReadsBefore);

    // Каждое чтение согласования получает не больше порции сохранённых
    // идентификаторов, а число чтений линейно по сохранённым и недостающим
    // строкам.
    const pageSize = 2;
    final missingCount = expectedAfter.length - storedBefore.length;
    final windows = fault.boundedReads;
    expect(windows, isNotEmpty);
    expect(windows, everyElement(lessThanOrEqualTo(pageSize)));
    expect(
      windows.length,
      lessThanOrEqualTo(
        (storedBefore.length + pageSize - 1) ~/ pageSize +
            (missingCount + pageSize - 1) ~/ pageSize +
            1,
      ),
    );
    // Восемь внутренних окон и последнее окно области, каждое из двух
    // сохранённых строк.
    expect(windows, List.filled(9, pageSize));
    // Кроме событий самой команды удаления, диагностика получает только
    // начало и завершение каждого чтения согласования. Их тип не содержит
    // курсора, окна и идентификаторов согласования.
    expect(
      diagnostics.events
          .skip(eventsBefore)
          .where((event) => event is! TagCommandDiagnosticsEvent),
      [
        for (var read = 0; read < windows.length; read++) ...[
          _reconciliationRead(isA<DiagnosticsStarted>()),
          _reconciliationRead(
            isA<DiagnosticsSucceeded>(),
            completion: CatalogReconciliationReadCompletion.portion,
          ),
        ],
      ],
    );

    // Результат совпадает с новым чтением той же выдачи.
    final fresh = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: 0,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(fresh.dispose);
    final freshSubscription = fresh.listen(provider, (_, _) {});
    addTearDown(freshSubscription.close);
    await fresh.read(provider.future);
    fresh.read(provider.notifier).changeTagFilter(filter);
    var reread = await fresh.read(provider.future) as IntentionCatalogLoaded;
    while (reread.nextCursor != null) {
      await fresh
          .read(provider.notifier)
          .loadNextPageIfNeeded(visibleIndex: reread.items.length - 1);
      reread = fresh.read(provider).requireValue as IntentionCatalogLoaded;
    }
    expect(reread.totalCount, reconciled.totalCount);
    List<List<Object>> contents(IntentionCatalogLoaded state) => [
      for (final item in state.items)
        [item.id, ...item.tags.map((tag) => tag.id)],
    ];
    expect(contents(reread), contents(reconciled));
  });

  group('полное создание через настоящий репозиторий и coordinator', () {
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301), _tagId(303)],
      excludedTagIds: [_tagId(302)],
    );

    /// Загружает выдачу с названием «ходить» и [filter] в порядке [order];
    /// [loadAll] догружает её до конца.
    Future<IntentionCatalogLoaded> loadFiltered(
      IntentionCatalogViewModelProvider provider, {
      IntentionCatalogOrder order = IntentionCatalogOrder.createdAtDescending,
      bool loadAll = false,
    }) async {
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final model = container.read(provider.notifier);
      model.changeTitleFilter('ходить');
      model.changeOrder(order);
      model.changeTagFilter(filter);
      var loaded =
          await container.read(provider.future) as IntentionCatalogLoaded;
      while (loadAll && loaded.nextCursor != null) {
        await model.loadNextPageIfNeeded(visibleIndex: loaded.items.length - 1);
        loaded =
            container.read(provider).requireValue as IntentionCatalogLoaded;
      }
      return loaded;
    }

    for (final (name, order, loadAll, before, after, complete) in [
      (
        'частично загруженный префикс',
        IntentionCatalogOrder.createdAtDescending,
        false,
        [10, 2],
        [_created, 10, 2],
        [_created, 10, 2, 1],
      ),
      (
        'полностью загруженная выдача',
        IntentionCatalogOrder.createdAtDescending,
        true,
        [10, 2, 1],
        [_created, 10, 2, 1],
        [_created, 10, 2, 1],
      ),
      (
        'место за границей загруженной области',
        IntentionCatalogOrder.createdAtAscending,
        false,
        [1, 2],
        [1, 2],
        [1, 2, 10, _created],
      ),
    ]) {
      test('подходящее созданное намерение учитывается один раз с точным '
          'количеством без сброса выдачи: $name', () async {
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final loaded = await loadFiltered(
          provider,
          order: order,
          loadAll: loadAll,
        );
        expect(loaded.items.map((item) => item.id), [
          for (final number in before) _intentionId(number),
        ]);
        expect(loaded.totalCount, 3);
        final eventsBefore = diagnostics.events.length;
        final states = <AsyncValue<IntentionCatalogState>>[];
        final observer = container.listen(
          provider,
          (_, next) => states.add(next),
        );
        addTearDown(observer.close);

        final completion = await _create(
          container,
          CreateIntention.withInitialState(
            title: 'Ходить по лесу',
            description: 'Тропа у реки',
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
            tagIds: [_tagId(303), _tagId(301)],
          ),
        );
        final current = await _awaitRevisionAfter(
          container,
          provider,
          loaded,
        ) as IntentionCatalogLoaded;

        final createdId = _createdId(completion);
        List<IntentionId> ids(List<int> numbers) => [
          for (final number in numbers)
            number == _created ? createdId : _intentionId(number),
        ];
        expect(current.items.map((item) => item.id), ids(after));
        expect(current.totalCount, 4);
        expect(
          current.revision.compareTo(completion.revision!),
          GraphRevisionOrder.same,
        );
        expect(current.nextCursor, same(loaded.nextCursor));
        expect(current.query, same(loaded.query));
        expect(current.selection.titleFilterText, 'ходить');
        expect(current.selection.order, order);
        expect(current.selection.tagFilter, filter);
        expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
        expect(states.where((state) => state.isLoading), isEmpty);
        expect(states.map((state) => state.requireValue), [same(current)]);
        // Выдачу согласует сам пакет создания: без нового чтения каталога и
        // без самостоятельных команд готовности, отметки или назначения.
        expect(diagnostics.events.skip(eventsBefore), [_createdSuccessfully]);
        if (after.contains(_created)) {
          final row = current.items.singleWhere((item) => item.id == createdId);
          expect(row.title, 'Ходить по лесу');
          expect(row.hasDescription, isTrue);
          expect(row.readiness, IntentionReadiness.ready);
          expect(row.favoriteMark, FavoriteMark.favorite);
          expect(row.tags.map((tag) => (tag.id, tag.name.value)), [
            (_tagId(301), 'Здоровье'),
            (_tagId(303), 'Отдых'),
          ]);
        }

        final model = container.read(provider.notifier);
        var completed = current;
        while (completed.nextCursor != null) {
          await model.loadNextPageIfNeeded(
            visibleIndex: completed.items.length - 1,
          );
          completed =
              container.read(provider).requireValue as IntentionCatalogLoaded;
        }
        expect(completed.items.map((item) => item.id), ids(complete));
        expect(completed.totalCount, 4);
        expect(completed.query, same(loaded.query));
        expect(
          _contents(completed.items),
          _contents(await _readWhole(repository, completed.query)),
        );
      });
    }

    for (final (name, title, tagNumbers) in [
      ('не подходит названию', 'Читать у реки', [301, 303]),
      ('без обязательного тега', 'Ходить у реки', [301]),
      ('с исключённым тегом', 'Ходить у реки', [301, 302, 303]),
    ]) {
      test('неподходящее созданное намерение не появляется в выдаче и не '
          'меняет количество: $name', () async {
        final provider = intentionCatalogViewModelProvider(
          const BrowseIntentionCatalog(),
        );
        final loaded = await loadFiltered(provider);
        expect(loaded.items.map((item) => item.id), [
          _intentionId(10),
          _intentionId(2),
        ]);
        expect(loaded.totalCount, 3);
        final eventsBefore = diagnostics.events.length;
        final states = <AsyncValue<IntentionCatalogState>>[];
        final observer = container.listen(
          provider,
          (_, next) => states.add(next),
        );
        addTearDown(observer.close);

        final completion = await _create(
          container,
          CreateIntention.withInitialState(
            title: title,
            description: null,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
            tagIds: [for (final number in tagNumbers) _tagId(number)],
          ),
        );
        final current = await _awaitRevisionAfter(
          container,
          provider,
          loaded,
        ) as IntentionCatalogLoaded;

        expect(current.items, loaded.items);
        expect(current.totalCount, 3);
        expect(
          current.revision.compareTo(completion.revision!),
          GraphRevisionOrder.same,
        );
        expect(current.nextCursor, same(loaded.nextCursor));
        expect(current.query, same(loaded.query));
        expect(current.selection.tagFilter, filter);
        expect(states.where((state) => state.isLoading), isEmpty);
        expect(states.map((state) => state.requireValue), [same(current)]);
        expect(diagnostics.events.skip(eventsBefore), [_createdSuccessfully]);

        await container
            .read(provider.notifier)
            .loadNextPageIfNeeded(visibleIndex: current.items.length - 1);
        final completed =
            container.read(provider).requireValue as IntentionCatalogLoaded;
        expect(completed.items.map((item) => item.id), [
          _intentionId(10),
          _intentionId(2),
          _intentionId(1),
        ]);
        expect(completed.totalCount, 3);
        expect(completed.nextCursor, isNull);
        expect(
          completed.items.map((item) => item.id),
          isNot(contains(_createdId(completion))),
        );
      });
    }

    for (final (readiness, after) in [
      (IntentionReadiness.ready, [_created, 10, 1]),
      (IntentionReadiness.notReady, [10, 1]),
    ]) {
      test('начальная готовность определяет принадлежность выдаче выбора '
          'действия: ${readiness.name}', () async {
        final provider = intentionCatalogViewModelProvider(
          const SelectDailyChoiceAction(),
        );
        final loaded = await loadFiltered(provider);
        expect(loaded.items.map((item) => item.id), [
          _intentionId(10),
          _intentionId(1),
        ]);
        expect(loaded.totalCount, 2);
        expect(loaded.nextCursor, isNull);
        final states = <AsyncValue<IntentionCatalogState>>[];
        final observer = container.listen(
          provider,
          (_, next) => states.add(next),
        );
        addTearDown(observer.close);

        final completion = await _create(
          container,
          CreateIntention.withInitialState(
            title: 'Ходить по лесу',
            description: null,
            readiness: readiness,
            favoriteMark: FavoriteMark.notFavorite,
            tagIds: [_tagId(301), _tagId(303)],
          ),
        );
        final current = await _awaitRevisionAfter(
          container,
          provider,
          loaded,
        ) as IntentionCatalogLoaded;

        final createdId = _createdId(completion);
        expect(current.items.map((item) => item.id), [
          for (final number in after)
            number == _created ? createdId : _intentionId(number),
        ]);
        expect(current.totalCount, after.length);
        expect(current.nextCursor, isNull);
        expect(current.query, same(loaded.query));
        expect(states.where((state) => state.isLoading), isEmpty);
        expect(states.map((state) => state.requireValue), [same(current)]);
        expect(
          _contents(current.items),
          _contents(await _readWhole(repository, current.query)),
        );
      });
    }
  });

  group('модель выбранных условий по тегам', () {
    const browse = BrowseIntentionCatalog();
    final catalog = intentionCatalogViewModelProvider(browse);
    final conditions = intentionTagConditionsViewModelProvider(browse);

    void open(IntentionCatalogPurpose purpose) {
      addTearDown(
        container
            .listen(intentionCatalogViewModelProvider(purpose), (_, _) {})
            .close,
      );
      addTearDown(
        container
            .listen(intentionTagConditionsViewModelProvider(purpose), (_, _) {})
            .close,
      );
    }

    Future<IntentionCatalogConfirmedState> confirmed([
      IntentionCatalogViewModelProvider? provider,
    ]) async =>
        await container.read((provider ?? catalog).future)
            as IntentionCatalogConfirmedState;

    test('добавление, переключение и снятие условий сразу применяют '
        'настоящий поиск и не меняют теги', () async {
      open(browse);
      await confirmed();
      final snapshot = await _tagSnapshot(repository);
      final model = container.read(conditions.notifier);
      final assignments = await _assignmentCount(database);

      model.applySelection(snapshot.select(301, _present));
      var state = await confirmed();
      expect(state.query.tagFilter.requiredTagIds, {_tagId(301)});
      expect(state.totalCount, 6);

      model.applySelection(snapshot.select(302, _absent));
      state = await confirmed();
      expect(state.totalCount, 5);
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Здоровье', false),
        (_tagId(302), _absent, 'Спорт', false),
      ]);

      model.toggleRequirement(_tagId(302));
      state = await confirmed();
      expect(state.totalCount, 1);
      expect(
        (state as IntentionCatalogLoaded).items.single.id,
        _intentionId(4),
      );

      // Повторный выбор меняет надобность существующего условия на месте.
      model.applySelection(snapshot.select(301, _absent));
      state = await confirmed();
      expect(state, isA<IntentionCatalogEmpty>());
      expect(_shown(container, conditions), [
        (_tagId(301), _absent, 'Здоровье', false),
        (_tagId(302), _present, 'Спорт', false),
      ]);

      model.remove(_tagId(301));
      state = await confirmed();
      expect(state.query.tagFilter, container.read(conditions).tagFilter);
      expect(state.query.tagFilter.excludedTagIds, isEmpty);
      expect(state.totalCount, 1);

      final catalogModel = container.read(catalog.notifier);
      catalogModel.changeScope(IntentionScope.archived);
      catalogModel.changeOrder(IntentionCatalogOrder.createdAtAscending);
      state = await confirmed();
      expect(state.query.scope, IntentionScope.archived);
      expect(state.query.tagFilter, container.read(conditions).tagFilter);
      expect(_shown(container, conditions), [
        (_tagId(302), _present, 'Спорт', false),
      ]);

      // Поиск только читает: теги и назначения остались прежними.
      expect((await _tagSnapshot(repository)).names, snapshot.names);
      expect(await _assignmentCount(database), assignments);
    });

    test('переименование и удаление выбранных тегов сохраняют условия, а '
        'одноимённый новый тег их не подменяет', () async {
      open(browse);
      await confirmed();
      final snapshot = await _tagSnapshot(repository);
      final model = container.read(conditions.notifier);
      model.applySelection(snapshot.select(301, _present));
      model.applySelection(snapshot.select(302, _absent));
      expect((await confirmed()).totalCount, 5);

      await _completeTag(
        container,
        (coordinator) => coordinator.acceptTagRename(
          RenameTag(
            tagId: _tagId(301),
            name: TagName.fromInput('Самочувствие'),
          ),
        ),
      );
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Самочувствие', false),
        (_tagId(302), _absent, 'Спорт', false),
      ]);
      expect((await confirmed()).totalCount, 5);

      await _deleteTag(container, _tagId(301));
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Самочувствие', true),
        (_tagId(302), _absent, 'Спорт', false),
      ]);
      // Удалённый обязательный тег даёт успешную пустую выдачу.
      var state = await _awaitCatalog(
        container,
        catalog,
        (state) => state.totalCount == 0,
      );
      expect(state.query.tagFilter.requiredTagIds, {_tagId(301)});

      await _completeTag(
        container,
        (coordinator) => coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(TagName.fromInput('Самочувствие')),
        ),
      );
      final recreated = (await _tagSnapshot(repository)).tags
          .singleWhere((tag) => tag.name.value == 'Самочувствие');
      expect(recreated.id, isNot(_tagId(301)));
      await _assignTag(container, recreated.id, _intentionId(7));
      await pumpEventQueue();
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Самочувствие', true),
        (_tagId(302), _absent, 'Спорт', false),
      ]);
      state = await confirmed();
      expect(state.totalCount, 0);

      // Явное снятие условия удалённого тега возобновляет поиск.
      model.remove(_tagId(301));
      state = await confirmed();
      expect(state.totalCount, 7);
      expect(_shown(container, conditions), [
        (_tagId(302), _absent, 'Спорт', false),
      ]);
    });

    test('выбор из устаревшего снимка предъявляется с актуальным названием '
        'и признаком удаления', () async {
      open(browse);
      await confirmed();
      final stale = await _tagSnapshot(repository);
      await _completeTag(
        container,
        (coordinator) => coordinator.acceptTagRename(
          RenameTag(tagId: _tagId(302), name: TagName.fromInput('Бег')),
        ),
      );
      await _deleteTag(container, _tagId(304));
      final model = container.read(conditions.notifier);

      model.applySelection(stale.select(302, _absent));
      model.applySelection(stale.select(304, _present));

      // Поиск применён сразу, до уточнения предъявления.
      expect(
        container.read(catalog.notifier).selection.tagFilter,
        IntentionTagFilter(
          requiredTagIds: [_tagId(304)],
          excludedTagIds: [_tagId(302)],
        ),
      );
      await _awaitConditions(container, conditions, [
        (_tagId(302), _absent, 'Бег', false),
        (_tagId(304), _present, 'Работа', true),
      ]);
      expect(await confirmed(), isA<IntentionCatalogEmpty>());
    });

    test('отказ чтения тега не выглядит удалением, а следующее '
        'подтверждённое изменение повторяет уточнение', () async {
      open(browse);
      await confirmed();
      final stale = await _tagSnapshot(repository);
      await _deleteTag(container, _tagId(304));
      final model = container.read(conditions.notifier);

      fault.failNextTagRead = true;
      model.applySelection(stale.select(304, _present));
      for (var attempt = 0; fault.failNextTagRead; attempt++) {
        expect(attempt, lessThan(1000), reason: 'Чтение тега не выполнено.');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await pumpEventQueue();
      expect(_shown(container, conditions), [
        (_tagId(304), _present, 'Работа', false),
      ]);

      await _assignTag(container, _tagId(303), _intentionId(7));
      await _awaitConditions(container, conditions, [
        (_tagId(304), _present, 'Работа', true),
      ]);
    });

    test('условия разных назначений независимы и не сохраняются после '
        'закрытия поиска', () async {
      const action = SelectDailyChoiceAction();
      final actionCatalog = intentionCatalogViewModelProvider(action);
      final actionConditions = intentionTagConditionsViewModelProvider(action);
      final subscriptions = [
        container.listen(catalog, (_, _) {}),
        container.listen(conditions, (_, _) {}),
      ];
      open(action);
      await confirmed();
      await confirmed(actionCatalog);
      final snapshot = await _tagSnapshot(repository);

      container
          .read(conditions.notifier)
          .applySelection(snapshot.select(301, _present));
      expect((await confirmed()).totalCount, 6);
      expect(container.read(actionConditions).conditions, isEmpty);
      var actionState = await confirmed(actionCatalog);
      expect(actionState.query.tagFilter, IntentionTagFilter.empty);
      expect(actionState.totalCount, 6);

      container
          .read(actionConditions.notifier)
          .applySelection(snapshot.select(302, _absent));
      actionState = await confirmed(actionCatalog);
      expect(
        actionState.query.readinessFilter,
        IntentionReadinessFilter.readyOnly,
      );
      expect(actionState.totalCount, 5);
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Здоровье', false),
      ]);
      expect((await confirmed()).query.tagFilter.excludedTagIds, isEmpty);

      for (final subscription in subscriptions) {
        subscription.close();
      }
      await container.pump();
      open(browse);
      expect(container.read(conditions).conditions, isEmpty);
      final reopened = await confirmed();
      expect(reopened.query.tagFilter, IntentionTagFilter.empty);
      expect(reopened.totalCount, 8);
      expect(_shown(container, actionConditions), [
        (_tagId(302), _absent, 'Спорт', false),
      ]);
    });
  });
}

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;

/// Полный снимок каталога тегов, из которого пользователь выбирает условие.
final class _TagSnapshot {
  const _TagSnapshot(this.tags, this.revision);

  final List<tag_domain.Tag> tags;
  final GraphRevision revision;

  List<String> get names => [for (final tag in tags) tag.name.value];

  IntentionTagConditionSelection select(
    int number,
    IntentionTagRequirement requirement,
  ) => IntentionTagConditionSelection(
    tag: tags.singleWhere((tag) => tag.id == _tagId(number)),
    requirement: requirement,
    snapshotRevision: revision,
  );
}

Future<_TagSnapshot> _tagSnapshot(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getTagCatalog(const TagCatalogBrowseMode());
  final snapshot = (result as TagCatalogSuccess).value;
  return _TagSnapshot(snapshot.items, snapshot.revision);
}

Future<int> _assignmentCount(AppDatabase database) async {
  final row = await database
      .customSelect('SELECT count(*) AS total FROM tag_assignments')
      .getSingle();
  return row.read<int>('total');
}

List<(TagId, IntentionTagRequirement, String, bool)> _shown(
  ProviderContainer container,
  IntentionTagConditionsViewModelProvider provider,
) => [
  for (final condition in container.read(provider).conditions)
    (
      condition.tagId,
      condition.requirement,
      condition.name.value,
      condition.isDeleted,
    ),
];

/// Ждёт уточнения предъявления условий чтением настоящего адаптера.
Future<void> _awaitConditions(
  ProviderContainer container,
  IntentionTagConditionsViewModelProvider provider,
  List<(TagId, IntentionTagRequirement, String, bool)> expected,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (equals(expected).matches(_shown(container, provider), {})) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(_shown(container, provider), expected);
}

/// Ждёт подтверждённой выдачи, согласованной с изменением тегов.
Future<IntentionCatalogConfirmedState> _awaitCatalog(
  ProviderContainer container,
  IntentionCatalogViewModelProvider provider,
  bool Function(IntentionCatalogConfirmedState state) isReconciled,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    final current = container.read(provider).value;
    if (current is IntentionCatalogConfirmedState && isReconciled(current)) {
      return current;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Согласованная выдача не опубликована.');
}

/// Проводит команду тега настоящим адаптером через coordinator.
Future<void> _completeTag(
  ProviderContainer container,
  TagCommandStart Function(GraphCommandCoordinator coordinator) accept,
) async {
  final start = accept(
    container.read(graphCommandCoordinatorProvider.notifier),
  );
  final completion = await (start as TagCommandAccepted).future;
  expect(completion.isFailure, isFalse);
}

Future<void> _seedCatalog(AppDatabase database) =>
    database.transaction(() async {
      for (final (number, title, ready, archived, tags) in [
        (1, 'Ходить в парк', 1, 0, [301, 303]),
        (2, 'Ходить в парк', 0, 0, [301, 303]),
        (3, 'Ходить в парк', 1, 1, [301, 303]),
        (4, 'Ходить в зал', 1, 0, [301, 302, 303]),
        (5, 'Ходить до магазина', 1, 0, [301]),
        (6, 'Читать в тишине', 1, 0, [301, 303]),
        (7, 'Ходить без тегов', 0, 0, <int>[]),
        (8, 'Ходить на работу', 1, 0, [304]),
        (9, 'Ходить в парк', 0, 1, [301, 303]),
        (10, 'Ходить в парк', 1, 0, [301, 303]),
      ]) {
        await database.customStatement(
          '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
          [tagFixtureId(number), title, ready, archived, number, number],
        );
        for (final tag in tags) {
          await database.customStatement(
            'INSERT OR IGNORE INTO tags (id, name) VALUES (?, ?)',
            [tagFixtureId(tag), _tagNames[tag]],
          );
          await database.customStatement(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tag), tagFixtureId(number)],
          );
        }
      }
    });

/// Намерения новее каталога, отсечённые только исключённым «Спорт».
Future<void> _seedExcludedMatches(AppDatabase database) =>
    database.transaction(() async {
      for (final number in [11, 12, 13]) {
        await database.customStatement(
          '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, 1, 0, ?, ?)''',
          [tagFixtureId(number), 'Ходить в бассейн', number, number],
        );
        for (final tag in [301, 302]) {
          await database.customStatement(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tag), tagFixtureId(number)],
          );
        }
      }
    });

/// Намерения 20–39 со «Здоровьем»; нечётные отсечены исключённым «Спортом».
Future<void> _seedWindowedArea(AppDatabase database) =>
    database.transaction(() async {
      for (var number = 20; number <= 39; number++) {
        await database.customStatement(
          '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, 1, 0, ?, ?)''',
          [tagFixtureId(number), 'Плавать $number', number, number],
        );
        for (final tag in [301, if (number.isOdd) 302]) {
          await database.customStatement(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tag), tagFixtureId(number)],
          );
        }
      }
    });

/// Проводит физическое удаление тега настоящим адаптером через coordinator.
Future<void> _deleteTag(ProviderContainer container, TagId tagId) async {
  final start = container
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptTagDelete(DeleteTag(tagId));
  final completion = await (start as TagCommandAccepted).future;
  expect(completion.isFailure, isFalse);
}

/// Назначает тег намерению настоящим адаптером через coordinator.
Future<void> _assignTag(
  ProviderContainer container,
  TagId tagId,
  IntentionId intentionId,
) async {
  final start = container
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptTagAssign(AssignTag(tagId: tagId, intentionId: intentionId));
  final completion = await (start as TagCommandAccepted).future;
  expect(completion.isFailure, isFalse);
}

/// Номер созданного в сценарии намерения в ожидаемой выдаче: его
/// идентификатор выдаёт настоящий генератор.
const _created = 0;

/// Создаёт намерение настоящим адаптером через coordinator.
Future<IntentionCommandCompletion> _create(
  ProviderContainer container,
  CreateIntention command,
) async {
  final start = container
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptCreation(IntentionCreationFormKey(), command);
  final completion = await (start as IntentionCommandAccepted).future;
  expect(completion.isFailure, isFalse);
  return completion;
}

IntentionId _createdId(IntentionCommandCompletion completion) =>
    switch (completion.result) {
      ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
      _ => fail('Создание не подтверждено.'),
    };

/// Единственное диагностическое событие полного создания: успешный исход.
final _createdSuccessfully = isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'команда',
      IntentionCommandDiagnosticsType.create,
    )
    .having((event) => event.status, 'статус', isA<DiagnosticsSucceeded>());

/// Сопоставимое содержимое строк выдачи вместе с данными начального
/// состояния.
List<List<Object?>> _contents(List<IntentionSummary> items) => [
  for (final item in items)
    [
      item.id,
      item.title,
      item.readiness,
      item.favoriteMark,
      ...item.tags.map((tag) => tag.id),
    ],
];

/// Читает всю выдачу [query] заново настоящим адаптером.
Future<List<IntentionSummary>> _readWhole(
  DriftPersonalGraphRepository repository,
  IntentionCatalogQuery query,
) async {
  final items = <IntentionSummary>[];
  IntentionCatalogCursor? cursor;
  do {
    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: query.scope,
        readinessFilter: query.readinessFilter,
        titleFilter: query.titleFilter?.map((value) => value),
        tagFilter: query.tagFilter,
        excludedIntentionId: query.excludedIntentionId,
        order: query.order,
        pageSize: query.pageSize,
        cursor: cursor,
      ),
    );
    final page = switch (result) {
      ResultSuccess(:final value) => value,
      ResultFailure() => fail('Чтение выдачи отказало.'),
    };
    items.addAll(page.items);
    cursor = page.nextCursor;
  } while (cursor != null);
  return items;
}

/// Ждёт публикации явного отказа обновления.
Future<IntentionCatalogConfirmedState> _awaitRefreshFailure(
  ProviderContainer container,
  IntentionCatalogViewModelProvider provider,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    final current = container.read(provider).value;
    if (current is IntentionCatalogConfirmedState &&
        current.refresh is! IntentionCatalogRefreshIdle) {
      return current;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Отказ обновления не опубликован.');
}

/// Ждёт публикации подтверждённого состояния более новой ревизии.
Future<IntentionCatalogConfirmedState> _awaitRevisionAfter(
  ProviderContainer container,
  IntentionCatalogViewModelProvider provider,
  IntentionCatalogConfirmedState previous,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    final current = container.read(provider).value;
    if (current is IntentionCatalogConfirmedState &&
        current.revision.compareTo(previous.revision) ==
            GraphRevisionOrder.newer) {
      return current;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Согласованная выдача не опубликована.');
}

Matcher _reconciliationRead(
  Matcher status, {
  CatalogReconciliationReadCompletion? completion,
}) => isA<CatalogReconciliationReadDiagnosticsEvent>()
    .having((event) => event.completion, 'завершение', completion)
    .having((event) => event.status, 'статус', status);

int _catalogPageReads(InMemoryDiagnosticsSink diagnostics) => diagnostics.events
    .whereType<CatalogPageReadDiagnosticsEvent>()
    .where((event) => event.status is DiagnosticsStarted)
    .length;

const _tagNames = {301: 'Здоровье', 302: 'Спорт', 303: 'Отдых', 304: 'Работа'};

IntentionId _intentionId(int number) => switch (IntentionId.decode(
  tagFixtureId(number),
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Неверный ID намерения.'),
};

TagId _tagId(int number) => switch (TagId.decode(tagFixtureId(number))) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Неверный ID тега.'),
};

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  @override
  void record(DiagnosticsEvent event) {
    throw StateError('Контролируемый отказ диагностики.');
  }
}

final class _CatalogReadFault extends LocalDatabaseConnectionObserver {
  bool failNextSelect = false;

  /// Отказывает следующему чтению одного тега по идентификатору.
  bool failNextTagRead = false;

  /// Отказывает следующему чтению с условиями по тегам: команды тегов таких
  /// чтений не выполняют.
  bool failNextFilteredSelect = false;
  int selects = 0;

  /// Число сохранённых идентификаторов, переданных каждой ограниченной
  /// выборкой с условиями по тегам.
  final boundedReads = <int>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    selects++;
    final sql = statement.statements.join('\n');
    if (sql.contains('json_each') && sql.contains('LIMIT')) {
      boundedReads.add(
        sql.contains('stored_row')
            ? (jsonDecode(
                statement.arguments.whereType<String>().lastWhere(
                  (argument) => argument.startsWith('['),
                ),
              ) as List).length
            : 0,
      );
    }
    if (failNextTagRead && sql.contains('FROM tags WHERE id = ?')) {
      failNextTagRead = false;
      throw SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'Контролируемая недоступность чтения тега.',
      );
    }
    if (failNextFilteredSelect &&
        statement.statements.any((sql) => sql.contains('json_each'))) {
      failNextFilteredSelect = false;
      throw SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'Контролируемая недоступность чтения согласования.',
      );
    }
    if (failNextSelect) {
      failNextSelect = false;
      throw SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'Контролируемая недоступность чтения каталога.',
      );
    }
  }
}
