import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _stopPointEnvironment = 'DOABLE_MIGRATION_STOP_POINT';
const _databasePathEnvironment = 'DOABLE_MIGRATION_DATABASE_PATH';
const _startedMarker = 'DOABLE_MIGRATION_WORKER_STARTED';
const _readyMarker = 'DOABLE_MIGRATION_WORKER_READY';

void main() {
  test('дочерний процесс останавливается в заданной точке миграции', () async {
    stdout.writeln('$_startedMarker:$pid');
    await stdout.flush();
    final databasePath = Platform.environment[_databasePathEnvironment];
    if (databasePath == null || databasePath.isEmpty) {
      throw StateError('Не задан путь к файлу мигрируемой базы данных.');
    }
    final stopPoint = _MigrationStopPoint.parse(
      Platform.environment[_stopPointEnvironment],
    );
    final observer = _MigrationStopObserver(stopPoint);
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(File(databasePath)),
        observer,
      ),
    );

    try {
      await database.open();
      if (stopPoint == _MigrationStopPoint.afterCommit) {
        await _reportReadyAndWait();
      }
    } finally {
      await database.close();
    }
  }, timeout: Timeout.none);
}

final class _MigrationStopObserver extends LocalDatabaseConnectionObserver {
  const _MigrationStopObserver(this.stopPoint);

  final _MigrationStopPoint stopPoint;

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if (stopPoint != _MigrationStopPoint.beforeCommit ||
        statement.operation != LocalDatabaseSqlOperation.custom) {
      return;
    }
    final versionMarker = RegExp(
      '^PRAGMA user_version\\s*=\\s*${AppDatabase.currentSchemaVersion};?\$',
      caseSensitive: false,
    );
    if (!statement.statements.any(
      (sql) => versionMarker.hasMatch(sql.trim()),
    )) {
      return;
    }

    // Маркер версии — последняя запись внутри транзакции перед её commit.
    await _reportReadyAndWait();
  }
}

Future<Never> _reportReadyAndWait() async {
  stdout.writeln('$_readyMarker:$pid');
  await stdout.flush();
  await Completer<void>().future;
  throw StateError('Недостижимое завершение ожидания прерывания процесса.');
}

enum _MigrationStopPoint {
  beforeCommit,
  afterCommit;

  static _MigrationStopPoint parse(String? value) => switch (value) {
    'before_commit' => beforeCommit,
    'after_commit' => afterCommit,
    _ => throw StateError('Неизвестная точка остановки миграции: $value.'),
  };
}
