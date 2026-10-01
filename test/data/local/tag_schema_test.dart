import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/local_database_harness.dart';

const _firstIntention = '018f0b5d-6b2e-7c80-8000-000000000001';
const _secondIntention = '018f0b5d-6b2e-7c80-8000-000000000002';
const _relation = '018f0b5d-6b2e-7c80-8000-000000000003';
const _firstTag = '018f0b5d-6b2e-7c80-8000-000000000004';
const _secondTag = '018f0b5d-6b2e-7c80-8000-000000000005';
const _thirdTag = '018f0b5d-6b2e-7c80-8000-000000000006';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    await harness.openReadyDatabase(setup: (connection) => raw = connection);
    raw.execute(
      'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1), (?, ?, 1, 1)',
      [_firstIntention, 'Первое', _secondIntention, 'Второе'],
    );
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority)
         VALUES (?, ?, ?, 'need', 1)''',
      [_relation, _firstIntention, _secondIntention],
    );
  });

  tearDown(() => harness.dispose());

  test('создаёт версию 1 с индексами, ключом названия и внешними ключами', () {
    expect(AppDatabase.currentSchemaVersion, 1);
    expect(
      raw.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );
    final objects = raw
        .select("SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'])
        .toSet();
    expect(
      objects,
      containsAll([
        'tags',
        'tag_assignments',
        'tag_assignments_tag_order',
        'tag_assignments_intention',
        'tag_assignments_intention_order',
        'tags_immutable_identity',
        'tag_assignments_immutable_identity',
        'tag_assignments_valid_tag_order_insert',
        'tag_assignments_fill_tag_order',
        'tag_assignments_valid_tag_order_update',
      ]),
    );
    final key = raw
        .select('PRAGMA table_xinfo(tags)')
        .singleWhere((row) => row['name'] == 'name_key');
    expect(key['hidden'], 3);
    final foreignKeys = raw.select('PRAGMA foreign_key_list(tag_assignments)');
    expect(
      foreignKeys
          .map(
            (row) => (
              row['table'],
              row['from'],
              row['to'],
              row['on_update'],
              row['on_delete'],
            ),
          )
          .toSet(),
      {
        ('tags', 'tag_id', 'id', 'RESTRICT', 'CASCADE'),
        ('intentions', 'intention_id', 'id', 'RESTRICT', 'CASCADE'),
      },
    );
  });

  test('хранит назначение только с обязательным намерением', () {
    final columns = {
      for (final row in raw.select('PRAGMA table_info(tag_assignments)'))
        row['name']! as String: row['notnull']! as int,
    };
    expect(columns, {
      'creation_sequence': 1,
      'tag_id': 1,
      'tag_creation_sequence': 1,
      'intention_id': 1,
    });

    final uniqueIndexes = [
      for (final index in raw.select('PRAGMA index_list(tag_assignments)'))
        if (index['unique'] == 1)
          [
            for (final column in raw.select(
              'SELECT name FROM pragma_index_info(?) ORDER BY seqno',
              [index['name']],
            ))
              column['name']! as String,
          ],
    ];
    expect(uniqueIndexes, [
      ['tag_id', 'intention_id'],
    ]);

    final indexedColumns = {
      for (final index in raw.select('PRAGMA index_list(tag_assignments)'))
        for (final column in raw.select(
          'SELECT name FROM pragma_index_info(?)',
          [index['name']],
        ))
          column['name']! as String,
    };
    expect(indexedColumns, isNot(contains('long_term_relation_id')));

    final relationObjects = raw.select('''
      SELECT name
      FROM sqlite_schema
      WHERE tbl_name = 'tag_assignments'
        AND (name LIKE '%long_term_relation%' OR sql LIKE '%long_term_relation%')
    ''');
    expect(relationObjects, isEmpty);
  });

  test('отклоняет неверные названия и дубликаты после Unicode folding', () {
    for (final invalid in [
      '',
      ' Дом',
      'Дом ',
      'До\u0000м',
      '\uFEFFДом',
      'а' * 256,
    ]) {
      expect(
        () => _addTag(raw, _firstTag, invalid),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Недопустимое название должно быть отклонено.',
      );
    }
    expect(
      () => raw.execute('INSERT INTO tags (id, name) VALUES (?, x\'80\')', [
        _firstTag,
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );
    _addTag(raw, _firstTag, 'Straße');
    expect(
      raw.select('SELECT name_key FROM tags').single['name_key'],
      'strasse',
    );
    expect(
      () => _addTag(raw, _secondTag, 'STRASSE'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute(
        'INSERT INTO tags (id, name, name_key) VALUES (?, ?, ?)',
        [_secondTag, 'Другое', 'чужой ключ'],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute('UPDATE tags SET name_key = ? WHERE id = ?', [
        'чужой ключ',
        _firstTag,
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => _addTag(raw, _firstTag, 'Другое'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', ['Все', _firstTag]);
    _addTag(raw, _secondTag, 'Всё');
    expect(
      raw.select('SELECT name_key FROM tags WHERE id = ?', [
        _firstTag,
      ]).single['name_key'],
      'все',
    );
    expect(
      raw.select('SELECT name_key FROM tags WHERE id = ?', [
        _secondTag,
      ]).single['name_key'],
      'всё',
    );
  });

  test('разрешает только существующее намерение и одну пару', () {
    _addTag(raw, _firstTag, 'Дом');
    for (final intentionId in [null, 'нет-намерения', _relation]) {
      expect(
        () => _addAssignment(raw, _firstTag, intentionId),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Получателем может быть только существующее намерение.',
      );
    }
    expect(
      () => raw.execute(
        'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
        [_firstTag, _relation],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => _addAssignment(raw, 'нет-тега', _firstIntention),
      throwsA(isA<sqlite.SqliteException>()),
    );
    _addAssignment(raw, _firstTag, _firstIntention);
    _addAssignment(raw, _firstTag, _secondIntention);
    expect(
      () => _addAssignment(raw, _firstTag, _firstIntention),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      raw
          .select('SELECT intention_id FROM tag_assignments')
          .map((row) => row['intention_id']),
      [_firstIntention, _secondIntention],
    );
  });

  test('запрещает подменять идентичность и сохраняет максимум sequence', () {
    _addTag(raw, _firstTag, 'Первый');
    _addTag(raw, _secondTag, 'Второй');
    _addAssignment(raw, _firstTag, _firstIntention);
    _addAssignment(raw, _secondTag, _secondIntention);
    for (final table in ['tags', 'tag_assignments']) {
      for (final sequence in [0, -1]) {
        expect(
          () => raw.execute(
            table == 'tags'
                ? 'INSERT INTO tags (creation_sequence, id, name) VALUES (?, ?, ?)'
                : 'INSERT INTO tag_assignments (creation_sequence, tag_id, intention_id) VALUES (?, ?, ?)',
            table == 'tags'
                ? [sequence, _thirdTag, 'Третий']
                : [sequence, _firstTag, _secondIntention],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      }
    }
    final tagSequence =
        raw.select('SELECT creation_sequence FROM tags WHERE id = ?', [
              _secondTag,
            ]).single['creation_sequence']
            as int;
    final assignmentSequence =
        raw
                .select(
                  'SELECT MAX(creation_sequence) AS value FROM tag_assignments',
                )
                .single['value']
            as int;
    expect(tagSequence, greaterThan(0));
    expect(assignmentSequence, greaterThan(0));
    for (final update in [
      ('tags', 'id', _thirdTag, 'id', _firstTag),
      ('tags', 'creation_sequence', tagSequence + 1, 'id', _firstTag),
      (
        'tag_assignments',
        'tag_id',
        _secondTag,
        'intention_id',
        _firstIntention,
      ),
      (
        'tag_assignments',
        'intention_id',
        _secondIntention,
        'intention_id',
        _firstIntention,
      ),
      (
        'tag_assignments',
        'intention_id',
        null,
        'intention_id',
        _firstIntention,
      ),
      (
        'tag_assignments',
        'creation_sequence',
        assignmentSequence + 1,
        'intention_id',
        _firstIntention,
      ),
    ]) {
      expect(
        () => raw.execute(
          'UPDATE ${update.$1} SET ${update.$2} = ? WHERE ${update.$4} = ?',
          [update.$3, update.$5],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
      _secondIntention,
    ]);
    _addAssignment(raw, _firstTag, _secondIntention);
    expect(
      raw.select(
        'SELECT creation_sequence FROM tag_assignments WHERE intention_id = ?',
        [_secondIntention],
      ).single['creation_sequence'],
      greaterThan(assignmentSequence),
    );
    raw.execute('DELETE FROM tags WHERE id = ?', [_secondTag]);
    _addTag(raw, _thirdTag, 'Третий');
    expect(
      raw.select('SELECT creation_sequence FROM tags WHERE id = ?', [
        _thirdTag,
      ]).single['creation_sequence'],
      greaterThan(tagSequence),
    );
  });

  test('каскады удаляют только назначения удалённого тега или намерения', () {
    _addTag(raw, _firstTag, 'Первый');
    _addTag(raw, _secondTag, 'Второй');
    _addAssignment(raw, _firstTag, _firstIntention);
    _addAssignment(raw, _secondTag, _firstIntention);
    _addAssignment(raw, _secondTag, _secondIntention);
    raw.execute('DELETE FROM tags WHERE id = ?', [_firstTag]);
    expect(raw.select('SELECT id FROM intentions'), hasLength(2));
    expect(raw.select('SELECT id FROM long_term_relations'), hasLength(1));
    expect(
      raw
          .select('SELECT tag_id FROM tag_assignments')
          .map((row) => row['tag_id']),
      [_secondTag, _secondTag],
    );
    raw.execute('DELETE FROM long_term_relations WHERE id = ?', [_relation]);
    expect(raw.select('SELECT * FROM tag_assignments'), hasLength(2));
    raw.execute('DELETE FROM intentions WHERE id = ?', [_firstIntention]);
    expect(
      raw
          .select('SELECT intention_id FROM tag_assignments')
          .single['intention_id'],
      _secondIntention,
    );
    expect(raw.select('SELECT id FROM tags').single['id'], _secondTag);
  });
}

void _addTag(sqlite.Database db, String id, String name) {
  db.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [id, name]);
}

void _addAssignment(sqlite.Database db, String tagId, String? intentionId) {
  db.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagId, intentionId],
  );
}
