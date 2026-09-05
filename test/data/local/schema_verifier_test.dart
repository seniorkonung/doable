import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/doable_schema_verifier.dart';

void main() {
  test(
    'Doable verifier проверяет schema через настроенную reference connection',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      addTearDown(database.close);

      await expectLater(verifyDoableDatabaseSchema(database), completes);

      final referenceSearchKey = await readDoableVerifierReferenceSearchKey(
        database,
        'Straße',
      );

      expect(referenceSearchKey, titleSearchKey('Straße'));
    },
  );

  group('raw-negative SQLite setup fixture', () {
    test(
      'без канонической регистрации synthetic dependent schema не создаётся',
      () {
        final database = sqlite.sqlite3.openInMemory();
        addTearDown(database.close);

        expect(
          () => database.execute(_syntheticDependentSchema),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );

    test(
      'без канонической регистрации synthetic dependent schema не изменяется',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'doable_raw_negative_sqlite_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final databaseFile = File('${directory.path}/synthetic.sqlite');

        final configuredDatabase = sqlite.sqlite3.open(databaseFile.path);
        try {
          configureDoableSqliteConnection(configuredDatabase);
          configuredDatabase.execute(_syntheticDependentSchema);
        } finally {
          configuredDatabase.close();
        }

        final unconfiguredDatabase = sqlite.sqlite3.open(databaseFile.path);
        try {
          expect(
            () => unconfiguredDatabase.execute(
              "INSERT INTO synthetic_titles(title) VALUES ('Straße')",
            ),
            throwsA(isA<sqlite.SqliteException>()),
          );
          expect(
            unconfiguredDatabase.select('SELECT * FROM synthetic_titles'),
            isEmpty,
          );
        } finally {
          unconfiguredDatabase.close();
        }
      },
    );

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
