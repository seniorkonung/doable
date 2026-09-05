import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Проверяет схему Doable через единственный настроенный drift_dev verifier.
Future<void> verifyDoableDatabaseSchema(AppDatabase database) =>
    _verifyDoableDatabaseSchema(database);

/// Выполняет проверочный SQL на reference connection, создаваемом drift_dev.
///
/// Нужен только raw contract-тестам. Обычные verification harnesses не
/// принимают и не передают SQLite setup.
Future<String> readDoableVerifierReferenceSearchKey(
  AppDatabase database,
  String title,
) async {
  late String searchKey;
  await _verifyDoableDatabaseSchema(
    database,
    onReferenceConnection: (reference) {
      searchKey =
          reference.select('SELECT doable_title_search_key(?) AS search_key', [
                title,
              ]).single['search_key']
              as String;
    },
  );
  return searchKey;
}

Future<void> _verifyDoableDatabaseSchema(
  AppDatabase database, {
  void Function(sqlite.Database reference)? onReferenceConnection,
}) {
  // drift_dev создаёт отдельную in-memory reference connection и передаёт ей
  // setup до создания ожидаемой schema:
  // https://drift.simonbinder.eu/migrations/tests/#verifying-a-database-schema-at-runtime
  return database.validateDatabaseSchema(
    options: const ValidationOptions(validateDropped: true),
    setup: (reference) {
      configureDoableSqliteConnection(reference);
      onReferenceConnection?.call(reference);
    },
  );
}
