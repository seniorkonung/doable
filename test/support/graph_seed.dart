import 'package:doable/src/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Заполняет граф записями [write] в одной транзакции или точке сохранения
/// с выключенным захватом фактов: заполненные так строки в лог фактов не
/// попадают. Отказ записи откатывает и записи, и выключение захвата и
/// доходит до вызывающего кода без замены.
Future<void> seedGraph(AppDatabase database, Future<void> Function() write) =>
    database.transaction(() async {
      await database.customStatement(_disableCapture);
      await write();
      await database.customStatement(_enableCapture);
    });

/// [seedGraph] через низкоуровневое соединение `sqlite3`.
void seedRawGraph(sqlite.Database database, void Function() write) {
  database.execute('SAVEPOINT graph_seed');
  try {
    database.execute(_disableCapture);
    write();
    database
      ..execute(_enableCapture)
      ..execute('RELEASE graph_seed');
  } on Object {
    database
      ..execute('ROLLBACK TO graph_seed')
      ..execute('RELEASE graph_seed');
    rethrow;
  }
}

const _disableCapture = 'UPDATE graph_log_control SET capture = 0';
const _enableCapture = 'UPDATE graph_log_control SET capture = 1';
