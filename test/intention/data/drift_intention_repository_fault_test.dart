import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftIntentionRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  group('DriftIntentionRepository.execute — физическое удаление', () {
    test('преобразует blocking foreign key удаления в conflict и сохраняет строку с FTS', () async {
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

      expect(result, _failure<IntentionConflictFailure>());
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
      await expectLater(verifyIntentionTitlesFtsIntegrity(database), completes);
      expect(diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(), [
        _failedCommand(
          IntentionCommandDiagnosticsType.delete,
          DiagnosticsFailureCode.conflict,
        ),
      ]);
    });
  });

  group('DriftIntentionRepository.execute — откат после DML', () {
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
    'DriftIntentionRepository.execute — безопасные unexpected failures',
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
}

Future<({AppDatabase database, DriftIntentionRepository repository})>
_replaceDatabase(
  LocalDatabaseConnectionObserver observer,
  AppDatabase previousDatabase,
  InMemoryDiagnosticsSink diagnostics,
) async {
  await previousDatabase.close();
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(),
      observer,
    ),
  );
  await database.open();
  return (database: database, repository: _repository(database, diagnostics));
}

DriftIntentionRepository _repository(
  AppDatabase database,
  InMemoryDiagnosticsSink diagnostics,
) => DriftIntentionRepository(
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
        titleSearchKey: titleSearchKey(title),
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
  expect(row.updatedAt, createdAt.microsecondsSinceEpoch);
}

Future<List<IntentionId>> _matchingIds(
  IntentionRepository repository,
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
    isA<ResultFailure<IntentionCommandSuccess>>().having(
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

enum _DmlOperation { insert, update, delete }

final class _FailAfterDmlInterceptor extends LocalDatabaseConnectionObserver {
  _FailAfterDmlInterceptor(this._operation);

  final _DmlOperation _operation;
  var _armed = false;
  var _hasFailed = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_matches(statement.operation)) return;
    if (_armed && !_hasFailed) {
      _hasFailed = true;
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
