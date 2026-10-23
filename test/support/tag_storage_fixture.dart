import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'graph_seed.dart';
import 'tag_positions.dart';

String tagFixtureId(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

const firstTagNumber = 301;
const lastTagNumber = 302;

/// Назначения двух тегов намерениям обоих охватов.
void seedTagStorageFixture(sqlite.Database database) {
  seedRawGraph(database, () {
    _writeTagRecipientGraph(database);
    database.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
      tagFixtureId(firstTagNumber),
      'Дом',
      tagPositionKey(firstTagNumber),
    ]);
    database.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
      tagFixtureId(lastTagNumber),
      'Работа',
      tagPositionKey(lastTagNumber),
    ]);
    for (final number in [1, 2]) {
      database.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(number)],
      );
    }
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(lastTagNumber), tagFixtureId(3)],
    );
  });
}

void seedTagRecipientGraphFixture(sqlite.Database database) {
  seedRawGraph(database, () => _writeTagRecipientGraph(database));
}

void _writeTagRecipientGraph(sqlite.Database database) {
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

/// Большие воспроизводимые списки для измерения двух видов чтения.
/// Первое намерение получает чётные теги, третье — каждый третий тег;
/// при плотных получателях второе и четвёртое намерения получают все теги.
void seedLargeTagReadFixture(
  sqlite.Database database, {
  int tagCount = 1203,
  bool includeDenseRecipients = false,
}) {
  seedRawGraph(database, () {
    for (final number in [1, 2, 3, if (includeDenseRecipients) 4]) {
      database.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(number),
          'Намерение $number',
          0,
          number == 2 ? 1 : 0,
          number,
          number,
        ],
      );
    }
    for (var index = 0; index < tagCount; index++) {
      final id = tagFixtureId(10000 + index);
      database.execute(
        'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
        [
          id,
          'Тег ${index.toString().padLeft(5, '0')}',
          tagPositionKey(10000 + index),
        ],
      );
      for (final (number, assigned) in [
        (1, index.isEven),
        (3, index % 3 == 0),
        (2, includeDenseRecipients),
        (4, includeDenseRecipients),
      ]) {
        if (!assigned) continue;
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [id, tagFixtureId(number)],
        );
      }
    }
  });
}

/// Число назначений, которое создаёт [seedLargeTagReadFixture].
int largeTagReadFixtureAssignmentCount({
  required int tagCount,
  required bool includeDenseRecipients,
}) =>
    (tagCount + 1) ~/ 2 +
    (tagCount + 2) ~/ 3 +
    (includeDenseRecipients ? tagCount * 2 : 0);

/// Общий тег назначен каждому получателю, половина из них архивна;
/// сохраняемый тег назначен исходному намерению и тем же получателям.
void seedWidelyAssignedTagFixture(
  sqlite.Database database, {
  required int recipients,
}) {
  seedRawGraph(database, () {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(1), 'Исходное намерение', 0, 0, 1, 1],
    );
    for (final (number, name) in [
      (9000, 'Общий тег'),
      (9001, 'Сохранённый тег'),
    ]) {
      database.execute(
        'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
        [tagFixtureId(number), name, tagPositionKey(number)],
      );
    }
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(9001), tagFixtureId(1)],
    );
    for (var index = 0; index < recipients; index++) {
      final intentionId = tagFixtureId(10000 + index);
      final relationId = tagFixtureId(20000 + index);
      final archived = index.isOdd ? 1 : 0;
      database.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [intentionId, 'Получатель $index', 0, archived, index + 2, index + 2],
      );
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [relationId, tagFixtureId(1), intentionId, 'need', 2, archived],
      );
      for (final tagNumber in [9000, 9001]) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(tagNumber), intentionId],
        );
      }
    }
  });
}
