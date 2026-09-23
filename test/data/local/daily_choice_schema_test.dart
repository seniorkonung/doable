import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/local_database_harness.dart';

const _source = '018f0b5d-6b2e-7c80-8000-000000000001';
const _selected = '018f0b5d-6b2e-7c80-8000-000000000002';
const _other = '018f0b5d-6b2e-7c80-8000-000000000003';
const _relation = '018f0b5d-6b2e-7c80-8000-000000000004';
const _secondRelation = '018f0b5d-6b2e-7c80-8000-000000000005';
const _choice = '018f0b5d-6b2e-7c80-8000-000000000006';
const _secondChoice = '018f0b5d-6b2e-7c80-8000-000000000007';
const _firstStep = '018f0b5d-6b2e-7c80-8000-000000000008';
const _secondStep = '018f0b5d-6b2e-7c80-8000-000000000009';
const _thirdStep = '018f0b5d-6b2e-7c80-8000-00000000000a';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
    );
    await database.open();
    final fragment = File('lib/src/data/local/schema/daily_choice_schema.drift')
        .readAsStringSync();
    raw.execute(
      fragment.replaceFirst("import 'long_term_relation_schema.drift';", ''),
    );

    for (final (id, title) in [
      (_source, 'Исходное намерение'),
      (_selected, 'Выбранное действие'),
      (_other, 'Другое действие'),
    ]) {
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
        [id, title],
      );
    }
    _addRelation(raw, _relation, _source, _selected);
    _addRelation(raw, _secondRelation, _selected, _other);
  });

  tearDown(() => harness.dispose());

  test(
    'сохраняет полные дубликаты с отдельной последовательностью создания',
    () {
      _addChoice(raw, _choice);
      _addChoice(raw, _secondChoice);
      _addStep(raw, _firstStep, _choice, _relation);
      _addStep(raw, _secondStep, _secondChoice, _relation);
      final rows = raw.select(
        'SELECT id, creation_sequence FROM daily_choices ORDER BY creation_sequence',
      );
      expect(rows.map((row) => row['id']), [_choice, _secondChoice]);
      final firstSequence = rows.first['creation_sequence'] as int;
      final secondSequence = rows.last['creation_sequence'] as int;
      expect(secondSequence, greaterThan(firstSequence));
      expect(
        () => raw.execute('UPDATE daily_choices SET id = ? WHERE id = ?', [
          _thirdStep,
          _choice,
        ]),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        () => raw.execute(
          'UPDATE daily_choices SET creation_sequence = ? WHERE id = ?',
          [secondSequence + 1, _choice],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      raw.execute('DELETE FROM daily_choices WHERE id = ?', [_secondChoice]);
      _addChoice(raw, _thirdStep);
      expect(
        raw.select('SELECT creation_sequence FROM daily_choices WHERE id = ?', [
          _thirdStep,
        ]).single['creation_sequence'],
        greaterThan(secondSequence),
      );
    },
  );

  test('отклоняет недопустимые поля и прямые ссылки выбора', () {
    for (final values in [
      (_source, _source, '2026-09-23', null, 0),
      ('нет-намерения', _selected, '2026-09-23', null, 0),
      (_source, 'нет-действия', '2026-09-23', null, 0),
      (_source, _selected, '2026-9-23', null, 0),
      (_source, _selected, '2026-09-23T00:00', null, 0),
      (_source, _selected, '2026-09-23', 'До\u0000ма', 0),
      (_source, _selected, '2026-09-23', null, 2),
      (_source, _selected, '2026-09-23', null, 'неизвестно'),
    ]) {
      expect(
        () => raw.execute(
          '''INSERT INTO daily_choices
            (id, source_intention_id, selected_intention_id,
             choice_date, description, is_completed)
            VALUES (?, ?, ?, ?, ?, ?)''',
          [_choice, values.$1, values.$2, values.$3, values.$4, values.$5],
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Недопустимая строка $values должна быть отклонена.',
      );
    }
    expect(raw.select('SELECT id FROM daily_choices'), isEmpty);
  });

  test('защищает участников, используемую связь и границы каскада', () {
    _addChoice(raw, _choice);
    _addChoice(raw, _secondChoice);
    _addStep(raw, _firstStep, _choice, _relation);
    _addStep(raw, _secondStep, _secondChoice, _relation);

    for (final sql in [
      'DELETE FROM intentions WHERE id = ?',
      'UPDATE intentions SET id = ? WHERE id = ?',
    ]) {
      expect(
        () => raw.execute(
          sql,
          sql.startsWith('DELETE') ? [_source] : [_thirdStep, _source],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(
      () => raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
        _relation,
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute('UPDATE long_term_relations SET id = ? WHERE id = ?', [
        _thirdStep,
        _relation,
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );

    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]);
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), hasLength(1));
    expect(
      () => raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
        _relation,
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_secondChoice]);
    raw.execute('DELETE FROM long_term_relations WHERE id = ?', [_relation]);
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), isEmpty);
  });

  test('защищает прямых участников без долговременных связей', () {
    raw.execute('DELETE FROM long_term_relations');
    _addChoice(raw, _choice);
    for (final id in [_source, _selected]) {
      expect(
        () => raw.execute('DELETE FROM intentions WHERE id = ?', [id]),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]);
    raw.execute('DELETE FROM intentions WHERE id = ?', [_source]);
    raw.execute('DELETE FROM intentions WHERE id = ?', [_selected]);
  });

  test('не допускает чужого предшественника, самоссылку, второй корень и ветвление', () {
    _addChoice(raw, _choice);
    _addChoice(raw, _secondChoice);
    _addStep(raw, _firstStep, _choice, _relation);
    _addStep(raw, _secondStep, _secondChoice, _relation);

    expect(
      () => _addStep(raw, _thirdStep, _choice, _relation),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => _addStep(raw, _thirdStep, _choice, _relation, _thirdStep),
      throwsA(isA<sqlite.SqliteException>()),
    );
    _failsAtCommit(raw, () {
      _addStep(raw, _thirdStep, _choice, _relation, _secondStep);
    });
    _failsAtCommit(raw, () {
      _addStep(raw, _thirdStep, _choice, _relation, 'нет-шага');
    });
    expect(
      () => _addStep(raw, _thirdStep, 'нет-выбора', _relation),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => _addStep(raw, _thirdStep, _choice, 'нет-связи', _firstStep),
      throwsA(isA<sqlite.SqliteException>()),
    );

    _addStep(raw, _thirdStep, _choice, _secondRelation, _firstStep);
    expect(
      () => _addStep(raw, _secondStep, _choice, _secondRelation, _firstStep),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), hasLength(3));
  });

  test('откатывает незавершённый выбор при ошибке отложенной ссылки', () {
    _failsAtCommit(raw, () {
      _addChoice(raw, _choice);
      _addStep(raw, _firstStep, _choice, _relation, 'нет-шага');
    });
    expect(raw.select('SELECT id FROM daily_choices'), isEmpty);
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), isEmpty);
  });

  test('разрешает удалять всю цепочку в обоих порядках', () {
    for (final order in [
      [_firstStep, _secondStep, _thirdStep],
      [_thirdStep, _secondStep, _firstStep],
    ]) {
      _addChoice(raw, _choice);
      _addStep(raw, _firstStep, _choice, _relation);
      _addStep(raw, _secondStep, _choice, _secondRelation, _firstStep);
      _addStep(raw, _thirdStep, _choice, _relation, _secondStep);
      raw.execute('BEGIN');
      for (final id in order) {
        raw.execute('DELETE FROM daily_choice_path_steps WHERE id = ?', [id]);
      }
      raw.execute('COMMIT');
      expect(raw.select('SELECT id FROM daily_choice_path_steps'), isEmpty);
      raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]);
    }
  });

  test(
    'разрешает добавить предшественника после следующего шага в транзакции',
    () {
      _addChoice(raw, _choice);
      raw.execute('BEGIN');
      _addStep(raw, _secondStep, _choice, _secondRelation, _firstStep);
      _addStep(raw, _firstStep, _choice, _relation);
      raw.execute('COMMIT');
      expect(
        raw.select('SELECT id FROM daily_choice_path_steps'),
        hasLength(2),
      );
    },
  );

  test('блокирует смену смысла используемой связи, сохраняя остальные правки', () {
    _addChoice(raw, _choice);
    _addStep(raw, _firstStep, _choice, _relation);
    for (final (column, value) in [
      ('type', 'can'),
      ('source_intention_id', _other),
      ('related_intention_id', _other),
    ]) {
      expect(
        () => raw.execute(
          'UPDATE long_term_relations SET $column = ?, description = ? WHERE id = ?',
          [value, 'Изменение', _relation],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(
      raw.select('SELECT description FROM long_term_relations WHERE id = ?', [
        _relation,
      ]).single['description'],
      isNull,
    );
    raw.execute(
      '''UPDATE long_term_relations
         SET type = 'need', source_intention_id = ?, related_intention_id = ?,
             priority = 2, description = 'Допустимо', is_archived = 1
         WHERE id = ?''',
      [_source, _selected, _relation],
    );
    final row = raw.select('SELECT * FROM long_term_relations WHERE id = ?', [
      _relation,
    ]).single;
    expect(row['priority'], 2);
    expect(row['description'], 'Допустимо');
    expect(row['is_archived'], 1);
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]);
    raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
      'can',
      _relation,
    ]);
    expect(
      raw.select('SELECT type FROM long_term_relations WHERE id = ?', [
        _relation,
      ]).single['type'],
      'can',
    );
  });

  test('предоставляет индексы каталога, участников и обратных ссылок', () {
    final names = raw
        .select("SELECT name FROM sqlite_schema WHERE type = 'index'")
        .map((row) => row['name'])
        .toSet();
    expect(
      names,
      containsAll([
        'daily_choices_date_creation_order',
        'daily_choices_source_date_creation_order',
        'daily_choices_selected_date_creation_order',
        'daily_choices_source_recent',
        'daily_choices_selected_recent',
        'daily_choice_path_steps_one_root',
        'daily_choice_path_steps_one_successor',
        'daily_choice_path_steps_relation',
      ]),
    );
    final plan = raw.select(
      '''
      EXPLAIN QUERY PLAN
      SELECT id FROM daily_choice_path_steps WHERE daily_choice_id = ?
    ''',
      [_choice],
    );
    expect(
      plan.map((row) => row['detail']),
      contains(contains('daily_choice_path_steps')),
    );
    expect(plan.map((row) => row['detail']), contains(contains('INDEX')));
  });
}

void _addRelation(
  sqlite.Database db,
  String id,
  String source,
  String related,
) {
  db.execute(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id, type, priority)
       VALUES (?, ?, ?, 'need', 1)''',
    [id, source, related],
  );
}

void _addChoice(sqlite.Database db, String id) {
  db.execute(
    '''INSERT INTO daily_choices
       (id, source_intention_id, selected_intention_id,
        choice_date, is_completed)
       VALUES (?, ?, ?, '2026-09-23', 0)''',
    [id, _source, _selected],
  );
}

void _addStep(
  sqlite.Database db,
  String id,
  String owner,
  String relation, [
  String? previous,
]) {
  db.execute(
    '''INSERT INTO daily_choice_path_steps
       (id, daily_choice_id, long_term_relation_id, previous_step_id)
       VALUES (?, ?, ?, ?)''',
    [id, owner, relation, previous],
  );
}

void _failsAtCommit(sqlite.Database db, void Function() write) {
  db.execute('BEGIN');
  try {
    write();
    expect(() => db.execute('COMMIT'), throwsA(isA<sqlite.SqliteException>()));
  } finally {
    db.execute('ROLLBACK');
  }
}
