import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  group('lifecycle постоянного локального хранилища', () {
    test('in-memory bootstrap включает внешние ключи и проверяет согласованность FTS', () async {
      final harness = LocalDatabaseHarness.inMemory();
      addTearDown(harness.dispose);

      final database = await harness.openReadyDatabase();
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000301',
        title: 'Проверить память',
        titleSearchKey: 'проверить память',
        createdAt: 1704067200000000,
        updatedAt: 1704067200000000,
      );

      await _expectStorageIsReady(database);
    });

    test('file-backed graph сохраняет UUID v4 и v7, текст, состояния и UTC-времена после полного закрытия', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);

      final firstDatabase = await harness.openReadyDatabase();
      await _insertIntention(
        firstDatabase,
        id: 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        title: 'Сохранить текст',
        titleSearchKey: 'сохранить текст',
        description: '  Точный текст\nбез нормализации  ',
        isActionReady: true,
        createdAt: 1704067200000000,
        updatedAt: 1704153600000000,
      );
      await _insertIntention(
        firstDatabase,
        id: '018f0b5d-6b2e-7c80-8000-000000000302',
        title: 'Архивное намерение',
        titleSearchKey: 'архивное намерение',
        isArchived: true,
        createdAt: 1704240000000000,
        updatedAt: 1704326400000000,
      );

      await harness.closePersistenceObjectGraph();

      final reopenedDatabase = await harness.openReadyDatabase();
      final rows = await reopenedDatabase.customSelect('''
              SELECT
                id,
                title,
                description,
                is_action_ready,
                is_archived,
                created_at,
                updated_at
              FROM intentions
              ORDER BY id ASC
            ''').get();

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.read<String>('id')), [
        '018f0b5d-6b2e-7c80-8000-000000000302',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
      ]);
      expect(rows[0].read<String>('title'), 'Архивное намерение');
      expect(rows[0].read<String?>('description'), isNull);
      expect(rows[0].read<int>('is_action_ready'), 0);
      expect(rows[0].read<int>('is_archived'), 1);
      expect(rows[0].read<int>('created_at'), 1704240000000000);
      expect(rows[0].read<int>('updated_at'), 1704326400000000);
      expect(rows[1].read<String>('title'), 'Сохранить текст');
      expect(
        rows[1].read<String?>('description'),
        '  Точный текст\nбез нормализации  ',
      );
      expect(rows[1].read<int>('is_action_ready'), 1);
      expect(rows[1].read<int>('is_archived'), 0);
      expect(rows[1].read<int>('created_at'), 1704067200000000);
      expect(rows[1].read<int>('updated_at'), 1704153600000000);
      await _expectStorageIsReady(reopenedDatabase);
    });

    test(
      'отказ bootstrap от более новой file-backed схемы не изменяет файл',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        late List<int> originalBytes;

        final result = await harness.open(
          setup: (database) {
            database
              ..execute('CREATE TABLE future_data (value TEXT NOT NULL)')
              ..execute("INSERT INTO future_data(value) VALUES ('сохранённое')")
              ..execute('PRAGMA user_version = 2');
            originalBytes = harness.databaseFile.readAsBytesSync();
          },
        );

        expect(result, isA<LocalDataIncompatibleSchema>());
        expect(await harness.databaseFile.readAsBytes(), originalBytes);
      },
    );

    test('обычный повторный bootstrap не выполняет полный FTS audit', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);

      final firstDatabase = await harness.openReadyDatabase();
      await _insertIntention(
        firstDatabase,
        id: '018f0b5d-6b2e-7c80-8000-000000000303',
        title: 'Первое намерение для проверки открытия',
        titleSearchKey: 'первое намерение для проверки открытия',
        createdAt: 1704412800000000,
        updatedAt: 1704412800000000,
      );
      await _insertIntention(
        firstDatabase,
        id: '018f0b5d-6b2e-7c80-8000-000000000304',
        title: 'Второе намерение для проверки открытия',
        titleSearchKey: 'второе намерение для проверки открытия',
        createdAt: 1704499200000000,
        updatedAt: 1704499200000000,
      );
      await harness.closePersistenceObjectGraph();

      final sqlTrace = _SqlTrace();
      final bootstrap = LocalDataBootstrap(
        executorFactory: () =>
            NativeDatabase(harness.databaseFile).interceptWith(sqlTrace),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(bootstrap.close);

      expect(await bootstrap.open(), isA<LocalDataReady>());
      final trace = sqlTrace.statements.join('\n').toLowerCase();
      expect(trace, contains('pragma user_version'));
      expect(trace, contains('sqlite_schema'));
      expect(trace, contains('pragma foreign_keys = on'));
      expect(trace, isNot(contains('integrity-check')));
    });

    test(
      'dispose закрывает file-backed graph и удаляет его временные ресурсы',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();

        await harness.openReadyDatabase();
        expect(await harness.databaseFile.exists(), isTrue);

        await harness.dispose();

        expect(await harness.temporaryDirectory.exists(), isFalse);
      },
    );
  });
}

Future<void> _expectStorageIsReady(GeneratedDatabase database) async {
  final foreignKeys = await database
      .customSelect('PRAGMA foreign_keys')
      .getSingle();

  expect(foreignKeys.read<int>('foreign_keys'), 1);
  await expectLater(verifyIntentionTitlesFtsIntegrity(database), completes);
}

Future<void> _insertIntention(
  GeneratedDatabase database, {
  required String id,
  required String title,
  required String titleSearchKey,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required int createdAt,
  required int updatedAt,
}) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id,
        title,
        title_search_key,
        description,
        is_action_ready,
        is_archived,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      id,
      title,
      titleSearchKey,
      description,
      isActionReady ? 1 : 0,
      isArchived ? 1 : 0,
      createdAt,
      updatedAt,
    ],
  );
}

final class _SqlTrace extends QueryInterceptor {
  final statements = <String>[];

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_TracingQueryExecutorUser(user, this));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    this.statements.addAll(statements.statements);
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

final class _TracingQueryExecutorUser implements QueryExecutorUser {
  const _TracingQueryExecutorUser(this._delegate, this._sqlTrace);

  final QueryExecutorUser _delegate;
  final _SqlTrace _sqlTrace;

  @override
  int get schemaVersion => _delegate.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      _delegate.beforeOpen(executor.interceptWith(_sqlTrace), details);
}
