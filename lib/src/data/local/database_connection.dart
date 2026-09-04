import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

import 'sqlite_connection_setup.dart';

export 'sqlite_connection_setup.dart'
    show
        composeDoableSqliteConnectionSetup,
        configureDoableSqliteConnection,
        doableTitleSearchKeyFunctionName;

abstract final class AndroidProductionDatabaseConnection {
  static const databaseName = 'doable';
  static const databaseFileName = '$databaseName.sqlite';

  static File databaseFileIn(Directory applicationDocumentsDirectory) =>
      File.fromUri(applicationDocumentsDirectory.uri.resolve(databaseFileName));

  static List<File> sqliteFilesIn(Directory applicationDocumentsDirectory) {
    final databaseFile = databaseFileIn(applicationDocumentsDirectory);
    return [
      databaseFile,
      File('${databaseFile.path}-wal'),
      File('${databaseFile.path}-shm'),
    ];
  }
}

QueryExecutor openAndroidProductionDatabaseConnection() => driftDatabase(
  name: AndroidProductionDatabaseConnection.databaseName,
  native: const DriftNativeOptions(setup: configureDoableSqliteConnection),
);

QueryExecutor openInMemoryLocalDatabase({DatabaseSetup? setup}) =>
    NativeDatabase.memory(setup: composeDoableSqliteConnectionSetup(setup));

QueryExecutor openFileBackedLocalDatabase(
  File databaseFile, {
  DatabaseSetup? setup,
}) => NativeDatabase(
  databaseFile,
  setup: composeDoableSqliteConnectionSetup(setup),
);
