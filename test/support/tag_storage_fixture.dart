import 'package:sqlite3/sqlite3.dart' as sqlite;

String tagFixtureId(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

const firstTagNumber = 301;
const lastTagNumber = 302;

void seedTagStorageFixture(sqlite.Database database) {
  for (final (number, archived) in [(1, 0), (2, 1), (3, 0)]) {
    database.execute(
      'INSERT INTO intentions (id, title, description, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        'Намерение $number',
        'Описание $number',
        1,
        archived,
        100 + number,
        200 + number,
      ],
    );
  }
  for (final (number, related, archived) in [(101, 3, 0), (102, 2, 1)]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(1),
        tagFixtureId(related),
        'need',
        2,
        archived,
      ],
    );
  }
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [tagFixtureId(201), tagFixtureId(1), tagFixtureId(3), '2026-09-25', 1],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [tagFixtureId(202), tagFixtureId(201), tagFixtureId(101)],
  );
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(firstTagNumber),
    'Дом',
  ]);
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(lastTagNumber),
    'Работа',
  ]);
  for (final number in [1, 2]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(number)],
    );
  }
  for (final number in [101, 102]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(number)],
    );
  }
  database.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(lastTagNumber), tagFixtureId(3)],
  );
}

Map<String, List<List<Object?>>> retainedTagFixtureGraph(sqlite.Database db) =>
    {
      for (final table in [
        'intentions',
        'intention_titles_fts',
        'long_term_relations',
        'daily_choices',
        'daily_choice_path_steps',
      ])
        table: db
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => row.values.toList())
            .toList(),
    };
