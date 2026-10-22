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

import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_positions.dart';
import '../../../support/tag_storage_fixture.dart';
import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

final _actionSearchPurpose = SelectDailyChoiceAction(
  session: IntentionSearchSession(),
);

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
        ('действие', _actionSearchPurpose, [10, 1]),
        (
          'участник активной связи',
          SelectRelationParticipant(
            session: IntentionSearchSession(),
            excludedIntentionId: _intentionId(2),
            selectionContext:
                RelationParticipantSelectionContext.activeRelation,
          ),
          [10, 1],
        ),
        (
          'участник архивной связи',
          SelectRelationParticipant(
            session: IntentionSearchSession(),
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
    });
  }

  test('поздние реальные порции не смешиваются после замены условий', () async {
    final filter = IntentionTagFilter(
      requiredTagIds: [_tagId(301), _tagId(303)],
      excludedTagIds: [_tagId(304)],
    );
    const expectedIds = [10, 4, 2, 1];
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
    final oldFirst = await repository.getCatalogPage(delayedReads.queryAt(0));
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
    final previous =
        await delayedContainer.read(provider.future) as IntentionCatalogLoaded;
    expect(previous.totalCount, 5);
    expect(previous.items.map((item) => item.id), [
      _intentionId(10),
      _intentionId(5),
    ]);
    delayedReads.complete(0, oldFirst);
    await Future<void>.delayed(Duration.zero);
    final afterOldFirst =
        delayedContainer.read(provider).requireValue as IntentionCatalogLoaded;
    expect(afterOldFirst.totalCount, 5);
    expect(afterOldFirst.items.map((item) => item.id), [
      _intentionId(10),
      _intentionId(5),
    ]);

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
    final current =
        await delayedContainer.read(provider.future) as IntentionCatalogLoaded;
    expect(current.query.tagFilter, filter);
    expect(current.totalCount, 4);
    expect(current.items.map((item) => item.id), [
      for (final number in expectedIds.take(2)) _intentionId(number),
    ]);
    delayedReads.complete(2, oldContinuation);
    await oldRequest;
    final afterOldContinuation =
        delayedContainer.read(provider).requireValue as IntentionCatalogLoaded;
    expect(afterOldContinuation.totalCount, 4);
    expect(afterOldContinuation.items.map((item) => item.id), [
      for (final number in expectedIds.take(2)) _intentionId(number),
    ]);

    final newRequest = model.loadNextPageIfNeeded(visibleIndex: 1);
    delayedReads.complete(
      4,
      await repository.getCatalogPage(delayedReads.queryAt(4)),
    );
    await newRequest;
    final loaded =
        delayedContainer.read(provider).requireValue as IntentionCatalogLoaded;
    expect(loaded.items.map((item) => item.id), [
      for (final number in expectedIds) _intentionId(number),
    ]);
    expect(loaded.totalCount, 4);
    expect(loaded.nextCursor, isNull);
    for (final item in loaded.items) {
      expect(filter.matches(item.tags.map((tag) => tag.id).toSet()), isTrue);
    }
  });

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

      final missingTag = IntentionTagFilter(requiredTagIds: [_tagId(999)]);
      model.changeTagFilter(missingTag);
      final empty =
          await container.read(provider.future) as IntentionCatalogEmpty;
      expect(empty.query.tagFilter, missingTag);
      expect(empty.selection.tagFilter, missingTag);
      expect(empty.totalCount, 0);
      expect(empty.nextCursor, isNull);

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

  test('удаление исключённого тега снимает его условие и начинает новую '
      'выдачу с первой порции, и она показывает прежде отсечённые намерения '
      'через настоящий репозиторий', () async {
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

    await _deleteTag(container, _tagId(302));
    final current = await _awaitRevisionAfter(container, provider, loaded);

    expect(current, isA<IntentionCatalogLoaded>());
    final restarted = current as IntentionCatalogLoaded;
    expect(restarted.items.map((item) => item.id), [
      _intentionId(13),
      _intentionId(12),
    ]);
    expect(restarted.totalCount, 9);
    expect(restarted.nextCursor, isNotNull);
    expect(
      restarted.selection.tagFilter,
      IntentionTagFilter(requiredTagIds: [_tagId(301)]),
    );
    expect(_catalogPageReads(diagnostics), pageReadsBefore + 1);
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
        final pageReadsBefore = _catalogPageReads(diagnostics);
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
        expect(current.nextCursor, same(loaded.nextCursor));
        expect(current.selection.titleFilterText, 'ходить');
        expect(current.selection.order, order);
        expect(current.selection.tagFilter, filter);
        expect(states.where((state) => state.isLoading), isEmpty);
        // Выдачу согласует сам пакет создания, без нового чтения каталога.
        expect(_catalogPageReads(diagnostics), pageReadsBefore);
        if (after.contains(_created)) {
          final row = current.items.singleWhere((item) => item.id == createdId);
          expect(row.title, 'Ходить по лесу');
          expect(row.hasDescription, isTrue);
          expect(row.readiness, IntentionReadiness.ready);
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
        expect(
          _contents(completed.items),
          _contents(await _readWhole(repository, completed.query)),
        );
      });
    }

    // Отдельные условия принадлежности проверяет модель каталога; здесь —
    // настоящий пакет создания неподходящего намерения.
    test('неподходящее созданное намерение с исключённым тегом не появляется '
        'в выдаче и не меняет количество', () async {
      const title = 'Ходить у реки';
      const tagNumbers = [301, 302, 303];
      final provider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final loaded = await loadFiltered(provider);
      expect(loaded.items.map((item) => item.id), [
        _intentionId(10),
        _intentionId(2),
      ]);
      expect(loaded.totalCount, 3);
      final pageReadsBefore = _catalogPageReads(diagnostics);
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
      expect(current.nextCursor, same(loaded.nextCursor));
      expect(current.selection.tagFilter, filter);
      expect(states.where((state) => state.isLoading), isEmpty);
      expect(_catalogPageReads(diagnostics), pageReadsBefore);

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

    for (final (readiness, after) in [
      (IntentionReadiness.ready, [_created, 10, 1]),
      (IntentionReadiness.notReady, [10, 1]),
    ]) {
      test('начальная готовность определяет принадлежность выдаче выбора '
          'действия: ${readiness.name}', () async {
        final provider = intentionCatalogViewModelProvider(
          _actionSearchPurpose,
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
        expect(states.where((state) => state.isLoading), isEmpty);
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

    test('переименование сохраняет условия, удаление обязательного тега '
        'снимает его условие и расширяет выдачу, а одноимённый новый тег '
        'условие не восстанавливает', () async {
      open(browse);
      await confirmed();
      final snapshot = await _tagSnapshot(repository);
      final model = container.read(conditions.notifier);
      model.applySelection(snapshot.select(301, _present));
      model.applySelection(snapshot.select(302, _absent));
      expect((await confirmed()).totalCount, 5);

      await _completeTag(
        container,
        (coordinator) => coordinator.acceptTagUpdate(
          UpdateTag(
            tagId: _tagId(301),
            name: TagName.fromInput('Самочувствие'),
            color: null,
          ),
        ),
      );
      expect(_shown(container, conditions), [
        (_tagId(301), _present, 'Самочувствие'),
        (_tagId(302), _absent, 'Спорт'),
      ]);
      expect((await confirmed()).totalCount, 5);

      await _deleteTag(container, _tagId(301));
      expect(_shown(container, conditions), [(_tagId(302), _absent, 'Спорт')]);
      final remaining = IntentionTagFilter(excludedTagIds: [_tagId(302)]);
      var state = await _awaitCatalog(
        container,
        catalog,
        (state) => state.query.tagFilter == remaining,
      );
      expect(state.totalCount, 7);

      await _completeTag(
        container,
        (coordinator) => coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(
            name: TagName.fromInput('Самочувствие'),
            color: null,
            placement: TagPlacement.first,
          ),
        ),
      );
      final recreated = (await _tagSnapshot(repository)).tags
          .singleWhere((tag) => tag.name.value == 'Самочувствие');
      expect(recreated.id, isNot(_tagId(301)));
      await _assignTag(container, recreated.id, _intentionId(7));
      await pumpEventQueue();
      expect(_shown(container, conditions), [(_tagId(302), _absent, 'Спорт')]);
      state = await confirmed();
      expect(state.query.tagFilter, remaining);
      expect(state.totalCount, 7);
    });

    test('удаление снимает условие и в другом открытом поиске: каждый '
        'начинает новую выдачу одним чтением без промежуточной пустой '
        'выдачи', () async {
      final action = intentionCatalogViewModelProvider(_actionSearchPurpose);
      open(browse);
      open(_actionSearchPurpose);
      await confirmed();
      await confirmed(action);
      final snapshot = await _tagSnapshot(repository);
      container
          .read(conditions.notifier)
          .applySelection(snapshot.select(302, _present));
      container.read(
          intentionTagConditionsViewModelProvider(_actionSearchPurpose)
              .notifier,
        )
        ..applySelection(snapshot.select(301, _present))
        ..applySelection(snapshot.select(302, _absent));
      final browseBefore = await confirmed();
      final actionBefore = await confirmed(action);
      expect(browseBefore.totalCount, 1);
      expect(actionBefore.totalCount, 4);
      final published = <IntentionCatalogConfirmedState>[];
      for (final provider in [catalog, action]) {
        addTearDown(
          container.listen(provider, (_, next) {
            // Перечитывание сохраняет прежнее значение до новой выдачи.
            if (next.isLoading) return;
            if (next.value case final IntentionCatalogConfirmedState state) {
              published.add(state);
            }
          }).close,
        );
      }
      final pageReadsBefore = _catalogPageReads(diagnostics);

      await _deleteTag(container, _tagId(302));
      final browseAfter = await _awaitRevisionAfter(
        container,
        catalog,
        browseBefore,
      );
      final actionAfter = await _awaitRevisionAfter(
        container,
        action,
        actionBefore,
      );

      expect(_shown(container, conditions), isEmpty);
      expect(
        _shown(
          container,
          intentionTagConditionsViewModelProvider(_actionSearchPurpose),
        ),
        [(_tagId(301), _present, 'Здоровье')],
      );
      expect(browseAfter.query.tagFilter, IntentionTagFilter.empty);
      expect(browseAfter.totalCount, 8);
      expect(
        actionAfter.query.tagFilter,
        IntentionTagFilter(requiredTagIds: [_tagId(301)]),
      );
      expect(actionAfter.totalCount, 5);
      expect(published, [browseAfter, actionAfter]);
      expect(_catalogPageReads(diagnostics), pageReadsBefore + 2);
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

List<(TagId, IntentionTagRequirement, String)> _shown(
  ProviderContainer container,
  IntentionTagConditionsViewModelProvider provider,
) => [
  for (final condition in container.read(provider).conditions)
    (condition.tagId, condition.requirement, condition.name.value),
];

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
    seedGraph(database, () async {
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
            'INSERT OR IGNORE INTO tags (id, name, position) VALUES (?, ?, ?)',
            [tagFixtureId(tag), _tagNames[tag], tagPositionKey(tag)],
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
    seedGraph(database, () async {
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

/// Сопоставимое содержимое строк выдачи вместе с данными начального
/// состояния.
List<List<Object?>> _contents(List<IntentionSummary> items) => [
  for (final item in items)
    [item.id, item.title, item.readiness, ...item.tags.map((tag) => tag.id)],
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

final class _CatalogReadFault extends LocalDatabaseConnectionObserver {
  bool failNextSelect = false;
  int selects = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    selects++;
    if (failNextSelect) {
      failNextSelect = false;
      throw SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'Контролируемая недоступность чтения каталога.',
      );
    }
  }
}
