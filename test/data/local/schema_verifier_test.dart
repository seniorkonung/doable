import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('сохраняемая схема не ссылается на функции проверки связей', () async {
    final database = AppDatabase(openInMemoryLocalDatabase());
    addTearDown(database.close);

    final references = await database.customSelect('''
      SELECT name
      FROM sqlite_schema
      WHERE sql LIKE '%doable_relation_%'
    ''').get();

    expect(references, isEmpty);
  });

  group('raw-negative SQLite setup fixture', () {
    test('fixture collision не заменяет каноническую search-key function', () {
      final database = sqlite.sqlite3.openInMemory();
      addTearDown(database.close);
      _registerCollidingFixtureFunction(database);
      configureDoableSqliteConnection(database);
      database
        ..execute(_syntheticDependentSchema)
        ..execute("INSERT INTO synthetic_titles(title) VALUES ('Straße')");

      final searchKey = database
          .select('SELECT search_key FROM synthetic_titles')
          .single['search_key'];

      expect(searchKey, titleSearchKey('Straße'));
    });
  });
}

const _syntheticDependentSchema = '''
  CREATE TABLE synthetic_titles (
    title TEXT NOT NULL,
    search_key TEXT GENERATED ALWAYS AS (doable_title_search_key(title)) STORED
  )
''';

void _registerCollidingFixtureFunction(sqlite.Database database) {
  database.createFunction(
    functionName: doableTitleSearchKeyFunctionName,
    argumentCount: const sqlite.AllowedArgumentCount(1),
    deterministic: true,
    directOnly: false,
    function: (_) => 'fixture-implementation',
  );
}
