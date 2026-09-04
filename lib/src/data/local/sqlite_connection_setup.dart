import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart' as sqlite;

const doableTitleSearchKeyFunctionName = 'doable_title_search_key';

/// Регистрирует долговечную SQLite-функцию поискового ключа до работы Drift.
void configureDoableSqliteConnection(CommonDatabase database) {
  (database as sqlite.Database).createFunction(
    functionName: doableTitleSearchKeyFunctionName,
    argumentCount: const sqlite.AllowedArgumentCount(1),
    deterministic: true,
    directOnly: false,
    function: (arguments) => titleSearchKey(arguments.single as String),
  );
}

DatabaseSetup composeDoableSqliteConnectionSetup(DatabaseSetup? fixtureSetup) =>
    (database) {
      configureDoableSqliteConnection(database);
      fixtureSetup?.call(database);
    };
