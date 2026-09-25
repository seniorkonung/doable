import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
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
  test('все поддерживаемые обновления дают контракт новой установки и сохраняют граф', () async {
    final fresh = await LocalDatabaseHarness.fileBacked();
    addTearDown(fresh.dispose);
    final freshDatabase = await fresh.openReadyDatabase();
    await verifyDoableDatabaseSchema(freshDatabase);
    await fresh.closePersistenceObjectGraph();
    final freshSchema = _schemaContract(fresh.databaseFile);

    for (final sourceVersion in [
      publishedIntentionSchemaVersion,
      publishedRelationSchemaVersion,
      publishedDailyChoiceSchemaVersion,
    ]) {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      await _createPublishedGraphFixture(harness.databaseFile, sourceVersion);
      final before = _graphRows(harness.databaseFile, sourceVersion);

      final migrated = await harness.openReadyDatabase();
      await verifyDoableDatabaseSchema(migrated);
      await verifyIntentionTitlesFtsIntegrity(migrated);
      expect(
        (await migrated.customSelect('PRAGMA foreign_key_check').get()),
        isEmpty,
        reason: 'Исходная версия $sourceVersion',
      );
      expect(
        (await migrated.customSelect('PRAGMA foreign_keys').getSingle())
            .read<int>('foreign_keys'),
        1,
      );
      await harness.closePersistenceObjectGraph();

      expect(
        _schemaContract(harness.databaseFile),
        freshSchema,
        reason: 'Исходная версия $sourceVersion',
      );
      expect(
        _graphRows(harness.databaseFile, sourceVersion),
        before,
        reason: 'Исходная версия $sourceVersion',
      );
      _expectEmptyTagTables(harness.databaseFile);

      final reopened = await harness.openReadyDatabase();
      await verifyDoableDatabaseSchema(reopened);
      await harness.closePersistenceObjectGraph();
      expect(_graphRows(harness.databaseFile, sourceVersion), before);
    }
  });

  test(
    'сбой шага 3 → 4 до commit сохраняет дневной путь и позволяет повтор',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      await createSchemaV3Fixture(
        harness.databaseFile,
        seed: _seedPublishedDailyGraph,
      );
      final before = _graphRows(
        harness.databaseFile,
        publishedDailyChoiceSchemaVersion,
      );
      final interceptor = _Schema3To4FailureInterceptor();

      final failed = await harness.open(observer: interceptor);
      expect(failed, isA<LocalDataUnexpectedFailure>());
      expect(interceptor.didInjectFailure, isTrue);
      await harness.closePersistenceObjectGraph();
      expect(
        _graphRows(harness.databaseFile, publishedDailyChoiceSchemaVersion),
        before,
      );
      _expectNoTagTables(
        harness.databaseFile,
        publishedDailyChoiceSchemaVersion,
      );

      final recovered = await harness.openReadyDatabase();
      await verifyDoableDatabaseSchema(recovered);
      await harness.closePersistenceObjectGraph();
      expect(
        _graphRows(harness.databaseFile, publishedDailyChoiceSchemaVersion),
        before,
      );
      _expectEmptyTagTables(harness.databaseFile);
    },
  );

  for (final stopPoint in _MigrationProcessStopPoint.values) {
    test(
      'останов процесса на переходе 3 → 4 ${stopPoint.testDescription} сохраняет дневной путь',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        await createSchemaV3Fixture(
          harness.databaseFile,
          seed: _seedPublishedDailyGraph,
        );
        final before = _graphRows(
          harness.databaseFile,
          publishedDailyChoiceSchemaVersion,
        );

        await _runMigrationWorkerUntilStopPoint(harness, stopPoint);
        expect(
          _graphRows(harness.databaseFile, publishedDailyChoiceSchemaVersion),
          before,
        );
        if (stopPoint.isAfterCommit) {
          _expectEmptyTagTables(harness.databaseFile);
        } else {
          _expectNoTagTables(
            harness.databaseFile,
            publishedDailyChoiceSchemaVersion,
          );
        }

        final recovered = await harness.openReadyDatabase();
        await verifyDoableDatabaseSchema(recovered);
        await harness.closePersistenceObjectGraph();
        expect(
          _graphRows(harness.databaseFile, publishedDailyChoiceSchemaVersion),
          before,
        );
        _expectEmptyTagTables(harness.databaseFile);
      },
    );
  }

  test(
    'читатель схемы 3 отклоняет настоящий файл версии 4 без изменения',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      await createSchemaV3Fixture(
        harness.databaseFile,
        seed: _seedPublishedDailyGraph,
      );
      await harness.openReadyDatabase();
      await harness.closePersistenceObjectGraph();
      final before = await harness.databaseFile.readAsBytes();
      final reader = _Schema3Reader(harness.databaseFile);
      addTearDown(reader.close);

      await expectLater(
        reader.customSelect('SELECT id FROM intentions').get(),
        throwsA(
          isA<IncompatibleLocalDataSchemaException>()
              .having(
                (error) => error.expectedSchemaVersion,
                'ожидаемая версия',
                3,
              )
              .having(
                (error) => error.detectedSchemaVersion,
                'версия файла',
                4,
              ),
        ),
      );
      expect(await harness.databaseFile.readAsBytes(), before);
      _expectEmptyTagTables(harness.databaseFile);
    },
  );

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

  test('переход 2 → 3 сохраняет граф и не создаёт дневные выборы', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    await createSchemaV2Fixture(
      harness.databaseFile,
      seed: _seedPublishedGraph,
    );

    final migratedDatabase = await harness.openReadyDatabase();
    await expectLater(verifyDoableDatabaseSchema(migratedDatabase), completes);
    await harness.closePersistenceObjectGraph();
    _expectPublishedGraph(
      harness.databaseFile,
      expectedSchemaVersion: AppDatabase.currentSchemaVersion,
      hasChoiceSchema: true,
    );

    final reopenedDatabase = await harness.openReadyDatabase();
    await expectLater(verifyDoableDatabaseSchema(reopenedDatabase), completes);
    await harness.closePersistenceObjectGraph();
    _expectPublishedGraph(
      harness.databaseFile,
      expectedSchemaVersion: AppDatabase.currentSchemaVersion,
      hasChoiceSchema: true,
    );
  });

  test('сбой перехода 2 → 3 оставляет прежний граф и версию', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    await createSchemaV2Fixture(
      harness.databaseFile,
      seed: _seedPublishedGraph,
    );
    final interceptor = _Schema2To3FailureInterceptor();

    final failedResult = await harness.open(observer: interceptor);
    expect(failedResult, isA<LocalDataUnexpectedFailure>());
    expect(interceptor.didInjectFailure, isTrue);
    await harness.closePersistenceObjectGraph();
    _expectPublishedGraph(
      harness.databaseFile,
      expectedSchemaVersion: publishedRelationSchemaVersion,
      hasChoiceSchema: false,
    );

    final reopenedDatabase = await harness.openReadyDatabase();
    await expectLater(verifyDoableDatabaseSchema(reopenedDatabase), completes);
    await harness.closePersistenceObjectGraph();
    _expectPublishedGraph(
      harness.databaseFile,
      expectedSchemaVersion: AppDatabase.currentSchemaVersion,
      hasChoiceSchema: true,
    );
  });

  for (final stopPoint in _MigrationProcessStopPoint.values) {
    test(
      'прерывание перехода 2 → 3 ${stopPoint.testDescription} сохраняет целый граф',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        await createSchemaV2Fixture(
          harness.databaseFile,
          seed: _seedPublishedGraph,
        );

        await _runMigrationWorkerUntilStopPoint(harness, stopPoint);
        _expectPublishedGraph(
          harness.databaseFile,
          expectedSchemaVersion: stopPoint.isAfterCommit
              ? AppDatabase.currentSchemaVersion
              : publishedRelationSchemaVersion,
          hasChoiceSchema: stopPoint.isAfterCommit,
        );

        final reopenedDatabase = await harness.openReadyDatabase();
        await expectLater(
          verifyDoableDatabaseSchema(reopenedDatabase),
          completes,
        );
        await harness.closePersistenceObjectGraph();
        _expectPublishedGraph(
          harness.databaseFile,
          expectedSchemaVersion: AppDatabase.currentSchemaVersion,
          hasChoiceSchema: true,
        );
      },
    );
  }

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

final class _Schema3Reader extends GeneratedDatabase {
  _Schema3Reader(File file)
    : super(
        NativeDatabase(file, setup: composeDoableSqliteConnectionSetup(null)),
      );

  @override
  int get schemaVersion => publishedDailyChoiceSchemaVersion;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => localDataMigrationStrategy(this);
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

void _seedPublishedGraph(sqlite.Database database) {
  _seedPublishedIntentions(database);
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
}

void _seedPublishedDailyGraph(sqlite.Database database) {
  _seedPublishedGraph(database);
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

Future<void> _createPublishedGraphFixture(File file, int version) =>
    switch (version) {
      publishedIntentionSchemaVersion => createSchemaV1Fixture(
        file,
        seed: _seedPublishedIntentions,
      ),
      publishedRelationSchemaVersion => createSchemaV2Fixture(
        file,
        seed: _seedPublishedGraph,
      ),
      publishedDailyChoiceSchemaVersion => createSchemaV3Fixture(
        file,
        seed: _seedPublishedDailyGraph,
      ),
      _ => throw ArgumentError.value(version, 'version'),
    };

Map<String, List<Map<String, Object?>>> _graphRows(File file, int version) {
  expect(file.existsSync(), isTrue);
  final database = sqlite.sqlite3.open(file.path);
  try {
    final tables = [
      'intentions',
      if (version >= publishedRelationSchemaVersion) 'long_term_relations',
      if (version >= publishedDailyChoiceSchemaVersion) ...[
        'daily_choices',
        'daily_choice_path_steps',
      ],
    ];
    final hasSequenceTable = database.select('''
      SELECT name FROM sqlite_schema WHERE name = 'sqlite_sequence'
    ''').isNotEmpty;
    return {
      for (final table in tables)
        table: database
            .select('SELECT rowid, * FROM $table ORDER BY rowid')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      'sqlite_sequence': !hasSequenceTable
          ? <Map<String, Object?>>[]
          : database
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

void _expectNoTagTables(File file, int expectedVersion) {
  expect(file.existsSync(), isTrue);
  final database = sqlite.sqlite3.open(file.path);
  try {
    expect(
      database.select('PRAGMA user_version').single['user_version'],
      expectedVersion,
    );
    expect(
      database.select('''
      SELECT name FROM sqlite_schema
      WHERE name IN ('tags', 'tag_assignments')
    '''),
      isEmpty,
    );
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    database.execute('''
      INSERT INTO intention_titles_fts(intention_titles_fts, rank)
      VALUES ('integrity-check', 1)
    ''');
  } finally {
    database.close();
  }
}

void _expectEmptyTagTables(File file) {
  expect(file.existsSync(), isTrue);
  final database = sqlite.sqlite3.open(file.path);
  try {
    expect(
      database.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );
    expect(database.select('SELECT id FROM tags'), isEmpty);
    expect(database.select('SELECT tag_id FROM tag_assignments'), isEmpty);
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    database.execute('''
      INSERT INTO intention_titles_fts(intention_titles_fts, rank)
      VALUES ('integrity-check', 1)
    ''');
  } finally {
    database.close();
  }
}

void _expectPublishedGraph(
  File databaseFile, {
  required int expectedSchemaVersion,
  required bool hasChoiceSchema,
}) {
  _expectPublishedIntentions(
    databaseFile,
    expectedSchemaVersion: expectedSchemaVersion,
    hasRelationSchema: true,
  );
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('''
        SELECT creation_sequence, id, source_intention_id,
          related_intention_id, type, priority, description, is_archived
        FROM long_term_relations
      ''').single,
      {
        'creation_sequence': 47,
        'id': '018f0b5d-6b2e-7c80-8000-000000000313',
        'source_intention_id': _activeIntentionId,
        'related_intention_id': _archivedIntentionId,
        'type': 'need',
        'priority': 2,
        'description': '  Сохранённая связь  ',
        'is_archived': 1,
      },
    );
    final choiceTables = database.select('''
      SELECT name FROM sqlite_schema
      WHERE type = 'table'
        AND name IN ('daily_choices', 'daily_choice_path_steps')
      ORDER BY name
    ''');
    expect(choiceTables, hasChoiceSchema ? hasLength(2) : isEmpty);
    if (hasChoiceSchema) {
      expect(database.select('SELECT id FROM daily_choices'), isEmpty);
      expect(
        database.select('SELECT id FROM daily_choice_path_steps'),
        isEmpty,
      );
    }
  } finally {
    database.close();
  }
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

    final choiceTables = database.select('''
      SELECT name FROM sqlite_schema
      WHERE type = 'table'
        AND name IN ('daily_choices', 'daily_choice_path_steps')
      ORDER BY name
    ''');
    if (expectedSchemaVersion == AppDatabase.currentSchemaVersion) {
      expect(choiceTables, hasLength(2));
      expect(database.select('SELECT id FROM daily_choices'), isEmpty);
      expect(
        database.select('SELECT id FROM daily_choice_path_steps'),
        isEmpty,
      );
    } else {
      expect(choiceTables, isEmpty);
    }
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

final class _InjectedSchema2To3Failure implements Exception {
  const _InjectedSchema2To3Failure();
}

final class _InjectedSchema3To4Failure implements Exception {
  const _InjectedSchema3To4Failure();
}

final class _Schema3To4FailureInterceptor
    extends LocalDatabaseConnectionObserver {
  var didInjectFailure = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (didInjectFailure) return;
    final createsTagAssignmentTable = statement.statements.any(
      (sql) => RegExp(
        r'^CREATE TABLE(?: IF NOT EXISTS)? ["`]?tag_assignments["` ]?',
        caseSensitive: false,
      ).hasMatch(sql.trimLeft()),
    );
    if (!createsTagAssignmentTable) return;
    didInjectFailure = true;
    throw const _InjectedSchema3To4Failure();
  }
}

final class _Schema2To3FailureInterceptor
    extends LocalDatabaseConnectionObserver {
  var didInjectFailure = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (didInjectFailure) return;
    final createsChoiceTable = statement.statements.any(
      (sql) => RegExp(
        r'^CREATE TABLE(?: IF NOT EXISTS)? ["`]?daily_choices["`]?',
        caseSensitive: false,
      ).hasMatch(sql.trimLeft()),
    );
    if (!createsChoiceTable) return;

    didInjectFailure = true;
    throw const _InjectedSchema2To3Failure();
  }
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
