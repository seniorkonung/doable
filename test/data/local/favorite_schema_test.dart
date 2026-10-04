import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/local_database_harness.dart';

const _firstIntention = '018f0b5d-6b2e-7c80-8000-000000000001';
const _secondIntention = '018f0b5d-6b2e-7c80-8000-000000000002';
const _thirdIntention = '018f0b5d-6b2e-7c80-8000-000000000003';
const _missingIntention = '018f0b5d-6b2e-7c80-8000-000000000004';
const _tag = '018f0b5d-6b2e-7c80-8000-000000000005';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    await harness.openReadyDatabase(setup: (connection) => raw = connection);
    raw.execute(
      '''INSERT INTO intentions (id, title, is_archived, created_at, updated_at)
         VALUES (?, ?, 0, 1, 1), (?, ?, 1, 1, 1), (?, ?, 0, 1, 1)''',
      [
        _firstIntention,
        'Первое',
        _secondIntention,
        'Архивированное',
        _thirdIntention,
        'Третье',
      ],
    );
  });

  tearDown(() => harness.dispose());

  test('создаёт таблицу отметок в единственной версии схемы 1', () {
    expect(AppDatabase.currentSchemaVersion, 1);
    expect(
      raw.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );

    final columns = {
      for (final row in raw.select('PRAGMA table_info(favorite_intentions)'))
        row['name']! as String: (
          type: row['type'],
          notNull: row['notnull'],
          primaryKey: row['pk'],
        ),
    };
    expect(columns, {
      'intention_id': (type: 'TEXT', notNull: 1, primaryKey: 1),
      'position': (type: 'INTEGER', notNull: 1, primaryKey: 0),
    });

    expect(
      raw
          .select('PRAGMA foreign_key_list(favorite_intentions)')
          .map(
            (row) => (
              row['table'],
              row['from'],
              row['to'],
              row['on_update'],
              row['on_delete'],
            ),
          ),
      [('intentions', 'intention_id', 'id', 'RESTRICT', 'CASCADE')],
    );

    final uniqueColumns = {
      for (final index in raw.select('PRAGMA index_list(favorite_intentions)'))
        if (index['unique'] == 1)
          [
            for (final column in raw.select(
              'SELECT name FROM pragma_index_info(?) ORDER BY seqno',
              [index['name']],
            ))
              column['name']! as String,
          ].join(','),
    };
    expect(uniqueColumns, {'intention_id', 'position'});
  });

  test('состоит из таблицы и защитного триггера без функций приложения', () {
    final objects = raw.select('''
      SELECT name, sql
      FROM sqlite_schema
      WHERE tbl_name = 'favorite_intentions' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    ''');

    expect(objects.map((row) => row['name']), [
      'favorite_intentions',
      'favorite_intentions_immutable_identity',
    ]);
    for (final object in objects) {
      expect(
        object['sql']! as String,
        isNot(contains('doable_')),
        reason: 'Объект ${object['name']} не должен зависеть от соединения.',
      );
    }
  });

  test('хранит отметку активного и архивированного намерения с местом', () {
    _addFavorite(raw, _secondIntention, 1);
    _addFavorite(raw, _firstIntention, 7);

    expect(_favorites(raw), [(_secondIntention, 1), (_firstIntention, 7)]);
  });

  test('отклоняет отметку отсутствующего намерения', () {
    _addFavorite(raw, _firstIntention, 1);

    for (final intentionId in [_missingIntention, null]) {
      expect(
        () => _addFavorite(raw, intentionId, 2),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Отметка возможна только у существующего намерения.',
      );
    }

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет вторую отметку того же намерения', () {
    _addFavorite(raw, _firstIntention, 1);

    expect(
      () => _addFavorite(raw, _firstIntention, 2),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет второе намерение на занятом месте', () {
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);

    expect(
      () => _addFavorite(raw, _thirdIntention, 1),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute(
        'UPDATE favorite_intentions SET position = 1 WHERE intention_id = ?',
        [_secondIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1), (_secondIntention, 2)]);
  });

  test('отклоняет отсутствующее, неположительное и нецелое место', () {
    _addFavorite(raw, _firstIntention, 1);

    for (final position in <Object?>[null, 0, -1, 1.5, 'второе', '']) {
      expect(
        () => _addFavorite(raw, _secondIntention, position),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Место $position недопустимо при отметке.',
      );
      expect(
        () => raw.execute(
          'UPDATE favorite_intentions SET position = ? WHERE intention_id = ?',
          [position, _firstIntention],
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Место $position недопустимо при изменении.',
      );
    }

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет недопустимую запись целиком вместе с допустимыми', () {
    _addFavorite(raw, _firstIntention, 1);

    expect(
      () => raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, 2), (?, 1)',
        [_secondIntention, _thirdIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, 2), (?, 3)',
        [_secondIntention, _missingIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('запрещает подменять намерение отметки и допускает смену места', () {
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);

    for (final intentionId in [_thirdIntention, _missingIntention, null]) {
      expect(
        () => raw.execute(
          'UPDATE favorite_intentions SET intention_id = ? '
          'WHERE intention_id = ?',
          [intentionId, _firstIntention],
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Отметка не переносится на $intentionId.',
      );
    }
    expect(_favorites(raw), [(_firstIntention, 1), (_secondIntention, 2)]);

    raw.execute(
      'UPDATE favorite_intentions SET position = 5 WHERE intention_id = ?',
      [_firstIntention],
    );
    raw.execute(
      'UPDATE favorite_intentions SET intention_id = ?, position = 1 '
      'WHERE intention_id = ?',
      [_secondIntention, _secondIntention],
    );

    expect(_favorites(raw), [(_secondIntention, 1), (_firstIntention, 5)]);
  });

  test('удаление намерения удаляет только его строку отметки', () {
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_tag, 'Дом']);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?), (?, ?)',
      [_tag, _firstIntention, _tag, _thirdIntention],
    );
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);
    _addFavorite(raw, _thirdIntention, 3);

    raw.execute('DELETE FROM intentions WHERE id = ?', [_secondIntention]);

    expect(_favorites(raw), [(_firstIntention, 1), (_thirdIntention, 3)]);
    expect(
      raw
          .select('SELECT id FROM intentions ORDER BY id')
          .map((row) => row['id']),
      [_firstIntention, _thirdIntention],
    );
    expect(raw.select('SELECT * FROM tag_assignments'), hasLength(2));
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('снятие отметки сохраняет намерение и остальные отметки', () {
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);

    raw.execute('DELETE FROM favorite_intentions WHERE intention_id = ?', [
      _firstIntention,
    ]);

    expect(_favorites(raw), [(_secondIntention, 2)]);
    expect(raw.select('SELECT id FROM intentions'), hasLength(3));
  });
}

void _addFavorite(sqlite.Database db, String? intentionId, Object? position) {
  db.execute(
    'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
    [intentionId, position],
  );
}

List<(Object?, Object?)> _favorites(sqlite.Database db) => [
  for (final row in db.select(
    'SELECT intention_id, position FROM favorite_intentions ORDER BY position',
  ))
    (row['intention_id'], row['position']),
];
