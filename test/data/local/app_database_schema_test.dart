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

      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
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
        await expectLater(
          database.customStatement(
            '''
              INSERT INTO intentions (
                id, title, description, created_at, updated_at
              ) VALUES (?, ?, ?, ?, ?)
            ''',
            [
              '018f0b5d-6b2e-7c80-8000-000000000015',
              'Допустимый заголовок',
              'Недопустимое\u0000описание',
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

  group('схема долговременных связей', () {
    test(
      'сохраняет направленную пару только один раз независимо от типа и архива',
      () async {
        await _insertIntention(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000101',
          title: 'Исходное намерение',
          description: null,
          createdAt: 1000000,
          updatedAt: 1000000,
        );
        await _insertIntention(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000102',
          title: 'Связанное намерение',
          description: null,
          createdAt: 2000000,
          updatedAt: 2000000,
        );

        await _insertLongTermRelation(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000111',
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000101',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000102',
          type: 'need',
          priority: 2,
        );
        await _insertLongTermRelation(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000112',
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000102',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000101',
          type: 'can',
          priority: 1,
        );

        await expectLater(
          _insertLongTermRelation(
            database,
            id: '018f0b5d-6b2e-7c80-8000-000000000113',
            sourceId: '018f0b5d-6b2e-7c80-8000-000000000101',
            relatedId: '018f0b5d-6b2e-7c80-8000-000000000102',
            type: 'can',
            priority: 4,
            isArchived: 1,
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          _insertLongTermRelation(
            database,
            id: '018f0b5d-6b2e-7c80-8000-000000000114',
            sourceId: '018f0b5d-6b2e-7c80-8000-000000000101',
            relatedId: '018f0b5d-6b2e-7c80-8000-000000000101',
            type: 'need',
            priority: 1,
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );

        final relations = await database
            .customSelect('SELECT id FROM long_term_relations ORDER BY id')
            .get();
        expect(relations, hasLength(2));
      },
    );

    test('отклоняет недопустимые коды, приоритет и NUL в описании', () async {
      await _insertRelationParticipants(database);
      final invalidRelations = [
        (
          id: '018f0b5d-6b2e-7c80-8000-000000000121',
          type: 'unknown',
          priority: 1,
          description: null,
          isArchived: 0,
        ),
        (
          id: '018f0b5d-6b2e-7c80-8000-000000000122',
          type: 'need',
          priority: 0,
          description: null,
          isArchived: 0,
        ),
        (
          id: '018f0b5d-6b2e-7c80-8000-000000000123',
          type: 'can',
          priority: 5,
          description: null,
          isArchived: 0,
        ),
        (
          id: '018f0b5d-6b2e-7c80-8000-000000000124',
          type: 'need',
          priority: 1,
          description: null,
          isArchived: 2,
        ),
        (
          id: '018f0b5d-6b2e-7c80-8000-000000000125',
          type: 'can',
          priority: 4,
          description: 'Недопустимое\u0000описание',
          isArchived: 0,
        ),
      ];

      for (final relation in invalidRelations) {
        await expectLater(
          _insertLongTermRelation(
            database,
            id: relation.id,
            sourceId: '018f0b5d-6b2e-7c80-8000-000000000131',
            relatedId: '018f0b5d-6b2e-7c80-8000-000000000132',
            type: relation.type,
            priority: relation.priority,
            description: relation.description,
            isArchived: relation.isArchived,
          ),
          throwsA(isA<sqlite.SqliteException>()),
          reason: 'Недопустимая связь ${relation.id} должна быть отклонена.',
        );
      }

      final relations = await database
          .customSelect('SELECT id FROM long_term_relations')
          .get();
      expect(relations, isEmpty);
    });

    test('защищает ссылочную целостность и активность участников', () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000141',
        title: 'Активное исходное намерение',
        description: null,
        createdAt: 1000000,
        updatedAt: 1000000,
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000142',
        title: 'Архивированный участник',
        description: null,
        createdAt: 2000000,
        updatedAt: 2000000,
        isArchived: true,
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000143',
        title: 'Активный связанный участник',
        description: null,
        createdAt: 3000000,
        updatedAt: 3000000,
      );

      await expectLater(
        _insertLongTermRelation(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000151',
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000141',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000142',
          type: 'need',
          priority: 1,
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      await _insertLongTermRelation(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000152',
        sourceId: '018f0b5d-6b2e-7c80-8000-000000000141',
        relatedId: '018f0b5d-6b2e-7c80-8000-000000000142',
        type: 'need',
        priority: 1,
        isArchived: 1,
      );
      await expectLater(
        database.customStatement(
          'UPDATE long_term_relations SET is_archived = 0 WHERE id = ?',
          ['018f0b5d-6b2e-7c80-8000-000000000152'],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      await _insertLongTermRelation(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000153',
        sourceId: '018f0b5d-6b2e-7c80-8000-000000000141',
        relatedId: '018f0b5d-6b2e-7c80-8000-000000000143',
        type: 'can',
        priority: 2,
      );
      await expectLater(
        database.customStatement(
          'UPDATE intentions SET is_archived = 1 WHERE id = ?',
          ['018f0b5d-6b2e-7c80-8000-000000000141'],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        database.customStatement('DELETE FROM intentions WHERE id = ?', [
          '018f0b5d-6b2e-7c80-8000-000000000143',
        ]),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test(
      'запрещает изменять идентичность и последовательность создания',
      () async {
        await _insertRelationParticipants(database);
        const relationId = '018f0b5d-6b2e-7c80-8000-000000000161';
        await _insertLongTermRelation(
          database,
          id: relationId,
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000131',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000132',
          type: 'need',
          priority: 1,
        );
        final original = await database
            .customSelect(
              'SELECT creation_sequence, id FROM long_term_relations WHERE id = ?',
              variables: [Variable.withString(relationId)],
            )
            .getSingle();

        await expectLater(
          database.customStatement(
            'UPDATE long_term_relations SET id = ? WHERE id = ?',
            ['018f0b5d-6b2e-7c80-8000-000000000162', relationId],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          database.customStatement(
            'UPDATE long_term_relations SET creation_sequence = ? WHERE id = ?',
            [original.read<int>('creation_sequence') + 1, relationId],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );

        final stored = await database
            .customSelect(
              'SELECT creation_sequence, id FROM long_term_relations',
            )
            .getSingle();
        expect(stored.read<String>('id'), relationId);
        expect(
          stored.read<int>('creation_sequence'),
          original.read<int>('creation_sequence'),
        );
      },
    );

    test(
      'не переиспользует максимальную последовательность после удаления',
      () async {
        await _insertRelationParticipants(database);
        await _insertIntention(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000133',
          title: 'Следующее связанное намерение',
          description: null,
          createdAt: 3000000,
          updatedAt: 3000000,
        );
        const firstRelationId = '018f0b5d-6b2e-7c80-8000-000000000171';
        const secondRelationId = '018f0b5d-6b2e-7c80-8000-000000000172';
        await _insertLongTermRelation(
          database,
          id: firstRelationId,
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000131',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000132',
          type: 'need',
          priority: 2,
        );
        final firstSequence = await _relationCreationSequence(
          database,
          firstRelationId,
        );

        await database.customStatement(
          'DELETE FROM long_term_relations WHERE id = ?',
          [firstRelationId],
        );
        await _insertLongTermRelation(
          database,
          id: secondRelationId,
          sourceId: '018f0b5d-6b2e-7c80-8000-000000000131',
          relatedId: '018f0b5d-6b2e-7c80-8000-000000000133',
          type: 'need',
          priority: 2,
        );

        expect(
          await _relationCreationSequence(database, secondRelationId),
          greaterThan(firstSequence),
        );
      },
    );

    test(
      'использует отдельный индекс для каждой направленной группы',
      () async {
        const groupIndexes = [
          (
            participantColumn: 'source_intention_id',
            indexName: 'long_term_relations_source_group_order',
          ),
          (
            participantColumn: 'related_intention_id',
            indexName: 'long_term_relations_related_group_order',
          ),
        ];

        for (final group in groupIndexes) {
          final plan = await database
              .customSelect(
                '''
          EXPLAIN QUERY PLAN
          SELECT id
          FROM long_term_relations
          WHERE ${group.participantColumn} = ?
            AND type = ?
            AND is_archived = ?
          ORDER BY priority ASC, creation_sequence ASC
          LIMIT 50
        ''',
                variables: [
                  Variable.withString('018f0b5d-6b2e-7c80-8000-000000000131'),
                  Variable.withString('need'),
                  Variable.withInt(0),
                ],
              )
              .get();

          expect(
            plan.map((row) => row.read<String>('detail')),
            contains(contains(group.indexName)),
            reason: 'Ожидался индекс ${group.indexName}.',
          );
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
  bool isArchived = false,
}) => database.customStatement(
  '''
      INSERT INTO intentions (
        id, title, description, is_archived, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    ''',
  [id, title, description, isArchived ? 1 : 0, createdAt, updatedAt],
);

Future<void> _insertRelationParticipants(AppDatabase database) async {
  await _insertIntention(
    database,
    id: '018f0b5d-6b2e-7c80-8000-000000000131',
    title: 'Исходное намерение',
    description: null,
    createdAt: 1000000,
    updatedAt: 1000000,
  );
  await _insertIntention(
    database,
    id: '018f0b5d-6b2e-7c80-8000-000000000132',
    title: 'Связанное намерение',
    description: null,
    createdAt: 2000000,
    updatedAt: 2000000,
  );
}

Future<void> _insertLongTermRelation(
  AppDatabase database, {
  required String id,
  required String sourceId,
  required String relatedId,
  required String type,
  required int priority,
  String? description,
  int isArchived = 0,
}) => database.customStatement(
  '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      description,
      is_archived
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ''',
  [id, sourceId, relatedId, type, priority, description, isArchived],
);

Future<int> _relationCreationSequence(
  AppDatabase database,
  String relationId,
) async {
  final row = await database
      .customSelect(
        'SELECT creation_sequence FROM long_term_relations WHERE id = ?',
        variables: [Variable.withString(relationId)],
      )
      .getSingle();
  return row.read<int>('creation_sequence');
}

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
