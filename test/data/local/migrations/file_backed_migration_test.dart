import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/doable_schema_verifier.dart';
import '../../../support/local_database_harness.dart';
import '../../../support/schema_v1_fixture.dart';

const _activeIntentionId = '018f0b5d-6b2e-7c80-8000-000000000311';
const _archivedIntentionId = '018f0b5d-6b2e-7c80-8000-000000000312';
const _workerStopPointEnvironment = 'DOABLE_MIGRATION_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_MIGRATION_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_MIGRATION_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_MIGRATION_WORKER_READY';

void main() {
  test('прерванное первичное создание не оставляет schema objects и допускает повтор', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final failureInterceptor = _InitialSchemaCreationFailureInterceptor();

    final failedResult = await harness.open(observer: failureInterceptor);

    expect(failedResult, isA<LocalDataUnexpectedFailure>());
    expect(failureInterceptor.didInjectFailure, isTrue);
    expect(failureInterceptor.didCloseExecutor, isTrue);

    await harness.closePersistenceObjectGraph();
    await _expectStorageWithoutUserSchema(harness.databaseFile);

    final reopenedDatabase = await harness.openReadyDatabase();
    final version = await reopenedDatabase
        .customSelect('PRAGMA user_version')
        .getSingle();
    final foreignKeys = await reopenedDatabase
        .customSelect('PRAGMA foreign_keys')
        .getSingle();

    expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
    expect(foreignKeys.read<int>('foreign_keys'), 1);
    await expectLater(
      verifyIntentionTitlesFtsIntegrity(reopenedDatabase),
      completes,
    );
  });

  test('файловая миграция с внедрённым отказом оставляет целую схему после повторного открытия', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    await createSchemaV1Fixture(
      harness.databaseFile,
      seed: _seedPublishedIntentions,
    );
    final failureInterceptor = _Schema1To2FailureInterceptor();

    final failedResult = await harness.open(observer: failureInterceptor);

    expect(failedResult, isA<LocalDataUnexpectedFailure>());
    expect(failureInterceptor.didInjectFailure, isTrue);

    await harness.closePersistenceObjectGraph();
    _expectPublishedIntentions(
      harness.databaseFile,
      expectedSchemaVersion: publishedIntentionSchemaVersion,
      hasRelationSchema: false,
    );

    final reopenedDatabase = await harness.openReadyDatabase();
    await expectLater(
      verifyIntentionTitlesFtsIntegrity(reopenedDatabase),
      completes,
    );
    await expectLater(verifyDoableDatabaseSchema(reopenedDatabase), completes);
    await harness.closePersistenceObjectGraph();

    _expectPublishedIntentions(
      harness.databaseFile,
      expectedSchemaVersion: AppDatabase.currentSchemaVersion,
      hasRelationSchema: true,
    );
  });

  test(
    'успешная миграция сохраняет намерения после повторного открытия',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      await createSchemaV1Fixture(
        harness.databaseFile,
        seed: _seedPublishedIntentions,
      );

      final migratedDatabase = await harness.openReadyDatabase();
      await expectLater(
        verifyDoableDatabaseSchema(migratedDatabase),
        completes,
      );
      await harness.closePersistenceObjectGraph();
      _expectPublishedIntentions(
        harness.databaseFile,
        expectedSchemaVersion: AppDatabase.currentSchemaVersion,
        hasRelationSchema: true,
      );

      final reopenedDatabase = await harness.openReadyDatabase();
      await expectLater(
        verifyDoableDatabaseSchema(reopenedDatabase),
        completes,
      );
      await harness.closePersistenceObjectGraph();
      _expectPublishedIntentions(
        harness.databaseFile,
        expectedSchemaVersion: AppDatabase.currentSchemaVersion,
        hasRelationSchema: true,
      );
    },
  );

  for (final stopPoint in _MigrationProcessStopPoint.values) {
    test(
      'принудительное завершение ${stopPoint.testDescription} сохраняет целое хранилище',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        await createSchemaV1Fixture(
          harness.databaseFile,
          seed: _seedPublishedIntentions,
        );

        await _runMigrationWorkerUntilStopPoint(harness, stopPoint);

        _expectPublishedIntentions(
          harness.databaseFile,
          expectedSchemaVersion: stopPoint.expectedInterruptedVersion,
          hasRelationSchema: stopPoint.isAfterCommit,
        );

        final recoveredDatabase = await harness.openReadyDatabase();
        await expectLater(
          verifyDoableDatabaseSchema(recoveredDatabase),
          completes,
        );
        await harness.closePersistenceObjectGraph();
        _expectPublishedIntentions(
          harness.databaseFile,
          expectedSchemaVersion: AppDatabase.currentSchemaVersion,
          hasRelationSchema: true,
        );
      },
    );
  }
}

void _seedPublishedIntentions(sqlite.Database database) {
  database.execute('''
    INSERT INTO intentions (
      id,
      title,
      description,
      is_action_ready,
      is_archived,
      created_at,
      updated_at
    ) VALUES
      (
        '$_activeIntentionId',
        'Straße',
        '  Точный текст
без нормализации  ',
        1,
        0,
        1704067200000000,
        1704153600000000
      ),
      (
        '$_archivedIntentionId',
        'Архивное намерение',
        NULL,
        0,
        1,
        1704240000000000,
        1704326400000000
      )
  ''');
}

void _expectPublishedIntentions(
  File databaseFile, {
  required int expectedSchemaVersion,
  required bool hasRelationSchema,
}) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('PRAGMA user_version').single['user_version'],
      expectedSchemaVersion,
    );
    expect(
      database
          .select('''
            SELECT
              id,
              title,
              title_search_key,
              description,
              is_action_ready,
              is_archived,
              created_at,
              updated_at
            FROM intentions
            ORDER BY id
          ''')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
      [
        {
          'id': _activeIntentionId,
          'title': 'Straße',
          'title_search_key': 'strasse',
          'description': '  Точный текст\nбез нормализации  ',
          'is_action_ready': 1,
          'is_archived': 0,
          'created_at': 1704067200000000,
          'updated_at': 1704153600000000,
        },
        {
          'id': _archivedIntentionId,
          'title': 'Архивное намерение',
          'title_search_key': 'архивное намерение',
          'description': null,
          'is_action_ready': 0,
          'is_archived': 1,
          'created_at': 1704240000000000,
          'updated_at': 1704326400000000,
        },
      ],
    );
    expect(
      database.select('''
        SELECT rowid
        FROM intention_titles_fts
        WHERE title_search_key MATCH '"strasse"'
      '''),
      hasLength(1),
    );
    expect(
      database
          .select('SELECT id FROM intentions WHERE is_archived = 0 ORDER BY id')
          .single['id'],
      _activeIntentionId,
    );
    expect(
      database
          .select('SELECT id FROM intentions WHERE is_archived = 1 ORDER BY id')
          .single['id'],
      _archivedIntentionId,
    );

    final relationSchema = database.select('''
      SELECT name
      FROM sqlite_schema
      WHERE name = 'long_term_relations'
    ''');
    expect(relationSchema, hasRelationSchema ? hasLength(1) : isEmpty);
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
    testDescription: 'до подтверждения миграции',
    expectedInterruptedVersion: publishedIntentionSchemaVersion,
  ),
  afterCommit(
    environmentValue: 'after_commit',
    testDescription: 'после подтверждения миграции',
    expectedInterruptedVersion: AppDatabase.currentSchemaVersion,
  );

  const _MigrationProcessStopPoint({
    required this.environmentValue,
    required this.testDescription,
    required this.expectedInterruptedVersion,
  });

  final String environmentValue;
  final String testDescription;
  final int expectedInterruptedVersion;

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

final class _InjectedInitialCreationFailure implements Exception {
  const _InjectedInitialCreationFailure();
}

final class _InjectedSchema1To2Failure implements Exception {
  const _InjectedSchema1To2Failure();
}

final class _Schema1To2FailureInterceptor
    extends LocalDatabaseConnectionObserver {
  var didInjectFailure = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (didInjectFailure) return;
    final createsRelationTable = statement.statements.any(
      (sql) => RegExp(
        r'^CREATE TABLE(?: IF NOT EXISTS)? ["`]?long_term_relations["`]?',
        caseSensitive: false,
      ).hasMatch(sql.trimLeft()),
    );
    if (!createsRelationTable) return;

    didInjectFailure = true;
    throw const _InjectedSchema1To2Failure();
  }
}

final class _InitialSchemaCreationFailureInterceptor
    extends LocalDatabaseConnectionObserver {
  var didInjectFailure = false;
  var didCloseExecutor = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!didInjectFailure &&
        statement.operation == LocalDatabaseSqlOperation.custom &&
        _isSchemaCreate(statement.statements.single)) {
      didInjectFailure = true;
      throw const _InjectedInitialCreationFailure();
    }
  }

  @override
  void beforeClose() {
    didCloseExecutor = true;
  }

  bool _isSchemaCreate(String statement) {
    return RegExp(
      r'^CREATE (?:TABLE|VIRTUAL TABLE|INDEX|TRIGGER|VIEW)\b',
      caseSensitive: false,
    ).hasMatch(statement.trimLeft());
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
