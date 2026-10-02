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
