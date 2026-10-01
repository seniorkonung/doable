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
import '../../../support/tag_storage_fixture.dart';

const _activeIntentionId = '018f0b5d-6b2e-7c80-8000-000000000311';
const _archivedIntentionId = '018f0b5d-6b2e-7c80-8000-000000000312';
const _selectedIntentionId = '018f0b5d-6b2e-7c80-8000-000000000314';
const _activeRelationId = '018f0b5d-6b2e-7c80-8000-000000000315';
const _dailyChoiceId = '018f0b5d-6b2e-7c80-8000-000000000316';
const _pathStepId = '018f0b5d-6b2e-7c80-8000-000000000317';
const _middleIntentionId = '018f0b5d-6b2e-7c80-8000-000000000318';
const _finalRelationId = '018f0b5d-6b2e-7c80-8000-000000000319';
const _finalPathStepId = '018f0b5d-6b2e-7c80-8000-000000000320';
const _workerStopPointEnvironment = 'DOABLE_MIGRATION_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_MIGRATION_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_MIGRATION_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_MIGRATION_WORKER_READY';

void main() {
  test(
    'текущая схема на файловой базе совпадает с новой установкой и сохраняет '
    'граф, назначения и счётчик после повторного открытия',
    () async {
      final fresh = await LocalDatabaseHarness.fileBacked();
      addTearDown(fresh.dispose);
      final freshDatabase = await fresh.openReadyDatabase();
      await verifyDoableDatabaseSchema(freshDatabase);
      await fresh.closePersistenceObjectGraph();
      final freshSchema = _schemaContract(fresh.databaseFile);

      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (database) => raw = database);
      _seedStoredGraph(raw);
      seedTagStorageFixture(raw);
      // Последнее назначение удалено: следующий номер должен продолжить счётчик
      // последовательности, а не максимум сохранённых строк.
      raw.execute('DELETE FROM tag_assignments WHERE creation_sequence = 3');
      await harness.closePersistenceObjectGraph();
      final beforeGraph = _graphRows(harness.databaseFile);
      final beforeAssignments = _assignmentRows(harness.databaseFile);
      expect(beforeAssignments.rows, hasLength(2));
      expect(beforeAssignments.sequence, 3);

      final reopened = await harness.openReadyDatabase();
      await verifyDoableDatabaseSchema(reopened);
      await verifyIntentionTitlesFtsIntegrity(reopened);
      expect(
        await reopened.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        (await reopened.customSelect('PRAGMA foreign_keys').getSingle())
            .read<int>('foreign_keys'),
        1,
      );
      await harness.closePersistenceObjectGraph();

      expect(_schemaContract(harness.databaseFile), freshSchema);
      expect(_graphRows(harness.databaseFile), beforeGraph);
      final afterAssignments = _assignmentRows(harness.databaseFile);
      expect(afterAssignments.rows, beforeAssignments.rows);
      expect(afterAssignments.sequence, beforeAssignments.sequence);
      _expectStoredIntentionsSearchable(harness.databaseFile);

      final database = sqlite.sqlite3.open(harness.databaseFile.path);
      try {
        composeDoableSqliteConnectionSetup(null)(database);
        expect(
          database.select('PRAGMA user_version').single['user_version'],
          AppDatabase.currentSchemaVersion,
        );
        expect(
          database.select('''
          SELECT 1 FROM tag_assignments a JOIN tags t ON t.id = a.tag_id
          WHERE a.tag_creation_sequence <> t.creation_sequence
        '''),
          isEmpty,
        );
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(lastTagNumber), _activeIntentionId],
        );
        expect(
          database
              .select(
                '''
          SELECT creation_sequence FROM tag_assignments
          WHERE tag_id = ? AND intention_id = ?
        ''',
                [tagFixtureId(lastTagNumber), _activeIntentionId],
              )
              .single['creation_sequence'],
          4,
        );
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        database.close();
      }
    },
  );

  for (final failurePoint in _InitialCreationFailurePoint.values) {
    test(
      'отказ создания ${failurePoint.testDescription} не оставляет частичной '
      'схемы, сохраняет файл и допускает повторное создание',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        _markEmptyStorageFile(harness.databaseFile);
        final failureInterceptor = _InitialSchemaCreationFailureInterceptor(
          failurePoint,
        );

        final failedResult = await harness.open(observer: failureInterceptor);

        expect(failedResult, isA<LocalDataUnexpectedFailure>());
        expect(failureInterceptor.didInjectFailure, isTrue);
        expect(failureInterceptor.didCloseExecutor, isTrue);

        await harness.closePersistenceObjectGraph();
        await _expectStorageWithoutUserSchema(harness.databaseFile);
        _expectStorageFileKept(harness.databaseFile);

        await _expectRecreatedSchemaSurvivesReopen(harness);
      },
    );
  }

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

      await _expectRecreatedSchemaSurvivesReopen(harness);
    });
  }
}

void _seedStoredIntentions(sqlite.Database database) {
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

void _seedStoredGraph(sqlite.Database database) {
  _seedStoredIntentions(database);
  database.execute('''
    INSERT INTO long_term_relations (
      creation_sequence,
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      description,
      is_archived
    ) VALUES (
      47,
      '018f0b5d-6b2e-7c80-8000-000000000313',
      '$_activeIntentionId',
      '$_archivedIntentionId',
      'need',
      2,
      '  Сохранённая связь  ',
      1
    )
  ''');
  database.execute('''
    INSERT INTO intentions (
      id, title, description, is_action_ready, is_archived,
      created_at, updated_at
    ) VALUES
      (
        '$_middleIntentionId', 'Промежуточное намерение', NULL,
        0, 0, 1704326400000000, 1704412800000000
      ),
      (
        '$_selectedIntentionId', 'Выбранное действие', '  Текст действия  ',
        1, 0, 1704412800000000, 1704499200000000
      )
  ''');
  database.execute('''
    INSERT INTO long_term_relations (
      creation_sequence, id, source_intention_id, related_intention_id,
      type, priority, description, is_archived
    ) VALUES
      (
        48, '$_activeRelationId', '$_activeIntentionId',
        '$_middleIntentionId', 'can', 4, '  Начало пути  ', 0
      ),
      (
        49, '$_finalRelationId', '$_middleIntentionId',
        '$_selectedIntentionId', 'need', 1, '  Конец пути  ', 0
      )
  ''');
  database.execute('''
    INSERT INTO daily_choices (
      creation_sequence, id, source_intention_id, selected_intention_id,
      choice_date, description, is_completed
    ) VALUES (
      63, '$_dailyChoiceId', '$_activeIntentionId',
      '$_selectedIntentionId', '2026-09-25', '  Сделано  ', 1
    )
  ''');
  database.execute('''
    INSERT INTO daily_choice_path_steps (
      id, daily_choice_id, long_term_relation_id, previous_step_id
    ) VALUES
      ('$_pathStepId', '$_dailyChoiceId', '$_activeRelationId', NULL),
      ('$_finalPathStepId', '$_dailyChoiceId', '$_finalRelationId', '$_pathStepId')
  ''');
}

Map<String, List<Map<String, Object?>>> _graphRows(File file) {
  expect(file.existsSync(), isTrue);
  final database = sqlite.sqlite3.open(file.path);
  try {
    const tables = [
      'intentions',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tags',
    ];
    return {
      for (final table in tables)
        table: database
            .select('SELECT rowid, * FROM $table ORDER BY rowid')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      'sqlite_sequence': database
          .select(
            "SELECT name, seq FROM sqlite_sequence WHERE name IN (${tables.map((_) => '?').join(', ')}) ORDER BY name",
            tables,
          )
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
    };
  } finally {
    database.close();
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

({List<Map<String, Object?>> rows, int? sequence}) _assignmentRows(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    return (
      rows: [
        for (final row in database.select('''
          SELECT * FROM tag_assignments ORDER BY creation_sequence
        '''))
          Map<String, Object?>.from(row),
      ],
      sequence:
          database
                  .select(
                    "SELECT seq FROM sqlite_sequence WHERE name = 'tag_assignments'",
                  )
                  .firstOrNull?['seq']
              as int?,
    );
  } finally {
    database.close();
  }
}

/// Сохранённые названия остаются доступными поиску после повторного открытия.
void _expectStoredIntentionsSearchable(File databaseFile) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('SELECT title_search_key FROM intentions WHERE id = ?', [
        _activeIntentionId,
      ]).single['title_search_key'],
      'strasse',
    );
    expect(
      database.select('''
        SELECT rowid
        FROM intention_titles_fts
        WHERE title_search_key MATCH '"strasse"'
      '''),
      hasLength(1),
    );
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
  } finally {
    database.close();
  }
}

/// Следующий запуск создаёт или открывает схему на том же файле, а повторное
/// открытие после закрытия видит тот же подтверждённый контракт схемы.
Future<void> _expectRecreatedSchemaSurvivesReopen(
  LocalDatabaseHarness harness,
) async {
  final createdDatabase = await harness.openReadyDatabase();
  await expectLater(verifyDoableDatabaseSchema(createdDatabase), completes);
  await expectLater(
    verifyIntentionTitlesFtsIntegrity(createdDatabase),
    completes,
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

enum _InitialCreationFailurePoint {
  firstSchemaObject(testDescription: 'на первом объекте схемы'),
  versionMarker(testDescription: 'после всех объектов и проверок схемы');

  const _InitialCreationFailurePoint({required this.testDescription});

  final String testDescription;
}

final class _InitialSchemaCreationFailureInterceptor
    extends LocalDatabaseConnectionObserver {
  _InitialSchemaCreationFailureInterceptor(this.failurePoint);

  final _InitialCreationFailurePoint failurePoint;
  var didInjectFailure = false;
  var didCloseExecutor = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (didInjectFailure ||
        statement.operation != LocalDatabaseSqlOperation.custom) {
      return;
    }
    final isFailurePoint = switch (failurePoint) {
      _InitialCreationFailurePoint.firstSchemaObject => _isSchemaCreate(
        statement.statements.single,
      ),
      _InitialCreationFailurePoint.versionMarker => _isVersionMarker(
        statement.statements.single,
      ),
    };
    if (!isFailurePoint) return;

    didInjectFailure = true;
    throw const _InjectedInitialCreationFailure();
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
