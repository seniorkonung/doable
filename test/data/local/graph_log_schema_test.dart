import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';

const _source = '018f0b5d-6b2e-7c80-8000-000000000001';
const _selected = '018f0b5d-6b2e-7c80-8000-000000000002';
const _other = '018f0b5d-6b2e-7c80-8000-000000000003';
const _created = '018f0b5d-6b2e-7c80-8000-000000000004';
const _relation = '018f0b5d-6b2e-7c80-8000-000000000011';
const _secondRelation = '018f0b5d-6b2e-7c80-8000-000000000012';
const _createdRelation = '018f0b5d-6b2e-7c80-8000-000000000013';
const _tag = '018f0b5d-6b2e-7c80-8000-000000000021';
const _secondTag = '018f0b5d-6b2e-7c80-8000-000000000022';
const _choice = '018f0b5d-6b2e-7c80-8000-000000000031';
const _firstStep = '018f0b5d-6b2e-7c80-8000-000000000041';
const _secondStep = '018f0b5d-6b2e-7c80-8000-000000000042';

typedef _Mark = (String kind, String entity, String firstOperation);

/// Отказ триггера, которым база прерывает запись в обход единого пути.
final _bypassRejection = isA<sqlite.SqliteException>().having(
  (error) => error.message,
  'message',
  'graph write outside the graph write path',
);

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
    );
    await database.open();
  });

  tearDown(() => harness.dispose());

  /// Граф, на котором проверяются отметки: три намерения, две связи и тег.
  /// Заполнен без отметок.
  void addGraph() => seedRawGraph(raw, () {
    for (final (id, title) in [
      (_source, 'Исходное намерение'),
      (_selected, 'Выбранное действие'),
      (_other, 'Другое действие'),
    ]) {
      _addIntention(raw, id, title);
    }
    _addRelation(raw, _relation, _source, _selected);
    _addRelation(raw, _secondRelation, _selected, _other);
    _addTag(raw, _tag, 'Дом');
  });

  test('новая установка включает захват без признака записи и начинает лог '
      'с позиции 0', () {
    expect(raw.select('SELECT capture, writing FROM graph_log_control'), [
      {'capture': 1, 'writing': 0},
    ]);
    for (final table in [
      'graph_log_packages',
      'graph_snapshots',
      'graph_backups',
    ]) {
      expect(raw.select('SELECT * FROM $table'), isEmpty, reason: table);
    }
    expect(_marks(raw), isEmpty);
  });

  /// Вставка, изменение и удаление строк каждой таблицы графа и шагов пути
  /// по порядку, начиная с графа [addGraph], с отметками каждой операции.
  List<(String, void Function(), Set<_Mark>)> operations() => [
    (
      'создание тега',
      () => _addTag(raw, _secondTag, 'Работа'),
      {('tag', _secondTag, 'insert')},
    ),
    (
      'переименование тега',
      () => raw.execute("UPDATE tags SET name = 'Офис' WHERE id = ?", [
        _secondTag,
      ]),
      {('tag', _secondTag, 'update')},
    ),
    (
      'создание намерения',
      () => _addIntention(raw, _created, 'Новое намерение'),
      {('intention', _created, 'insert')},
    ),
    (
      'изменение намерения',
      () => raw.execute(
        "UPDATE intentions SET title = 'Другое название' WHERE id = ?",
        [_created],
      ),
      {('intention', _created, 'update')},
    ),
    (
      'назначение тега',
      () => _addAssignment(raw, _secondTag, _source),
      {('tagAssignment', '$_secondTag/$_source', 'insert')},
    ),
    (
      'изменение строки назначения',
      () => raw.execute(
        'UPDATE tag_assignments SET intention_id = intention_id '
        'WHERE tag_id = ?',
        [_secondTag],
      ),
      {('tagAssignment', '$_secondTag/$_source', 'update')},
    ),
    (
      'снятие тега',
      () => raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        _secondTag,
      ]),
      {('tagAssignment', '$_secondTag/$_source', 'delete')},
    ),
    (
      'создание связи',
      () => _addRelation(raw, _createdRelation, _source, _other),
      {('longTermRelation', _createdRelation, 'insert')},
    ),
    (
      'изменение связи',
      () => raw.execute(
        'UPDATE long_term_relations SET priority = 3 WHERE id = ?',
        [_createdRelation],
      ),
      {('longTermRelation', _createdRelation, 'update')},
    ),
    (
      'удаление связи',
      () => raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
        _createdRelation,
      ]),
      {('longTermRelation', _createdRelation, 'delete')},
    ),
    (
      'создание дневного выбора',
      () => _addChoice(raw, _choice),
      {('dailyChoice', _choice, 'insert')},
    ),
    (
      'добавление шага пути',
      () => _addStep(raw, _firstStep, _choice, _relation),
      {('dailyChoice', _choice, 'update')},
    ),
    (
      'изменение шага пути',
      () => raw.execute(
        'UPDATE daily_choice_path_steps SET long_term_relation_id = ? '
        'WHERE id = ?',
        [_secondRelation, _firstStep],
      ),
      {('dailyChoice', _choice, 'update')},
    ),
    (
      'удаление шага пути',
      () => raw.execute('DELETE FROM daily_choice_path_steps WHERE id = ?', [
        _firstStep,
      ]),
      {('dailyChoice', _choice, 'update')},
    ),
    (
      'изменение дневного выбора',
      () => raw.execute(
        'UPDATE daily_choices SET is_completed = 1 WHERE id = ?',
        [_choice],
      ),
      {('dailyChoice', _choice, 'update')},
    ),
    (
      'удаление дневного выбора',
      () => raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]),
      {('dailyChoice', _choice, 'delete')},
    ),
    (
      'удаление намерения',
      () => raw.execute('DELETE FROM intentions WHERE id = ?', [_created]),
      {('intention', _created, 'delete')},
    ),
    (
      'удаление тега',
      () => raw.execute('DELETE FROM tags WHERE id = ?', [_secondTag]),
      {('tag', _secondTag, 'delete')},
    ),
  ];

  test('отмечает каждую операцию каждой таблицы графа', () {
    addGraph();

    for (final (description, write, expected) in operations()) {
      _writeGraph(raw, write);
      expect(_marks(raw), expected, reason: description);
      _clearMarks(raw);
    }
  });

  test('без признака записи отклоняет каждую операцию каждой таблицы графа, '
      'не меняя строк и не оставляя отметок', () {
    addGraph();

    for (final (description, write, _) in operations()) {
      final rows = _graphRows(raw);
      expect(write, throwsA(_bypassRejection), reason: description);
      expect(_graphRows(raw), rows, reason: description);
      expect(_marks(raw), isEmpty, reason: description);

      _writeGraph(raw, write);
      _clearMarks(raw);
    }
  });

  test('сохраняет первую операцию при повторных изменениях сущности', () {
    addGraph();
    seedRawGraph(raw, () => _addAssignment(raw, _tag, _source));

    _writeGraph(raw, () {
      _addIntention(raw, _created, 'Новое намерение');
      raw.execute("UPDATE intentions SET title = 'Изменено' WHERE id = ?", [
        _created,
      ]);
      raw.execute('DELETE FROM intentions WHERE id = ?', [_created]);
      raw.execute("UPDATE tags SET name = 'Квартира' WHERE id = ?", [_tag]);
      raw.execute('DELETE FROM tag_assignments');
      raw.execute('DELETE FROM tags WHERE id = ?', [_tag]);
      _addTag(raw, _secondTag, 'Работа');
      _addAssignment(raw, _secondTag, _source);
      raw.execute('DELETE FROM tag_assignments');
      _addAssignment(raw, _secondTag, _source);
      _addChoice(raw, _choice);
      _addStep(raw, _firstStep, _choice, _relation);
    });

    expect(_marks(raw), {
      ('intention', _created, 'insert'),
      ('tag', _tag, 'update'),
      ('tagAssignment', '$_tag/$_source', 'delete'),
      ('tag', _secondTag, 'insert'),
      ('tagAssignment', '$_secondTag/$_source', 'insert'),
      ('dailyChoice', _choice, 'insert'),
    });
  });

  test('каскадные удаления отмечают дочерние сущности', () {
    addGraph();
    seedRawGraph(raw, () {
      _addIntention(raw, _created, 'Намерение без связей');
      _addTag(raw, _secondTag, 'Работа');
      _addAssignment(raw, _tag, _source);
      _addAssignment(raw, _tag, _selected);
      _addAssignment(raw, _tag, _created);
      _addAssignment(raw, _secondTag, _created);
      _addChoice(raw, _choice);
      _addStep(raw, _firstStep, _choice, _relation);
      _addStep(raw, _secondStep, _choice, _secondRelation, _firstStep);
    });

    _writeGraph(
      raw,
      () => raw.execute('DELETE FROM tags WHERE id = ?', [_tag]),
    );
    expect(_marks(raw), {
      ('tag', _tag, 'delete'),
      ('tagAssignment', '$_tag/$_source', 'delete'),
      ('tagAssignment', '$_tag/$_selected', 'delete'),
      ('tagAssignment', '$_tag/$_created', 'delete'),
    });
    _clearMarks(raw);

    _writeGraph(
      raw,
      () => raw.execute('DELETE FROM intentions WHERE id = ?', [_created]),
    );
    expect(_marks(raw), {
      ('intention', _created, 'delete'),
      ('tagAssignment', '$_secondTag/$_created', 'delete'),
    });
    _clearMarks(raw);

    _writeGraph(
      raw,
      () => raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]),
    );
    expect(raw.select('SELECT * FROM daily_choice_path_steps'), isEmpty);
    // Каскад удаляет шаги раньше, чем срабатывает AFTER DELETE самого
    // выбора, поэтому первая операция — изменение шагов его пути.
    expect(_marks(raw), {('dailyChoice', _choice, 'update')});
  });

  test('выключенный захват не оставляет отметок', () {
    addGraph();
    seedRawGraph(raw, () {
      _addAssignment(raw, _tag, _source);
      _addChoice(raw, _choice);
      _addStep(raw, _firstStep, _choice, _relation);
    });
    raw.execute('UPDATE graph_log_control SET capture = 0');

    _addIntention(raw, _created, 'Новое намерение');
    raw.execute("UPDATE intentions SET title = 'Изменено' WHERE id = ?", [
      _created,
    ]);
    _addTag(raw, _secondTag, 'Работа');
    raw.execute("UPDATE tags SET name = 'Офис' WHERE id = ?", [_secondTag]);
    _addAssignment(raw, _secondTag, _created);
    raw.execute(
      'UPDATE tag_assignments SET intention_id = intention_id '
      'WHERE tag_id = ?',
      [_secondTag],
    );
    _addRelation(raw, _createdRelation, _source, _other);
    raw.execute('UPDATE long_term_relations SET priority = 2 WHERE id = ?', [
      _createdRelation,
    ]);
    raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
      _createdRelation,
    ]);
    raw.execute(
      'UPDATE daily_choice_path_steps SET long_term_relation_id = ? '
      'WHERE id = ?',
      [_secondRelation, _firstStep],
    );
    raw.execute('UPDATE daily_choices SET is_completed = 1 WHERE id = ?', [
      _choice,
    ]);
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_choice]);
    raw.execute('DELETE FROM tags WHERE id = ?', [_tag]);
    raw.execute('DELETE FROM intentions WHERE id = ?', [_created]);
    expect(_marks(raw), isEmpty);

    raw.execute('UPDATE graph_log_control SET capture = 1');
    _writeGraph(
      raw,
      () => raw.execute("UPDATE tags SET name = 'Дом' WHERE id = ?", [
        _secondTag,
      ]),
    );
    expect(_marks(raw), {('tag', _secondTag, 'update')});
  });

  test('позиции удалённых пакетов не используются повторно', () {
    // Сжатие удаляет все пакеты до нового снимка, включая последний.
    _addChangePackage(raw);
    _addChangePackage(raw);
    raw.execute('DELETE FROM graph_log_packages');

    _addChangePackage(raw);

    expect(raw.select('SELECT position FROM graph_log_packages'), [
      {'position': 3},
    ]);
  });

  test('пакет «сброс» удерживает свой снимок в реестре', () {
    _addSnapshot(raw, 'сброс');
    raw.execute('''
      INSERT INTO graph_log_packages (recorded_at, kind, snapshot_id)
      VALUES (1, 'reset', 1)
    ''');

    expect(
      () => raw.execute('DELETE FROM graph_snapshots'),
      throwsA(isA<sqlite.SqliteException>()),
    );

    raw.execute('DELETE FROM graph_log_packages');
    raw.execute('DELETE FROM graph_snapshots');
    expect(raw.select('SELECT * FROM graph_snapshots'), isEmpty);
  });

  test('отклоняет несогласованные пакеты и копии', () {
    _addSnapshot(raw, 'снимок');
    final facts = Uint8List.fromList([0x7b, 0x7d, 0x0a]);
    final invalidRows = <(String, String, List<Object?>)>[
      (
        'изменение без версии формата',
        'INSERT INTO graph_log_packages (recorded_at, kind, facts) '
            "VALUES (1, 'change', ?)",
        [facts],
      ),
      (
        'изменение без фактов',
        'INSERT INTO graph_log_packages (recorded_at, kind, format_version) '
            "VALUES (1, 'change', 1)",
        [],
      ),
      (
        'изменение со ссылкой на снимок',
        'INSERT INTO graph_log_packages '
            '(recorded_at, kind, format_version, facts, snapshot_id) '
            "VALUES (1, 'change', 1, ?, 1)",
        [facts],
      ),
      (
        'сброс с версией формата',
        'INSERT INTO graph_log_packages '
            '(recorded_at, kind, format_version, snapshot_id) '
            "VALUES (1, 'reset', 1, 1)",
        [],
      ),
      (
        'сброс без снимка',
        'INSERT INTO graph_log_packages (recorded_at, kind) '
            "VALUES (1, 'reset')",
        [],
      ),
      (
        'сброс с фактами',
        'INSERT INTO graph_log_packages '
            '(recorded_at, kind, facts, snapshot_id) '
            "VALUES (1, 'reset', ?, 1)",
        [facts],
      ),
      (
        'неизвестный вид пакета',
        'INSERT INTO graph_log_packages '
            '(recorded_at, kind, format_version, facts) '
            "VALUES (1, 'other', 1, ?)",
        [facts],
      ),
      (
        'копия без сводки и признака замены',
        'INSERT INTO graph_backups (position, kind, made_at, graph_replaced) '
            "VALUES (1, 'daily', 1, 0)",
        [],
      ),
      (
        'копия со сводкой и признаком замены',
        'INSERT INTO graph_backups '
            '(position, kind, made_at, graph_replaced, '
            'added_count, changed_count, deleted_count) '
            "VALUES (1, 'daily', 1, 1, 0, 0, 0)",
        [],
      ),
      (
        'копия с неполной сводкой',
        'INSERT INTO graph_backups '
            '(position, kind, made_at, graph_replaced, '
            'added_count, changed_count) '
            "VALUES (1, 'manual', 1, 0, 1, 0)",
        [],
      ),
      (
        'неизвестный вид копии',
        'INSERT INTO graph_backups '
            '(position, kind, made_at, graph_replaced, '
            'added_count, changed_count, deleted_count) '
            "VALUES (1, 'weekly', 1, 0, 0, 0, 0)",
        [],
      ),
    ];

    for (final (description, sql, parameters) in invalidRows) {
      expect(
        () => raw.execute(sql, parameters),
        throwsA(isA<sqlite.SqliteException>()),
        reason: description,
      );
    }
    expect(raw.select('SELECT * FROM graph_log_packages'), isEmpty);
    expect(raw.select('SELECT * FROM graph_backups'), isEmpty);

    raw.execute(
      'INSERT INTO graph_backups (position, kind, made_at, graph_replaced) '
      "VALUES (1, 'before_replacement', 1, 1)",
    );
    raw.execute(
      'INSERT INTO graph_backups '
      '(position, kind, made_at, graph_replaced, '
      'added_count, changed_count, deleted_count) '
      "VALUES (1, 'manual', 1, 0, 3, 2, 1)",
    );
    expect(raw.select('SELECT * FROM graph_backups'), hasLength(2));
  });
}

Set<_Mark> _marks(sqlite.Database db) => {
  for (final row in db.select('''
    SELECT 'tag' AS kind, tag_id AS entity, first_operation
    FROM graph_log_tag_marks
    UNION ALL
    SELECT 'intention', intention_id, first_operation
    FROM graph_log_intention_marks
    UNION ALL
    SELECT 'tagAssignment', tag_id || '/' || intention_id, first_operation
    FROM graph_log_tag_assignment_marks
    UNION ALL
    SELECT 'longTermRelation', long_term_relation_id, first_operation
    FROM graph_log_long_term_relation_marks
    UNION ALL
    SELECT 'dailyChoice', daily_choice_id, first_operation
    FROM graph_log_daily_choice_marks
  '''))
    (
      row['kind'] as String,
      row['entity'] as String,
      row['first_operation'] as String,
    ),
};

/// Строки таблиц графа и шагов пути.
List<Map<String, Object?>> _graphRows(sqlite.Database db) => [
  for (final table in [
    'tags',
    'intentions',
    'tag_assignments',
    'long_term_relations',
    'daily_choices',
    'daily_choice_path_steps',
  ])
    for (final row in db.select('SELECT * FROM $table ORDER BY rowid'))
      {'table': table, ...row},
];

/// Выполняет [write] так же, как единый путь записи графа: в одной точке
/// сохранения с признаком записи, снятым перед её подтверждением.
void _writeGraph(sqlite.Database db, void Function() write) {
  db
    ..execute('SAVEPOINT graph_write')
    ..execute('UPDATE graph_log_control SET writing = 1');
  write();
  db
    ..execute('UPDATE graph_log_control SET writing = 0')
    ..execute('RELEASE graph_write');
}

void _clearMarks(sqlite.Database db) {
  for (final table in [
    'graph_log_tag_marks',
    'graph_log_intention_marks',
    'graph_log_tag_assignment_marks',
    'graph_log_long_term_relation_marks',
    'graph_log_daily_choice_marks',
  ]) {
    db.execute('DELETE FROM $table');
  }
}

void _addIntention(sqlite.Database db, String id, String title) {
  db.execute(
    'INSERT INTO intentions (id, title, created_at, updated_at) '
    'VALUES (?, ?, 1, 1)',
    [id, title],
  );
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

void _addTag(sqlite.Database db, String id, String name) {
  db.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [id, name]);
}

void _addAssignment(sqlite.Database db, String tagId, String intentionId) {
  db.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagId, intentionId],
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

void _addChangePackage(sqlite.Database db) {
  db.execute(
    'INSERT INTO graph_log_packages (recorded_at, kind, format_version, facts) '
    "VALUES (1, 'change', 1, ?)",
    [
      Uint8List.fromList([0x7b, 0x7d, 0x0a]),
    ],
  );
}

void _addSnapshot(sqlite.Database db, String fileName) {
  db.execute(
    'INSERT INTO graph_snapshots '
    '(position, format_version, file_name, byte_size, checksum) '
    'VALUES (0, 1, ?, 20, zeroblob(32))',
    [fileName],
  );
}
