import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/data/local/sqlite_relation_integrity_functions.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
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

  test('регистрирует обязательные функции на production, in-memory и file-backed соединениях', () async {
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
        await _expectRelationIntegrityFunctions(database);
        await _expectTagNameFunctions(database);
      } finally {
        await database.close();
      }
    }
  });

  test('регистрирует функции связей и тегов на isolate-соединении', () async {
    final isolate = await spawnConfiguredInMemoryLocalDatabaseIsolate();
    addTearDown(isolate.shutdownAll);
    final database = AppDatabase(await isolate.connect());
    addTearDown(database.close);

    await _expectRelationIntegrityFunctions(database);
    await _expectTagNameFunctions(database);
  });

  test('открытие соединения не запускает аудит всего графа', () async {
    final trace = _StatementTrace();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        trace,
      ),
    );
    addTearDown(database.close);

    await database.open();

    expect(
      trace.statements.where(
        (statement) =>
            statement.operation == LocalDatabaseSqlOperation.select &&
            statement.statements.any(
              (sql) => sql.contains('FROM long_term_relations'),
            ),
      ),
      isEmpty,
    );
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
    await _expectTagNameFunctions(database);
  });

  test(
    'канонический setup заменяет fixture-функции с теми же именами',
    () async {
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: _replaceCanonicalFunctions),
      );
      addTearDown(database.close);

      final searchKey = await database
          .customSelect(
            "SELECT doable_title_search_key('Straße') AS search_key",
          )
          .getSingle();

      expect(searchKey.read<String>('search_key'), 'strasse');
      await _expectRelationIntegrityFunctions(database);
      await _expectTagNameFunctions(database);
    },
  );
}

Future<void> _expectRelationIntegrityFunctions(AppDatabase database) async {
  final row = await database
      .customSelect(
        '''
          SELECT
            $relationIdIntegrityFunctionName(CAST(? AS BLOB)) AS relation_id,
            $intentionIdIntegrityFunctionName(CAST(? AS BLOB)) AS intention_id,
            $relationDescriptionIntegrityFunctionName(
              CAST(? AS BLOB)
            ) AS description,
            $relationIdIntegrityFunctionName(
              CAST('не-uuid' AS BLOB)
            ) AS invalid_relation_id,
            $relationDescriptionIntegrityFunctionName(
              x'80'
            ) AS malformed_description
        ''',
        variables: [
          Variable.withString('018f0b5d-6b2e-7c80-8000-000000000001'),
          Variable.withString('018f0b5d-6b2e-7c80-8000-000000000002'),
          Variable.withString('Допустимое описание'),
        ],
      )
      .getSingle();

  expect(row.read<int>('relation_id'), 1);
  expect(row.read<int>('intention_id'), 1);
  expect(row.read<int>('description'), 1);
  expect(row.read<int>('invalid_relation_id'), 0);
  expect(row.read<int>('malformed_description'), 0);
}

Future<void> _expectTagNameFunctions(AppDatabase database) async {
  final row = await database.customSelect('''
    SELECT
      $tagNameValidFunctionName('Straße') AS valid,
      $tagNameKeyFunctionName('Straße') AS name_key,
      $tagNameValidFunctionName(' Straße') AS invalid,
      $tagNameKeyFunctionName(' Straße') AS invalid_key
  ''').getSingle();

  expect(row.read<int>('valid'), 1);
  expect(row.read<String>('name_key'), 'strasse');
  expect(row.read<int>('invalid'), 0);
  expect(row.readNullable<String>('invalid_key'), isNull);
}

void _registerFixtureFunction(sqlite.Database database) {
  database.createFunction(
    functionName: 'fixture_marker',
    argumentCount: const sqlite.AllowedArgumentCount(0),
    function: (_) => 'готово',
  );
}

void _replaceCanonicalFunctions(sqlite.Database database) {
  database
    ..createFunction(
      functionName: doableTitleSearchKeyFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (_) => 'fixture-implementation',
    )
    ..createFunction(
      functionName: relationIdIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (_) => 1,
    )
    ..createFunction(
      functionName: intentionIdIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (_) => 1,
    )
    ..createFunction(
      functionName: relationDescriptionIntegrityFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (_) => 1,
    )
    ..createFunction(
      functionName: tagNameValidFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (_) => 1,
    )
    ..createFunction(
      functionName: tagNameKeyFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (_) => 'fixture-implementation',
    );
}

final class _StatementTrace extends LocalDatabaseConnectionObserver {
  final statements = <LocalDatabaseSqlStatement>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.add(statement);
  }
}
