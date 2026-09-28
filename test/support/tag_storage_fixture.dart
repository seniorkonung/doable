import 'package:sqlite3/sqlite3.dart' as sqlite;

String tagFixtureId(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

const firstTagNumber = 301;
const lastTagNumber = 302;

void seedTagStorageFixture(sqlite.Database database) {
  seedTagRecipientGraphFixture(database);
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

void seedTagRecipientGraphFixture(sqlite.Database database) {
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

/// Навигация различает одноимённые намерения, собственный архив связи
/// и связь дневного пути; непомеченный сосед не входит в выдачу.
void seedTagNavigationFixture(
  sqlite.Database database, {
  required int extraPairsPerScope,
}) {
  seedTagRecipientGraphFixture(database);
  database.execute('UPDATE intentions SET title = ? WHERE id = ?', [
    'Одинаковое намерение',
    tagFixtureId(1),
  ]);
  database.execute('UPDATE intentions SET title = ? WHERE id = ?', [
    'Непомеченный сосед',
    tagFixtureId(3),
  ]);
  database.execute(
    'INSERT INTO intentions (id, title, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    [tagFixtureId(4), 'Одинаковое намерение', 'Описание 4', 104, 204],
  );
  database.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
    [tagFixtureId(103), tagFixtureId(1), tagFixtureId(4), 'can', 3, 1],
  );
  for (final (number, name) in [
    (firstTagNumber, 'Дом 🏷️'),
    (303, 'Без назначений'),
    (304, 'Только в архиве'),
  ]) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  for (final (column, number) in [
    ('intention_id', 1),
    ('long_term_relation_id', 101),
    ('intention_id', 4),
    ('intention_id', 2),
    ('long_term_relation_id', 102),
    ('long_term_relation_id', 103),
  ]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(number)],
    );
  }
  database.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(304), tagFixtureId(2)],
  );
  for (var index = 0; index < extraPairsPerScope; index++) {
    for (final archived in [0, 1]) {
      final intentionId = tagFixtureId(1000 + archived * 100 + index);
      final relationId = tagFixtureId(2000 + archived * 100 + index);
      database.execute(
        'INSERT INTO intentions (id, title, description, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          intentionId,
          'Получатель $archived/$index',
          'Описание $archived/$index',
          archived,
          1000 + index,
          1000 + index,
        ],
      );
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [relationId, tagFixtureId(1), intentionId, 'need', 2, archived],
      );
      for (final (column, id) in [
        ('intention_id', intentionId),
        ('long_term_relation_id', relationId),
      ]) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), id],
        );
      }
    }
  }
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

/// Входящая помеченная связь, свободные получатели и непомеченная связь
/// позволяют проверить границы каскада и физического удаления в навигации.
void seedTagNavigationLifecycleFixture(sqlite.Database database) {
  seedTagNavigationFixture(database, extraPairsPerScope: 0);
  database.execute(
    'INSERT INTO intentions (id, title, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    [tagFixtureId(5), 'Отдельное намерение', 'Описание 5', 105, 205],
  );
  for (final (number, source, related) in [
    (104, 3, 1),
    (105, 3, 4),
    (106, 4, 3),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(source),
        tagFixtureId(related),
        'can',
        3,
      ],
    );
  }
  for (final (column, number) in [
    ('long_term_relation_id', 104),
    ('long_term_relation_id', 106),
    ('intention_id', 5),
  ]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(number)],
    );
  }
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(lastTagNumber),
    'Работа',
  ]);
  for (final (column, number) in [
    ('intention_id', 3),
    ('long_term_relation_id', 103),
  ]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
      [tagFixtureId(lastTagNumber), tagFixtureId(number)],
    );
  }
}

/// Большие воспроизводимые списки для измерения двух видов чтения.
void seedLargeTagReadFixture(
  sqlite.Database database, {
  int tagCount = 1203,
  bool includeDenseRecipients = false,
}) {
  database.execute('BEGIN');
  try {
    for (final number in [1, 2, 3]) {
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
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(101), tagFixtureId(1), tagFixtureId(3), 'need', 2, 0],
    );
    if (includeDenseRecipients) {
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(102), tagFixtureId(3), tagFixtureId(1), 'need', 2, 0],
      );
    }
    for (var index = 0; index < tagCount; index++) {
      final id = tagFixtureId(10000 + index);
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        id,
        'Тег ${index.toString().padLeft(5, '0')}',
      ]);
      if (index.isEven) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [id, tagFixtureId(1)],
        );
      }
      if (index % 3 == 0) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [id, tagFixtureId(101)],
        );
      }
      if (includeDenseRecipients) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [id, tagFixtureId(2)],
        );
        database.execute(
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [id, tagFixtureId(102)],
        );
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
}

/// Один тег назначен каждому получателю двух видов, половина из них архивна.
void seedWidelyAssignedTagFixture(
  sqlite.Database database, {
  int recipientPairs = 1200,
}) {
  database.execute('BEGIN');
  try {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(1), 'Исходное намерение', 0, 0, 1, 1],
    );
    for (final (number, name) in [
      (9000, 'Общий тег'),
      (9001, 'Сохранённый тег'),
    ]) {
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        name,
      ]);
    }
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(9001), tagFixtureId(1)],
    );
    for (var index = 0; index < recipientPairs; index++) {
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
      database.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(9000), intentionId],
      );
      database.execute(
        'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
        [tagFixtureId(9000), relationId],
      );
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
}

/// Смешанная выдача с редким архивом и таким же числом посторонних назначений.
/// Архивная связь каждого двадцатого получателя имеет активных участников,
/// если сам получатель не входит в архив каждого сорокового намерения.
void seedLargeTaggedEntitiesFixture(
  sqlite.Database database, {
  required int recipientPairs,
}) {
  database.execute('BEGIN');
  try {
    database.execute(
      'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [tagFixtureId(1), 'Исходное намерение', 1, 1],
    );
    for (final (number, name) in [
      (9000, 'Выбранный тег'),
      (9001, 'Другой тег'),
    ]) {
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        name,
      ]);
    }
    for (var index = 0; index < recipientPairs; index++) {
      final intentionId = tagFixtureId(100000 + index);
      final relationId = tagFixtureId(200000 + index);
      database.execute(
        'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [
          intentionId,
          'Получатель $index',
          index % 40 == 0 ? 1 : 0,
          index + 2,
          index + 2,
        ],
      );
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [
          relationId,
          tagFixtureId(1),
          intentionId,
          index.isEven ? 'need' : 'can',
          2,
          index % 20 == 0 ? 1 : 0,
        ],
      );
      // Назначения постороннего тега чередуются с выбранным, но не входят
      // ни в основной запрос, ни в аудит ссылок выбранного тега.
      for (final (column, id) in [
        ('intention_id', intentionId),
        ('long_term_relation_id', relationId),
      ]) {
        for (final tagNumber in [9000, 9001]) {
          database.execute(
            'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
            [tagFixtureId(tagNumber), id],
          );
        }
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
}
