import 'dart:async';

import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  group('file-backed DriftPersonalGraphRepository', () {
    test('сохраняет полный lifecycle через публичную seam после повторного открытия', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final activeId = _id('550e8400-e29b-41d4-a716-446655440000');
      final archivedId = _id('018f0b5d-6b2e-7c80-8000-000000000801');
      final deletedId = _id('018f0b5d-6b2e-7c80-8000-000000000802');

      final firstRevision = await _createFirstObjectGraph(
        harness,
        activeId: activeId,
        archivedId: archivedId,
        deletedId: deletedId,
      );

      final reopenedDatabase = await harness.openReadyDatabase();
      final PersonalGraphRepository repository = DriftPersonalGraphRepository(
        reopenedDatabase,
        _SequenceIntentionIdGenerator(const []),
        () => DateTime.utc(2026, 9, 3, 18),
        InMemoryDiagnosticsSink(),
      );

      final reopenedSnapshot = _graphSnapshot(
        await repository.watchIntention(activeId).first,
      );
      expect(
        firstRevision.compareTo(reopenedSnapshot.revision),
        GraphRevisionOrder.differentEpoch,
      );
      final active = reopenedSnapshot.value;
      expect(active, isNotNull);
      expect(active!.id, activeId);
      expect(active.title, 'Переписать "статью"');
      expect(active.description, '  Сохранить точный\nтекст  ');
      expect(active.readiness, IntentionReadiness.ready);
      expect(active.archiveState, IntentionArchiveState.active);
      expect(active.createdAt.value, DateTime.utc(2026, 9, 3, 10));
      expect(active.updatedAt.value, DateTime.utc(2026, 9, 3, 12));

      final archived = _watched(
        await repository.watchIntention(archivedId).first,
      );
      expect(archived, isNotNull);
      expect(archived!.id, archivedId);
      expect(archived.title, 'Архивировать журнал');
      expect(archived.description, isNull);
      expect(archived.readiness, IntentionReadiness.notReady);
      expect(archived.archiveState, IntentionArchiveState.archived);
      expect(archived.createdAt.value, DateTime.utc(2026, 9, 3, 13));
      expect(archived.updatedAt.value, DateTime.utc(2026, 9, 3, 16));

      expect(
        _watched(await repository.watchIntention(deletedId).first),
        isNull,
      );

      final activePage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.active)),
      );
      expect(activePage.totalCount, 1);
      expect(activePage.items.map((item) => item.id), [activeId]);

      final archivedPage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.archived)),
      );
      expect(archivedPage.totalCount, 1);
      expect(archivedPage.items.map((item) => item.id), [archivedId]);

      final allPage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.all)),
      );
      expect(allPage.totalCount, 2);
      expect(allPage.items.map((item) => item.id), [activeId, archivedId]);

      final filteredPage = _firstPage(
        await repository.getCatalogPage(
          _catalogQuery(IntentionScope.all, titleFilter: '  "статью"  '),
        ),
      );
      expect(filteredPage.totalCount, 1);
      expect(filteredPage.items.map((item) => item.id), [activeId]);

      await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
    });

    test('не считает историческую generated search key corruption и пересчитывает её после записи', () async {
      const idValue = '018f0b5d-6b2e-7c80-8000-000000000821';
      const title = 'Kxyz';
      const historicalSearchKey = 'устаревшая-проекция';
      final id = _id(idValue);
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);

      await harness.openReadyDatabase();
      await harness.closePersistenceObjectGraph();

      final legacyDatabase = sqlite.sqlite3.open(harness.databaseFile.path);
      try {
        _registerSearchKeyFunction(legacyDatabase, historicalSearchKey);
        legacyDatabase.execute(
          '''
              INSERT INTO intentions (id, title, created_at, updated_at)
              VALUES (?, ?, ?, ?)
            ''',
          [
            idValue,
            title,
            DateTime.utc(2026, 9, 4, 10).microsecondsSinceEpoch,
            DateTime.utc(2026, 9, 4, 10).microsecondsSinceEpoch,
          ],
        );
        expect(
          legacyDatabase
              .select('SELECT title_search_key FROM intentions')
              .single['title_search_key'],
          historicalSearchKey,
        );
      } finally {
        legacyDatabase.close();
      }

      final historicalDatabase = await harness.openReadyDatabase();
      final PersonalGraphRepository historicalRepository =
          DriftPersonalGraphRepository(
            historicalDatabase,
            _SequenceIntentionIdGenerator(const []),
            () => DateTime.utc(2026, 9, 4, 11),
            InMemoryDiagnosticsSink(),
          );

      final allPage = _firstPage(
        await historicalRepository.getCatalogPage(
          _catalogQuery(IntentionScope.all),
        ),
      );
      final historicalFilterPage = _firstPage(
        await historicalRepository.getCatalogPage(
          _catalogQuery(IntentionScope.all, titleFilter: 'kxyz'),
        ),
      );
      final historicalProjectionQuery = _catalogQuery(
        IntentionScope.all,
        titleFilter: 'устаревшая',
      );
      expect(allPage.items.map((item) => item.id), [id]);
      expect(allPage.items.single.title, title);
      expect(historicalFilterPage.totalCount, 0);
      expect(historicalFilterPage.items, isEmpty);

      final updateResult = await historicalRepository.execute(
        UpdateIntention(
          id: id,
          title: title,
          description: 'Запись пересчитывает поисковую проекцию',
        ),
      );
      expect(
        updateResult,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final updateSuccess =
          (updateResult
                      as ResultSuccess<
                        ConfirmedGraphResult<IntentionCommandSuccess>
                      >)
                  .value
                  .value
              as IntentionSaved;
      final mutation = updateSuccess.catalogMutation as IntentionCatalogUpdated;
      expect(mutation.before.summary.title, title);
      expect(mutation.before.matches(historicalProjectionQuery), isTrue);
      expect(
        mutation.before.matches(
          _catalogQuery(IntentionScope.all, titleFilter: 'kxyz'),
        ),
        isFalse,
      );
      expect(mutation.after.summary.title, title);
      expect(mutation.after.matches(historicalProjectionQuery), isFalse);
      expect(
        mutation.after.matches(
          _catalogQuery(IntentionScope.all, titleFilter: 'kxyz'),
        ),
        isTrue,
      );
      await harness.closePersistenceObjectGraph();

      final currentDatabase = sqlite.sqlite3.open(harness.databaseFile.path);
      try {
        configureDoableSqliteConnection(currentDatabase);
        expect(
          currentDatabase
              .select('SELECT title, title_search_key FROM intentions')
              .single,
          {'title': title, 'title_search_key': titleSearchKey(title)},
        );
        expect(
          currentDatabase.select('''
              SELECT rowid
              FROM intention_titles_fts
              WHERE title_search_key MATCH '"kxyz"'
            '''),
          hasLength(1),
        );
        currentDatabase
          ..execute('''
              INSERT INTO intention_titles_fts(intention_titles_fts, rank)
              VALUES ('integrity-check', 1)
            ''')
          ..execute('''
              INSERT INTO intention_titles_fts(intention_titles_fts)
              VALUES ('rebuild')
            ''')
          ..execute('''
              INSERT INTO intention_titles_fts(intention_titles_fts, rank)
              VALUES ('integrity-check', 1)
            ''');
      } finally {
        currentDatabase.close();
      }

      final updatedDatabase = await harness.openReadyDatabase();
      final PersonalGraphRepository updatedRepository =
          DriftPersonalGraphRepository(
            updatedDatabase,
            _SequenceIntentionIdGenerator(const []),
            () => DateTime.utc(2026, 9, 4, 12),
            InMemoryDiagnosticsSink(),
          );
      final updatedPage = _firstPage(
        await updatedRepository.getCatalogPage(
          _catalogQuery(IntentionScope.all, titleFilter: 'kxyz'),
        ),
      );

      expect(updatedPage.totalCount, 1);
      expect(updatedPage.items.map((item) => item.id), [id]);
      await verifyIntentionTitlesFtsIntegrity(updatedDatabase);
    });

    for (final fixture in [
      (description: 'некорректным', id: 'not-a-uuid'),
      (description: 'nil UUID', id: '00000000-0000-0000-0000-000000000000'),
    ]) {
      test(
        'возвращает corruption без частичной страницы после повторного открытия строки с ${fixture.description} идентификатором',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final database = await harness.openReadyDatabase();
          await database.customStatement(
            '''
              INSERT INTO intentions (
                id,
                title,
                description,
                is_action_ready,
                is_archived,
                created_at,
                updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              fixture.id,
              'Повреждённое намерение',
              null,
              0,
              0,
              DateTime.utc(2026, 9, 3, 10).microsecondsSinceEpoch,
              DateTime.utc(2026, 9, 3, 10).microsecondsSinceEpoch,
            ],
          );
          await harness.closePersistenceObjectGraph();

          final reopenedDatabase = await harness.openReadyDatabase();
          final PersonalGraphRepository repository =
              DriftPersonalGraphRepository(
                reopenedDatabase,
                _SequenceIntentionIdGenerator(const []),
                () => DateTime.utc(2026, 9, 3, 11),
                InMemoryDiagnosticsSink(),
              );

          final result = await repository.getCatalogPage(
            _catalogQuery(IntentionScope.all),
          );

          expect(
            result,
            isA<ResultFailure<IntentionCatalogPage>>().having(
              (failure) => failure.failure,
              'failure',
              isA<IntentionCorruptionFailure>(),
            ),
          );
          await harness.closePersistenceObjectGraph();
        },
      );
    }
  });
}

Future<GraphRevision> _createFirstObjectGraph(
  LocalDatabaseHarness harness, {
  required IntentionId activeId,
  required IntentionId archivedId,
  required IntentionId deletedId,
}) async {
  final database = await harness.openReadyDatabase();
  final PersonalGraphRepository repository = DriftPersonalGraphRepository(
    database,
    _SequenceIntentionIdGenerator([activeId, archivedId, deletedId]),
    _SequenceClock([
      DateTime.utc(2026, 9, 3, 10),
      DateTime.utc(2026, 9, 3, 11),
      DateTime.utc(2026, 9, 3, 12),
      DateTime.utc(2026, 9, 3, 13),
      DateTime.utc(2026, 9, 3, 14),
      DateTime.utc(2026, 9, 3, 15),
      DateTime.utc(2026, 9, 3, 16),
      DateTime.utc(2026, 9, 3, 17),
    ]).call,
    InMemoryDiagnosticsSink(),
  );

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Исходная статья', description: 'Черновик'),
    ),
  );
  _saved(
    await repository.execute(
      UpdateIntention(
        id: activeId,
        title: 'Переписать "статью"',
        description: '  Сохранить точный\nтекст  ',
      ),
    ),
  );
  _saved(await repository.execute(EnableIntentionReadiness(activeId)));

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Архивировать журнал', description: null),
    ),
  );
  _saved(await repository.execute(ArchiveIntention(archivedId)));
  _saved(await repository.execute(RestoreIntention(archivedId)));
  _saved(await repository.execute(ArchiveIntention(archivedId)));

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Удалить черновик', description: null),
    ),
  );
  expect(
    await repository.execute(DeleteIntention(deletedId)),
    _deleted(deletedId),
  );

  final firstSnapshot = Completer<Result<GraphSnapshot<IntentionDetails?>>>();
  final subscription = repository
      .watchIntention(activeId)
      .listen(firstSnapshot.complete);
  final snapshot = _graphSnapshot(await firstSnapshot.future);
  expect(snapshot.value?.id, activeId);
  await subscription.cancel();

  await harness.closePersistenceObjectGraph();
  return snapshot.revision;
}

IntentionCatalogQuery _catalogQuery(
  IntentionScope scope, {
  String? titleFilter,
}) => IntentionCatalogQuery(
  scope: scope,
  titleFilter: titleFilter,
  order: const IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.ascending,
  ),
  pageSize: 10,
);

IntentionCatalogFirstPage _firstPage(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page, isA<IntentionCatalogFirstPage>());
  return page as IntentionCatalogFirstPage;
}

Intention _saved(Result<ConfirmedGraphResult<IntentionCommandSuccess>> result) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  final success =
      (result as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
          .value
          .value;
  expect(success, isA<IntentionSaved>());
  return (success as IntentionSaved).intention;
}

GraphSnapshot<Intention?> _graphSnapshot(
  Result<GraphSnapshot<IntentionDetails?>> result,
) {
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  final snapshot =
      (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;
  return GraphSnapshot(
    value: snapshot.value?.intention,
    revision: snapshot.revision,
  );
}

Intention? _watched(Result<GraphSnapshot<IntentionDetails?>> result) =>
    _graphSnapshot(result).value;

Matcher _deleted(IntentionId id) =>
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.value.value,
      'value',
      isA<IntentionDeleted>().having((success) => success.id, 'id', id),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

void _registerSearchKeyFunction(sqlite.Database database, String searchKey) {
  database.createFunction(
    functionName: doableTitleSearchKeyFunctionName,
    argumentCount: const sqlite.AllowedArgumentCount(1),
    deterministic: true,
    directOnly: false,
    function: (_) => searchKey,
  );
}

final class _SequenceIntentionIdGenerator implements IntentionIdGenerator {
  _SequenceIntentionIdGenerator(this._ids);

  final List<IntentionId> _ids;
  var _nextIndex = 0;

  @override
  IntentionId generate() {
    if (_nextIndex == _ids.length) {
      throw StateError(
        'Не осталось идентификаторов для тестовой последовательности.',
      );
    }
    return _ids[_nextIndex++];
  }
}

final class _SequenceClock {
  _SequenceClock(this._times);

  final List<DateTime> _times;
  var _nextIndex = 0;

  DateTime call() {
    if (_nextIndex == _times.length) {
      throw StateError('Не осталось времён для тестовой последовательности.');
    }
    return _times[_nextIndex++];
  }
}
