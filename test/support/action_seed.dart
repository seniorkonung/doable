import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Идентификатор сущности теста по номеру в той же форме, что у настоящих.
String seedUuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

/// Идентификатор намерения, заполненного с номером [number].
IntentionId seedIntentionId(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;

/// Идентификатор действия, заполненного с номером [number].
ActionId seedActionId(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

/// Намерение без связей. Вызывать внутри `seedRawGraph`.
void seedIntention(sqlite.Database db, String id, String title) {
  db.execute(
    'INSERT INTO intentions (id, title, created_at, updated_at) '
    'VALUES (?, ?, 1, 1)',
    [id, title],
  );
}

/// Активная связь «нужно». Вызывать внутри `seedRawGraph`.
void seedRelation(
  sqlite.Database db,
  String id,
  String source,
  String related,
) {
  db.execute(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id, type, priority,
        created_at, updated_at)
       VALUES (?, ?, ?, 'need', 1, 1, 1)''',
    [id, source, related],
  );
}

/// Действие с путём [path] от корневого намерения к конечному. Время
/// создания и изменения — [timestamp] микросекунд. Вызывать внутри
/// `seedRawGraph`.
void seedAction(
  sqlite.Database db, {
  required String id,
  required List<String> path,
  String title = 'Пробежка',
  String? description,
  String date = '2026-10-08',
  int? hour,
  int priority = 4,
  bool isCompleted = false,
  int timestamp = 1,
}) {
  db.execute(_insertAction, [
    id,
    title,
    description,
    date,
    hour,
    priority,
    isCompleted ? 1 : 0,
    timestamp,
    timestamp,
  ]);
  for (final (position, intention) in path.indexed) {
    db.execute(insertActionPathItem, [
      id,
      position,
      intention,
      position == 0 ? null : path[position - 1],
      actionPathRole(position, path.length),
    ]);
  }
}

/// [seedAction] через соединение базы приложения. Вызывать внутри
/// `seedGraph` или `recordGraphChange`.
Future<void> insertAction(
  AppDatabase database, {
  required String id,
  required List<String> path,
  String title = 'Пробежка',
  String date = '2026-10-08',
  int timestamp = 1,
}) async {
  await database.customStatement(_insertAction, [
    id,
    title,
    null,
    date,
    null,
    4,
    0,
    timestamp,
    timestamp,
  ]);
  for (final (position, intention) in path.indexed) {
    await database.customStatement(insertActionPathItem, [
      id,
      position,
      intention,
      position == 0 ? null : path[position - 1],
      actionPathRole(position, path.length),
    ]);
  }
}

const _insertAction = '''INSERT INTO actions
   (id, title, description, date, scheduled_hour, priority, is_completed,
    created_at, updated_at)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''';

/// Вставка строки пути уже вставленного действия. Аргументы: действие,
/// позиция, намерение, предыдущее намерение и роль из [actionPathRole];
/// копию ключа порядка вставка берёт из строки действия.
const insertActionPathItem = '''INSERT INTO action_path_items
   (action_id, position, intention_id, previous_intention_id, role,
    order_date, order_hour, order_sequence)
   SELECT ?1, ?2, ?3, ?4, ?5,
          date, COALESCE(scheduled_hour, -1), creation_sequence
   FROM actions WHERE id = ?1''';

/// Хранимая роль строки на позиции [position] пути из [length] намерений.
String actionPathRole(int position, int length) => switch (position) {
  0 when length == 1 => 'single',
  0 => 'root',
  _ when position == length - 1 => 'terminal',
  _ => 'intermediate',
};
