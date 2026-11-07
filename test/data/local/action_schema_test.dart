import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';

const _health = '018f0b5d-6b2e-7c80-8000-000000000001';
const _sport = '018f0b5d-6b2e-7c80-8000-000000000002';
const _run = '018f0b5d-6b2e-7c80-8000-000000000003';
const _other = '018f0b5d-6b2e-7c80-8000-000000000004';
const _healthSport = '018f0b5d-6b2e-7c80-8000-000000000011';
const _sportRun = '018f0b5d-6b2e-7c80-8000-000000000012';
const _healthRun = '018f0b5d-6b2e-7c80-8000-000000000013';
const _recreated = '018f0b5d-6b2e-7c80-8000-000000000014';
const _reverse = '018f0b5d-6b2e-7c80-8000-000000000015';
const _action = '018f0b5d-6b2e-7c80-8000-000000000021';
const _secondAction = '018f0b5d-6b2e-7c80-8000-000000000022';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
    );
    await database.open();
    seedRawGraph(raw, () {
      for (final (id, title) in [
        (_health, 'Быть здоровым'),
        (_sport, 'Заниматься спортом'),
        (_run, 'Бегать'),
        (_other, 'Другое намерение'),
      ]) {
        raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) '
          'VALUES (?, ?, 1, 1)',
          [id, title],
        );
      }
      _addRelation(raw, _healthSport, _health, _sport, 'need');
      _addRelation(raw, _sportRun, _sport, _run, 'can');
      _addRelation(raw, _healthRun, _health, _run, 'need');
    });
  });

  tearDown(() => harness.dispose());

  test('сохраняет весь день, границы часа и все приоритеты и отклоняет '
      'недопустимые поля действия', () {
    seedRawGraph(raw, () => _addAction(raw, _action));

    for (final (hour, priority, isCompleted) in [
      (0, 1, 1),
      (23, 2, 0),
      (null, 3, 1),
      (12, 4, 0),
    ]) {
      seedRawGraph(
        raw,
        () => raw.execute(
          'UPDATE actions SET scheduled_hour = ?, priority = ?, '
          'is_completed = ?',
          [hour, priority, isCompleted],
        ),
      );
      expect(
        raw.select(
          'SELECT scheduled_hour, priority, is_completed FROM actions',
        ),
        [
          {
            'scheduled_hour': hour,
            'priority': priority,
            'is_completed': isCompleted,
          },
        ],
      );
    }
    final valid = _actionRows(raw);

    for (final (column, invalidValues) in [
      ('title', [null, '', 'Недопустимое\u0000название']),
      ('description', [' \n\t', 'Недопустимое\u0000описание']),
      ('date', [null, '2026-9-23', '2026-09-23T00:00', 20260923]),
      (
        'scheduled_hour',
        [
          -1,
          24,
          0.5,
          'весь день',
          Uint8List.fromList([0]),
        ],
      ),
      ('priority', [null, 0, 5, 1.5, 'P1']),
      ('is_completed', [null, 2, 'да']),
      ('created_at', [null, 'вчера']),
      ('updated_at', [null, 1.5]),
    ]) {
      for (final value in invalidValues) {
        expect(
          () => seedRawGraph(
            raw,
            () => raw.execute('UPDATE actions SET $column = ?', [value]),
          ),
          throwsA(isA<sqlite.SqliteException>()),
          reason: 'Недопустимое значение $column: $value.',
        );
      }
    }
    expect(_actionRows(raw), valid);
  });

  test('запрещает менять идентичность и последовательность создания', () {
    seedRawGraph(raw, () => _addAction(raw, _action));

    for (final column in ['id', 'creation_sequence']) {
      expect(
        () => seedRawGraph(
          raw,
          () => raw.execute('UPDATE actions SET $column = ?', [
            column == 'id' ? _secondAction : 100,
          ]),
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: column,
      );
    }
  });

  test('путь переживает удаление своих намерений и связей и удаляется '
      'вместе с действием', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport, _run]);
    });
    final path = _pathRows(raw);

    seedRawGraph(raw, () {
      raw.execute('DELETE FROM long_term_relations');
      raw.execute('DELETE FROM intentions WHERE id IN (?, ?)', [
        _health,
        _sport,
      ]);
    });
    expect(_pathRows(raw), path);

    seedRawGraph(raw, () => raw.execute('DELETE FROM actions'));
    expect(_pathRows(raw), isEmpty);
  });

  test('принимает строки пути только по порядку позиций без повторов', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPathItem(raw, _action, 0, _health, null, role: 'root');
      _addPathItem(raw, _action, 1, _sport, _health, role: 'intermediate');
    });

    for (final (description, position, intention, previous) in [
      ('корень с предыдущим намерением', 0, _run, _sport),
      ('пропуск позиции', 3, _run, _sport),
      ('чужое предыдущее намерение', 2, _run, _health),
      ('продолжение без предыдущего намерения', 2, _run, null),
      ('повтор намерения', 2, _health, _sport),
      ('отрицательная позиция', -1, _run, null),
    ]) {
      expect(
        () => seedRawGraph(
          raw,
          () => _addPathItem(
            raw,
            _action,
            position,
            intention,
            previous,
            role: position == 0 ? 'root' : 'terminal',
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: description,
      );
    }
    expect(
      () => seedRawGraph(
        raw,
        () => _addPathItem(raw, _other, 0, _run, null, role: 'single'),
      ),
      throwsA(isA<sqlite.SqliteException>()),
      reason: 'строка пути несуществующего действия',
    );

    seedRawGraph(
      raw,
      () => _addPathItem(raw, _action, 2, _run, _sport, role: 'terminal'),
    );
    expect(_pathOf(raw, _action), [_health, _sport, _run]);
  });

  test('принимает роль строки пути, только согласованную с позицией и ролью '
      'предыдущей позиции', () {
    seedRawGraph(raw, () => _addAction(raw, _action));

    for (final (description, path) in [
      ('корень с ролью промежуточного', [(_health, 'intermediate')]),
      ('корень с ролью конечного', [(_health, 'terminal')]),
      ('неизвестная роль', [(_health, 'leaf')]),
      ('продолжение с ролью корневого', [(_health, 'root'), (_sport, 'root')]),
      (
        'продолжение с ролью единственного',
        [(_health, 'root'), (_sport, 'single')],
      ),
      (
        'продолжение после конечного',
        [(_health, 'root'), (_sport, 'terminal'), (_run, 'terminal')],
      ),
      (
        'продолжение после единственного',
        [(_health, 'single'), (_sport, 'terminal')],
      ),
    ]) {
      expect(
        () => seedRawGraph(raw, () {
          for (final (position, (intention, role)) in path.indexed) {
            _addPathItem(
              raw,
              _action,
              position,
              intention,
              position == 0 ? null : path[position - 1].$1,
              role: role,
            );
          }
        }),
        throwsA(isA<sqlite.SqliteException>()),
        reason: description,
      );
      expect(_pathOf(raw, _action), isEmpty, reason: description);
    }

    seedRawGraph(raw, () => _addPath(raw, _action, [_health, _sport, _run]));
    expect(
      raw
          .select('SELECT role FROM action_path_items ORDER BY position')
          .map((row) => row['role']),
      ['root', 'intermediate', 'terminal'],
    );
  });

  test('отклоняет строку пути с копией ключа порядка, не совпадающей с '
      'действием', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      raw.execute('UPDATE actions SET scheduled_hour = 9');
    });
    final key = _orderKeyOf(raw, _action)!;

    for (final (description, wrong) in [
      (
        'чужая дата',
        (date: '2026-09-24', hour: key.hour, sequence: key.sequence),
      ),
      ('чужой час', (date: key.date, hour: 10, sequence: key.sequence)),
      (
        '«Весь день» у действия на час',
        (date: key.date, hour: -1, sequence: key.sequence),
      ),
      (
        'чужая последовательность',
        (date: key.date, hour: key.hour, sequence: key.sequence + 1),
      ),
    ]) {
      expect(
        () => seedRawGraph(
          raw,
          () => _addPathItem(
            raw,
            _action,
            0,
            _health,
            null,
            role: 'single',
            orderKey: wrong,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: description,
      );
    }
    expect(_pathOf(raw, _action), isEmpty);
  });

  test('изменение даты и часа действия переписывает копию ключа порядка в '
      'строках его пути', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport]);
      _addAction(raw, _secondAction);
      _addPath(raw, _secondAction, [_health]);
    });
    final untouched = _orderKeysOf(raw, _secondAction);

    for (final (date, hour) in [
      ('2026-09-30', 7),
      ('2026-09-30', null),
      ('2026-10-01', 23),
    ]) {
      seedRawGraph(
        raw,
        () => raw.execute(
          'UPDATE actions SET date = ?, scheduled_hour = ? WHERE id = ?',
          [date, hour, _action],
        ),
      );
      final key = _orderKeyOf(raw, _action)!;
      expect(key.hour, hour ?? -1);
      expect(_orderKeysOf(raw, _action), [key, key]);
    }
    expect(_orderKeysOf(raw, _secondAction), untouched);
  });

  test('отклоняет строку пути с неизвестным намерением и принимает '
      'намерение из надгробия', () {
    seedRawGraph(raw, () => _addAction(raw, _action));
    const unknown = '018f0b5d-6b2e-7c80-8000-0000000000ff';

    expect(
      () => seedRawGraph(
        raw,
        () => _addPathItem(raw, _action, 0, unknown, null, role: 'single'),
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    seedRawGraph(raw, () {
      raw.execute(
        "INSERT INTO deleted_intentions (intention_id, title) "
        "VALUES (?, 'Удалённое намерение')",
        [unknown],
      );
      _addPathItem(raw, _action, 0, unknown, null, role: 'single');
    });
    expect(_pathOf(raw, _action), [unknown]);
  });

  test('запрещает менять строки пути, кроме копии ключа порядка, и '
      'надгробия', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport]);
      _addAction(raw, _secondAction);
    });
    seedRawGraph(raw, () {
      raw.execute('DELETE FROM long_term_relations');
      raw.execute('DELETE FROM intentions WHERE id = ?', [_sport]);
    });

    for (final statement in [
      "UPDATE action_path_items SET action_id = '$_secondAction'",
      'UPDATE action_path_items SET position = position + 10',
      'UPDATE action_path_items SET intention_id = '
          "'$_other' WHERE position = 1",
      'UPDATE action_path_items SET previous_intention_id = NULL',
      "UPDATE action_path_items SET role = 'single'",
      'UPDATE action_path_items SET order_sequence = order_sequence + 1',
      "UPDATE deleted_intentions SET title = 'Другое название'",
      "UPDATE deleted_relation_pairs SET type = 'can'",
    ]) {
      expect(
        () => seedRawGraph(raw, () => raw.execute(statement)),
        throwsA(isA<sqlite.SqliteException>()),
        reason: statement,
      );
    }
  });

  test('создаёт надгробие намерения с названием только для намерения пути', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport]);
      raw.execute('DELETE FROM long_term_relations');
      raw.execute('DELETE FROM intentions WHERE id IN (?, ?)', [
        _sport,
        _other,
      ]);
    });

    expect(raw.select('SELECT * FROM deleted_intentions'), [
      {'intention_id': _sport, 'title': 'Заниматься спортом'},
    ]);
  });

  test('создаёт надгробие пары с типом только для звена пути в его '
      'направлении, а новая связь пары снимает его', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport, _run]);
      raw.execute('DELETE FROM long_term_relations');
    });

    expect(_pairTombstones(raw), {
      (_health, _sport, 'need'),
      (_sport, _run, 'can'),
    });

    seedRawGraph(
      raw,
      () => _addRelation(raw, _recreated, _sport, _run, 'need'),
    );
    expect(_pairTombstones(raw), {(_health, _sport, 'need')});

    seedRawGraph(
      raw,
      () => _addRelation(raw, _reverse, _sport, _health, 'can'),
    );
    expect(_pairTombstones(raw), {
      (_health, _sport, 'need'),
    }, reason: 'связь обратного направления — другая пара');
  });

  test('отклоняет надгробие существующего намерения и пары и намерение '
      'с надгробием', () {
    for (final (description, statement, arguments) in [
      (
        'надгробие существующего намерения',
        "INSERT INTO deleted_intentions (intention_id, title) VALUES (?, 'X')",
        [_health],
      ),
      (
        'надгробие пары с существующей связью',
        'INSERT INTO deleted_relation_pairs '
            "(source_intention_id, related_intention_id, type) "
            "VALUES (?, ?, 'need')",
        [_health, _sport],
      ),
    ]) {
      expect(
        () => seedRawGraph(raw, () => raw.execute(statement, arguments)),
        throwsA(isA<sqlite.SqliteException>()),
        reason: description,
      );
    }

    const deleted = '018f0b5d-6b2e-7c80-8000-0000000000fe';
    seedRawGraph(
      raw,
      () => raw.execute(
        "INSERT INTO deleted_intentions (intention_id, title) VALUES (?, 'X')",
        [deleted],
      ),
    );
    expect(
      () => seedRawGraph(
        raw,
        () => raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) '
          "VALUES (?, 'Воскрешённое', 1, 1)",
          [deleted],
        ),
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });

  test('снимает надгробия, на которые больше не ссылается ни один путь', () {
    seedRawGraph(raw, () {
      _addAction(raw, _action);
      _addPath(raw, _action, [_health, _sport, _run]);
      _addAction(raw, _secondAction);
      _addPath(raw, _secondAction, [_health, _sport]);
      raw.execute('DELETE FROM long_term_relations');
      raw.execute('DELETE FROM intentions WHERE id IN (?, ?)', [_sport, _run]);
    });
    expect(_intentionTombstones(raw), {_sport, _run});
    expect(_pairTombstones(raw), {
      (_health, _sport, 'need'),
      (_sport, _run, 'can'),
    });

    seedRawGraph(
      raw,
      () => raw.execute('DELETE FROM actions WHERE id = ?', [_action]),
    );
    expect(_intentionTombstones(raw), {_sport});
    expect(_pairTombstones(raw), {(_health, _sport, 'need')});

    seedRawGraph(
      raw,
      () => raw.execute('DELETE FROM action_path_items WHERE action_id = ?', [
        _secondAction,
      ]),
    );
    expect(_intentionTombstones(raw), isEmpty);
    expect(_pairTombstones(raw), isEmpty);
  });
}

void _addRelation(
  sqlite.Database db,
  String id,
  String source,
  String related,
  String type,
) {
  db.execute(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id, type, priority, created_at, updated_at)
       VALUES (?, ?, ?, ?, 1, 0, 0)''',
    [id, source, related, type],
  );
}

void _addAction(sqlite.Database db, String id) {
  db.execute(
    '''INSERT INTO actions
       (id, title, date, priority, is_completed, created_at, updated_at)
       VALUES (?, 'Пробежка', '2026-09-23', 4, 0, 1, 1)''',
    [id],
  );
}

void _addPath(sqlite.Database db, String actionId, List<String> intentions) {
  for (final (position, intention) in intentions.indexed) {
    _addPathItem(
      db,
      actionId,
      position,
      intention,
      position == 0 ? null : intentions[position - 1],
      role: switch (position) {
        0 when intentions.length == 1 => 'single',
        0 => 'root',
        _ when position == intentions.length - 1 => 'terminal',
        _ => 'intermediate',
      },
    );
  }
}

typedef _OrderKey = ({String date, int hour, int sequence});

/// Вставляет строку пути. Копия ключа порядка по умолчанию берётся из
/// действия, а у несуществующего действия — произвольная.
void _addPathItem(
  sqlite.Database db,
  String actionId,
  int position,
  String intention,
  String? previous, {
  required String role,
  _OrderKey? orderKey,
}) {
  final key =
      orderKey ??
      _orderKeyOf(db, actionId) ??
      (date: '2026-09-23', hour: -1, sequence: 1);
  db.execute(
    '''INSERT INTO action_path_items
       (action_id, position, intention_id, previous_intention_id, role,
        order_date, order_hour, order_sequence)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      actionId,
      position,
      intention,
      previous,
      role,
      key.date,
      key.hour,
      key.sequence,
    ],
  );
}

_OrderKey? _orderKeyOf(sqlite.Database db, String actionId) {
  final rows = db.select(
    'SELECT date, COALESCE(scheduled_hour, -1) AS hour, creation_sequence '
    'FROM actions WHERE id = ?',
    [actionId],
  );
  if (rows.isEmpty) return null;
  final row = rows.single;
  return (
    date: row['date'] as String,
    hour: row['hour'] as int,
    sequence: row['creation_sequence'] as int,
  );
}

List<_OrderKey> _orderKeysOf(sqlite.Database db, String actionId) => [
  for (final row in db.select(
    'SELECT order_date, order_hour, order_sequence FROM action_path_items '
    'WHERE action_id = ? ORDER BY position',
    [actionId],
  ))
    (
      date: row['order_date'] as String,
      hour: row['order_hour'] as int,
      sequence: row['order_sequence'] as int,
    ),
];

List<Map<String, Object?>> _actionRows(sqlite.Database db) => [
  for (final row in db.select('SELECT * FROM actions')) {...row},
];

List<Map<String, Object?>> _pathRows(sqlite.Database db) => [
  for (final row in db.select(
    'SELECT * FROM action_path_items ORDER BY action_id, position',
  ))
    {...row},
];

List<String> _pathOf(sqlite.Database db, String actionId) => [
  for (final row in db.select(
    'SELECT intention_id FROM action_path_items '
    'WHERE action_id = ? ORDER BY position',
    [actionId],
  ))
    row['intention_id'] as String,
];

Set<String> _intentionTombstones(sqlite.Database db) => {
  for (final row in db.select('SELECT intention_id FROM deleted_intentions'))
    row['intention_id'] as String,
};

Set<(String, String, String)> _pairTombstones(sqlite.Database db) => {
  for (final row in db.select('SELECT * FROM deleted_relation_pairs'))
    (
      row['source_intention_id'] as String,
      row['related_intention_id'] as String,
      row['type'] as String,
    ),
};
