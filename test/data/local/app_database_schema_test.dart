import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(openInMemoryLocalDatabase());
  });

  tearDown(() => database.close());

  group('схема локальных намерений', () {
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
          seedGraph(
            database,
            () => database.customStatement(
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
          ),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          seedGraph(
            database,
            () => database.customStatement(
              'UPDATE intentions SET title_search_key = ? WHERE id = ?',
              ['подменённый ключ', fixtures.first.id],
            ),
          ),
          throwsA(isA<Exception>()),
        );

        await seedGraph(
          database,
          () => database.customStatement(
            'UPDATE intentions SET title = ? WHERE id = ?',
            ['Straße', fixtures.first.id],
          ),
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
          seedGraph(
            database,
            () => database.customStatement(
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
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          seedGraph(
            database,
            () => database.customStatement(
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
            seedGraph(
              database,
              () =>
                  database.customStatement(statement.sql, statement.arguments),
            ),
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

    test('отклоняет неполную строку и недопустимые boolean', () async {
      await expectLater(
        seedGraph(
          database,
          () => database.customStatement(
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
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        seedGraph(
          database,
          () => database.customStatement(
            '''
          INSERT INTO intentions (
            id, title, created_at, updated_at
          ) VALUES (?, NULL, ?, ?)
        ''',
            ['018f0b5d-6b2e-7c80-8000-000000000005', 1000000, 1000000],
          ),
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        seedGraph(
          database,
          () => database.customStatement(
            '''
          INSERT INTO intentions (
            id, title, created_at, updated_at
          ) VALUES (?, ?, ?, ?)
        ''',
            ['018f0b5d-6b2e-7c80-8000-000000000006', '', 1000000, 1000000],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
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
        seedGraph(
          database,
          () => database.customStatement(
            'UPDATE long_term_relations SET is_archived = 0 WHERE id = ?',
            ['018f0b5d-6b2e-7c80-8000-000000000152'],
          ),
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
        seedGraph(
          database,
          () => database.customStatement(
            'UPDATE intentions SET is_archived = 1 WHERE id = ?',
            ['018f0b5d-6b2e-7c80-8000-000000000141'],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        seedGraph(
          database,
          () => database.customStatement(
            'DELETE FROM intentions WHERE id = ?',
            ['018f0b5d-6b2e-7c80-8000-000000000143'],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('запрещает изменять идентичность и последовательность создания', () async {
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
        seedGraph(
          database,
          () => database.customStatement(
            'UPDATE long_term_relations SET id = ? WHERE id = ?',
            ['018f0b5d-6b2e-7c80-8000-000000000162', relationId],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        seedGraph(
          database,
          () => database.customStatement(
            'UPDATE long_term_relations SET creation_sequence = ? WHERE id = ?',
            [original.read<int>('creation_sequence') + 1, relationId],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      final stored = await database
          .customSelect('SELECT creation_sequence, id FROM long_term_relations')
          .getSingle();
      expect(stored.read<String>('id'), relationId);
      expect(
        stored.read<int>('creation_sequence'),
        original.read<int>('creation_sequence'),
      );
    });

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

        await seedGraph(
          database,
          () => database.customStatement(
            'DELETE FROM long_term_relations WHERE id = ?',
            [firstRelationId],
          ),
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
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, description, is_archived, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    ''',
    [id, title, description, isArchived ? 1 : 0, createdAt, updatedAt],
  ),
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
}) => seedGraph(
  database,
  () => database.customStatement(
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
  ),
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
