import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
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
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/doable_schema_verifier.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/intention_creation_durability_fixture.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  group('file-backed DriftPersonalGraphRepository', () {
    test('после отказавшего создания открывает тот же файл без созданного намерения', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final id = _id('018f0b5d-6b2e-7c80-8000-000000000811');
      final interceptor = _FailAfterDmlInterceptor(_DmlOperation.insert);
      final firstDatabase = await harness.openReadyDatabase(
        observer: interceptor,
      );
      final PersonalGraphRepository firstRepository =
          DriftPersonalGraphRepository(
            firstDatabase,
            _SequenceIntentionIdGenerator([id]),
            () => DateTime.utc(2026, 9, 3, 10),
            InMemoryDiagnosticsSink(),
          );

      interceptor.arm();
      final result = await firstRepository.execute(
        const CreateIntention(
          title: 'Несохранённое создание',
          description: 'Не должно остаться в файле',
        ),
      );

      expect(result, _unexpectedCommandFailure());
      final firstSnapshot =
          Completer<Result<GraphSnapshot<IntentionDetails?>>>();
      final subscription = firstRepository
          .watchIntention(id)
          .listen(firstSnapshot.complete);
      expect(_watched(await firstSnapshot.future), isNull);
      await subscription.cancel();
      await harness.closePersistenceObjectGraph();

      final reopenedDatabase = await harness.openReadyDatabase();
      final PersonalGraphRepository reopenedRepository =
          DriftPersonalGraphRepository(
            reopenedDatabase,
            _SequenceIntentionIdGenerator(const []),
            () => DateTime.utc(2026, 9, 3, 11),
            InMemoryDiagnosticsSink(),
          );

      expect(
        _watched(await reopenedRepository.watchIntention(id).first),
        isNull,
      );
      final page = _firstPage(
        await reopenedRepository.getCatalogPage(
          _catalogQuery(
            IntentionScope.all,
            titleFilter: 'несохранённое создание',
          ),
        ),
      );
      expect(page.totalCount, 0);
      expect(page.items, isEmpty);
      await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
      await harness.closePersistenceObjectGraph();
    });

    for (final scenario in [
      _PostDmlFailureReopenScenario(
        description: 'изменения',
        operation: _DmlOperation.update,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000812'),
        initialTitle: 'Исходное обновление',
        initialDescription: 'Исходное описание',
        failedCommand: (id) => UpdateIntention(
          id: id,
          title: 'Несохранённое обновление',
          description: 'Несохранённое описание',
        ),
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        updatedAt: DateTime.utc(2026, 9, 3, 10),
        scope: IntentionScope.active,
        titleFilter: 'исходное обновление',
      ),
      _PostDmlFailureReopenScenario(
        description: 'изменения готовности к действию',
        operation: _DmlOperation.update,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000813'),
        initialTitle: 'Намерение для готовности',
        initialDescription: 'Сохраняемая готовность',
        failedCommand: EnableIntentionReadiness.new,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        updatedAt: DateTime.utc(2026, 9, 3, 10),
        scope: IntentionScope.active,
        titleFilter: 'намерение для готовности',
      ),
      _PostDmlFailureReopenScenario(
        description: 'физического удаления',
        operation: _DmlOperation.delete,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000814'),
        initialTitle: 'Архивируемое намерение',
        initialDescription: null,
        preparationCommands: [
          EnableIntentionReadiness.new,
          ArchiveIntention.new,
        ],
        failedCommand: DeleteIntention.new,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        updatedAt: DateTime.utc(2026, 9, 3, 12),
        scope: IntentionScope.archived,
        titleFilter: 'архивируемое намерение',
      ),
    ]) {
      test(
        'после отказавшего ${scenario.description} сохраняет согласованное намерение после повторного открытия',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final interceptor = _FailAfterDmlInterceptor(scenario.operation);
          final firstDatabase = await harness.openReadyDatabase(
            observer: interceptor,
          );
          final PersonalGraphRepository firstRepository =
              DriftPersonalGraphRepository(
                firstDatabase,
                _SequenceIntentionIdGenerator([scenario.id]),
                _SequenceClock([
                  DateTime.utc(2026, 9, 3, 10),
                  DateTime.utc(2026, 9, 3, 11),
                  DateTime.utc(2026, 9, 3, 12),
                  DateTime.utc(2026, 9, 3, 13),
                ]).call,
                InMemoryDiagnosticsSink(),
              );

          _saved(
            await firstRepository.execute(
              CreateIntention(
                title: scenario.initialTitle,
                description: scenario.initialDescription,
              ),
            ),
          );
          for (final command in scenario.preparationCommands) {
            _saved(await firstRepository.execute(command(scenario.id)));
          }

          interceptor.arm();
          expect(
            await firstRepository.execute(scenario.failedCommand(scenario.id)),
            _unexpectedCommandFailure(),
          );
          final firstSnapshot =
              Completer<Result<GraphSnapshot<IntentionDetails?>>>();
          final subscription = firstRepository
              .watchIntention(scenario.id)
              .listen(firstSnapshot.complete);
          _expectIntention(_watched(await firstSnapshot.future), scenario);
          await subscription.cancel();
          await harness.closePersistenceObjectGraph();

          final reopenedDatabase = await harness.openReadyDatabase();
          final PersonalGraphRepository reopenedRepository =
              DriftPersonalGraphRepository(
                reopenedDatabase,
                _SequenceIntentionIdGenerator(const []),
                () => DateTime.utc(2026, 9, 3, 14),
                InMemoryDiagnosticsSink(),
              );

          _expectIntention(
            _watched(
              await reopenedRepository.watchIntention(scenario.id).first,
            ),
            scenario,
          );
          final scopePage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(scenario.scope),
            ),
          );
          expect(scopePage.totalCount, 1);
          expect(scopePage.items.map((item) => item.id), [scenario.id]);

          final excludedScope = switch (scenario.scope) {
            IntentionScope.active => IntentionScope.archived,
            IntentionScope.archived => IntentionScope.active,
            IntentionScope.all => throw StateError(
              'Охват all не может быть исключающим.',
            ),
          };
          final excludedPage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(excludedScope),
            ),
          );
          expect(excludedPage.totalCount, 0);
          expect(excludedPage.items, isEmpty);

          final filteredPage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(
                IntentionScope.all,
                titleFilter: scenario.titleFilter,
              ),
            ),
          );
          expect(filteredPage.totalCount, 1);
          expect(filteredPage.items.map((item) => item.id), [scenario.id]);
          await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
          await harness.closePersistenceObjectGraph();
        },
      );
    }

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

  group('Полное создание намерения в файловом хранилище', () {
    test('повторное открытие восстанавливает подтверждённое намерение со '
        'всеми тегами, готовностью, избранным, местом и временем в новой '
        'эпохе ревизий', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final prepared = await _prepareCreationStorage(harness);

      final database = await harness.openReadyDatabase();
      final result = await creationDurabilityRepository(database)
          .execute(creationDurabilityCommand());
      expect(
        result,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final creationRevision =
          (result
                  as ResultSuccess<
                    ConfirmedGraphResult<IntentionCommandSuccess>
                  >)
              .value
              .revision;
      await harness.closePersistenceObjectGraph();

      late sqlite.Database raw;
      final reopenedDatabase = await harness.openReadyDatabase(
        setup: (db) => raw = db,
      );
      final reopenedRepository = _reopenedRepository(reopenedDatabase);

      final reopenedRevision = await _expectWholeCreation(
        reopenedRepository,
        raw,
        prepared,
      );
      expect(
        creationRevision.compareTo(reopenedRevision),
        GraphRevisionOrder.differentEpoch,
      );
      await _expectIntactStorage(
        reopenedRepository,
        reopenedDatabase,
        raw,
        prepared,
      );
    });

    for (final boundary in _CreationFaultBoundary.values) {
      test('отказ ${boundary.description} не оставляет частей создания '
          'после повторного открытия', () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        final prepared = await _prepareCreationStorage(harness);
        final interceptor = _CreationFaultInterceptor(boundary);

        final database = await harness.openReadyDatabase(observer: interceptor);
        interceptor.arm();
        final result = await creationDurabilityRepository(database)
            .execute(creationDurabilityCommand());
        expect(result, _unexpectedCommandFailure());
        expect(interceptor.hasFailed, isTrue);
        await harness.closePersistenceObjectGraph();

        late sqlite.Database raw;
        final reopenedDatabase = await harness.openReadyDatabase(
          setup: (db) => raw = db,
        );
        final repository = _reopenedRepository(reopenedDatabase);
        await _expectNoCreation(repository, raw, prepared);
        await _expectIntactStorage(repository, reopenedDatabase, raw, prepared);
      });
    }

    group('Остановка отдельного процесса', () {
      for (final stopPoint in _CreationStopPoint.values) {
        test('${stopPoint.testDescription} оставляет целое состояние после '
            'повторного открытия', () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final prepared = await _prepareCreationStorage(harness);

          await _runCreationWorkerUntilStopPoint(harness, stopPoint);

          late sqlite.Database raw;
          final reopenedDatabase = await harness.openReadyDatabase(
            setup: (db) => raw = db,
          );
          final repository = _reopenedRepository(reopenedDatabase);
          switch (stopPoint) {
            case _CreationStopPoint.beforeCommit:
              await _expectNoCreation(repository, raw, prepared);
            case _CreationStopPoint.afterCommit:
              await _expectWholeCreation(repository, raw, prepared);
          }
          await _expectIntactStorage(
            repository,
            reopenedDatabase,
            raw,
            prepared,
          );
        }, timeout: Timeout.none);
      }
    });
  });
}

/// Хранилище до создания намерения: строки прежнего графа, схема и ревизия
/// репозитория, который записал прежний граф.
typedef _PreparedCreationStorage = ({
  Map<String, List<List<Object?>>> graph,
  List<List<Object?>> schema,
  GraphRevision revision,
});

/// Записывает прежний граф и самостоятельный тег «Спорт» отдельной
/// подтверждённой командой и закрывает хранилище.
Future<_PreparedCreationStorage> _prepareCreationStorage(
  LocalDatabaseHarness harness,
) async {
  late sqlite.Database raw;
  final database = await harness.openReadyDatabase(setup: (db) => raw = db);
  seedCreationDurabilityGraph(raw);
  final created = await creationDurabilityRepository(database)
      .execute(CreateTag(TagName.fromInput('Спорт')));
  expect(created, isA<TagCommandSucceeded>());
  final prepared = (
    graph: _storedGraph(raw),
    schema: _storedSchema(raw),
    revision: (created as TagCommandSucceeded).value.revision,
  );
  await harness.closePersistenceObjectGraph();
  return prepared;
}

/// Репозиторий повторно открытого хранилища: собственных идентификаторов и
/// показаний часов у него нет, ревизии начинаются в новой эпохе.
DriftPersonalGraphRepository _reopenedRepository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      _SequenceIntentionIdGenerator(const []),
      () => DateTime.utc(2026, 10, 4, 18),
      InMemoryDiagnosticsSink(),
    );

/// Подтверждённое полное создание видно публичными чтениями и поиском,
/// а прежний граф не изменён. Возвращает ревизию чтения намерения.
Future<GraphRevision> _expectWholeCreation(
  DriftPersonalGraphRepository repository,
  sqlite.Database raw,
  _PreparedCreationStorage prepared,
) async {
  final id = creationDurabilityIntentionId;
  final standaloneTagId = creationDurabilityStandaloneTagId;
  final existingTagId = creationDurabilityExistingTagId;

  final snapshot = _readValue(await repository.watchIntention(id).first);
  expect(
    prepared.revision.compareTo(snapshot.revision),
    GraphRevisionOrder.differentEpoch,
  );
  final details = snapshot.value;
  expect(details, isNotNull);
  final intention = details!.intention;
  expect(intention.title, 'Полное намерение');
  expect(intention.description, '  Подробное\nописание  ');
  expect(intention.readiness, IntentionReadiness.ready);
  expect(intention.archiveState, IntentionArchiveState.active);
  expect(intention.createdAt.value, creationDurabilityTime);
  expect(intention.updatedAt.value, creationDurabilityTime);
  expect(details.favoriteMark, FavoriteMark.favorite);

  final assignments = _readValue(await repository.getTagAssignments(id));
  expect(
    [for (final tag in assignments.items) (tag.id, tag.name.value)],
    [(existingTagId, 'Дом'), (standaloneTagId, 'Спорт')],
  );

  // Поиск сочетает название с готовностью и обоими назначенными тегами.
  final found = _firstPage(
    await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: 'полное',
        tagFilter: IntentionTagFilter(
          requiredTagIds: [existingTagId, standaloneTagId],
        ),
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 10,
      ),
    ),
  );
  expect(found.totalCount, 1);
  final summary = found.items.single;
  expect(summary.id, id);
  expect(summary.readiness, IntentionReadiness.ready);
  expect(summary.favoriteMark, FavoriteMark.favorite);
  expect(summary.tags.map((tag) => tag.id), [existingTagId, standaloneTagId]);
  expect(summary.createdAt.value, creationDurabilityTime);
  expect(summary.updatedAt.value, creationDurabilityTime);

  final favorites = _readValue(await repository.getFavoriteIntentions());
  expect(favorites.items.map((row) => row.id), [_id(tagFixtureId(1)), id]);
  expect(favorites.archivedCount, 1);
  expect(await _taggedActiveIds(repository, standaloneTagId), [id]);
  expect(await _taggedActiveIds(repository, existingTagId), [
    _id(tagFixtureId(1)),
    id,
  ]);

  // Место встаёт за максимумом всего порядка, включая архивированное.
  expect(storedFavoriteMarks(raw), [
    (tagFixtureId(1), 2),
    (tagFixtureId(2), 5),
    (id.toCanonicalString(), 6),
  ]);
  expect(_storedGraph(raw, excluded: id), prepared.graph);
  return snapshot.revision;
}

/// Ни намерения, ни его назначений, ни места избранного нет: публичные
/// чтения и строки хранилища совпадают с прежним графом.
Future<void> _expectNoCreation(
  DriftPersonalGraphRepository repository,
  sqlite.Database raw,
  _PreparedCreationStorage prepared,
) async {
  final id = creationDurabilityIntentionId;
  expect(_watched(await repository.watchIntention(id).first), isNull);
  expect(
    await repository.getTagAssignments(id),
    isA<TagAssignmentsError>().having(
      (result) => result.failure,
      'причина',
      isA<TagAssignmentsIntentionNotFound>(),
    ),
  );
  final found = _firstPage(
    await repository.getCatalogPage(
      _catalogQuery(IntentionScope.all, titleFilter: 'полное'),
    ),
  );
  expect(found.totalCount, 0);
  expect(found.items, isEmpty);

  final favorites = _readValue(await repository.getFavoriteIntentions());
  expect(favorites.items.map((row) => row.id), [_id(tagFixtureId(1))]);
  expect(favorites.archivedCount, 1);
  expect(
    await _taggedActiveIds(repository, creationDurabilityStandaloneTagId),
    isEmpty,
  );
  expect(await _taggedActiveIds(repository, creationDurabilityExistingTagId), [
    _id(tagFixtureId(1)),
  ]);

  expect(storedFavoriteMarks(raw), [
    (tagFixtureId(1), 2),
    (tagFixtureId(2), 5),
  ]);
  expect(_storedGraph(raw), prepared.graph);
}

/// Самостоятельный тег доступен, хранилище целостно, поисковая проекция
/// согласована, а схема и её версия не изменились.
Future<void> _expectIntactStorage(
  DriftPersonalGraphRepository repository,
  AppDatabase database,
  sqlite.Database raw,
  _PreparedCreationStorage prepared,
) async {
  final tags = _readValue(
    await repository.getTagCatalog(const TagCatalogBrowseMode()),
  );
  expect(
    [for (final tag in tags.items) (tag.id, tag.name.value)],
    containsAllInOrder([
      (creationDurabilityExistingTagId, 'Дом'),
      (creationDurabilityStandaloneTagId, 'Спорт'),
    ]),
  );
  expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
  expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  await verifyIntentionTitlesFtsIntegrity(database);
  await expectLater(verifyDoableDatabaseSchema(database), completes);
  expect(
    raw.select('PRAGMA user_version').single.values.single,
    AppDatabase.currentSchemaVersion,
  );
  expect(_storedSchema(raw), prepared.schema);
}

Future<List<IntentionId>> _taggedActiveIds(
  DriftPersonalGraphRepository repository,
  TagId tagId,
) async => [
  for (final item in _readValue(
    await repository.getTaggedIntentionsPage(
      TaggedIntentionsQuery(tagId: tagId, scope: TaggedIntentionsScope.active),
    ),
  ).items)
    item.id,
];

/// Строки личного графа в порядке записи. Для намерения [excluded] не
/// учитываются его собственная строка, назначения и место избранного.
Map<String, List<List<Object?>>> _storedGraph(
  sqlite.Database database, {
  IntentionId? excluded,
}) => {
  for (final (table, ownerColumn) in const [
    ('intentions', 'id'),
    ('tag_assignments', 'intention_id'),
    ('favorite_intentions', 'intention_id'),
    ('tags', null),
    ('long_term_relations', null),
    ('daily_choices', null),
    ('daily_choice_path_steps', null),
  ])
    table: database
        .select(
          switch (ownerColumn) {
            null => 'SELECT * FROM $table ORDER BY rowid',
            final column =>
              'SELECT * FROM $table WHERE $column IS NOT ? ORDER BY rowid',
          },
          [if (ownerColumn != null) excluded?.toCanonicalString()],
        )
        .map((row) => row.values.toList())
        .toList(),
};

List<List<Object?>> _storedSchema(sqlite.Database database) => database
    .select('SELECT type, name, tbl_name, sql FROM sqlite_schema ORDER BY name')
    .map((row) => row.values.toList())
    .toList();

T _readValue<T, F extends GraphCommandFailure>(GraphResult<T, F> result) =>
    switch (result) {
      GraphResultSuccess(:final value) => value,
      GraphResultFailure(:final failure) => throw TestFailure(
        'Ожидался успех чтения, получен отказ $failure.',
      ),
    };

Future<void> _runCreationWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  _CreationStopPoint stopPoint,
) async {
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_operation_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    _findFlutterExecutable(),
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      _workerOperationEnvironment: 'intention_full_create',
      _workerStopPointEnvironment: stopPoint.environmentValue,
      _workerDatabasePathEnvironment: harness.databaseFile.path,
    },
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final ready = Completer<int>();
  final startedPidPattern = RegExp('$_workerStartedMarker:(\\d+)');
  final readyPidPattern = RegExp('$_workerReadyMarker:(\\d+)');
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedWorkerPid;

  process.stdout.transform(utf8.decoder).listen((chunk) {
    stdoutBuffer.write(chunk);
    final output = stdoutBuffer.toString();
    final startedMatch = startedPidPattern.firstMatch(output);
    if (startedMatch != null) {
      startedWorkerPid = int.parse(startedMatch.group(1)!);
    }
    final readyMatch = readyPidPattern.firstMatch(output);
    if (readyMatch != null && !ready.isCompleted) {
      ready.complete(int.parse(readyMatch.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((exitCode) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс полного создания завершился с кодом $exitCode до точки '
            '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
            'stderr:\n$stderrBuffer',
          ),
        );
      }
    }),
  );

  var workerWasKilled = false;
  try {
    final workerPid = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс полного создания не достиг точки '
        '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
        'stderr:\n$stderrBuffer',
      ),
    );
    // Точку остановки сообщил тот же отдельный процесс, который начал
    // операцию, а не процесс самого теста.
    expect(workerPid, startedWorkerPid);
    expect(workerPid, isNot(pid));
    workerWasKilled = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(
      workerWasKilled,
      isTrue,
      reason: 'Не удалось принудительно завершить процесс полного создания.',
    );
  } finally {
    if (!workerWasKilled) {
      final workerPid = startedWorkerPid;
      if (workerPid != null) {
        Process.killPid(workerPid, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
    }
  }

  final exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
  await Future.wait([stdoutDone.future, stderrDone.future]);
  expect(exitCode, isNot(0));
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Не удалось найти Flutter SDK от Platform.resolvedExecutable.',
      );
    }
    directory = parent;
  }
}

enum _CreationStopPoint {
  beforeCommit(
    environmentValue: 'before_commit',
    testDescription:
        'остановка после всех записей полного создания до подтверждения',
  ),
  afterCommit(
    environmentValue: 'after_commit',
    testDescription: 'остановка после подтверждения полного создания',
  );

  const _CreationStopPoint({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;
}

/// Границы транзакции полного создания, сразу после которых она отказывает.
enum _CreationFaultBoundary {
  intentionInsert('после вставки намерения'),
  firstAssignment('после части назначений'),
  favoritePlace('после записи места избранного'),
  finalRead('при чтении окончательного результата');

  const _CreationFaultBoundary(this.description);

  final String description;
}

/// После [arm] прерывает транзакцию на заданной границе: действие операции
/// уже внесено в транзакцию, а её результат не доходит до репозитория.
final class _CreationFaultInterceptor extends LocalDatabaseConnectionObserver {
  _CreationFaultInterceptor(this._boundary);

  final _CreationFaultBoundary _boundary;
  var _armed = false;
  var _wroteFavoritePlace = false;
  var hasFailed = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_armed || hasFailed) return;
    final insertedTable = switch (statement.operation) {
      LocalDatabaseSqlOperation.insert => _insertedTable(statement),
      _ => null,
    };
    final reached = switch (_boundary) {
      _CreationFaultBoundary.intentionInsert => insertedTable == 'intentions',
      _CreationFaultBoundary.firstAssignment =>
        insertedTable == 'tag_assignments',
      _CreationFaultBoundary.favoritePlace =>
        insertedTable == 'favorite_intentions',
      _CreationFaultBoundary.finalRead =>
        _wroteFavoritePlace &&
            statement.operation == LocalDatabaseSqlOperation.select,
    };
    if (insertedTable == 'favorite_intentions') _wroteFavoritePlace = true;
    if (!reached) return;
    hasFailed = true;
    throw StateError('CANARY-creation-fault');
  }
}

String _insertedTable(LocalDatabaseSqlStatement statement) {
  final match = RegExp(
    r'^\s*INSERT\s+INTO\s+"?(\w+)"?',
    caseSensitive: false,
  ).firstMatch(statement.statements.single);
  return match?.group(1) ??
      (throw StateError('Не удалось определить таблицу вставки.'));
}

const _workerOperationEnvironment = 'DOABLE_GRAPH_OPERATION';
const _workerStopPointEnvironment = 'DOABLE_GRAPH_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_GRAPH_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_GRAPH_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_GRAPH_WORKER_READY';

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

Matcher _unexpectedCommandFailure() =>
    isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.failure,
      'failure',
      isA<IntentionUnexpectedFailure>(),
    );

void _expectIntention(
  Intention? intention,
  _PostDmlFailureReopenScenario scenario,
) {
  expect(intention, isNotNull);
  expect(intention!.id, scenario.id);
  expect(intention.title, scenario.initialTitle);
  expect(intention.description, scenario.initialDescription);
  expect(intention.readiness, scenario.readiness);
  expect(intention.archiveState, scenario.archiveState);
  expect(intention.createdAt.value, DateTime.utc(2026, 9, 3, 10));
  expect(intention.updatedAt.value, scenario.updatedAt);
}

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

enum _DmlOperation { insert, update, delete }

typedef _IntentionCommandFactory = IntentionCommand Function(IntentionId id);

final class _PostDmlFailureReopenScenario {
  _PostDmlFailureReopenScenario({
    required this.description,
    required this.operation,
    required this.id,
    required this.initialTitle,
    required this.initialDescription,
    required this.failedCommand,
    required this.readiness,
    required this.archiveState,
    required this.updatedAt,
    required this.scope,
    required this.titleFilter,
    this.preparationCommands = const [],
  });

  final String description;
  final _DmlOperation operation;
  final IntentionId id;
  final String initialTitle;
  final String? initialDescription;
  final List<_IntentionCommandFactory> preparationCommands;
  final _IntentionCommandFactory failedCommand;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final DateTime updatedAt;
  final IntentionScope scope;
  final String titleFilter;
}

final class _FailAfterDmlInterceptor extends LocalDatabaseConnectionObserver {
  _FailAfterDmlInterceptor(this._operation);

  final _DmlOperation _operation;
  var _armed = false;
  var _hasFailed = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final isExpectedOperation = switch (_operation) {
      _DmlOperation.insert =>
        statement.operation == LocalDatabaseSqlOperation.insert,
      _DmlOperation.update =>
        statement.operation == LocalDatabaseSqlOperation.update,
      _DmlOperation.delete =>
        statement.operation == LocalDatabaseSqlOperation.delete,
    };
    if (!isExpectedOperation) return;
    if (_armed && !_hasFailed) {
      _hasFailed = true;
      throw StateError('CANARY-after-dml-failure');
    }
  }
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
