@Tags(['flutter_process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/doable_schema_verifier.dart';
import '../../../support/local_database_harness.dart';

const _workerStopPointEnvironment = 'DOABLE_MIGRATION_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_MIGRATION_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_MIGRATION_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_MIGRATION_WORKER_READY';

void main() {
  // Отказ в самом конце создания, когда все объекты схемы уже созданы:
  // откат обязан убрать их все, поэтому более ранняя точка ничего не добавляет.
  test(
    'отказ создания после всех объектов и проверок схемы не оставляет '
    'частичной схемы, сохраняет файл и допускает повторное создание',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      _markEmptyStorageFile(harness.databaseFile);
      final failureInterceptor = _InitialSchemaCreationFailureInterceptor();

      final failedResult = await harness.open(observer: failureInterceptor);

      expect(failedResult, isA<LocalDataUnexpectedFailure>());
      expect(failureInterceptor.didInjectFailure, isTrue);
      expect(failureInterceptor.didCloseExecutor, isTrue);

      await harness.closePersistenceObjectGraph();
      await _expectStorageWithoutUserSchema(harness.databaseFile);
      _expectStorageFileKept(harness.databaseFile);

      await _expectCurrentSchemaSurvivesReopen(harness);
    },
  );

  for (final stopPoint in _MigrationProcessStopPoint.values) {
    test('остановка процесса ${stopPoint.testDescription} создания схемы '
        'оставляет либо целую схему, либо файл без схемы', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      _markEmptyStorageFile(harness.databaseFile);

      await _runMigrationWorkerUntilStopPoint(harness, stopPoint);

      if (stopPoint.isAfterCommit) {
        _expectCurrentSchemaContract(harness.databaseFile);
      } else {
        await _expectStorageWithoutUserSchema(harness.databaseFile);
      }
      _expectStorageFileKept(harness.databaseFile);

      await _expectCurrentSchemaSurvivesReopen(harness);
    });
  }
}

Map<String, String?> _schemaContract(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    return {
      for (final row in database.select('''
        SELECT type, name, sql FROM sqlite_schema
        WHERE name NOT LIKE 'sqlite_%'
        ORDER BY type, name
      '''))
        '${row['type']}:${row['name']}': row['sql'] as String?,
    };
  } finally {
    database.close();
  }
}

Future<void> _runMigrationWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  _MigrationProcessStopPoint stopPoint,
) async {
  final flutterExecutable = _findFlutterExecutable();
  final workerPath = File.fromUri(
    Directory.current.uri.resolve('test/support/migration_process_worker.dart'),
  ).path;
  final process = await Process.start(
    flutterExecutable,
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      _workerStopPointEnvironment: stopPoint.environmentValue,
      _workerDatabasePathEnvironment: harness.databaseFile.path,
    },
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final ready = Completer<int>();
  final startedPidPattern = RegExp('$_workerStartedMarker:(\\d+)');
  final readyPidPattern = RegExp('$_workerReadyMarker:(\\d+)');
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedWorkerPid;

  process.stdout.transform(utf8.decoder).listen((chunk) {
    stdoutBuffer.write(chunk);
    final output = stdoutBuffer.toString();
    final startedMatch = startedPidPattern.firstMatch(output);
    if (startedMatch != null) {
      startedWorkerPid = int.parse(startedMatch.group(1)!);
    }
    final match = readyPidPattern.firstMatch(output);
    if (match != null && !ready.isCompleted) {
      ready.complete(int.parse(match.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((exitCode) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс миграции завершился с кодом $exitCode '
            'до точки ${stopPoint.environmentValue}.\n'
            'stdout:\n$stdoutBuffer\n'
            'stderr:\n$stderrBuffer',
          ),
        );
      }
    }),
  );

  var workerWasKilled = false;
  try {
    final workerPid = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс миграции не достиг точки '
        '${stopPoint.environmentValue}.\n'
        'stdout:\n$stdoutBuffer\n'
        'stderr:\n$stderrBuffer',
      ),
    );
    workerWasKilled = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(
      workerWasKilled,
      isTrue,
      reason: 'Не удалось принудительно завершить процесс миграции.',
    );
  } finally {
    if (!workerWasKilled) {
      final workerPid = startedWorkerPid;
      if (workerPid != null) {
        Process.killPid(workerPid, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
    }
  }
  final exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
  await Future.wait([stdoutDone.future, stderrDone.future]);

  expect(exitCode, isNot(0));
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Не удалось найти Flutter SDK от Platform.resolvedExecutable.',
      );
    }
    directory = parent;
  }
}

enum _MigrationProcessStopPoint {
  beforeCommit(
    environmentValue: 'before_commit',
    testDescription: 'до подтверждения',
  ),
  afterCommit(
    environmentValue: 'after_commit',
    testDescription: 'после подтверждения',
  );

  const _MigrationProcessStopPoint({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;

  bool get isAfterCommit => this == afterCommit;
}

Future<void> _expectStorageWithoutUserSchema(File databaseFile) async {
  final executor = NativeDatabase(
    databaseFile,
    setup: composeDoableSqliteConnectionSetup(null),
  );
  addTearDown(executor.close);
  await executor.ensureOpen(const _SchemaInspectionExecutorUser());

  final schemaObjects = await executor.runSelect('''
      SELECT name FROM sqlite_schema
      WHERE type IN ('table', 'index', 'trigger', 'view')
        AND name NOT LIKE 'sqlite_%'
    ''', const []);
  final version = await executor.runSelect('PRAGMA user_version', const []);

  expect(schemaObjects, isEmpty);
  expect(version.single['user_version'], 0);
}

/// Метка файла в заголовке SQLite: не является объектом схемы, но теряется,
/// если файл хранилища удалён или создан заново.
const _storageFileMarker = 0x444F4142;

void _markEmptyStorageFile(File databaseFile) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    database.execute('PRAGMA application_id = $_storageFileMarker');
  } finally {
    database.close();
  }
}

void _expectStorageFileKept(File databaseFile) {
  expect(databaseFile.existsSync(), isTrue);
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('PRAGMA application_id').single['application_id'],
      _storageFileMarker,
      reason: 'Файл хранилища не должен удаляться или создаваться заново.',
    );
  } finally {
    database.close();
  }
}

void _expectCurrentSchemaContract(File databaseFile) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );
    expect(
      database.select(
        "SELECT name FROM sqlite_schema WHERE type = 'table' "
        "AND name = 'tag_assignments'",
      ),
      hasLength(1),
    );
    expect(
      database.select(
        "SELECT name FROM sqlite_schema "
        "WHERE tbl_name = 'favorite_intentions'",
      ),
      isEmpty,
    );
  } finally {
    database.close();
  }
}

/// Следующий запуск создаёт или открывает схему на том же файле, а повторное
/// открытие после закрытия видит тот же подтверждённый контракт схемы.
Future<void> _expectCurrentSchemaSurvivesReopen(
  LocalDatabaseHarness harness,
) async {
  final createdDatabase = await harness.openReadyDatabase();
  await expectLater(verifyDoableDatabaseSchema(createdDatabase), completes);
  await expectLater(
    verifyIntentionTitlesFtsIntegrity(createdDatabase),
    completes,
  );
  expect(
    await createdDatabase.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await createdDatabase.customSelect('PRAGMA foreign_keys').getSingle())
        .read<int>('foreign_keys'),
    1,
  );
  await harness.closePersistenceObjectGraph();
  final createdSchema = _schemaContract(harness.databaseFile);
  _expectStorageFileKept(harness.databaseFile);

  final reopenedDatabase = await harness.openReadyDatabase();
  await expectLater(verifyDoableDatabaseSchema(reopenedDatabase), completes);
  final version = await reopenedDatabase
      .customSelect('PRAGMA user_version')
      .getSingle();
  expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  await harness.closePersistenceObjectGraph();
  expect(_schemaContract(harness.databaseFile), createdSchema);
  _expectStorageFileKept(harness.databaseFile);
}

final class _InjectedInitialCreationFailure implements Exception {
  const _InjectedInitialCreationFailure();
}

/// Отказывает на маркере версии — последней записи создания схемы.
final class _InitialSchemaCreationFailureInterceptor
    extends LocalDatabaseConnectionObserver {
  var didInjectFailure = false;
  var didCloseExecutor = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (didInjectFailure ||
        statement.operation != LocalDatabaseSqlOperation.custom ||
        !_isVersionMarker(statement.statements.single)) {
      return;
    }

    didInjectFailure = true;
    throw const _InjectedInitialCreationFailure();
  }

  @override
  void beforeClose() {
    didCloseExecutor = true;
  }

  // Маркер версии — последняя запись создания: к этому моменту все объекты
  // схемы созданы, а проверки внешних ключей и поискового индекса пройдены.
  bool _isVersionMarker(String statement) {
    return RegExp(
      '^PRAGMA user_version\\s*=\\s*${AppDatabase.currentSchemaVersion};?\$',
      caseSensitive: false,
    ).hasMatch(statement.trim());
  }
}

final class _SchemaInspectionExecutorUser implements QueryExecutorUser {
  const _SchemaInspectionExecutorUser();

  @override
  int get schemaVersion => 0;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
