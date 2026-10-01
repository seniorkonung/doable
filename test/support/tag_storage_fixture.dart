import 'package:sqlite3/sqlite3.dart' as sqlite;

String tagFixtureId(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

const firstTagNumber = 301;
const lastTagNumber = 302;

/// Посторонний тег фикстуры жизненного цикла навигации.
const restTagNumber = 306;

/// Назначения двух тегов намерениям обоих охватов.
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

/// Навигация различает одноимённые намерения; назначения другого тега
/// чередуются с выбранным, но, как и непомеченный сосед, не входят в выдачу.
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
    (lastTagNumber, 'Работа'),
  ]) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  for (final (tagNumber, intentionNumber) in [
    (firstTagNumber, 1),
    (lastTagNumber, 1),
    (firstTagNumber, 4),
    (firstTagNumber, 2),
    (lastTagNumber, 2),
    (lastTagNumber, 4),
  ]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(tagNumber), tagFixtureId(intentionNumber)],
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
      for (final tagNumber in [firstTagNumber, lastTagNumber]) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(tagNumber), intentionId],
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

/// Отдельное намерение, связи без назначений и назначения других тегов
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
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(restTagNumber),
    'Отдых',
  ]);
  for (final (tagNumber, intentionNumber) in [
    (restTagNumber, 3),
    (restTagNumber, 5),
    (firstTagNumber, 5),
    (lastTagNumber, 3),
    (lastTagNumber, 5),
  ]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(tagNumber), tagFixtureId(intentionNumber)],
    );
  }
}

/// Большие воспроизводимые списки для измерения двух видов чтения.
/// Первое намерение получает чётные теги, третье — каждый третий тег;
/// при плотных получателях второе и четвёртое намерения получают все теги.
void seedLargeTagReadFixture(
  sqlite.Database database, {
  int tagCount = 1203,
  bool includeDenseRecipients = false,
}) {
  database.execute('BEGIN');
  try {
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
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        id,
        'Тег ${index.toString().padLeft(5, '0')}',
      ]);
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
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
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
  int recipients = 2400,
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
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
}

/// Смешанная выдача с редким архивом и таким же числом посторонних
/// назначений. На каждую пару приходятся основной получатель, архивный
/// у каждой сороковой пары, и дополнительный, архивный только у двадцатой
/// пары из каждых сорока. Выбранный и другой теги назначены обоим.
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
      final primary = _largeTaggedPrimary(index);
      final counterpart = _largeTaggedCounterpart(index);
      for (final recipient in [primary, counterpart]) {
        database.execute(
          'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [
            recipient.id,
            'Получатель ${recipient.title}',
            recipient.archived ? 1 : 0,
            index + 2,
            index + 2,
          ],
        );
      }
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(300000 + index),
          tagFixtureId(1),
          primary.id,
          index.isEven ? 'need' : 'can',
          2,
          index % 20 == 0 ? 1 : 0,
        ],
      );
      // Назначения постороннего тега чередуются с выбранным, но не входят
      // ни в основной запрос, ни в аудит ссылок выбранного тега.
      for (final recipient in [primary, counterpart]) {
        for (final tagNumber in [9000, 9001]) {
          database.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tagNumber), recipient.id],
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

/// Получатели охвата из [seedLargeTaggedEntitiesFixture] в порядке назначения
/// выбранного тега вместе с порядковым номером среди всех его назначений.
List<(String id, int ordinal)> largeTaggedIntentions(
  int recipientPairs, {
  required bool archived,
}) => [
  for (var index = 0; index < recipientPairs; index++)
    for (final (offset, recipient) in [
      (0, _largeTaggedPrimary(index)),
      (1, _largeTaggedCounterpart(index)),
    ])
      if (recipient.archived == archived) (recipient.id, index * 2 + offset),
];

typedef _LargeTaggedRecipient = ({String id, String title, bool archived});

_LargeTaggedRecipient _largeTaggedPrimary(int index) => (
  id: tagFixtureId(100000 + index),
  title: '$index',
  archived: index % 40 == 0,
);

_LargeTaggedRecipient _largeTaggedCounterpart(int index) => (
  id: tagFixtureId(200000 + index),
  title: '$index/2',
  archived: index % 40 == 20,
);
