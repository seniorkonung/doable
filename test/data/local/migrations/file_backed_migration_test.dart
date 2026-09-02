import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/local_database_harness.dart';

void main() {
  test('прерванное первичное создание не оставляет schema objects и допускает повтор', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final failureInterceptor = _InitialSchemaCreationFailureInterceptor();

    final failedResult = await harness.open(
      queryInterceptor: failureInterceptor,
    );

    expect(failedResult, isA<LocalDataUnexpectedFailure>());
    expect(failureInterceptor.didInjectFailure, isTrue);
    expect(failureInterceptor.didCloseExecutor, isTrue);

    await harness.closePersistenceObjectGraph();
    await _expectStorageWithoutUserSchema(harness.databaseFile);

    final reopenedDatabase = await harness.openReadyDatabase();
    final version = await reopenedDatabase
        .customSelect('PRAGMA user_version')
        .getSingle();
    final foreignKeys = await reopenedDatabase
        .customSelect('PRAGMA foreign_keys')
        .getSingle();

    expect(version.read<int>('user_version'), 1);
    expect(foreignKeys.read<int>('foreign_keys'), 1);
    await expectLater(
      verifyIntentionTitlesFtsIntegrity(reopenedDatabase),
      completes,
    );
  });

  test('file-backed fault-injected migration оставляет целостную схему после повторного открытия', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final firstDatabase = await harness.openReadyDatabase();
    await _insertIntention(firstDatabase);
    await firstDatabase.customStatement('PRAGMA user_version = 1');

    await expectLater(
      runAtomicMigration(
        firstDatabase,
        targetSchemaVersion: 2,
        migrate: () async {
          await firstDatabase.customStatement(
            'ALTER TABLE intentions ADD COLUMN migration_probe TEXT',
          );
          await firstDatabase.customStatement(
            'UPDATE intentions SET migration_probe = ?',
            ['частично изменённые данные'],
          );
          throw const _InjectedMigrationFailure();
        },
      ),
      throwsA(isA<_InjectedMigrationFailure>()),
    );

    await harness.closePersistenceObjectGraph();

    final reopenedDatabase = await harness.openReadyDatabase();
    final columns = await reopenedDatabase
        .customSelect('PRAGMA table_info(intentions)')
        .get();
    final intention = await reopenedDatabase
        .customSelect('SELECT title FROM intentions')
        .getSingle();
    final version = await reopenedDatabase
        .customSelect('PRAGMA user_version')
        .getSingle();
    final foreignKeys = await reopenedDatabase
        .customSelect('PRAGMA foreign_keys')
        .getSingle();

    expect(
      columns.map((column) => column.read<String>('name')),
      isNot(contains('migration_probe')),
    );
    expect(intention.read<String>('title'), 'Сохранённое намерение');
    expect(version.read<int>('user_version'), 1);
    expect(foreignKeys.read<int>('foreign_keys'), 1);
    await expectLater(
      verifyIntentionTitlesFtsIntegrity(reopenedDatabase),
      completes,
    );

    await runAtomicMigration(
      reopenedDatabase,
      targetSchemaVersion: 2,
      migrate: () async {},
    );
    final retriedVersion = await reopenedDatabase
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(retriedVersion.read<int>('user_version'), 2);
  });
}

Future<void> _expectStorageWithoutUserSchema(File databaseFile) async {
  final executor = NativeDatabase(databaseFile);
  addTearDown(executor.close);
  await executor.ensureOpen(const _SchemaInspectionExecutorUser());

  final schemaObjects = await executor.runSelect('''
      SELECT name FROM sqlite_schema
      WHERE type IN ('table', 'index', 'trigger', 'view')
        AND name NOT LIKE 'sqlite_%'
    ''', const []);
  final version = await executor.runSelect('PRAGMA user_version', const []);

  expect(schemaObjects, isEmpty);
  expect(version.single['user_version'], 0);
}

Future<void> _insertIntention(GeneratedDatabase database) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, title_search_key, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
    ''',
    [
      '018f0b5d-6b2e-7c80-8000-000000000303',
      'Сохранённое намерение',
      'сохранённое намерение',
      1704067200000000,
      1704067200000000,
    ],
  );
}

final class _InjectedMigrationFailure implements Exception {
  const _InjectedMigrationFailure();
}

final class _InjectedInitialCreationFailure implements Exception {
  const _InjectedInitialCreationFailure();
}

final class _InitialSchemaCreationFailureInterceptor extends QueryInterceptor {
  var didInjectFailure = false;
  var didCloseExecutor = false;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    return executor.ensureOpen(_InterceptedQueryExecutorUser(user, this));
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (!didInjectFailure && _isSchemaCreate(statement)) {
      didInjectFailure = true;
      throw const _InjectedInitialCreationFailure();
    }
  }

  @override
  Future<void> close(QueryExecutor inner) async {
    didCloseExecutor = true;
    await inner.close();
  }

  bool _isSchemaCreate(String statement) {
    return RegExp(
      r'^CREATE (?:TABLE|VIRTUAL TABLE|INDEX|TRIGGER|VIEW)\b',
      caseSensitive: false,
    ).hasMatch(statement.trimLeft());
  }
}

final class _InterceptedQueryExecutorUser implements QueryExecutorUser {
  const _InterceptedQueryExecutorUser(this._delegate, this._interceptor);

  final QueryExecutorUser _delegate;
  final QueryInterceptor _interceptor;

  @override
  int get schemaVersion => _delegate.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) {
    return _delegate.beforeOpen(executor.interceptWith(_interceptor), details);
  }
}

final class _SchemaInspectionExecutorUser implements QueryExecutorUser {
  const _SchemaInspectionExecutorUser();

  @override
  int get schemaVersion => 0;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
