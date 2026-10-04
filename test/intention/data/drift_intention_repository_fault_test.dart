import 'dart:async';
import 'dart:convert';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
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
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

part 'catalog_tag_filter_failure_scenarios.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  _catalogTagFilterFailureScenarios((observer, setup) async {
    final replacement = await _replaceDatabase(
      observer,
      database,
      diagnostics,
      setup: setup,
    );
    database = replacement.database;
    repository = replacement.repository;
    return (
      database: database,
      repository: repository,
      diagnostics: diagnostics,
    );
  });

  _catalogReconciliationFailureScenarios((observer, setup) async {
    final replacement = await _replaceDatabase(
      observer,
      database,
      diagnostics,
      setup: setup,
    );
    database = replacement.database;
    repository = replacement.repository;
    return (
      database: database,
      repository: repository,
      diagnostics: diagnostics,
    );
  });

  group('Порция каталога — отказы получения собственных тегов', () {
    test('повреждённая ссылка отклоняет всю порцию и её продолжение', () async {
      for (final id in [_id(_firstUuid), _id(_secondUuid)]) {
        await _insertIntention(
          database,
          id: id,
          title: 'Одноимённое намерение',
          createdAt: DateTime.utc(2026, 9, 2, 10),
        );
      }
      final query = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 1,
      );
      final first = (await repository.getCatalogPage(
        query,
      ) as ResultSuccess<IntentionCatalogPage>).value;
      await database.customStatement('PRAGMA foreign_keys = OFF');
      await database.customStatement(
        'INSERT INTO tags (id, name) VALUES (?, ?)',
        [_relationUuid, 'CANARY-тег'],
      );
      await database.customStatement(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_relationUuid, _secondUuid],
      );
      await database.customStatement('DELETE FROM tags WHERE id = ?', [
        _relationUuid,
      ]);

      for (final request in [
        IntentionCatalogQuery(
          scope: query.scope,
          titleFilter: null,
          order: query.order,
          pageSize: 2,
        ),
        IntentionCatalogQuery(
          scope: query.scope,
          titleFilter: null,
          order: query.order,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ]) {
        expect(
          await repository.getCatalogPage(request),
          isA<ResultFailure<IntentionCatalogPage>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionCorruptionFailure>(),
          ),
        );
      }
    });

    test(
      'ошибка после получения назначений не публикует частичный успех',
      () async {
        for (final (error, expected, code)
            in <(Object, Matcher, DiagnosticsFailureCode)>[
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_BUSY,
                  message: 'CANARY-недоступность',
                ),
                isA<IntentionUnavailableFailure>(),
                DiagnosticsFailureCode.unavailable,
              ),
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_CORRUPT,
                  message: 'CANARY-повреждение',
                ),
                isA<IntentionCorruptionFailure>(),
                DiagnosticsFailureCode.corruption,
              ),
              (
                StateError('CANARY-неизвестный-отказ'),
                isA<IntentionUnexpectedFailure>(),
                DiagnosticsFailureCode.unexpected,
              ),
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_READONLY,
                  message: 'CANARY-неизвестный-SQLite-отказ',
                ),
                isA<IntentionUnexpectedFailure>(),
                DiagnosticsFailureCode.unexpected,
              ),
            ]) {
          final interceptor = _TagAssignmentReadInterceptor(failure: error);
          final replacement = await _replaceDatabase(
            interceptor,
            database,
            diagnostics,
          );
          database = replacement.database;
          repository = replacement.repository;
          await _insertIntention(
            database,
            id: _id(_firstUuid),
            title: 'CANARY-намерение',
            createdAt: DateTime.utc(2026, 9, 2, 10),
          );
          await database.customStatement(
            'INSERT INTO tags (id, name) VALUES (?, ?)',
            [_relationUuid, 'CANARY-тег'],
          );
          await database.customStatement(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_relationUuid, _firstUuid],
          );
          final result = await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: null,
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
            ),
          );

          expect(
            result,
            isA<ResultFailure<IntentionCatalogPage>>().having(
              (result) => result.failure,
              'причина',
              expected,
            ),
          );
          expect(
            diagnostics.events.last,
            isA<CatalogPageReadDiagnosticsEvent>().having(
              (event) => event.status,
              'исход',
              isA<DiagnosticsFailed>().having(
                (status) => status.code,
                'категория',
                code,
              ),
            ),
          );
          expect(diagnostics.events.toString(), isNot(contains('CANARY')));
        }
      },
    );
  });

  group('Чтения намерений — отказы получения отметки избранного', () {
    test(
      'отказ чтения отметки сохраняет категорию без частичного успеха',
      () async {
        for (final (error, expected, code)
            in <(Object, Matcher, DiagnosticsFailureCode)>[
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_BUSY,
                  message: 'CANARY-недоступность',
                ),
                isA<IntentionUnavailableFailure>(),
                DiagnosticsFailureCode.unavailable,
              ),
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_CORRUPT,
                  message: 'CANARY-повреждение',
                ),
                isA<IntentionCorruptionFailure>(),
                DiagnosticsFailureCode.corruption,
              ),
              (
                StateError('CANARY-неизвестный-отказ'),
                isA<IntentionUnexpectedFailure>(),
                DiagnosticsFailureCode.unexpected,
              ),
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_READONLY,
                  message: 'CANARY-неизвестный-SQLite-отказ',
                ),
                isA<IntentionUnexpectedFailure>(),
                DiagnosticsFailureCode.unexpected,
              ),
            ]) {
          final interceptor = _FavoriteMarkReadInterceptor(failure: error);
          late Database raw;
          final replacement = await _replaceDatabase(
            interceptor,
            database,
            diagnostics,
            setup: (connection) => raw = connection,
          );
          database = replacement.database;
          repository = replacement.repository;
          await _insertIntention(
            database,
            id: _id(_firstUuid),
            title: 'CANARY-намерение',
            createdAt: DateTime.utc(2026, 9, 2, 10),
          );
          storeFavoriteMark(raw, intentionId: _firstUuid, position: 1);
          final query = IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 1,
          );
          Matcher failed<TEvent extends DiagnosticsEvent>(
            DiagnosticsStatus Function(TEvent) status,
          ) => isA<TEvent>().having(
            status,
            'исход',
            isA<DiagnosticsFailed>().having(
              (status) => status.code,
              'категория',
              code,
            ),
          );

          expect(
            await repository.getCatalogPage(query),
            isA<ResultFailure<IntentionCatalogPage>>().having(
              (result) => result.failure,
              'причина',
              expected,
            ),
          );
          expect(
            diagnostics.events.last,
            failed<CatalogPageReadDiagnosticsEvent>((event) => event.status),
          );

          expect(
            await repository.getCatalogReconciliationPortion(
              IntentionCatalogReconciliationQuery(
                catalogQuery: query,
                boundary: const IntentionCatalogCompletedBoundary(),
                window: IntentionCatalogFinalReconciliationWindow(const []),
              ),
            ),
            isA<ResultFailure<IntentionCatalogReconciliationOutcome>>().having(
              (result) => result.failure,
              'причина',
              expected,
            ),
          );

          expect(
            await repository.watchIntention(_id(_firstUuid)).first,
            isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
              (result) => result.failure,
              'причина',
              expected,
            ),
          );
          expect(
            diagnostics.events.last,
            failed<IntentionDetailReadDiagnosticsEvent>(
              (event) => event.status,
            ),
          );

          // Снимок «до» читает отметку раньше записи: команда не оставляет
          // изменения намерения.
          expect(
            await repository.execute(
              UpdateIntention(
                id: _id(_firstUuid),
                title: 'CANARY-новое название',
                description: null,
              ),
            ),
            isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
                .having((result) => result.failure, 'причина', expected),
          );
          expect(
            diagnostics.events.last,
            _failedCommand(IntentionCommandDiagnosticsType.update, code),
          );
          await _expectStoredIntention(
            database,
            id: _id(_firstUuid),
            title: 'CANARY-намерение',
            description: null,
            isActionReady: false,
            isArchived: false,
            createdAt: DateTime.utc(2026, 9, 2, 10),
          );
          expect(interceptor.failedReads, 4);
          expect(diagnostics.events.toString(), isNot(contains('CANARY')));
        }
      },
    );

    test('место без намерения вне запрошенных не отказывает чтению, а повреждённая отметка запрошенного отказывает', () async {
      late Database raw;
      final replacement = await _replaceDatabase(
        const _PassiveObserver(),
        database,
        diagnostics,
        setup: (connection) => raw = connection,
      );
      database = replacement.database;
      repository = replacement.repository;
      await _insertIntention(
        database,
        id: _id(_firstUuid),
        title: 'CANARY-целостное',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: _id(_secondUuid),
        title: 'CANARY-повреждённое',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _relationUuid,
        position: 1,
      );
      storeFavoriteMark(raw, intentionId: _firstUuid, position: 2);
      storeFavoriteMarkWithInvalidPosition(
        raw,
        intentionId: _secondUuid,
        position: 0,
      );
      IntentionCatalogQuery query({
        required int pageSize,
        IntentionCatalogCursor? cursor,
      }) => IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: pageSize,
        cursor: cursor,
      );
      Matcher corrupted<TEvent extends DiagnosticsEvent>(
        DiagnosticsStatus Function(TEvent) status,
      ) => isA<TEvent>().having(
        status,
        'исход',
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'категория',
          DiagnosticsFailureCode.corruption,
        ),
      );

      // Порция и подробные данные целостного намерения не зависят от
      // места без намерения и от повреждённой отметки вне запрошенных.
      final intactPage = await repository.getCatalogPage(query(pageSize: 1));
      expect(intactPage, isA<ResultSuccess<IntentionCatalogPage>>());
      final page = (intactPage as ResultSuccess<IntentionCatalogPage>).value;
      expect(page.items.single.id, _id(_firstUuid));
      expect(page.items.single.favoriteMark, FavoriteMark.favorite);
      expect(
        diagnostics.events.last,
        isA<CatalogPageReadDiagnosticsEvent>().having(
          (event) => event.status,
          'исход',
          isA<DiagnosticsSucceeded>(),
        ),
      );
      final intactDetails = await repository
          .watchIntention(_id(_firstUuid))
          .first;
      expect(
        intactDetails,
        isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>(),
      );
      expect(
        (intactDetails as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
            .value
            .value!
            .favoriteMark,
        FavoriteMark.favorite,
      );

      // Повреждённая отметка запрошенного намерения отклоняет порцию,
      // её продолжение и подробные данные целиком.
      for (final failing in [
        query(pageSize: 2),
        query(pageSize: 1, cursor: page.nextCursor),
      ]) {
        expect(
          await repository.getCatalogPage(failing),
          isA<ResultFailure<IntentionCatalogPage>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionCorruptionFailure>(),
          ),
        );
        expect(
          diagnostics.events.last,
          corrupted<CatalogPageReadDiagnosticsEvent>((event) => event.status),
        );
      }
      expect(
        await repository.watchIntention(_id(_secondUuid)).first,
        isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
          (result) => result.failure,
          'причина',
          isA<IntentionCorruptionFailure>(),
        ),
      );
      expect(
        diagnostics.events.last,
        corrupted<IntentionDetailReadDiagnosticsEvent>((event) => event.status),
      );
      expect(storedFavoriteMarks(raw), [
        (_secondUuid, 0),
        (_relationUuid, 1),
        (_firstUuid, 2),
      ]);
      expect(diagnostics.events.toString(), isNot(contains('CANARY')));
    });
  });

  group('DriftPersonalGraphRepository.execute — физическое удаление', () {
    test(
      'не выдаёт посторонний blocking foreign key за конфликт связей',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id,
          title: 'Блокирующее намерение',
          description: 'Исходное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        await database.customStatement('''
        CREATE TABLE test_only_blocking_links (
          intention_id TEXT NOT NULL REFERENCES intentions(id)
        )
      ''');
        await database.customStatement(
          'INSERT INTO test_only_blocking_links (intention_id) VALUES (?)',
          [id.toCanonicalString()],
        );

        final result = await repository.execute(DeleteIntention(id));

        expect(result, _failure<IntentionUnexpectedFailure>());
        await _expectStoredIntention(
          database,
          id: id,
          title: 'Блокирующее намерение',
          description: 'Исходное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        expect(await _matchingIds(repository, 'блокирующее'), [id]);
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
          [
            _failedCommand(
              IntentionCommandDiagnosticsType.delete,
              DiagnosticsFailureCode.unexpected,
            ),
          ],
        );
      },
    );
  });

  group('DriftPersonalGraphRepository.execute — откат после DML', () {
    test('откатывает create вместе с основной строкой и FTS', () async {
      final interceptor = _FailAfterDmlInterceptor(_DmlOperation.insert);
      final replacement = await _replaceDatabase(
        interceptor,
        database,
        diagnostics,
      );
      database = replacement.database;
      repository = replacement.repository;
      interceptor.arm();

      final result = await repository.execute(
        const CreateIntention(
          title: 'Создаваемое намерение',
          description: 'Создаваемое описание',
        ),
      );

      expect(result, _failure<IntentionUnexpectedFailure>());
      expect(await database.select(database.intentions).get(), isEmpty);
      expect(await _matchingIds(repository, 'создаваемое'), isEmpty);
      await expectLater(verifyIntentionTitlesFtsIntegrity(database), completes);
      expect(diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(), [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.unexpected,
        ),
      ]);
    });

    test(
      'откатывает update вместе с title search key, FTS и timestamps',
      () async {
        final interceptor = _FailAfterDmlInterceptor(_DmlOperation.update);
        final replacement = await _replaceDatabase(
          interceptor,
          database,
          diagnostics,
        );
        database = replacement.database;
        repository = replacement.repository;
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id,
          title: 'Исходное намерение',
          description: 'Исходное описание',
          createdAt: createdAt,
        );
        interceptor.arm();

        final result = await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Изменённое намерение',
            description: 'Изменённое описание',
          ),
        );

        expect(result, _failure<IntentionUnexpectedFailure>());
        await _expectStoredIntention(
          database,
          id: id,
          title: 'Исходное намерение',
          description: 'Исходное описание',
          isActionReady: false,
          isArchived: false,
          createdAt: createdAt,
        );
        expect(await _matchingIds(repository, 'исходное'), [id]);
        expect(await _matchingIds(repository, 'изменённое'), isEmpty);
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
      },
    );

    test(
      'откатывает state transition и сохраняет timestamps намерения',
      () async {
        final interceptor = _FailAfterDmlInterceptor(_DmlOperation.update);
        final replacement = await _replaceDatabase(
          interceptor,
          database,
          diagnostics,
        );
        database = replacement.database;
        repository = replacement.repository;
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id,
          title: 'Намерение для readiness',
          createdAt: createdAt,
        );
        interceptor.arm();

        final result = await repository.execute(EnableIntentionReadiness(id));

        expect(result, _failure<IntentionUnexpectedFailure>());
        await _expectStoredIntention(
          database,
          id: id,
          title: 'Намерение для readiness',
          description: null,
          isActionReady: false,
          isArchived: false,
          createdAt: createdAt,
        );
        expect(await _matchingIds(repository, 'readiness'), [id]);
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
      },
    );

    test(
      'откатывает связи и намерение при отказе между шагами каскада',
      () async {
        final interceptor = _FailAfterDmlInterceptor(_DmlOperation.update);
        final replacement = await _replaceDatabase(
          interceptor,
          database,
          diagnostics,
        );
        database = replacement.database;
        repository = replacement.repository;
        final owner = _id(_firstUuid);
        final neighbor = _id(_secondUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: owner,
          title: 'Архивируемое намерение',
          createdAt: createdAt,
        );
        await _insertIntention(
          database,
          id: neighbor,
          title: 'Соседнее намерение',
          createdAt: createdAt,
        );
        await _insertRelation(
          database,
          id: _relationUuid,
          sourceId: owner,
          relatedId: neighbor,
        );
        final revisionBefore = _countsRevision(
          await repository.getRelationCounts(owner),
        );
        final ownerEvents = StreamIterator(repository.watchIntention(owner));
        final neighborEvents = StreamIterator(
          repository.watchIntention(neighbor),
        );
        addTearDown(ownerEvents.cancel);
        addTearDown(neighborEvents.cancel);
        expect(await ownerEvents.moveNext(), isTrue);
        expect(await neighborEvents.moveNext(), isTrue);
        interceptor.detailReadStatements.clear();
        interceptor.arm();

        final result = await repository.execute(ArchiveIntention(owner));

        expect(result, _failure<IntentionUnexpectedFailure>());
        await _expectStoredIntention(
          database,
          id: owner,
          title: 'Архивируемое намерение',
          description: null,
          isActionReady: false,
          isArchived: false,
          createdAt: createdAt,
        );
        expect(await _relationIsArchived(database, _relationUuid), isFalse);
        expect(
          interceptor.failedStatement,
          contains('UPDATE long_term_relations'),
        );
        final revisionAfter = _countsRevision(
          await repository.getRelationCounts(owner),
        );
        expect(
          revisionBefore.compareTo(revisionAfter),
          GraphRevisionOrder.same,
        );
        await pumpEventQueue();
        expect(interceptor.detailReadStatements, isEmpty);
      },
    );

    test(
      'откатывает delete вместе с основной строкой, FTS и timestamps',
      () async {
        final interceptor = _FailAfterDmlInterceptor(_DmlOperation.delete);
        final replacement = await _replaceDatabase(
          interceptor,
          database,
          diagnostics,
        );
        database = replacement.database;
        repository = replacement.repository;
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id,
          title: 'Удаляемое намерение',
          description: 'Исходное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        interceptor.arm();

        final result = await repository.execute(DeleteIntention(id));

        expect(result, _failure<IntentionUnexpectedFailure>());
        await _expectStoredIntention(
          database,
          id: id,
          title: 'Удаляемое намерение',
          description: 'Исходное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        expect(await _matchingIds(repository, 'удаляемое'), [id]);
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
      },
    );
  });

  group('DriftPersonalGraphRepository.execute — откат и диагностика полного '
      'создания', () {
    final homeTagId = _tagId(tagFixtureId(firstTagNumber));
    final weekendTagId = _tagId(tagFixtureId(lastTagNumber));
    final missingTagId = _tagId(tagFixtureId(777));
    final activeFavoriteId = _id(_firstUuid);
    final archivedFavoriteId = _id(_archivedUuid);
    final newId = _id(_secondUuid);
    late Database raw;

    /// Подменяет хранилище и готовит прежний граф: активное избранное
    /// намерение, архивированное избранное на последнем месте порядка, теги
    /// «Дом» и «Выходные» и самостоятельный «Спорт», созданный отдельной
    /// командой до создания намерения. Возвращает идентификатор «Спорта».
    ///
    /// Репозиторий передаёт события диагностики в [diagnosticsSink], по
    /// умолчанию — в общий записывающий получатель теста.
    Future<TagId> replaceWithSeededGraph(
      LocalDatabaseConnectionObserver observer, {
      DiagnosticsSink? diagnosticsSink,
      List<IntentionId>? intentionIds,
    }) async {
      final replacement = await _replaceDatabase(
        observer,
        database,
        diagnosticsSink ?? diagnostics,
        setup: (connection) => raw = connection,
        // Повтор после отката снова получает тот же идентификатор: остаток
        // прежней попытки отклонил бы его конфликтом первичного ключа.
        intentionIds: intentionIds ?? [newId, newId],
      );
      database = replacement.database;
      repository = replacement.repository;
      await _insertIntention(
        database,
        id: activeFavoriteId,
        title: 'Активное избранное',
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await _insertIntention(
        database,
        id: archivedFavoriteId,
        title: 'Архивное избранное',
        isArchived: true,
        createdAt: DateTime.utc(2026, 9, 2),
      );
      storeFavoriteMark(
        raw,
        intentionId: activeFavoriteId.toCanonicalString(),
        position: 2,
      );
      storeFavoriteMark(
        raw,
        intentionId: archivedFavoriteId.toCanonicalString(),
        position: 5,
      );
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        homeTagId.toCanonicalString(),
        'Дом',
      ]);
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        weekendTagId.toCanonicalString(),
        'Выходные',
      ]);
      final created = await repository.execute(
        CreateTag(TagName.fromInput('Спорт')),
      );
      expect(created, isA<TagCommandSucceeded>());
      return ((created as TagCommandSucceeded).value.value as TagCreated)
          .tag
          .id;
    }

    CreateIntention fullCommand(Iterable<TagId> tagIds) =>
        CreateIntention.withInitialState(
          title: 'Полное намерение',
          description: 'Описание полного намерения',
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: tagIds,
        );

    /// Отказ не оставил части создания: публичные чтения, поиск, места
    /// избранного, строки хранилища и ревизия совпадают с [before], FTS
    /// целостна, а самостоятельный «Спорт» по-прежнему доступен.
    Future<void> expectRolledBack(
      _ObservedCreationGraph before, {
      String? reason,
    }) async {
      final after = await _observeCreationGraph(repository, raw);
      expect(after.facts, before.facts, reason: reason);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
        reason: reason,
      );
      expect(after.tagNames, ['Дом', 'Выходные', 'Спорт'], reason: reason);
      expect(
        _watched(await repository.watchIntention(newId).first),
        isNull,
        reason: reason,
      );
      expect(
        await repository.getTagAssignments(newId),
        isA<TagAssignmentsError>().having(
          (result) => result.failure,
          'причина',
          isA<TagAssignmentsIntentionNotFound>(),
        ),
        reason: reason,
      );
      await expectLater(
        verifyIntentionTitlesFtsIntegrity(database),
        completes,
        reason: reason,
      );
    }

    test('отказ после любой операции транзакции откатывает намерение, '
        'назначения, место избранного и FTS, сохраняя прежний граф, ревизию '
        'и самостоятельный тег', () async {
      // Пробное выполнение без отказа фиксирует операции транзакции.
      final probe = _StatementFaultInjector();
      final probeSportTagId = await replaceWithSeededGraph(probe);
      probe.observe();
      final probed = await repository.execute(
        fullCommand([homeTagId, weekendTagId, probeSportTagId]),
      );
      final operations = probe.stopObserving();
      expect(
        probed,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      expect(
        [
          for (final operation in operations)
            if (operation.operation != LocalDatabaseSqlOperation.select)
              (operation.operation, _writtenTable(operation)),
        ],
        [
          (LocalDatabaseSqlOperation.insert, 'intentions'),
          for (var index = 0; index < 3; index++)
            (LocalDatabaseSqlOperation.insert, 'tag_assignments'),
          (LocalDatabaseSqlOperation.insert, 'favorite_intentions'),
        ],
      );
      // До записей транзакция проверяет выбранные теги, после всех записей —
      // читает окончательный результат.
      final firstWrite = operations.indexWhere(
        (operation) => operation.operation != LocalDatabaseSqlOperation.select,
      );
      final lastWrite = operations.lastIndexWhere(
        (operation) => operation.operation != LocalDatabaseSqlOperation.select,
      );
      expect(firstWrite, greaterThan(0));
      expect(operations.skip(lastWrite + 1), isNotEmpty);

      for (var failAfter = 1; failAfter <= operations.length; failAfter++) {
        final faulted = operations[failAfter - 1];
        final reason =
            'отказ после операции $failAfter: ${faulted.operation.name} '
            '${_writtenTable(faulted)}';
        final stage = switch (failAfter - 1) {
          final index when index < firstWrite =>
            IntentionCreationCommandDiagnosticsStage.validation,
          final index when index <= lastWrite =>
            IntentionCreationCommandDiagnosticsStage.write,
          _ => IntentionCreationCommandDiagnosticsStage.resultRead,
        };
        final injector = _StatementFaultInjector();
        final sportTagId = await replaceWithSeededGraph(injector);
        final command = fullCommand([homeTagId, weekendTagId, sportTagId]);
        final before = await _observeCreationGraph(repository, raw);
        injector.failAfter(failAfter);

        final result = await repository.execute(command);

        expect(result, _failure<IntentionUnexpectedFailure>(), reason: reason);
        expect(
          injector.failedStatement,
          faulted.statements.single,
          reason: reason,
        );
        await expectRolledBack(before, reason: reason);
        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
          _failedCreation(stage, DiagnosticsFailureCode.unexpected),
          reason: reason,
        );

        // Повтор той же команды с тем же идентификатором создаёт весь набор
        // в конце полного порядка на новой ревизии.
        final retried = await repository.execute(command);
        expect(
          retried,
          isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
          reason: reason,
        );
        final confirmed = _readValue(retried);
        expect(
          confirmed.revision.compareTo(before.revision),
          GraphRevisionOrder.newer,
          reason: reason,
        );
        final summary = confirmed.value.catalogMutation.after!.summary;
        expect(summary.id, newId, reason: reason);
        expect(summary.tags.map((tag) => tag.id), [
          homeTagId,
          weekendTagId,
          sportTagId,
        ], reason: reason);
        expect(summary.favoriteMark, FavoriteMark.favorite, reason: reason);
        expect(storedFavoriteMarks(raw), [
          (activeFavoriteId.toCanonicalString(), 2),
          (archivedFavoriteId.toCanonicalString(), 5),
          (newId.toCanonicalString(), 6),
        ], reason: reason);
      }
    });

    test('несогласованный окончательный снимок отклоняется как повреждение '
        'до подтверждения без частичного результата', () async {
      final tamper = _FinalAssignmentsReadTamper();
      final sportTagId = await replaceWithSeededGraph(tamper);
      final before = await _observeCreationGraph(repository, raw);
      tamper.arm();

      final result = await repository.execute(
        fullCommand([homeTagId, weekendTagId, sportTagId]),
      );

      expect(result, _failure<IntentionCorruptionFailure>());
      expect(tamper.tampered, isTrue);
      await expectRolledBack(before);
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.resultRead,
          DiagnosticsFailureCode.corruption,
        ),
      );
    });

    test('отказ инфраструктуры при проверке выбранных тегов сохраняет свою '
        'категорию и не выдаётся за их отсутствие', () async {
      for (final (error, expected, code)
          in <(Object, Matcher, DiagnosticsFailureCode)>[
            (
              SqliteException(
                extendedResultCode: SqlError.SQLITE_BUSY,
                message: 'CANARY-недоступность',
              ),
              isA<IntentionUnavailableFailure>(),
              DiagnosticsFailureCode.unavailable,
            ),
            (
              SqliteException(
                extendedResultCode: SqlError.SQLITE_CORRUPT,
                message: 'CANARY-повреждение',
              ),
              isA<IntentionCorruptionFailure>(),
              DiagnosticsFailureCode.corruption,
            ),
            (
              StateError('CANARY-неизвестный-отказ'),
              isA<IntentionUnexpectedFailure>(),
              DiagnosticsFailureCode.unexpected,
            ),
            (
              SqliteException(
                extendedResultCode: SqlError.SQLITE_READONLY,
                message: 'CANARY-неизвестный-SQLite-отказ',
              ),
              isA<IntentionUnexpectedFailure>(),
              DiagnosticsFailureCode.unexpected,
            ),
          ]) {
        final interceptor = _SelectedTagsReadInterceptor(failure: error);
        final sportTagId = await replaceWithSeededGraph(interceptor);
        final before = await _observeCreationGraph(repository, raw);
        interceptor.arm();

        // Набор содержит и действительно отсутствующий тег: отказ чтения
        // не позволяет судить о наличии и не превращается в его отсутствие.
        final result = await repository.execute(
          fullCommand([homeTagId, missingTagId, sportTagId]),
        );

        expect(
          result,
          isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
              .having(
                (result) => result.failure,
                'причина',
                allOf(
                  expected,
                  isNot(isA<IntentionCreationTagsMissingFailure>()),
                ),
              ),
          reason: '$error',
        );
        expect(interceptor.failedReads, 1, reason: '$error');
        await expectRolledBack(before, reason: '$error');
        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
          _failedCreation(
            IntentionCreationCommandDiagnosticsStage.validation,
            code,
          ),
          reason: '$error',
        );
      }
    });

    test('повреждённые сохранённые данные выбранного тега остаются '
        'повреждением и рядом с отсутствующим тегом', () async {
      final sportTagId = await replaceWithSeededGraph(const _PassiveObserver());
      // Неканоничное название недостижимо через приложение: для его записи
      // отключается проверка схемы и подменяется функция ключа названия.
      raw.execute('PRAGMA ignore_check_constraints = ON');
      raw.createFunction(
        functionName: tagNameKeyFunctionName,
        argumentCount: const AllowedArgumentCount(1),
        deterministic: true,
        directOnly: false,
        function: (_) => 'повреждённый ключ',
      );
      raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
        ' Дом ',
        homeTagId.toCanonicalString(),
      ]);
      raw.execute('PRAGMA ignore_check_constraints = OFF');

      for (final tagIds in [
        [homeTagId],
        [missingTagId, homeTagId, weekendTagId, sportTagId],
      ]) {
        final reason = 'набор из ${tagIds.length}';
        final storedBefore = _storedCreationRows(raw);
        final revisionBefore = _catalogRevision(
          await repository.getCatalogPage(_allIntentionsQuery),
        );

        final result = await repository.execute(fullCommand(tagIds));

        expect(result, _failure<IntentionCorruptionFailure>(), reason: reason);
        expect(_storedCreationRows(raw), storedBefore, reason: reason);
        expect(
          _catalogRevision(await repository.getCatalogPage(_allIntentionsQuery))
              .compareTo(revisionBefore),
          GraphRevisionOrder.same,
          reason: reason,
        );
        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().last,
          _failedCreation(
            IntentionCreationCommandDiagnosticsStage.validation,
            DiagnosticsFailureCode.corruption,
          ),
          reason: reason,
        );
      }
    });

    /// Операции транзакции полного создания с тремя тегами и избранным,
    /// выполненного без отказа на отдельно подготовленном графе.
    Future<List<LocalDatabaseSqlStatement>> probeFullCreation() async {
      final probe = _StatementFaultInjector();
      final sportTagId = await replaceWithSeededGraph(probe);
      probe.observe();
      final probed = await repository.execute(
        fullCommand([homeTagId, weekendTagId, sportTagId]),
      );
      expect(
        probed,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      return probe.stopObserving();
    }

    test('успешное создание даёт одно событие создания на этапе проверки '
        'результата без событий самостоятельных команд', () async {
      for (final (name, build) in <(String, CreateIntention Function(TagId))>[
        (
          'минимальное',
          (_) => const CreateIntention(
            title: 'Минимальное намерение',
            description: null,
          ),
        ),
        (
          'полное',
          (sportTagId) => fullCommand([homeTagId, weekendTagId, sportTagId]),
        ),
      ]) {
        final sportTagId = await replaceWithSeededGraph(
          const _PassiveObserver(),
        );
        final command = build(sportTagId);
        final from = diagnostics.events.length;

        final result = await repository.execute(command);

        expect(
          result,
          isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
          reason: name,
        );
        // Начальные готовность, отметка и назначения не выдаются за
        // самостоятельные команды намерения, избранного или тегов.
        expect(diagnostics.events.skip(from), [
          _succeededCreation(),
        ], reason: name);
      }
    });

    test('отказ текста относится к этапу проверки и категории validation '
        'без обращения к хранилищу', () async {
      final probe = _StatementFaultInjector();
      final sportTagId = await replaceWithSeededGraph(probe);
      final from = diagnostics.events.length;
      probe.observe();

      final result = await repository.execute(
        CreateIntention.withInitialState(
          title: '   ',
          description: 'Описание без названия',
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: [homeTagId, sportTagId],
        ),
      );

      expect(result, _failure<IntentionTextInputValidationFailure>());
      expect(probe.stopObserving(), isEmpty);
      expect(diagnostics.events.skip(from), [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.validation,
          DiagnosticsFailureCode.validation,
        ),
      ]);
    });

    test('отсутствие выбранного тега относится к этапу проверки и категории '
        'validation, а не к сбою записи', () async {
      final sportTagId = await replaceWithSeededGraph(const _PassiveObserver());
      final before = await _observeCreationGraph(repository, raw);
      final from = diagnostics.events.length;

      final result = await repository.execute(
        fullCommand([homeTagId, missingTagId, sportTagId]),
      );

      expect(
        result,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'причина',
              isA<IntentionCreationTagsMissingFailure>().having(
                (failure) => failure.missingTagIds,
                'missingTagIds',
                {missingTagId},
              ),
            ),
      );
      expect(diagnostics.events.skip(from), [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.validation,
          DiagnosticsFailureCode.validation,
        ),
      ]);
      await expectRolledBack(before);
    });

    test('отказ хранилища при записи и при проверке результата относится к '
        'своему этапу с фактической категорией', () async {
      final operations = await probeFullCreation();
      final firstWrite =
          operations.indexWhere(
            (operation) =>
                operation.operation != LocalDatabaseSqlOperation.select,
          ) +
          1;

      for (final (failAfter, stage) in [
        (firstWrite, IntentionCreationCommandDiagnosticsStage.write),
        (
          operations.length,
          IntentionCreationCommandDiagnosticsStage.resultRead,
        ),
      ]) {
        for (final (error, expected, code)
            in <(Object, Matcher, DiagnosticsFailureCode)>[
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_BUSY,
                  message: 'CANARY-недоступность',
                ),
                isA<IntentionUnavailableFailure>(),
                DiagnosticsFailureCode.unavailable,
              ),
              (
                SqliteException(
                  extendedResultCode: SqlError.SQLITE_CORRUPT,
                  message: 'CANARY-повреждение',
                ),
                isA<IntentionCorruptionFailure>(),
                DiagnosticsFailureCode.corruption,
              ),
              (
                StateError('CANARY-неизвестный-отказ'),
                isA<IntentionUnexpectedFailure>(),
                DiagnosticsFailureCode.unexpected,
              ),
            ]) {
          final reason = '${stage.name}: $error';
          final injector = _StatementFaultInjector();
          final sportTagId = await replaceWithSeededGraph(injector);
          final before = await _observeCreationGraph(repository, raw);
          final from = diagnostics.events.length;
          injector.failAfter(failAfter, failure: error);

          final result = await repository.execute(
            fullCommand([homeTagId, weekendTagId, sportTagId]),
          );

          expect(
            result,
            isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
                .having((result) => result.failure, 'причина', expected),
            reason: reason,
          );
          expect(injector.failedStatement, isNotNull, reason: reason);
          expect(diagnostics.events.skip(from), [
            _failedCreation(stage, code),
          ], reason: reason);
          await expectRolledBack(before, reason: reason);
        }
      }
    });

    test('конфликт идентификатора при записи относится к этапу записи и '
        'категории conflict', () async {
      // Генератор выдаёт идентификатор уже сохранённого намерения.
      final sportTagId = await replaceWithSeededGraph(
        const _PassiveObserver(),
        intentionIds: [activeFavoriteId],
      );
      final before = await _observeCreationGraph(repository, raw);
      final from = diagnostics.events.length;

      final result = await repository.execute(
        fullCommand([homeTagId, sportTagId]),
      );

      expect(result, _failure<IntentionConflictFailure>());
      expect(diagnostics.events.skip(from), [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.conflict,
        ),
      ]);
      final after = await _observeCreationGraph(repository, raw);
      expect(after.facts, before.facts);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
    });

    test('длительность охватывает всю операцию до окончательного исхода, '
        'включая проверку результата', () async {
      const delay = Duration(milliseconds: 15);
      for (final failure in <Object?>[
        null,
        SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'CANARY-недоступность',
        ),
      ]) {
        final reason = failure == null ? 'успех' : 'отказ';
        final observer = _ResultReadDelay(delay, failure: failure);
        final sportTagId = await replaceWithSeededGraph(observer);
        final from = diagnostics.events.length;
        observer.arm();

        await repository.execute(
          fullCommand([homeTagId, weekendTagId, sportTagId]),
        );

        expect(observer.delayedReads, greaterThan(0), reason: reason);
        final events = diagnostics.events.skip(from).toList();
        expect(events, [
          if (failure == null)
            _succeededCreation()
          else
            _failedCreation(
              IntentionCreationCommandDiagnosticsStage.resultRead,
              DiagnosticsFailureCode.unavailable,
            ),
        ], reason: reason);
        final duration = switch (events.single.status) {
          DiagnosticsSucceeded(:final duration) => duration,
          DiagnosticsFailed(:final duration) => duration,
          DiagnosticsStarted() => throw TestFailure(
            'Нет окончательного исхода.',
          ),
        };
        expect(
          duration,
          greaterThanOrEqualTo(delay * observer.delayedReads),
          reason: reason,
        );
      }
    });

    test('сериализованные события создания не раскрывают текст, '
        'идентификаторы и названия тегов, состав избранного, SQL и путь '
        'базы', () async {
      const titleCanary = 'CANARY-название-намерения';
      const descriptionCanary = 'CANARY-описание-намерения';
      const pathCanary = '/CANARY/databases/doable.sqlite';
      const sqlCanary = 'INSERT INTO intentions /* CANARY-SQL */';
      final messages = <String>[];
      final operations = await probeFullCreation();
      final firstWrite =
          operations.indexWhere(
            (operation) =>
                operation.operation != LocalDatabaseSqlOperation.select,
          ) +
          1;
      final injector = _StatementFaultInjector();
      final sportTagId = await replaceWithSeededGraph(
        injector,
        diagnosticsSink: DeveloperDiagnosticsSink(messages.add),
        intentionIds: [newId, newId, newId],
      );
      CreateIntention command(Iterable<TagId> tagIds) =>
          CreateIntention.withInitialState(
            title: titleCanary,
            description: descriptionCanary,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
            tagIds: tagIds,
          );
      SqliteException privateFailure(int code) => SqliteException(
        extendedResultCode: code,
        message: 'CANARY-отказ $pathCanary',
        explanation: 'CANARY-пояснение $titleCanary',
        causingStatement: sqlCanary,
        parametersToStatement: [titleCanary, descriptionCanary],
      );
      final selectedTags = [homeTagId, weekendTagId, sportTagId];
      messages.clear();

      await repository.execute(
        CreateIntention.withInitialState(
          title: '',
          description: descriptionCanary,
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: selectedTags,
        ),
      );
      await repository.execute(command([...selectedTags, missingTagId]));
      injector.failAfter(
        firstWrite,
        failure: privateFailure(SqlError.SQLITE_BUSY),
      );
      await repository.execute(command(selectedTags));
      injector.failAfter(
        operations.length,
        failure: privateFailure(SqlError.SQLITE_CORRUPT),
      );
      await repository.execute(command(selectedTags));
      final created = await repository.execute(command(selectedTags));

      expect(
        created,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      expect(storedFavoriteMarks(raw).last, (newId.toCanonicalString(), 6));
      expect(
        [
          for (final message in messages)
            jsonDecode(message) as Map<String, Object?>,
        ],
        [
          for (final (stage, outcome, failureCode) in [
            ('validation', 'failed', 'validation'),
            ('validation', 'failed', 'validation'),
            ('write', 'failed', 'unavailable'),
            ('resultRead', 'failed', 'corruption'),
            ('resultRead', 'succeeded', null),
          ])
            {
              'operation': 'intentionCommand',
              'stage': stage,
              'outcome': outcome,
              'durationMicros': isA<int>(),
              'failureCode': ?failureCode,
              'commandType': 'create',
            },
        ],
      );
      final written = messages.join('\n');
      for (final secret in [
        'CANARY',
        titleCanary,
        descriptionCanary,
        pathCanary,
        'doable.sqlite',
        newId.toCanonicalString(),
        activeFavoriteId.toCanonicalString(),
        archivedFavoriteId.toCanonicalString(),
        for (final tagId in [...selectedTags, missingTagId])
          tagId.toCanonicalString(),
        'Дом',
        'Выходные',
        'Спорт',
        'favorite_intentions',
        'tag_assignments',
        'position',
        'INSERT',
        'SELECT',
        'Exception',
      ]) {
        expect(written, isNot(contains(secret)), reason: secret);
      }
    });

    test('отказ получателя диагностики не меняет результат, число записей и '
        'ревизию полного создания', () async {
      final failing = _ThrowingDiagnosticsSink();
      final probe = _StatementFaultInjector();
      final sportTagId = await replaceWithSeededGraph(
        probe,
        diagnosticsSink: failing,
      );
      final before = await _observeCreationGraph(repository, raw);
      failing.attemptedEvents.clear();
      probe.observe();

      final result = await repository.execute(
        fullCommand([homeTagId, weekendTagId, sportTagId]),
      );
      final operations = probe.stopObserving();
      final attempted = List.of(failing.attemptedEvents);

      final confirmed = _readValue(result);
      final created = confirmed.value.catalogMutation;
      expect(created, isA<IntentionCatalogCreated>());
      expect(created.after!.summary.id, newId);
      expect(created.after!.summary.readiness, IntentionReadiness.ready);
      expect(created.after!.summary.favoriteMark, FavoriteMark.favorite);
      expect(created.after!.summary.tags.map((tag) => tag.id), [
        homeTagId,
        weekendTagId,
        sportTagId,
      ]);
      expect(
        [
          for (final operation in operations)
            if (operation.operation != LocalDatabaseSqlOperation.select)
              (operation.operation, _writtenTable(operation)),
        ],
        [
          (LocalDatabaseSqlOperation.insert, 'intentions'),
          for (var index = 0; index < 3; index++)
            (LocalDatabaseSqlOperation.insert, 'tag_assignments'),
          (LocalDatabaseSqlOperation.insert, 'favorite_intentions'),
        ],
      );
      expect(attempted, [_succeededCreation()]);
      final after = await _observeCreationGraph(repository, raw);
      expect(
        confirmed.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        after.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
      expect(storedFavoriteMarks(raw), [
        (activeFavoriteId.toCanonicalString(), 2),
        (archivedFavoriteId.toCanonicalString(), 5),
        (newId.toCanonicalString(), 6),
      ]);
    });

    test('отказ получателя диагностики не меняет отказ, категорию и откат '
        'полного создания', () async {
      final operations = await probeFullCreation();
      final firstWrite =
          operations.indexWhere(
            (operation) =>
                operation.operation != LocalDatabaseSqlOperation.select,
          ) +
          1;
      final failing = _ThrowingDiagnosticsSink();
      final injector = _StatementFaultInjector();
      final sportTagId = await replaceWithSeededGraph(
        injector,
        diagnosticsSink: failing,
      );

      final missingBefore = await _observeCreationGraph(repository, raw);
      failing.attemptedEvents.clear();
      final missing = await repository.execute(
        fullCommand([homeTagId, missingTagId, sportTagId]),
      );
      expect(
        missing,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'причина',
              isA<IntentionCreationTagsMissingFailure>().having(
                (failure) => failure.missingTagIds,
                'missingTagIds',
                {missingTagId},
              ),
            ),
      );
      expect(failing.attemptedEvents, [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.validation,
          DiagnosticsFailureCode.validation,
        ),
      ]);
      await expectRolledBack(missingBefore);

      final writeBefore = await _observeCreationGraph(repository, raw);
      failing.attemptedEvents.clear();
      injector.failAfter(
        firstWrite,
        failure: SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'CANARY-недоступность',
        ),
      );
      final unavailable = await repository.execute(
        fullCommand([homeTagId, weekendTagId, sportTagId]),
      );
      expect(unavailable, _failure<IntentionUnavailableFailure>());
      expect(failing.attemptedEvents, [
        _failedCreation(
          IntentionCreationCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.unavailable,
        ),
      ]);
      await expectRolledBack(writeBefore);
    });
  });

  group(
    'DriftPersonalGraphRepository.execute — безопасные неизвестные отказы',
    () {
      test(
        'не считает constraint вне утверждённых контекстов conflict',
        () async {
          for (final extendedCode in [
            SqlError.SQLITE_CONSTRAINT,
            SqlExtendedError.SQLITE_CONSTRAINT_CHECK,
            SqlExtendedError.SQLITE_CONSTRAINT_NOTNULL,
            SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
            SqlExtendedError.SQLITE_CONSTRAINT_ROWID,
            SqlExtendedError.SQLITE_CONSTRAINT_TRIGGER,
            SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
            SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
            SqlError.SQLITE_CONSTRAINT | (99 << 8),
          ]) {
            final interceptor = _FailBeforeDmlInterceptor(
              _DmlOperation.update,
              SqliteException(
                extendedResultCode: extendedCode,
                message: 'CANARY-constraint',
              ),
            );
            final replacement = await _replaceDatabase(
              interceptor,
              database,
              diagnostics,
            );
            database = replacement.database;
            repository = replacement.repository;
            final id = _id(_firstUuid);
            await _insertIntention(
              database,
              id: id,
              title: 'Стабильное намерение',
              createdAt: DateTime.utc(2026, 9, 2, 10),
            );
            interceptor.arm();

            final result = await repository.execute(
              UpdateIntention(
                id: id,
                title: 'Изменённое намерение',
                description: null,
              ),
            );

            expect(
              result,
              _failure<IntentionUnexpectedFailure>(),
              reason: '$extendedCode',
            );
            expect(
              diagnostics.events.last,
              _failedCommand(
                IntentionCommandDiagnosticsType.update,
                DiagnosticsFailureCode.unexpected,
              ),
            );
          }
        },
      );

      test(
        'преобразует неизвестные SQLite и Dart ошибки command в unexpected',
        () async {
          for (final failure in <Object>[
            SqliteException(
              extendedResultCode: SqlError.SQLITE_READONLY,
              message: 'CANARY-readonly',
            ),
            StateError('CANARY-dart-error'),
          ]) {
            final interceptor = _FailBeforeDmlInterceptor(
              _DmlOperation.delete,
              failure,
            );
            final replacement = await _replaceDatabase(
              interceptor,
              database,
              diagnostics,
            );
            database = replacement.database;
            repository = replacement.repository;
            final id = _id(_firstUuid);
            await _insertIntention(
              database,
              id: id,
              title: 'Стабильное намерение',
              createdAt: DateTime.utc(2026, 9, 2, 10),
            );
            interceptor.arm();

            final result = await repository.execute(DeleteIntention(id));

            expect(result, _failure<IntentionUnexpectedFailure>());
            await _expectStoredIntention(
              database,
              id: id,
              title: 'Стабильное намерение',
              description: null,
              isActionReady: false,
              isArchived: false,
              createdAt: DateTime.utc(2026, 9, 2, 10),
            );
            expect(
              diagnostics.events.last,
              _failedCommand(
                IntentionCommandDiagnosticsType.delete,
                DiagnosticsFailureCode.unexpected,
              ),
            );
          }
        },
      );
    },
  );

  group('DriftPersonalGraphRepository — независимость от диагностики', () {
    test('завершает чтения при ошибке диагностического получателя', () async {
      final id = _id(_firstUuid);
      await _insertIntention(
        database,
        id: id,
        title: 'Подтверждённое намерение',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      final failingDiagnostics = _ThrowingDiagnosticsSink();
      repository = _repository(database, failingDiagnostics);

      final catalogResult = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        ),
      );
      final detailResult = await repository.watchIntention(id).first;

      expect(catalogResult, isA<ResultSuccess<IntentionCatalogPage>>());
      expect(
        detailResult,
        isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>(),
      );
      expect(
        failingDiagnostics.attemptedEvents.map((event) => event.runtimeType),
        [
          CatalogPageReadDiagnosticsEvent,
          CatalogPageReadDiagnosticsEvent,
          IntentionDetailReadDiagnosticsEvent,
          IntentionDetailReadDiagnosticsEvent,
        ],
      );
    });

    test(
      'сохраняет подтверждённую команду один раз при ошибке диагностики',
      () async {
        final failingDiagnostics = _ThrowingDiagnosticsSink();
        repository = _repository(database, failingDiagnostics);

        final result = await repository.execute(
          const CreateIntention(
            title: 'Сохранённое намерение',
            description: null,
          ),
        );

        expect(
          result,
          isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
        );
        final rows = await database.select(database.intentions).get();
        expect(rows, hasLength(1));
        expect(rows.single.title, 'Сохранённое намерение');
        expect(failingDiagnostics.attemptedEvents, [_succeededCreation()]);
      },
    );

    test('сохраняет весь каскад при ошибке диагностики после commit', () async {
      final owner = _id(_firstUuid);
      final neighbor = _id(_secondUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: owner,
        title: 'Архивируемое намерение',
        createdAt: createdAt,
      );
      await _insertIntention(
        database,
        id: neighbor,
        title: 'Соседнее намерение',
        createdAt: createdAt,
      );
      await _insertRelation(
        database,
        id: _relationUuid,
        sourceId: owner,
        relatedId: neighbor,
      );
      final failingDiagnostics = _ThrowingDiagnosticsSink();
      repository = _repository(database, failingDiagnostics);

      final result = await repository.execute(ArchiveIntention(owner));

      expect(
        result,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      await _expectStoredIntention(
        database,
        id: owner,
        title: 'Архивируемое намерение',
        description: null,
        isActionReady: false,
        isArchived: true,
        createdAt: createdAt,
        updatedAt: DateTime.utc(2026, 9, 3, 12),
      );
      expect(await _relationIsArchived(database, _relationUuid), isTrue);
      expect(failingDiagnostics.attemptedEvents, [
        isA<IntentionCommandDiagnosticsEvent>(),
      ]);
    });
  });
}

Future<({AppDatabase database, DriftPersonalGraphRepository repository})>
_replaceDatabase(
  LocalDatabaseConnectionObserver observer,
  AppDatabase previousDatabase,
  DiagnosticsSink diagnostics, {
  void Function(Database)? setup,
  List<IntentionId>? intentionIds,
}) async {
  await previousDatabase.close();
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(setup: setup),
      observer,
    ),
  );
  await database.open();
  return (
    database: database,
    repository: _repository(database, diagnostics, intentionIds: intentionIds),
  );
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics, {
  List<IntentionId>? intentionIds,
}) => DriftPersonalGraphRepository(
  database,
  _DeterministicIntentionIdGenerator(intentionIds ?? [_id(_secondUuid)]),
  () => DateTime.utc(2026, 9, 3, 12),
  diagnostics,
);

Future<void> _insertIntention(
  AppDatabase database, {
  required IntentionId id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required DateTime createdAt,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id.toCanonicalString(),
        title: title,
        description: Value(description),
        isActionReady: Value(isActionReady),
        isArchived: Value(isArchived),
        createdAt: createdAt.microsecondsSinceEpoch,
        updatedAt: createdAt.microsecondsSinceEpoch,
      ),
    );

Future<void> _expectStoredIntention(
  AppDatabase database, {
  required IntentionId id,
  required String title,
  required String? description,
  required bool isActionReady,
  required bool isArchived,
  required DateTime createdAt,
  DateTime? updatedAt,
}) async {
  final row = await (database.select(
    database.intentions,
  )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
  expect(row.title, title);
  expect(row.titleSearchKey, titleSearchKey(title));
  expect(row.description, description);
  expect(row.isActionReady, isActionReady);
  expect(row.isArchived, isArchived);
  expect(row.createdAt, createdAt.microsecondsSinceEpoch);
  expect(row.updatedAt, (updatedAt ?? createdAt).microsecondsSinceEpoch);
}

Future<void> _insertRelation(
  AppDatabase database, {
  required String id,
  required IntentionId sourceId,
  required IntentionId relatedId,
}) => database.customStatement(
  '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      is_archived
    ) VALUES (?, ?, ?, 'need', 1, 0)
  ''',
  [id, sourceId.toCanonicalString(), relatedId.toCanonicalString()],
);

Future<bool> _relationIsArchived(AppDatabase database, String id) async {
  final row = await database
      .customSelect(
        'SELECT is_archived FROM long_term_relations WHERE id = ?',
        variables: [Variable<String>(id)],
      )
      .getSingle();
  return row.read<int>('is_archived') == 1;
}

GraphRevision _countsRevision(Result<GraphSnapshot<RelationCounts>> result) {
  expect(result, isA<ResultSuccess<GraphSnapshot<RelationCounts>>>());
  return (result as ResultSuccess<GraphSnapshot<RelationCounts>>)
      .value
      .revision;
}

Future<List<IntentionId>> _matchingIds(
  PersonalGraphRepository repository,
  String titleFilter,
) async {
  final result = await repository.getCatalogPage(
    IntentionCatalogQuery(
      scope: IntentionScope.all,
      titleFilter: titleFilter,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: 100,
    ),
  );
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value.items
      .map((item) => item.id)
      .toList();
}

Matcher _failure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

Matcher _failedCommand(
  IntentionCommandDiagnosticsType commandType,
  DiagnosticsFailureCode failureCode,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'commandType', commandType)
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'code',
        failureCode,
      ),
    );

/// Окончательный отказ создания намерения на этапе [stage] с категорией
/// [failureCode].
Matcher _failedCreation(
  IntentionCreationCommandDiagnosticsStage stage,
  DiagnosticsFailureCode failureCode,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'commandType',
      IntentionCommandDiagnosticsType.create,
    )
    .having((event) => event.stage, 'stage', stage)
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsFailed>()
          .having((status) => status.code, 'code', failureCode)
          .having(
            (status) => status.duration,
            'duration',
            greaterThanOrEqualTo(Duration.zero),
          ),
    );

/// Успешное создание намерения: оно завершается проверкой результата.
Matcher _succeededCreation() => isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'commandType',
      IntentionCommandDiagnosticsType.create,
    )
    .having(
      (event) => event.stage,
      'stage',
      IntentionCreationCommandDiagnosticsStage.resultRead,
    )
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsSucceeded>().having(
        (status) => status.duration,
        'duration',
        greaterThanOrEqualTo(Duration.zero),
      ),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

final class _DeterministicIntentionIdGenerator implements IntentionIdGenerator {
  _DeterministicIntentionIdGenerator(this._ids);

  final List<IntentionId> _ids;
  var _next = 0;

  @override
  IntentionId generate() => _ids[_next++];
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-diagnostics-sink-failure');
  }
}

final class _TagAssignmentReadInterceptor
    extends LocalDatabaseConnectionObserver {
  _TagAssignmentReadInterceptor({required this.failure});

  final Object failure;

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (statement.statements.single.contains('FROM tag_assignments')) {
      throw failure;
    }
    return rows;
  }
}

/// Наблюдатель без вмешательства: даёт доступ к соединению хранилища.
final class _PassiveObserver extends LocalDatabaseConnectionObserver {
  const _PassiveObserver();
}

final class _FavoriteMarkReadInterceptor
    extends LocalDatabaseConnectionObserver {
  _FavoriteMarkReadInterceptor({required this.failure});

  final Object failure;
  var failedReads = 0;

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (statement.statements.single.contains('FROM favorite_intentions')) {
      failedReads++;
      throw failure;
    }
    return rows;
  }
}

enum _DmlOperation { insert, update, delete }

final class _FailAfterDmlInterceptor extends LocalDatabaseConnectionObserver {
  _FailAfterDmlInterceptor(this._operation);

  final _DmlOperation _operation;
  var _armed = false;
  var _hasFailed = false;
  String? failedStatement;
  final List<String> detailReadStatements = [];

  void arm() => _armed = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final sql = statement.statements.single;
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        sql.contains('FROM intentions') &&
        sql.contains('description') &&
        !sql.contains('title_search_key')) {
      detailReadStatements.add(sql);
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_matches(statement.operation)) return;
    if (_armed && !_hasFailed) {
      _hasFailed = true;
      failedStatement = statement.statements.single;
      throw StateError('CANARY-after-dml-failure');
    }
  }

  bool _matches(LocalDatabaseSqlOperation operation) => switch (_operation) {
    _DmlOperation.insert => operation == LocalDatabaseSqlOperation.insert,
    _DmlOperation.update => operation == LocalDatabaseSqlOperation.update,
    _DmlOperation.delete => operation == LocalDatabaseSqlOperation.delete,
  };
}

final class _FailBeforeDmlInterceptor extends LocalDatabaseConnectionObserver {
  _FailBeforeDmlInterceptor(this._operation, this._failure);

  final _DmlOperation _operation;
  final Object _failure;
  var _armed = false;

  void arm() => _armed = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_armed && _matches(statement.operation)) throw _failure;
  }

  bool _matches(LocalDatabaseSqlOperation operation) => switch (_operation) {
    _DmlOperation.insert => operation == LocalDatabaseSqlOperation.insert,
    _DmlOperation.update => operation == LocalDatabaseSqlOperation.update,
    _DmlOperation.delete => operation == LocalDatabaseSqlOperation.delete,
  };
}

/// Наблюдает операции хранилища и по запросу прерывает транзакцию сразу
/// после выполнения операции с заданным номером: её действие уже внесено в
/// транзакцию, а результат не доходит до репозитория.
final class _StatementFaultInjector extends LocalDatabaseConnectionObserver {
  final List<LocalDatabaseSqlStatement> _observed = [];
  var _observing = false;
  int? _failAfter;
  Object _failure = StateError('CANARY-statement-fault');
  String? failedStatement;

  void observe() {
    _observed.clear();
    _observing = true;
    _failAfter = null;
  }

  /// Прерывает транзакцию после операции [number] отказом [failure], по
  /// умолчанию — неизвестной ошибкой.
  void failAfter(int number, {Object? failure}) {
    observe();
    _failAfter = number;
    _failure = failure ?? StateError('CANARY-statement-fault');
  }

  List<LocalDatabaseSqlStatement> stopObserving() {
    _observing = false;
    return List.unmodifiable(_observed);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_observing) return;
    _observed.add(statement);
    if (_observed.length == _failAfter) {
      _observing = false;
      failedStatement = statement.statements.single;
      throw _failure;
    }
  }
}

/// После [arm] задерживает на [delay] каждое чтение, выполненное после первой
/// записи, то есть чтения окончательного результата создания. При заданном
/// [failure] первое такое чтение после задержки завершается этим отказом.
final class _ResultReadDelay extends LocalDatabaseConnectionObserver {
  _ResultReadDelay(this.delay, {this.failure});

  final Duration delay;
  final Object? failure;
  var _armed = false;
  var _wrote = false;
  var delayedReads = 0;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (_armed && statement.operation != LocalDatabaseSqlOperation.select) {
      _wrote = true;
    }
  }

  @override
  Future<List<Map<String, Object?>>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) async {
    if (!_armed || !_wrote) return rows;
    delayedReads++;
    await Future<void>.delayed(delay);
    if (failure case final failure?) {
      _armed = false;
      throw failure;
    }
    return rows;
  }
}

/// После записей команды убирает последнюю строку первого чтения назначений:
/// окончательный снимок расходится с записанным набором тегов.
final class _FinalAssignmentsReadTamper
    extends LocalDatabaseConnectionObserver {
  var _armed = false;
  var _wrote = false;
  var tampered = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (_armed && statement.operation == LocalDatabaseSqlOperation.insert) {
      _wrote = true;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (!_wrote ||
        tampered ||
        rows.isEmpty ||
        !statement.statements.single.contains('tag_assignments')) {
      return rows;
    }
    tampered = true;
    return rows.sublist(0, rows.length - 1);
  }
}

/// Отклоняет первое после [arm] чтение сохранённых тегов, с которого
/// начинается проверка выбранных тегов создания.
final class _SelectedTagsReadInterceptor
    extends LocalDatabaseConnectionObserver {
  _SelectedTagsReadInterceptor({required this.failure});

  final Object failure;
  var _armed = false;
  var failedReads = 0;

  void arm() => _armed = true;

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (_armed && statement.statements.single.contains('FROM tags')) {
      _armed = false;
      failedReads++;
      throw failure;
    }
    return rows;
  }
}

/// Таблица, в которую пишет операция, либо название операции чтения.
String _writtenTable(LocalDatabaseSqlStatement statement) {
  final match = RegExp(
    r'^\s*(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+"?(\w+)"?',
    caseSensitive: false,
  ).firstMatch(statement.statements.single);
  return match?.group(1) ?? statement.operation.name;
}

/// Состояние графа через публичные чтения и строки хранилища, которые
/// затрагивает создание намерения.
typedef _ObservedCreationGraph = ({
  List<Object?> facts,
  GraphRevision revision,
  List<String> tagNames,
});

final _allIntentionsQuery = IntentionCatalogQuery(
  scope: IntentionScope.all,
  titleFilter: null,
  order: IntentionCatalogOrder.createdAtAscending,
  pageSize: 100,
);

Future<_ObservedCreationGraph> _observeCreationGraph(
  DriftPersonalGraphRepository repository,
  Database raw,
) async {
  final page = _readValue(await repository.getCatalogPage(_allIntentionsQuery));
  final favorites = _readValue(await repository.getFavoriteIntentions());
  final tags = _readValue(
    await repository.getTagCatalog(const TagCatalogBrowseMode()),
  );
  return (
    facts: <Object?>[
      [
        for (final item in page.items)
          [
            item.id,
            item.title,
            item.readiness,
            item.archiveState,
            item.favoriteMark,
            [for (final tag in item.tags) tag.id],
          ],
      ],
      await _matchingIds(repository, 'полное'),
      [for (final row in favorites.items) row.id],
      favorites.archivedCount,
      [
        for (final tag in tags.items) [tag.id, tag.name.value],
      ],
      for (final tag in tags.items)
        for (final scope in TaggedIntentionsScope.values)
          [
            for (final item in _readValue(
              await repository.getTaggedIntentionsPage(
                TaggedIntentionsQuery(tagId: tag.id, scope: scope),
              ),
            ).items)
              item.id,
          ],
      _storedCreationRows(raw),
    ],
    revision: page.revision,
    tagNames: [for (final tag in tags.items) tag.name.value],
  );
}

/// Строки всех таблиц, которые затрагивает создание намерения.
List<Object?> _storedCreationRows(Database raw) => [
  for (final table in [
    'intentions',
    'tag_assignments',
    'favorite_intentions',
    'tags',
  ])
    [
      for (final row in raw.select('SELECT * FROM $table ORDER BY 1')) {...row},
    ],
];

T _readValue<T, F extends GraphCommandFailure>(GraphResult<T, F> result) =>
    switch (result) {
      GraphResultSuccess(:final value) => value,
      GraphResultFailure(:final failure) => throw TestFailure(
        'Ожидался успех чтения, получен отказ $failure.',
      ),
    };

GraphRevision _catalogRevision(Result<IntentionCatalogPage> result) =>
    _readValue(result).revision;

IntentionDetails? _watched(Result<GraphSnapshot<IntentionDetails?>> result) =>
    _readValue(result).value;

TagId _tagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw ArgumentError.value(value, 'value'),
};

const _firstUuid = '018f0b5d-6b2e-7c80-8000-000000000401';
const _secondUuid = '018f0b5d-6b2e-7c80-8000-000000000402';
const _relationUuid = '018f0b5d-6b2e-7c80-8000-000000000403';
const _archivedUuid = '018f0b5d-6b2e-7c80-8000-000000000404';
