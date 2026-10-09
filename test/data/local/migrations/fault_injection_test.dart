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

  group('диагностика несовместимого маркера версии', () {
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

List<String> _encode(Iterable<DiagnosticsEvent> events) {
  final messages = <String>[];
  final sink = DeveloperDiagnosticsSink(messages.add);
  for (final event in events) {
    sink.record(event);
  }
  return messages;
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

final class _StatementRecorder extends LocalDatabaseConnectionObserver {
  final List<String> statements = [];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.addAll(statement.statements);
  }
}
