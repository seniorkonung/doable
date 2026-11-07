import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/graph_fact_capture.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Заполняет граф записями [write] в одной транзакции или точке сохранения
/// с выключенным захватом фактов: заполненные так строки в лог фактов не
/// попадают. Отказ записи откатывает и записи, и выключение захвата и
/// доходит до вызывающего кода без замены. Без помощника база отклоняет
/// прямую запись в таблицы графа, пока захват включён.
Future<void> seedGraph(AppDatabase database, Future<void> Function() write) =>
    database.transaction(() async {
      await database.customStatement(_disableCapture);
      await write();
      await database.customStatement(_enableCapture);
    });

/// Записывает [write] в граф так же, как единый путь записи графа: одной
/// транзакцией с признаком записи, а отметки триггеров превращает в пакет
/// «изменение» лога фактов с моментом записи [recordedAt]. Так в лог
/// попадают записи, которые команды графа не создают, например действия.
/// Репозиторий о пакете не знает: его ревизия и наблюдатели не меняются.
Future<void> recordGraphChange(
  AppDatabase database,
  Future<void> Function() write, {
  required DateTime recordedAt,
}) => database.transaction(() async {
  await database.customStatement(_startWriting);
  await write();
  final facts = await GraphFactCapture(database).takeFacts();
  await database
      .into(database.graphLogPackages)
      .insert(
        GraphLogPackagesCompanion.insert(
          recordedAt: recordedAt.microsecondsSinceEpoch,
          kind: 'change',
          formatVersion: Value(GraphFormatVersion.current.number),
          facts: Value(GraphFormatCodec.encodePackage(facts)),
        ),
      );
  await database.customStatement(_stopWriting);
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
const _startWriting = 'UPDATE graph_log_control SET writing = 1';
const _stopWriting = 'UPDATE graph_log_control SET writing = 0';
