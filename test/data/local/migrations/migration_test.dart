import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/doable_schema_verifier.dart';
import '../../../support/local_database_harness.dart';
import '../../../support/schema_v1_fixture.dart';

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

  test('фикстура опубликованной схемы 1 использует снимок и обязательную настройку', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);

    await createSchemaV1Fixture(
      harness.databaseFile,
      seed: (rawDatabase) {
        final version = rawDatabase.select('PRAGMA user_version').single;
        final schemaObjects = rawDatabase.select('''
            SELECT name
            FROM sqlite_schema
            WHERE type IN ('table', 'index', 'trigger', 'view')
              AND name NOT LIKE 'sqlite_%'
          ''');

        rawDatabase.execute('''
            INSERT INTO intentions (id, title, created_at, updated_at)
            VALUES ('018f0b5d-6b2e-7c80-8000-000000000203', 'Straße', 1, 1)
          ''');
        final intention = rawDatabase.select('''
            SELECT title_search_key
            FROM intentions
            WHERE id = '018f0b5d-6b2e-7c80-8000-000000000203'
          ''').single;

        expect(version['user_version'], publishedIntentionSchemaVersion);
        expect(
          schemaObjects.map((row) => row['name']),
          containsAll(<String>[
            'intentions',
            'intention_titles_fts',
            'intentions_fts_after_insert',
            'intentions_all_updated_at_desc_id_asc',
          ]),
        );
        expect(intention['title_search_key'], 'strasse');
      },
    );
  });

  test('переходит со схемы 1 на схему 2 без переписывания намерений', () async {
    await database.close();
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late final Map<String, int> originalRowIds;

    await createSchemaV1Fixture(
      harness.databaseFile,
      seed: (rawDatabase) {
        rawDatabase.execute('''
          INSERT INTO intentions (
            id,
            title,
            description,
            is_action_ready,
            is_archived,
            created_at,
            updated_at
          ) VALUES
            (
              '018f0b5d-6b2e-7c80-8000-000000000211',
              'Straße',
              'Активное описание',
              1,
              0,
              2000000,
              1000000
            ),
            (
              '018f0b5d-6b2e-7c80-8000-000000000212',
              'Архивное намерение',
              NULL,
              0,
              1,
              3000000,
              4000000
            )
        ''');
        originalRowIds = {
          for (final row in rawDatabase.select(
            'SELECT rowid, id FROM intentions',
          ))
            row['id']! as String: row['rowid']! as int,
        };
      },
    );

    final migratedDatabase = await harness.openReadyDatabase();
    final version = await migratedDatabase
        .customSelect('PRAGMA user_version')
        .getSingle();
    final intentions = await migratedDatabase.customSelect('''
      SELECT
        rowid,
        id,
        title,
        title_search_key,
        description,
        is_action_ready,
        is_archived,
        created_at,
        updated_at
      FROM intentions
      ORDER BY id
    ''').get();
    final relations = await migratedDatabase
        .customSelect('SELECT id FROM long_term_relations')
        .get();

    expect(version.read<int>('user_version'), 2);
    expect(
      intentions
          .map(
            (row) => (
              rowId: row.read<int>('rowid'),
              id: row.read<String>('id'),
              title: row.read<String>('title'),
              searchKey: row.read<String>('title_search_key'),
              description: row.read<String?>('description'),
              isActionReady: row.read<bool>('is_action_ready'),
              isArchived: row.read<bool>('is_archived'),
              createdAt: row.read<int>('created_at'),
              updatedAt: row.read<int>('updated_at'),
            ),
          )
          .toList(),
      [
        (
          rowId: originalRowIds['018f0b5d-6b2e-7c80-8000-000000000211']!,
          id: '018f0b5d-6b2e-7c80-8000-000000000211',
          title: 'Straße',
          searchKey: 'strasse',
          description: 'Активное описание',
          isActionReady: true,
          isArchived: false,
          createdAt: 2000000,
          updatedAt: 1000000,
        ),
        (
          rowId: originalRowIds['018f0b5d-6b2e-7c80-8000-000000000212']!,
          id: '018f0b5d-6b2e-7c80-8000-000000000212',
          title: 'Архивное намерение',
          searchKey: 'архивное намерение',
          description: null,
          isActionReady: false,
          isArchived: true,
          createdAt: 3000000,
          updatedAt: 4000000,
        ),
      ],
    );
    expect(relations, isEmpty);
    await expectLater(
      verifyIntentionTitlesFtsIntegrity(migratedDatabase),
      completes,
    );
    await expectLater(verifyDoableDatabaseSchema(migratedDatabase), completes);
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
