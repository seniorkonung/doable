import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/doable_schema_verifier.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(openInMemoryLocalDatabase());
  });

  tearDown(() => database.close());

  test('схема версии 1 проходит сгенерированную валидацию', () async {
    await verifyDoableDatabaseSchema(database);
  });

  test(
    'migration connection возвращает тот же search key, что и Dart',
    () async {
      final row = await database
          .customSelect(
            'SELECT doable_title_search_key(?) AS search_key',
            variables: [Variable.withString('Straße')],
          )
          .getSingle();

      expect(row.read<String>('search_key'), titleSearchKey('Straße'));
    },
  );

  test('отключает внешние ключи до транзакции записи и возвращает их после миграции', () async {
    await database.customStatement('PRAGMA foreign_keys = ON');

    await runAtomicMigration(
      database,
      targetSchemaVersion: 1,
      migrate: () async {
        final foreignKeys = await database
            .customSelect('PRAGMA foreign_keys')
            .getSingle();

        expect(foreignKeys.read<int>('foreign_keys'), 0);
      },
    );

    final foreignKeys = await database
        .customSelect('PRAGMA foreign_keys')
        .getSingle();

    expect(foreignKeys.read<int>('foreign_keys'), 1);
  });

  test(
    'не поддерживает downgrade и не изменяет подтверждённые данные',
    () async {
      await _insertIntention(database);

      await expectLater(
        localDataMigrationStrategy(database)
            .onUpgrade(Migrator(database), 2, 1),
        throwsA(isA<UnsupportedError>()),
      );

      final titles = await database
          .customSelect('SELECT title FROM intentions')
          .get();

      expect(titles.single.read<String>('title'), 'Сохранённое намерение');
    },
  );

  test(
    '`foreign_key_check` откатывает маркер миграции и изменения схемы',
    () async {
      await database.customStatement(
        'CREATE TABLE migration_parent (id INTEGER PRIMARY KEY)',
      );
      await database.customStatement('''
      CREATE TABLE migration_child (
        parent_id INTEGER NOT NULL REFERENCES migration_parent(id)
      )
    ''');
      await database.customStatement('PRAGMA foreign_keys = OFF');
      await database.customStatement(
        'INSERT INTO migration_child (parent_id) VALUES (999)',
      );
      await database.customStatement('PRAGMA foreign_keys = ON');
      await database.customStatement('PRAGMA user_version = 1');

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: 2,
          migrate: () async {
            await database.customStatement(
              'CREATE TABLE migration_probe (id INTEGER PRIMARY KEY)',
            );
          },
        ),
        throwsA(isA<StateError>()),
      );

      final marker = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final probe = await database.customSelect('''
      SELECT name FROM sqlite_schema
      WHERE type = 'table' AND name = 'migration_probe'
    ''').get();

      expect(marker.read<int>('user_version'), 1);
      expect(probe, isEmpty);
    },
  );

  test('атомарно пересобранный FTS сохраняет скрытый rowid и проходит integrity-check', () async {
    await _insertIntention(database);
    final previousRowId = await _intentionRowId(database);

    await runAtomicMigration(
      database,
      targetSchemaVersion: 1,
      migrate: () async {
        await rebuildIntentionTitlesFts(database);
      },
    );

    expect(await _intentionRowId(database), previousRowId);
    await expectLater(verifyIntentionTitlesFtsIntegrity(database), completes);
  });
}

Future<void> _insertIntention(AppDatabase database) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, created_at, updated_at
      ) VALUES (?, ?, ?, ?)
    ''',
    [
      '018f0b5d-6b2e-7c80-8000-000000000202',
      'Сохранённое намерение',
      1000000,
      1000000,
    ],
  );
}

Future<int> _intentionRowId(AppDatabase database) async {
  final row = await database
      .customSelect('SELECT rowid FROM intentions')
      .getSingle();

  return row.read<int>('rowid');
}
