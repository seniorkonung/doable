import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(openInMemoryLocalDatabase());
  });

  tearDown(() => database.close());

  group('схема локальных намерений', () {
    test(
      'вычисляет поисковую проекцию только из записываемого title',
      () async {
        await database.customStatement(
          '''
            INSERT INTO intentions (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?)
          ''',
          ['018f0b5d-6b2e-7c80-8000-000000000000', 'Straße', 1000000, 1000000],
        );

        final stored = await database
            .customSelect(
              '''
            SELECT title, title_search_key
            FROM intentions
            WHERE id = ?
          ''',
              variables: [
                Variable.withString('018f0b5d-6b2e-7c80-8000-000000000000'),
              ],
            )
            .getSingle();
        final ftsColumns = await database
            .customSelect('PRAGMA table_info(intention_titles_fts)')
            .get();
        final updateTrigger = await database.customSelect('''
            SELECT sql
            FROM sqlite_schema
            WHERE type = 'trigger'
              AND name = 'intentions_fts_after_update_search_content'
          ''').getSingle();

        expect(stored.read<String>('title'), 'Straße');
        expect(stored.read<String>('title_search_key'), 'strasse');
        expect(ftsColumns.map((column) => column.read<String>('name')), [
          'title_search_key',
        ]);
        expect(
          updateTrigger.read<String>('sql'),
          contains('AFTER UPDATE ON intentions'),
        );
      },
    );

    test(
      'отклоняет прямую запись search key и согласует Unicode-проекции',
      () async {
        const fixtures = [
          (
            id: '018f0b5d-6b2e-7c80-8000-000000000007',
            title: 'K',
            expectedSearchKey: 'k',
          ),
          (
            id: '018f0b5d-6b2e-7c80-8000-000000000008',
            title: 'Straße',
            expectedSearchKey: 'strasse',
          ),
          (
            id: '018f0b5d-6b2e-7c80-8000-000000000009',
            title: 'İ',
            expectedSearchKey: 'i\u0307',
          ),
        ];

        for (final fixture in fixtures) {
          final sqliteSearchKey = await database
              .customSelect(
                'SELECT doable_title_search_key(?) AS search_key',
                variables: [Variable.withString(fixture.title)],
              )
              .getSingle();
          await _insertIntention(
            database,
            id: fixture.id,
            title: fixture.title,
            description: null,
            createdAt: 1000000,
            updatedAt: 1000000,
          );
          final stored = await database
              .customSelect(
                'SELECT title_search_key FROM intentions WHERE id = ?',
                variables: [Variable.withString(fixture.id)],
              )
              .getSingle();
          final filter = IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: fixture.title,
            order: IntentionCatalogOrder.createdAtDescending,
            pageSize: 1,
          ).titleFilter!;

          expect(titleSearchKey(fixture.title), fixture.expectedSearchKey);
          expect(
            sqliteSearchKey.read<String>('search_key'),
            fixture.expectedSearchKey,
          );
          expect(
            stored.read<String>('title_search_key'),
            fixture.expectedSearchKey,
          );
          expect(filter.map(titleSearchKey), fixture.expectedSearchKey);
        }

        await expectLater(
          database.customStatement(
            '''
              INSERT INTO intentions (
                id, title, title_search_key, created_at, updated_at
              ) VALUES (?, ?, ?, ?, ?)
            ''',
            [
              '018f0b5d-6b2e-7c80-8000-000000000010',
              'Нельзя записать ключ',
              'подменённый ключ',
              1000000,
              1000000,
            ],
          ),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          database.customStatement(
            'UPDATE intentions SET title_search_key = ? WHERE id = ?',
            ['подменённый ключ', fixtures.first.id],
          ),
          throwsA(isA<Exception>()),
        );

        await database.customStatement(
          'UPDATE intentions SET title = ? WHERE id = ?',
          ['Straße', fixtures.first.id],
        );
        final recalculated = await database
            .customSelect(
              'SELECT title_search_key FROM intentions WHERE id = ?',
              variables: [Variable.withString(fixtures.first.id)],
            )
            .getSingle();

        expect(recalculated.read<String>('title_search_key'), 'strasse');
      },
    );

    test('сохраняет одноимённые намерения с допускающим отсутствие описанием и исходными состояниями', () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000001',
        title: 'Быть здоровым',
        description: null,
        createdAt: 1000000,
        updatedAt: 1000000,
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000002',
        title: 'Быть здоровым',
        description: 'Сон и прогулки',
        createdAt: 2000000,
        updatedAt: 3000000,
      );

      final rows = await database.customSelect('''
              SELECT id, title, title_search_key, description,
                     is_action_ready, is_archived, created_at, updated_at
              FROM intentions
              ORDER BY id ASC
            ''').get();

      expect(database.schemaVersion, 1);
      expect(rows, hasLength(2));
      expect(
        rows[0].read<String>('id'),
        '018f0b5d-6b2e-7c80-8000-000000000001',
      );
      expect(rows[0].read<String>('title'), 'Быть здоровым');
      expect(rows[0].read<String>('title_search_key'), 'быть здоровым');
      expect(rows[0].read<String?>('description'), isNull);
      expect(rows[0].read<bool>('is_action_ready'), isFalse);
      expect(rows[0].read<bool>('is_archived'), isFalse);
      expect(rows[0].read<int>('created_at'), 1000000);
      expect(rows[0].read<int>('updated_at'), 1000000);
      expect(rows[1].read<String?>('description'), 'Сон и прогулки');
      expect(rows[1].read<int>('created_at'), 2000000);
      expect(rows[1].read<int>('updated_at'), 3000000);
    });

    test(
      'атомарно отклоняет NUL в каноническом тексте и сохраняет FTS',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000012';
        await _insertIntention(
          database,
          id: id,
          title: 'Сохранённое намерение',
          description: 'Сохранённое описание',
          createdAt: 1000000,
          updatedAt: 1000000,
        );

        await expectLater(
          database.customStatement(
            '''
              INSERT INTO intentions (id, title, created_at, updated_at)
              VALUES (?, ?, ?, ?)
            ''',
            [
              '018f0b5d-6b2e-7c80-8000-000000000013',
              'Недопустимый\u0000заголовок',
              1000000,
              1000000,
            ],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );

        for (final statement in [
          (
            sql: 'UPDATE intentions SET title = ? WHERE id = ?',
            arguments: ['Недопустимый\u0000заголовок', id],
          ),
          (
            sql: 'UPDATE intentions SET description = ? WHERE id = ?',
            arguments: ['Недопустимое\u0000описание', id],
          ),
        ]) {
          await expectLater(
            database.customStatement(statement.sql, statement.arguments),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }

        final row = await database
            .customSelect(
              'SELECT title, description FROM intentions WHERE id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingle();

        expect(row.read<String>('title'), 'Сохранённое намерение');
        expect(row.read<String>('description'), 'Сохранённое описание');
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
      },
    );

    test(
      'отклоняет NUL, возвращённый search-key function, в generated схеме',
      () async {
        final schema = await database.customSelect('''
          SELECT sql
          FROM sqlite_schema
          WHERE type = 'table' AND name = 'intentions'
        ''').getSingle();
        final rawDatabase = sqlite.sqlite3.openInMemory();
        addTearDown(rawDatabase.close);
        rawDatabase.createFunction(
          functionName: 'doable_title_search_key',
          argumentCount: const sqlite.AllowedArgumentCount(1),
          deterministic: true,
          directOnly: false,
          function: (_) => '\u0000',
        );
        rawDatabase.execute(schema.read<String>('sql'));

        expect(
          () => rawDatabase.execute('''
            INSERT INTO intentions (id, title, created_at, updated_at)
            VALUES ('018f0b5d-6b2e-7c80-8000-000000000014', 'Допустимый заголовок', 1000000, 1000000)
          '''),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );

    test('принимает обратный порядок корректных timestamps', () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000003',
        title: 'Показание после перевода часов',
        description: null,
        createdAt: 1000000,
        updatedAt: 999999,
      );

      final row =
          await (database.select(database.intentions)..where(
                (row) => row.id.equals('018f0b5d-6b2e-7c80-8000-000000000003'),
              ))
              .getSingle();

      expect(row.createdAt, 1000000);
      expect(row.updatedAt, 999999);
    });

    test('отклоняет неполную строку и недопустимые boolean', () async {
      await expectLater(
        database.customStatement(
          '''
          INSERT INTO intentions (
            id, title, is_action_ready, is_archived, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
          [
            '018f0b5d-6b2e-7c80-8000-000000000004',
            'Некорректное состояние',
            2,
            0,
            1000000,
            1000000,
          ],
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customStatement(
          '''
          INSERT INTO intentions (
            id, title, created_at, updated_at
          ) VALUES (?, NULL, ?, ?)
        ''',
          ['018f0b5d-6b2e-7c80-8000-000000000005', 1000000, 1000000],
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customStatement(
          '''
          INSERT INTO intentions (
            id, title, created_at, updated_at
          ) VALUES (?, ?, ?, ?)
        ''',
          ['018f0b5d-6b2e-7c80-8000-000000000006', '', 1000000, 1000000],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'использует ограничивающий индекс для каждого scope и порядка каталога',
      () async {
        for (final scope in _CatalogIndexScope.values) {
          for (final timestamp in _CatalogIndexTimestamp.values) {
            for (final direction in _CatalogIndexDirection.values) {
              final plan = await database.customSelect('''
                  EXPLAIN QUERY PLAN
                  SELECT id
                  FROM intentions
                  ${scope.whereClause}
                  ORDER BY ${timestamp.column} ${direction.sql}, id ASC
                  LIMIT 100
                ''').get();

              expect(
                plan.map((row) => row.read<String>('detail')),
                contains(contains(scope.indexName(timestamp, direction))),
                reason:
                    'Ожидался индекс ${scope.indexName(timestamp, direction)}.',
              );
            }
          }
        }
      },
    );
  });
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  required String? description,
  required int createdAt,
  required int updatedAt,
}) => database.customStatement(
  '''
      INSERT INTO intentions (
        id, title, description, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
    ''',
  [id, title, description, createdAt, updatedAt],
);

enum _CatalogIndexScope {
  active('WHERE is_archived = 0'),
  archived('WHERE is_archived = 1'),
  all('');

  const _CatalogIndexScope(this.whereClause);

  final String whereClause;

  String indexName(
    _CatalogIndexTimestamp timestamp,
    _CatalogIndexDirection direction,
  ) => 'intentions_${name}_${timestamp.column}_${direction.sql}_id_asc';
}

enum _CatalogIndexTimestamp {
  createdAt('created_at'),
  updatedAt('updated_at');

  const _CatalogIndexTimestamp(this.column);

  final String column;
}

enum _CatalogIndexDirection {
  ascending('asc'),
  descending('desc');

  const _CatalogIndexDirection(this.sql);

  final String sql;
}
