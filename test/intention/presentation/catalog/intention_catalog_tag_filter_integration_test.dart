import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
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

  setUp(() async {
    fault = _CatalogReadFault();
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
      InMemoryDiagnosticsSink(),
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
