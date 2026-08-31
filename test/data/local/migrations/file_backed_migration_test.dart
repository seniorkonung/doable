import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/local_database_harness.dart';

void main() {
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
