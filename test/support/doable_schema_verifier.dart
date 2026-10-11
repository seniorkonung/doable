import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:drift_dev/api/migrations_native.dart';

/// Проверяет схему Doable через единственный настроенный drift_dev verifier.
Future<void> verifyDoableDatabaseSchema(AppDatabase database) {
  // drift_dev создаёт отдельную in-memory reference connection и передаёт ей
  // setup до создания ожидаемой schema:
  // https://drift.simonbinder.eu/migrations/tests/#verifying-a-database-schema-at-runtime
  return database.validateDatabaseSchema(
    options: const ValidationOptions(validateDropped: true),
    setup: configureDoableSqliteConnection,
  );
}
