import 'dart:typed_data';

import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_positions.dart';

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
    seedRawGraph(raw, () {
      raw
        ..execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1), (?, ?, 1, 1)',
          [_firstIntention, 'Первое', _secondIntention, 'Второе'],
        )
        ..execute(
          '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority)
         VALUES (?, ?, ?, 'need', 1)''',
          [_relation, _firstIntention, _secondIntention],
        );
    });
  });

  tearDown(() => harness.dispose());

  test('отклоняет неверные названия и дубликаты после Unicode folding', () {
    // Пустое название, окружающие пробелы, NUL и длина: начальный BOM и
    // тонкости пробельных символов проверены в тесте функций SQLite.
    for (final invalid in ['', ' Дом', 'До\u0000м', 'а' * 256]) {
      expect(
        () => _addTag(raw, _firstTag, invalid),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Недопустимое название должно быть отклонено.',
      );
    }
    expect(
      () => seedRawGraph(
        raw,
        () => raw.execute(
          'INSERT INTO tags (id, name, position) VALUES (?, x\'80\', ?)',
          [_firstTag, 'a0'],
        ),
      ),
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
      () => seedRawGraph(
        raw,
        () => raw.execute(
          'INSERT INTO tags (id, name, position, name_key) VALUES (?, ?, ?, ?)',
          [_secondTag, 'Другое', 'a0', 'чужой ключ'],
        ),
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => seedRawGraph(
        raw,
        () => raw.execute('UPDATE tags SET name_key = ? WHERE id = ?', [
          'чужой ключ',
          _firstTag,
        ]),
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => _addTag(raw, _firstTag, 'Другое', position: 'a0'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    seedRawGraph(
      raw,
      () => raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
        'Все',
        _firstTag,
      ]),
    );
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

  test('хранит цвет только как отсутствие или код палитры тегов', () {
    final codes = [for (final color in TagColor.values) color.code];
    _addTag(raw, _firstTag, 'Без цвета');
    for (final (index, code) in codes.indexed) {
      _addColoredTag(raw, _coloredTag(index), 'Тег $code', code);
    }
    // Коды сравниваются точно: другой регистр — чужое значение.
    for (final invalid in ['red', 'Blue']) {
      expect(
        () => _addColoredTag(raw, _secondTag, 'Недопустимый', invalid),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Цвет вне палитры должен быть отклонён.',
      );
    }

    expect(
      raw
          .select('SELECT color FROM tags ORDER BY creation_sequence')
          .map((row) => row['color']),
      [null, ...codes],
    );
  });

  test('хранит место непустой уникальной строкой из цифр и латинских букв', () {
    _addTag(raw, _firstTag, 'Первый', position: 'a0');
    _addTag(raw, _secondTag, 'Второй', position: 'Zz0V');
    for (final invalid in <Object?>[
      null,
      '',
      ' a0',
      'a-0',
      'а0',
      'a0\u0000',
      Uint8List.fromList('a1'.codeUnits),
      'a0',
    ]) {
      expect(
        () => seedRawGraph(
          raw,
          () => raw.execute(
            'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
            [_thirdTag, 'Третий', invalid],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Место $invalid должно быть отклонено.',
      );
    }
    expect(
      raw
          .select('SELECT position FROM tags ORDER BY creation_sequence')
          .map((row) => row['position']),
      ['a0', 'Zz0V'],
    );
  });

  test('сортирует места как сравнение их кодовых единиц', () {
    // Ключи разных регистров и длин, перемешанные относительно порядка.
    final keys = [
      'a1',
      'Zz',
      'b00',
      'a0V',
      'A${'0' * 26}1',
      'a0',
      'Zzzz',
      'z1',
    ];
    for (final (index, key) in keys.indexed) {
      _addTag(raw, _coloredTag(index), 'Тег $index', position: key);
    }

    expect(
      raw
          .select('SELECT position FROM tags ORDER BY position')
          .map((row) => row['position']),
      [...keys]..sort(),
    );
  });

  test('разрешает только существующее намерение и одну пару', () {
    _addTag(raw, _firstTag, 'Дом');
    for (final intentionId in [null, 'нет-намерения']) {
      expect(
        () => _addAssignment(raw, _firstTag, intentionId),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Получателем может быть только существующее намерение.',
      );
    }
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
          () => seedRawGraph(
            raw,
            () => raw.execute(
              table == 'tags'
                  ? 'INSERT INTO tags (creation_sequence, id, name, position) VALUES (?, ?, ?, \'a0\')'
                  : 'INSERT INTO tag_assignments (creation_sequence, tag_id, intention_id) VALUES (?, ?, ?)',
              table == 'tags'
                  ? [sequence, _thirdTag, 'Третий']
                  : [sequence, _firstTag, _secondIntention],
            ),
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
        () => seedRawGraph(
          raw,
          () => raw.execute(
            'UPDATE ${update.$1} SET ${update.$2} = ? WHERE ${update.$4} = ?',
            [update.$3, update.$5],
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    seedRawGraph(
      raw,
      () => raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
        _secondIntention,
      ]),
    );
    _addAssignment(raw, _firstTag, _secondIntention);
    expect(
      raw.select(
        'SELECT creation_sequence FROM tag_assignments WHERE intention_id = ?',
        [_secondIntention],
      ).single['creation_sequence'],
      greaterThan(assignmentSequence),
    );
    seedRawGraph(
      raw,
      () => raw.execute('DELETE FROM tags WHERE id = ?', [_secondTag]),
    );
    _addTag(raw, _thirdTag, 'Третий');
    expect(
      raw.select('SELECT creation_sequence FROM tags WHERE id = ?', [
        _thirdTag,
      ]).single['creation_sequence'],
      greaterThan(tagSequence),
    );
  });
}

/// Без явного [position] место выводится из номера в [id], поэтому у
/// различных тегов оно различно.
void _addTag(sqlite.Database db, String id, String name, {String? position}) {
  seedRawGraph(
    db,
    () => db.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
      id,
      name,
      position ?? _positionOf(id),
    ]),
  );
}

void _addColoredTag(sqlite.Database db, String id, String name, String color) {
  seedRawGraph(
    db,
    () => db.execute(
      'INSERT INTO tags (id, name, color, position) VALUES (?, ?, ?, ?)',
      [id, name, color, _positionOf(id)],
    ),
  );
}

String _positionOf(String id) =>
    tagPositionKey(int.parse(id.substring(24), radix: 16));

String _coloredTag(int index) =>
    '018f0b5d-6b2e-7c80-8000-${(100 + index).toString().padLeft(12, '0')}';

void _addAssignment(sqlite.Database db, String tagId, String? intentionId) {
  seedRawGraph(
    db,
    () => db.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagId, intentionId],
    ),
  );
}
