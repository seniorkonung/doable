import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Сохраняет отметку избранного намерения строкой хранилища с местом
/// [position] в едином порядке. Защита схемы действует: недопустимая строка
/// отклоняется.
void storeFavoriteMark(
  sqlite.Database database, {
  required String intentionId,
  required int position,
}) {
  database.execute(
    'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
    [intentionId, position],
  );
}

/// Сохраняет отметку с местом, которое схема отклоняет, — повреждение
/// сохранённых данных, недостижимое через приложение. Проверка `CHECK`
/// отключается только на время записи этой строки.
void storeFavoriteMarkWithInvalidPosition(
  sqlite.Database database, {
  required String intentionId,
  required Object position,
}) {
  database.execute('PRAGMA ignore_check_constraints = ON');
  try {
    database.execute(
      'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
      [intentionId, position],
    );
  } finally {
    database.execute('PRAGMA ignore_check_constraints = OFF');
  }
}

/// Сохраняет место без существующего намерения — повреждение сохранённых
/// данных избранного, недостижимое через приложение. Проверка внешних ключей
/// отключается только на время записи этой строки; вызывается вне транзакции.
void storeFavoritePlaceWithoutIntention(
  sqlite.Database database, {
  required String intentionId,
  required int position,
}) {
  database.execute('PRAGMA foreign_keys = OFF');
  try {
    database.execute(
      'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
      [intentionId, position],
    );
  } finally {
    database.execute('PRAGMA foreign_keys = ON');
  }
}

/// Снимает защиту схемы с сохранённых данных избранного: таблица отметок
/// заменяется копией без первичного ключа, уникальности места, проверки места
/// и внешнего ключа с прежними строками. После этого [storeFavoriteMark]
/// записывает неоднозначный порядок и вторую отметку одного намерения —
/// повреждения, недостижимые через приложение.
void removeFavoriteSchemaProtection(sqlite.Database database) {
  database.execute(
    'ALTER TABLE favorite_intentions RENAME TO protected_favorite_intentions',
  );
  database.execute(
    'CREATE TABLE favorite_intentions (intention_id TEXT, position INTEGER)',
  );
  database.execute(
    'INSERT INTO favorite_intentions (intention_id, position) '
    'SELECT intention_id, position FROM protected_favorite_intentions',
  );
  database.execute('DROP TABLE protected_favorite_intentions');
}

/// Снимает отметку избранного намерения удалением её строки.
void removeFavoriteMark(
  sqlite.Database database, {
  required String intentionId,
}) {
  database.execute('DELETE FROM favorite_intentions WHERE intention_id = ?', [
    intentionId,
  ]);
}

/// Сохранённые отметки избранного — идентификатор намерения и его место —
/// в порядке мест.
List<(String, int)> storedFavoriteMarks(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT intention_id, position FROM favorite_intentions ORDER BY position',
  ))
    (row['intention_id'] as String, row['position'] as int),
];

/// Идентификатор избранного намерения большой фикстуры по его номеру.
String largeFavoriteFixtureId(int index) =>
    _largeFavoriteFixtureUuid(_largeFavoriteIntentionBase + index);

/// Строка большой фикстуры, ожидаемая в списке избранных намерений.
typedef LargeFavoriteFixtureRow = ({
  String id,
  String title,
  bool isActionReady,
  int activeRelationCount,
});

/// Большой воспроизводимый список избранного для измерения чтения целиком.
///
/// Места не следуют ни номерам, ни времени создания, ни названиям и идут с
/// пропусками. При положительном [archivedEvery] каждое такое по счёту
/// намерение архивировано. Каждое третье активное избранное намерение имеет
/// одну активную связь, каждое шестое — две. Каждое десятое намерение
/// получает неотмеченного соседа, который в список не входит.
void seedLargeFavoriteFixture(
  sqlite.Database database, {
  required int count,
  int archivedEvery = 0,
}) {
  if (count.gcd(_largeFavoritePlaceStep) != 1) {
    throw ArgumentError.value(count, 'count', 'Места не образуют порядок.');
  }
  database.execute('BEGIN');
  try {
    void insertIntention(
      int number,
      String title, {
      bool isActionReady = false,
      bool isArchived = false,
    }) => database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        _largeFavoriteFixtureUuid(number),
        title,
        isActionReady ? 1 : 0,
        isArchived ? 1 : 0,
        number,
        number,
      ],
    );

    for (final hub in _largeFavoriteHubs) {
      insertIntention(hub, 'Сосед $hub');
    }
    for (var index = 0; index < count; index++) {
      final isArchived = _isLargeFavoriteArchived(index, archivedEvery);
      insertIntention(
        _largeFavoriteIntentionBase + index,
        _largeFavoriteTitle(index),
        isActionReady: index.isEven,
        isArchived: isArchived,
      );
      if (index % 10 == 0) {
        insertIntention(
          _largeFavoriteUnmarkedBase + index,
          _largeFavoriteTitle(index),
        );
      }
      storeFavoriteMark(
        database,
        intentionId: largeFavoriteFixtureId(index),
        position: _largeFavoritePlace(index, count),
      );
      final relationCount = isArchived ? 0 : _largeFavoriteRelations(index);
      for (var relation = 0; relation < relationCount; relation++) {
        database.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, '
          'related_intention_id, type, priority, is_archived) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            _largeFavoriteFixtureUuid(
              _largeFavoriteRelationBase + index * 2 + relation,
            ),
            largeFavoriteFixtureId(index),
            _largeFavoriteFixtureUuid(_largeFavoriteHubs[relation]),
            'need',
            2,
            0,
          ],
        );
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  }
}

/// Активные избранные намерения, которые создаёт [seedLargeFavoriteFixture],
/// в порядке мест.
List<LargeFavoriteFixtureRow> largeFavoriteFixtureActiveRows({
  required int count,
  int archivedEvery = 0,
}) {
  final indexes =
      [
        for (var index = 0; index < count; index++)
          if (!_isLargeFavoriteArchived(index, archivedEvery)) index,
      ]..sort(
        (a, b) => _largeFavoritePlace(a, count) - _largeFavoritePlace(b, count),
      );
  return [
    for (final index in indexes)
      (
        id: largeFavoriteFixtureId(index),
        title: _largeFavoriteTitle(index),
        isActionReady: index.isEven,
        activeRelationCount: _largeFavoriteRelations(index),
      ),
  ];
}

/// Число архивированных избранных намерений большой фикстуры.
int largeFavoriteFixtureArchivedCount({
  required int count,
  int archivedEvery = 0,
}) => [
  for (var index = 0; index < count; index++)
    if (_isLargeFavoriteArchived(index, archivedEvery)) index,
].length;

const _largeFavoriteHubs = [90001, 90002];
const _largeFavoriteIntentionBase = 100000;
const _largeFavoriteRelationBase = 200000;
const _largeFavoriteUnmarkedBase = 300000;
const _largeFavoritePlaceStep = 7919;

String _largeFavoriteFixtureUuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

/// Название не уникально: каждое седьмое намерение — тёзка соседа.
String _largeFavoriteTitle(int index) =>
    'Избранное ${(index - index % 7 ~/ 6).toString().padLeft(5, '0')}';

int _largeFavoritePlace(int index, int count) =>
    index * _largeFavoritePlaceStep % count * 2 + 1;

bool _isLargeFavoriteArchived(int index, int archivedEvery) =>
    archivedEvery > 0 && index % archivedEvery == archivedEvery - 1;

int _largeFavoriteRelations(int index) => switch (index % 6) {
  0 => 2,
  3 => 1,
  _ => 0,
};
