import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/database_connection.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'production connection создаёт SQLite-файл через QueryExecutor',
    () async {
      final QueryExecutor connection =
          openAndroidProductionDatabaseConnection();

      expect(await connection.ensureOpen(_TestQueryExecutorUser()), isTrue);

      expect(
        File.fromUri(applicationDocumentsDirectory.uri.resolve('doable.sqlite'))
            .existsSync(),
        isTrue,
      );
      await AppDatabase(connection).close();
    },
  );

  test(
    'AppDatabase принимает QueryExecutor без platform-specific параметров',
    () async {
      final database = AppDatabase(NativeDatabase.memory());

      await database.close();
    },
  );
}

final class _TestQueryExecutorUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
