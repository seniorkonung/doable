import 'package:doable/src/data/local/app_database.dart'
    show LocalDatabaseConnectionObserver, LocalDatabaseSqlStatement;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Существующий hook настроенного соединения наблюдает реальные записи,
/// включая RETURNING через путь чтения, и прерывает неподтверждённую запись.
final class IntentionCreationStorageObserver
    extends LocalDatabaseConnectionObserver {
  IntentionCreationStorageObserver({required this.snapshotGraph});

  /// Сценарий определяет состав проверяемого графа; observer отвечает только
  /// за фиксацию состояния в точке отказа соединения.
  final Map<String, List<List<Object?>>> Function(sqlite.Database)
  snapshotGraph;

  late sqlite.Database connection;
  var _observing = false;
  var _fail = false;
  ({bool inTransaction, Map<String, List<List<Object?>>> graph})? faultPoint;
  static final _table = RegExp(
    r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|REPLACE\s+INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+"?(\w+)"?',
    caseSensitive: false,
  );

  void observeCreation({bool fail = false}) {
    _observing = true;
    _fail = fail;
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_observing) return;
    final tables = <String>[];
    for (final sql in statement.statements) {
      final prepared = connection.prepareMultiple(sql);
      try {
        for (final query in prepared) {
          if (!query.isReadOnly) {
            tables.add(_table.firstMatch(query.sql)?.group(1) ?? query.sql);
          }
        }
      } finally {
        for (final query in prepared) {
          query.close();
        }
      }
    }
    if (_fail && tables.contains('favorite_intentions')) {
      _fail = false;
      faultPoint = (
        inTransaction: !connection.autocommit,
        graph: snapshotGraph(connection),
      );
      throw sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'Управляемый отказ после полного начального состояния',
      );
    }
  }
}
