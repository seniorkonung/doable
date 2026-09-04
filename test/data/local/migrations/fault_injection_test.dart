import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/database_connection.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'атомарная миграция откатывает схему, данные и маркер версии после ошибки',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      addTearDown(database.close);

      await _insertIntention(database);
      await database.customStatement('PRAGMA user_version = 1');

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: 2,
          migrate: () async {
            await database.customStatement(
              'ALTER TABLE intentions ADD COLUMN migration_probe TEXT',
            );
            await database.customStatement(
              'UPDATE intentions SET migration_probe = ?',
              ['частично изменённые данные'],
            );
            throw const _InjectedMigrationFailure();
          },
        ),
        throwsA(isA<_InjectedMigrationFailure>()),
      );

      final columns = await database
          .customSelect('PRAGMA table_info(intentions)')
          .get();
      final intention = await database
          .customSelect('SELECT title FROM intentions')
          .getSingle();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();

      expect(
        columns.map((column) => column.read<String>('name')),
        isNot(contains('migration_probe')),
      );
      expect(intention.read<String>('title'), 'Сохранённое намерение');
      expect(version.read<int>('user_version'), 1);

      await runAtomicMigration(
        database,
        targetSchemaVersion: 2,
        migrate: () async {},
      );

      final retriedVersion = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(retriedVersion.read<int>('user_version'), 2);
      expect(database.schemaVersion, 1);
    },
  );

  test('контур инъекции ошибки закрывает неуспешное соединение', () async {
    final harness = _FailedMigrationConnectionHarness();
    addTearDown(harness.closeIfNeeded);

    await expectLater(
      harness.run(() {
        return runAtomicMigration(
          harness.database,
          targetSchemaVersion: 2,
          migrate: () async => throw const _InjectedMigrationFailure(),
        );
      }),
      throwsA(isA<_InjectedMigrationFailure>()),
    );

    expect(harness.isClosed, isTrue);
  });
}

Future<void> _insertIntention(AppDatabase database) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, title_search_key, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
    ''',
    [
      '018f0b5d-6b2e-7c80-8000-000000000201',
      'Сохранённое намерение',
      'сохранённое намерение',
      1000000,
      1000000,
    ],
  );
}

final class _InjectedMigrationFailure implements Exception {
  const _InjectedMigrationFailure();
}

final class _FailedMigrationConnectionHarness {
  _FailedMigrationConnectionHarness()
    : database = AppDatabase(openInMemoryLocalDatabase());

  final AppDatabase database;
  var isClosed = false;

  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      await database.close();
      isClosed = true;
      rethrow;
    }
  }

  Future<void> closeIfNeeded() async {
    if (!isClosed) {
      await database.close();
      isClosed = true;
    }
  }
}
