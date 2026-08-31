import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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

QueryExecutor openAndroidProductionDatabaseConnection() =>
    driftDatabase(name: AndroidProductionDatabaseConnection.databaseName);
