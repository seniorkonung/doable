import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporaryDirectory;
  late Directory applicationDocumentsDirectory;

  setUpAll(() {
    final testRoot = Directory.systemTemp.createTempSync(
      'doable_database_connection_',
    );
    temporaryDirectory = Directory.fromUri(testRoot.uri.resolve('cache/'))
      ..createSync();
    applicationDocumentsDirectory = Directory.fromUri(
      testRoot.uri.resolve('app_flutter/'),
    )..createSync();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return switch (call.method) {
            'getTemporaryDirectory' => temporaryDirectory.path,
            'getApplicationDocumentsDirectory' =>
              applicationDocumentsDirectory.path,
            _ => throw UnsupportedError('Неожиданный вызов path_provider'),
          };
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    applicationDocumentsDirectory.parent.deleteSync(recursive: true);
  });

  test('production locator разрешает SQLite-файл в app_flutter', () {
    final documentsDirectory = Directory(
      '/data/user/0/software.doable/app_flutter',
    );

    final sqliteFiles = AndroidProductionDatabaseConnection.sqliteFilesIn(
      documentsDirectory,
    );

    expect(AndroidProductionDatabaseConnection.databaseName, 'doable');
    expect(sqliteFiles.map((file) => file.path), [
      '/data/user/0/software.doable/app_flutter/doable.sqlite',
      '/data/user/0/software.doable/app_flutter/doable.sqlite-wal',
      '/data/user/0/software.doable/app_flutter/doable.sqlite-shm',
    ]);
  });

  test(
    'production connection создаёт SQLite-файл через настроенное соединение',
    () async {
      final database = AppDatabase(openAndroidProductionDatabaseConnection());
      addTearDown(database.close);
      await database.open();

      expect(
        File.fromUri(applicationDocumentsDirectory.uri.resolve('doable.sqlite'))
            .existsSync(),
        isTrue,
      );
    },
  );

  test(
    'AppDatabase принимает настроенное platform-neutral соединение',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());

      await database.close();
    },
  );

  test('регистрирует search-key function на production, in-memory и file-backed соединениях', () async {
    final connections = <ConfiguredLocalDatabaseConnection Function()>[
      openAndroidProductionDatabaseConnection,
      openInMemoryLocalDatabase,
      () => openFileBackedLocalDatabase(
        File.fromUri(temporaryDirectory.uri.resolve('file-backed.sqlite')),
      ),
    ];

    for (final connection in connections) {
      final database = AppDatabase(connection());
      try {
        final row = await database
            .customSelect(
              'SELECT doable_title_search_key(?) AS search_key',
              variables: [Variable.withString('Straße')],
            )
            .getSingle();

        expect(row.read<String>('search_key'), titleSearchKey('Straße'));
      } finally {
        await database.close();
      }
    }
  });

  test('объединяет search-key setup с fixture setup', () async {
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: _registerFixtureFunction),
    );
    addTearDown(database.close);

    final fixture = await database
        .customSelect('SELECT fixture_marker() AS value')
        .getSingle();
    final searchKey = await database
        .customSelect("SELECT doable_title_search_key('Straße') AS search_key")
        .getSingle();

    expect(fixture.read<String>('value'), 'готово');
    expect(searchKey.read<String>('search_key'), 'strasse');
  });

  test(
    'канонический search-key setup заменяет fixture-реализацию с тем же именем',
    () async {
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: _replaceSearchKeyFunction),
      );
      addTearDown(database.close);

      final searchKey = await database
          .customSelect(
            "SELECT doable_title_search_key('Straße') AS search_key",
          )
          .getSingle();

      expect(searchKey.read<String>('search_key'), 'strasse');
    },
  );
}

void _registerFixtureFunction(sqlite.Database database) {
  database.createFunction(
    functionName: 'fixture_marker',
    argumentCount: const sqlite.AllowedArgumentCount(0),
    function: (_) => 'готово',
  );
}

void _replaceSearchKeyFunction(sqlite.Database database) {
  database.createFunction(
    functionName: doableTitleSearchKeyFunctionName,
    argumentCount: const sqlite.AllowedArgumentCount(1),
    deterministic: true,
    directOnly: false,
    function: (_) => 'fixture-implementation',
  );
}
