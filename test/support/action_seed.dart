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
    db.execute(_insertPathItem, [
      id,
      position,
      intention,
      position == 0 ? null : path[position - 1],
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
    await database.customStatement(_insertPathItem, [
      id,
      position,
      intention,
      position == 0 ? null : path[position - 1],
    ]);
  }
}

const _insertAction = '''INSERT INTO actions
   (id, title, description, date, scheduled_hour, priority, is_completed,
    created_at, updated_at)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''';

const _insertPathItem = '''INSERT INTO action_path_items
   (action_id, position, intention_id, previous_intention_id)
   VALUES (?, ?, ?, ?)''';
