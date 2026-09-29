import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/doable_schema_verifier.dart';

const _nextSchemaVersion = AppDatabase.currentSchemaVersion + 1;

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(openInMemoryLocalDatabase());
  });

  tearDown(() => database.close());

  test('текущая схема проходит сгенерированную валидацию', () async {
    await verifyDoableDatabaseSchema(database);
  });

  test('новое хранилище создаётся в единственной версии схемы с пустыми дневными выборами', () async {
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    final choices = await database
        .customSelect('SELECT id FROM daily_choices')
        .get();
    final steps = await database
        .customSelect('SELECT id FROM daily_choice_path_steps')
        .get();

    expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
    expect(choices, isEmpty);
    expect(steps, isEmpty);
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
      targetSchemaVersion: AppDatabase.currentSchemaVersion,
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
        localDataMigrationStrategy(database).onUpgrade(
          Migrator(database),
          _nextSchemaVersion,
          AppDatabase.currentSchemaVersion,
        ),
        throwsA(
          isA<IncompatibleLocalDataSchemaException>()
              .having(
                (error) => error.expectedSchemaVersion,
                'ожидаемая версия',
                AppDatabase.currentSchemaVersion,
              )
              .having(
                (error) => error.detectedSchemaVersion,
                'обнаруженная версия',
                _nextSchemaVersion,
              ),
        ),
      );

      final titles = await database
          .customSelect('SELECT title FROM intentions')
          .get();

      expect(titles.single.read<String>('title'), 'Сохранённое намерение');
    },
  );

  test(
    'не обновляет хранилище с маркером ниже единственной версии схемы',
    () async {
      await _insertIntention(database);
      await database.customStatement('PRAGMA user_version = -1');

      await expectLater(
        localDataMigrationStrategy(
          database,
        ).onUpgrade(Migrator(database), -1, AppDatabase.currentSchemaVersion),
        throwsA(isA<CorruptLocalDataSchemaException>()),
      );

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final titles = await database
          .customSelect('SELECT title FROM intentions')
          .get();

      expect(version.read<int>('user_version'), -1);
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
      await database.customStatement(
        'PRAGMA user_version = ${AppDatabase.currentSchemaVersion}',
      );

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: _nextSchemaVersion,
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

      expect(
        marker.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
      expect(probe, isEmpty);
    },
  );

  test('атомарно пересобранный FTS сохраняет скрытый rowid и проходит integrity-check', () async {
    await _insertIntention(database);
    final previousRowId = await _intentionRowId(database);

    await runAtomicMigration(
      database,
      targetSchemaVersion: AppDatabase.currentSchemaVersion,
      migrate: () async {
        await rebuildIntentionTitlesFts(database);
      },
    );

    expect(await _intentionRowId(database), previousRowId);
    await expectLater(verifyIntentionTitlesFtsIntegrity(database), completes);
  });

  test(
    'повреждённый FTS не позволяет подтвердить новую версию схемы',
    () async {
      await _insertIntention(database);
      await database.customStatement(
        "INSERT INTO intention_titles_fts(intention_titles_fts) VALUES ('delete-all')",
      );

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: _nextSchemaVersion,
          migrate: () async {},
        ),
        throwsA(isA<Exception>()),
      );

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
    },
  );
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
