import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/fts_integrity.dart';
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
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
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
        _failedCommand(
          IntentionCommandDiagnosticsType.create,
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
        expect(failingDiagnostics.attemptedEvents, [
          isA<IntentionCommandDiagnosticsEvent>(),
        ]);
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
  InMemoryDiagnosticsSink diagnostics, {
  void Function(Database)? setup,
}) async {
  await previousDatabase.close();
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(setup: setup),
      observer,
    ),
  );
  await database.open();
  return (database: database, repository: _repository(database, diagnostics));
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftPersonalGraphRepository(
  database,
  _DeterministicIntentionIdGenerator([_id(_secondUuid)]),
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

const _firstUuid = '018f0b5d-6b2e-7c80-8000-000000000401';
const _secondUuid = '018f0b5d-6b2e-7c80-8000-000000000402';
const _relationUuid = '018f0b5d-6b2e-7c80-8000-000000000403';
