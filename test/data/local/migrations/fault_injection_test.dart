import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _nextSchemaVersion = AppDatabase.currentSchemaVersion + 1;
const _personalIntentionId = '018f0b5d-6b2e-7c80-8000-000000000291';
const _personalIntentionTitle = 'CANARY-намерение-личного-графа';
const _personalTagId = '018f0b5d-6b2e-7c80-8000-000000000292';
const _personalTagName = 'CANARY-тег-личного-графа';
const _personalDataMarkers = [
  _personalIntentionId,
  _personalIntentionTitle,
  _personalTagId,
  _personalTagName,
  'CANARY',
];

void main() {
  test(
    'атомарная миграция откатывает схему, данные и маркер версии после ошибки',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      addTearDown(database.close);

      await _insertIntention(database);

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: _nextSchemaVersion,
          migrate: () async {
            await database.customStatement(
              'ALTER TABLE intentions ADD COLUMN migration_probe TEXT',
            );
            await database.customStatement(
              'UPDATE intentions SET migration_probe = ?',
              ['частично изменённые данные'],
            );
            throw const _InjectedMigrationFailure();
          },
        ),
        throwsA(isA<_InjectedMigrationFailure>()),
      );

      final columns = await database
          .customSelect('PRAGMA table_info(intentions)')
          .get();
      final intention = await database
          .customSelect('SELECT title FROM intentions')
          .getSingle();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();

      expect(
        columns.map((column) => column.read<String>('name')),
        isNot(contains('migration_probe')),
      );
      expect(intention.read<String>('title'), 'Сохранённое намерение');
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );

      await runAtomicMigration(
        database,
        targetSchemaVersion: _nextSchemaVersion,
        migrate: () async {},
      );

      final retriedVersion = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(retriedVersion.read<int>('user_version'), _nextSchemaVersion);
      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
    },
  );

  test('контур инъекции ошибки закрывает неуспешное соединение', () async {
    final harness = _FailedMigrationConnectionHarness();
    addTearDown(harness.closeIfNeeded);

    await expectLater(
      harness.run(() {
        return runAtomicMigration(
          harness.database,
          targetSchemaVersion: _nextSchemaVersion,
          migrate: () async => throw const _InjectedMigrationFailure(),
        );
      }),
      throwsA(isA<_InjectedMigrationFailure>()),
    );

    expect(harness.isClosed, isTrue);
  });

  group('диагностика создания схемы', () {
    test(
      'ошибка получателя до создания не препятствует подтверждению',
      () async {
        final diagnostics = _SelectivelyThrowingDiagnosticsSink(
          (event) => event.status is DiagnosticsStarted,
        );

        final database = await _createSchemaWithDiagnostics(diagnostics);

        await _expectCurrentSchema(database);
        expect(
          diagnostics.attemptedEvents.map((event) => event.status.runtimeType),
          [DiagnosticsStarted, DiagnosticsSucceeded],
        );
      },
    );

    test('ошибка получателя после создания не меняет его исход', () async {
      final diagnostics = _SelectivelyThrowingDiagnosticsSink(
        (event) => event.status is DiagnosticsSucceeded,
      );

      final database = await _createSchemaWithDiagnostics(diagnostics);

      await _expectCurrentSchema(database);
      expect(
        diagnostics.attemptedEvents.map((event) => event.status.runtimeType),
        [DiagnosticsStarted, DiagnosticsSucceeded],
      );
    });

    test('отказ создания сохраняет версии, длительность и категорию без '
        'исходного исключения', () async {
      final databaseFile = await _temporaryDatabaseFile();
      final diagnostics = _SelectivelyThrowingDiagnosticsSink((_) => false);

      final result = await _openWithDiagnostics(
        databaseFile,
        diagnostics,
        observer: _SchemaCreationFailureInjector(),
      );

      expect(result, isA<LocalDataUnexpectedFailure>());
      final migrationEvents = diagnostics.attemptedEvents
          .whereType<MigrationDiagnosticsEvent>()
          .toList();
      expect(migrationEvents, hasLength(2));
      for (final event in migrationEvents) {
        expect(event.fromSchemaVersion, 0);
        expect(event.toSchemaVersion, AppDatabase.currentSchemaVersion);
      }
      expect(migrationEvents.first.status, isA<DiagnosticsStarted>());
      expect(
        migrationEvents.last.status,
        isA<DiagnosticsFailed>()
            .having(
              (status) => status.code,
              'категория отказа',
              DiagnosticsFailureCode.unexpected,
            )
            .having(
              (status) => status.duration,
              'длительность',
              greaterThanOrEqualTo(Duration.zero),
            ),
      );
      _expectEncodedMigrationEvents(
        migrationEvents,
        fromSchemaVersion: 0,
        failureCode: DiagnosticsFailureCode.unexpected,
      );
    });

    for (final sinkFailure in _DiagnosticsSinkFailure.values) {
      test('отказ получателя ${sinkFailure.testDescription} не меняет исход '
          'прерванного создания и повторного запуска', () async {
        final databaseFile = await _temporaryDatabaseFile();
        final diagnostics = _SelectivelyThrowingDiagnosticsSink(
          sinkFailure.shouldThrow,
        );

        final result = await _openWithDiagnostics(
          databaseFile,
          diagnostics,
          observer: _SchemaCreationFailureInjector(),
        );

        expect(result, isA<LocalDataUnexpectedFailure>());
        expect(
          diagnostics.attemptedEvents
              .whereType<MigrationDiagnosticsEvent>()
              .map((event) => event.status.runtimeType),
          [DiagnosticsStarted, DiagnosticsFailed],
        );
        _expectStorageWithoutSchema(databaseFile);

        final retried = await _openWithDiagnostics(databaseFile, diagnostics);
        expect(retried, isA<LocalDataReady>());
      });
    }
  });

  group('диагностика несовместимого маркера версии', () {
    test(
      'сохраняет версии, длительность и категорию без данных хранилища',
      () async {
        final databaseFile = await _storageWithNewerSchemaVersion();
        final preservedBytes = await databaseFile.readAsBytes();
        final diagnostics = _SelectivelyThrowingDiagnosticsSink((_) => false);

        final result = await _openWithDiagnostics(databaseFile, diagnostics);

        expect(
          result,
          isA<LocalDataIncompatibleSchema>()
              .having(
                (result) => result.expectedSchemaVersion,
                'ожидаемая версия',
                AppDatabase.currentSchemaVersion,
              )
              .having(
                (result) => result.detectedSchemaVersion,
                'обнаруженная версия',
                _nextSchemaVersion,
              ),
        );
        expect(await databaseFile.readAsBytes(), preservedBytes);
        final migrationEvents = diagnostics.attemptedEvents
            .whereType<MigrationDiagnosticsEvent>()
            .toList();
        expect(migrationEvents.map((event) => event.status.runtimeType), [
          DiagnosticsStarted,
          DiagnosticsFailed,
        ]);
        for (final event in migrationEvents) {
          expect(event.fromSchemaVersion, _nextSchemaVersion);
          expect(event.toSchemaVersion, AppDatabase.currentSchemaVersion);
        }
        _expectEncodedMigrationEvents(
          migrationEvents,
          fromSchemaVersion: _nextSchemaVersion,
          failureCode: DiagnosticsFailureCode.incompatibleSchema,
        );
        _expectEncodedWithoutPersonalData(diagnostics.attemptedEvents);
      },
    );

    for (final sinkFailure in _DiagnosticsSinkFailure.values) {
      test('отказ получателя ${sinkFailure.testDescription} не меняет '
          'несовместимость и файл хранилища', () async {
        final databaseFile = await _storageWithNewerSchemaVersion();
        final preservedBytes = await databaseFile.readAsBytes();
        final diagnostics = _SelectivelyThrowingDiagnosticsSink(
          sinkFailure.shouldThrow,
        );

        final result = await _openWithDiagnostics(databaseFile, diagnostics);

        expect(result, isA<LocalDataIncompatibleSchema>());
        expect(
          diagnostics.attemptedEvents
              .whereType<MigrationDiagnosticsEvent>()
              .map((event) => event.status.runtimeType),
          [DiagnosticsStarted, DiagnosticsFailed],
        );
        expect(await databaseFile.readAsBytes(), preservedBytes);
      });
    }

    test('сообщение отказа не содержит данных хранилища', () async {
      final databaseFile = await _storageWithNewerSchemaVersion();
      final database = AppDatabase(openFileBackedLocalDatabase(databaseFile));
      addTearDown(database.close);

      Object? failure;
      try {
        await database.open();
      } on Object catch (error) {
        failure = error;
      }

      expect(
        unwrapDriftRemoteException(failure!),
        isA<IncompatibleLocalDataSchemaException>(),
      );
      _expectWithoutPersonalData(failure.toString());
    });
  });

  test(
    'повторное открытие не выполняет аудит тегов, назначений и намерений',
    () async {
      final databaseFile = await _temporaryDatabaseFile();
      await _seedPersonalGraph(databaseFile);
      final statements = _StatementRecorder();
      final diagnostics = _SelectivelyThrowingDiagnosticsSink((_) => false);

      final result = await _openWithDiagnostics(
        databaseFile,
        diagnostics,
        observer: statements,
      );

      expect(result, isA<LocalDataReady>());
      expect(statements.statements, isNotEmpty);
      expect(
        statements.statements.where(
          RegExp(
            r'\b(?:tags|tag_assignments|intentions|intention_titles_fts)\b',
            caseSensitive: false,
          ).hasMatch,
        ),
        isEmpty,
      );
      expect(
        diagnostics.attemptedEvents.whereType<MigrationDiagnosticsEvent>(),
        isEmpty,
      );
      _expectEncodedWithoutPersonalData(diagnostics.attemptedEvents);
    },
  );
}

Future<File> _temporaryDatabaseFile() async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'doable_diagnostics_storage_',
  );
  addTearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });
  return File('${temporaryDirectory.path}/doable.sqlite');
}

Future<LocalDataBootstrapResult> _openWithDiagnostics(
  File databaseFile,
  DiagnosticsSink diagnostics, {
  LocalDatabaseConnectionObserver? observer,
}) async {
  final bootstrap = LocalDataBootstrap(
    connectionFactory: () {
      final connection = openFileBackedLocalDatabase(databaseFile);
      return switch (observer) {
        null => connection,
        final observer => observeConfiguredLocalDatabaseConnection(
          connection,
          observer,
        ),
      };
    },
    diagnosticsSink: diagnostics,
  );
  addTearDown(bootstrap.close);
  final result = await bootstrap.open();
  await bootstrap.close();
  return result;
}

/// Создаёт хранилище текущей схемы с тегом, назначенным намерению, чтобы
/// проверки могли искать пользовательские данные в диагностике.
Future<void> _seedPersonalGraph(File databaseFile) async {
  final bootstrap = LocalDataBootstrap(
    connectionFactory: () => openFileBackedLocalDatabase(databaseFile),
    diagnosticsSink: _SelectivelyThrowingDiagnosticsSink((_) => false),
  );
  try {
    final result = await bootstrap.open();
    final database = (result as LocalDataReady).database;
    await database.customStatement(
      '''
        INSERT INTO intentions (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      ''',
      [_personalIntentionId, _personalIntentionTitle, 1000000, 1000000],
    );
    await database.customStatement(
      'INSERT INTO tags (id, name) VALUES (?, ?)',
      [_personalTagId, _personalTagName],
    );
    await database.customStatement(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [_personalTagId, _personalIntentionId],
    );
  } finally {
    await bootstrap.close();
  }
}

Future<File> _storageWithNewerSchemaVersion() async {
  final databaseFile = await _temporaryDatabaseFile();
  await _seedPersonalGraph(databaseFile);
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    database.execute('PRAGMA user_version = $_nextSchemaVersion');
  } finally {
    database.close();
  }
  return databaseFile;
}

void _expectStorageWithoutSchema(File databaseFile) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    expect(
      database.select('''
        SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'
      '''),
      isEmpty,
    );
    expect(database.select('PRAGMA user_version').single['user_version'], 0);
  } finally {
    database.close();
  }
}

List<String> _encode(Iterable<DiagnosticsEvent> events) {
  final messages = <String>[];
  final sink = DeveloperDiagnosticsSink(messages.add);
  for (final event in events) {
    sink.record(event);
  }
  return messages;
}

void _expectEncodedMigrationEvents(
  List<MigrationDiagnosticsEvent> events, {
  required int fromSchemaVersion,
  required DiagnosticsFailureCode failureCode,
}) {
  final encoded = _encode(events).map(jsonDecode).toList();
  expect(encoded, [
    {
      'operation': 'migration',
      'outcome': 'started',
      'fromSchemaVersion': fromSchemaVersion,
      'toSchemaVersion': AppDatabase.currentSchemaVersion,
    },
    {
      'operation': 'migration',
      'outcome': 'failed',
      'durationMicros': isA<int>().having(
        (duration) => duration,
        'неотрицательная длительность',
        greaterThanOrEqualTo(0),
      ),
      'failureCode': failureCode.name,
      'fromSchemaVersion': fromSchemaVersion,
      'toSchemaVersion': AppDatabase.currentSchemaVersion,
    },
  ]);
  _expectEncodedWithoutPersonalData(events);
}

void _expectEncodedWithoutPersonalData(Iterable<DiagnosticsEvent> events) {
  for (final message in _encode(events)) {
    _expectWithoutPersonalData(message);
  }
}

void _expectWithoutPersonalData(String text) {
  for (final marker in _personalDataMarkers) {
    expect(text, isNot(contains(marker)));
  }
}

Future<AppDatabase> _createSchemaWithDiagnostics(
  DiagnosticsSink diagnostics,
) async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'doable_diagnostics_creation_',
  );
  addTearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });
  final databaseFile = File('${temporaryDirectory.path}/doable.sqlite');
  final database = AppDatabase(
    openFileBackedLocalDatabase(databaseFile),
    diagnosticsSink: diagnostics,
  );
  addTearDown(database.close);
  await database.open();
  return database;
}

Future<void> _expectCurrentSchema(AppDatabase database) async {
  final version = await database
      .customSelect('PRAGMA user_version')
      .getSingle();
  final relationTable = await database
      .customSelect(
        "SELECT name FROM sqlite_schema "
        "WHERE type = 'table' AND name = 'long_term_relations'",
      )
      .getSingleOrNull();
  expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  expect(relationTable?.read<String>('name'), 'long_term_relations');
}

Future<void> _insertIntention(AppDatabase database) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, created_at, updated_at
      ) VALUES (?, ?, ?, ?)
    ''',
    [
      '018f0b5d-6b2e-7c80-8000-000000000201',
      'Сохранённое намерение',
      1000000,
      1000000,
    ],
  );
}

final class _InjectedMigrationFailure implements Exception {
  const _InjectedMigrationFailure();
}

final class _SelectivelyThrowingDiagnosticsSink implements DiagnosticsSink {
  _SelectivelyThrowingDiagnosticsSink(this._shouldThrow);

  final bool Function(DiagnosticsEvent event) _shouldThrow;
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    if (_shouldThrow(event)) {
      throw StateError('CANARY-diagnostics-sink-failure');
    }
  }
}

enum _DiagnosticsSinkFailure {
  onStart(testDescription: 'при начале'),
  onCompletion(testDescription: 'при завершении'),
  onEveryEvent(testDescription: 'на каждом событии');

  const _DiagnosticsSinkFailure({required this.testDescription});

  final String testDescription;

  bool shouldThrow(DiagnosticsEvent event) => switch (this) {
    _DiagnosticsSinkFailure.onStart => event.status is DiagnosticsStarted,
    _DiagnosticsSinkFailure.onCompletion => event.status is! DiagnosticsStarted,
    _DiagnosticsSinkFailure.onEveryEvent => true,
  };
}

/// Прерывает создание на первом объекте схемы исключением с пользовательскими
/// данными, чтобы проверить, что они не попадают в диагностику.
final class _SchemaCreationFailureInjector
    extends LocalDatabaseConnectionObserver {
  var _didInjectFailure = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (_didInjectFailure ||
        statement.operation != LocalDatabaseSqlOperation.custom ||
        !RegExp(
          r'^CREATE\b',
          caseSensitive: false,
        ).hasMatch(statement.statements.single.trimLeft())) {
      return;
    }
    _didInjectFailure = true;
    throw StateError('$_personalTagName $_personalIntentionId');
  }
}

final class _StatementRecorder extends LocalDatabaseConnectionObserver {
  final List<String> statements = [];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.addAll(statement.statements);
  }
}

final class _FailedMigrationConnectionHarness {
  _FailedMigrationConnectionHarness()
    : database = AppDatabase(openInMemoryLocalDatabase());

  final AppDatabase database;
  var isClosed = false;

  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      await database.close();
      isClosed = true;
      rethrow;
    }
  }

  Future<void> closeIfNeeded() async {
    if (!isClosed) {
      await database.close();
      isClosed = true;
    }
  }
}
