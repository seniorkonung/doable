import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/in_memory_diagnostics_sink.dart';

const _sqliteIoerrCorruptFs = 8458;

void main() {
  group('LocalDataBootstrap', () {
    test(
      'открывает новую базу и предоставляет её только в результате ready',
      () async {
        final bootstrap = LocalDataBootstrap(
          connectionFactory: openInMemoryLocalDatabase,
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(bootstrap.close);

        final result = await bootstrap.open();

        expect(result, isA<LocalDataReady>());
        final ready = result as LocalDataReady;
        final foreignKeys = await ready.database
            .customSelect('PRAGMA foreign_keys')
            .getSingle();
        expect(foreignKeys.read<int>('foreign_keys'), 1);
      },
    );

    test('повторно открывает текущую совместимую схему', () async {
      final databaseFile = await _temporaryDatabaseFile();

      final firstBootstrap = _bootstrapFor(databaseFile);
      final firstResult = await firstBootstrap.open();
      expect(firstResult, isA<LocalDataReady>());
      await firstBootstrap.close();

      final currentBootstrap = _bootstrapFor(databaseFile);
      addTearDown(currentBootstrap.close);
      final currentResult = await currentBootstrap.open();

      expect(currentResult, isA<LocalDataReady>());
    });

    test('объединяет параллельные попытки открытия в один bootstrap', () async {
      var createdExecutors = 0;
      final bootstrap = LocalDataBootstrap(
        connectionFactory: () {
          createdExecutors += 1;
          return openInMemoryLocalDatabase();
        },
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(bootstrap.close);

      final results = await Future.wait([bootstrap.open(), bootstrap.open()]);

      expect(createdExecutors, 1);
      expect(results[0], same(results[1]));
      expect(results.first, isA<LocalDataReady>());
    });

    test(
      'отказывает от более новой схемы до feature-операций и не изменяет её',
      () async {
        final databaseFile = await _temporaryDatabaseFile();
        late List<int> preservedBytes;
        final bootstrap = _bootstrapFor(
          databaseFile,
          setup: (database) {
            database
              ..execute('CREATE TABLE future_data (value TEXT NOT NULL)')
              ..execute("INSERT INTO future_data(value) VALUES ('сохранённое')")
              ..execute('PRAGMA user_version = 2');
            preservedBytes = databaseFile.readAsBytesSync();
          },
        );
        addTearDown(bootstrap.close);

        final result = await bootstrap.open();

        expect(
          result,
          isA<LocalDataIncompatibleSchema>()
              .having(
                (failure) => failure.expectedSchemaVersion,
                'ожидаемая',
                1,
              )
              .having(
                (failure) => failure.detectedSchemaVersion,
                'обнаруженная',
                2,
              ),
        );
        expect(await databaseFile.readAsBytes(), preservedBytes);
      },
    );

    test(
      'классифицирует metadata версии 0 с сохранённой схемой как corruption',
      () async {
        final databaseFile = await _temporaryDatabaseFile();
        late List<int> preservedBytes;
        final bootstrap = _bootstrapFor(
          databaseFile,
          setup: (database) {
            database.execute(
              'CREATE TABLE orphaned_data (value TEXT NOT NULL)',
            );
            preservedBytes = databaseFile.readAsBytesSync();
          },
        );
        addTearDown(bootstrap.close);

        final result = await bootstrap.open();

        expect(result, isA<LocalDataCorruption>());
        expect(await databaseFile.readAsBytes(), preservedBytes);
      },
    );

    test(
      'классифицирует версию ниже 1 как corruption без её изменения',
      () async {
        final databaseFile = await _temporaryDatabaseFile();
        late List<int> preservedBytes;
        final bootstrap = _bootstrapFor(
          databaseFile,
          setup: (database) {
            database.execute('PRAGMA user_version = -1');
            preservedBytes = databaseFile.readAsBytesSync();
          },
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataCorruption>());
        expect(await databaseFile.readAsBytes(), preservedBytes);
      },
    );

    test(
      'классифицирует неизвестную причину открытия как unexpected',
      () async {
        _CloseTrackingObserver? failedObserver;
        final diagnosticsSink = InMemoryDiagnosticsSink();
        final bootstrap = LocalDataBootstrap(
          connectionFactory: () => _trackedConnection(
            openInMemoryLocalDatabase(
              setup: (_) => throw StateError('Недоступное хранилище'),
            ),
            (observer) => failedObserver = observer,
          ),
          diagnosticsSink: diagnosticsSink,
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataUnexpectedFailure>());
        expect(failedObserver!.closeCalls, 1);
        _expectBootstrapFailureCode(
          diagnosticsSink,
          DiagnosticsFailureCode.unexpected,
        );
      },
    );

    test(
      'сохраняет типизированную причину отказа bounded verification',
      () async {
        final scenarios = [
          (
            failure: SqliteException(
              extendedResultCode: SqlError.SQLITE_NOTADB,
              message: 'временная недоступность',
            ),
            expectedResult: isA<LocalDataCorruption>(),
            expectedCode: DiagnosticsFailureCode.corruption,
          ),
          (
            failure: SqliteException(
              extendedResultCode: SqlExtendedError.SQLITE_BUSY_RECOVERY,
              message: 'SQLite-файл повреждён',
            ),
            expectedResult: isA<LocalDataRetryableFailure>(),
            expectedCode: DiagnosticsFailureCode.unavailable,
          ),
          (
            failure: SqliteException(
              extendedResultCode: SqlError.SQLITE_CONSTRAINT,
              message: 'можно повторить попытку',
            ),
            expectedResult: isA<LocalDataUnexpectedFailure>(),
            expectedCode: DiagnosticsFailureCode.unexpected,
          ),
          (
            failure: StateError('Неизвестная причина'),
            expectedResult: isA<LocalDataUnexpectedFailure>(),
            expectedCode: DiagnosticsFailureCode.unexpected,
          ),
        ];

        for (final scenario in scenarios) {
          final databaseFile = await _temporaryDatabaseFile();
          final initialBootstrap = _bootstrapFor(databaseFile);
          expect(await initialBootstrap.open(), isA<LocalDataReady>());
          await initialBootstrap.close();
          final preservedBytes = await databaseFile.readAsBytes();

          final diagnosticsSink = InMemoryDiagnosticsSink();
          _BoundedVerificationFailureObserver? failedObserver;
          final bootstrap = LocalDataBootstrap(
            connectionFactory: () {
              final observer = _BoundedVerificationFailureObserver(
                scenario.failure,
              );
              failedObserver = observer;
              return observeConfiguredLocalDatabaseConnection(
                openFileBackedLocalDatabase(databaseFile),
                observer,
              );
            },
            diagnosticsSink: diagnosticsSink,
          );
          addTearDown(bootstrap.close);

          expect(await bootstrap.open(), scenario.expectedResult);
          expect(await databaseFile.readAsBytes(), preservedBytes);
          expect(failedObserver!.closeCalls, 1);
          _expectBootstrapFailureCode(diagnosticsSink, scenario.expectedCode);
        }
      },
    );

    test(
      'раскрывает SQLite BUSY чтения версии схемы из background executor',
      () async {
        final isolate = await spawnConfiguredInMemoryLocalDatabaseIsolate();
        addTearDown(isolate.shutdownAll);
        final connection = await isolate.connect();
        final diagnosticsSink = InMemoryDiagnosticsSink();
        final failedObserver = _BoundedVerificationFailureObserver(
          SqliteException(
            extendedResultCode: SqlExtendedError.SQLITE_BUSY_RECOVERY,
            message: 'SQLite-файл повреждён',
          ),
        );
        final bootstrap = LocalDataBootstrap(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            connection,
            failedObserver,
          ),
          diagnosticsSink: diagnosticsSink,
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataRetryableFailure>());
        expect(failedObserver.closeCalls, 1);
        _expectBootstrapFailureCode(
          diagnosticsSink,
          DiagnosticsFailureCode.unavailable,
        );
      },
    );

    test(
      'классифицирует неизвестную причину background executor как unexpected',
      () async {
        final isolate = await spawnConfiguredInMemoryLocalDatabaseIsolate();
        addTearDown(isolate.shutdownAll);
        final connection = await isolate.connect();
        final diagnosticsSink = InMemoryDiagnosticsSink();
        final failedObserver = _BoundedVerificationFailureObserver(
          StateError('Неизвестная причина'),
        );
        final bootstrap = LocalDataBootstrap(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            connection,
            failedObserver,
          ),
          diagnosticsSink: diagnosticsSink,
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataUnexpectedFailure>());
        expect(failedObserver.closeCalls, 1);
        _expectBootstrapFailureCode(
          diagnosticsSink,
          DiagnosticsFailureCode.unexpected,
        );
      },
    );

    test('классифицирует произвольный non-database файл как non-retryable corruption', () async {
      final databaseFile = await _temporaryDatabaseFile();
      await databaseFile.writeAsString('это не SQLite database');
      final diagnosticsSink = InMemoryDiagnosticsSink();
      _CloseTrackingObserver? failedObserver;
      final bootstrap = LocalDataBootstrap(
        connectionFactory: () => _trackedConnection(
          openFileBackedLocalDatabase(databaseFile),
          (observer) => failedObserver = observer,
        ),
        diagnosticsSink: diagnosticsSink,
      );
      addTearDown(bootstrap.close);

      final result = await bootstrap.open();

      expect(result, isA<LocalDataCorruption>());
      expect(failedObserver!.closeCalls, 1);
      _expectBootstrapFailureCode(
        diagnosticsSink,
        DiagnosticsFailureCode.corruption,
      );
    });

    test('классифицирует primary и extended коды CORRUPT и NOTADB без текста ошибки', () async {
      for (final exception in [
        SqliteException(
          extendedResultCode: SqlError.SQLITE_NOTADB,
          message: 'временная недоступность',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_CORRUPT_VTAB,
          message: 'можно повторить попытку',
        ),
      ]) {
        final diagnosticsSink = InMemoryDiagnosticsSink();
        _CloseTrackingObserver? failedObserver;
        final bootstrap = LocalDataBootstrap(
          connectionFactory: () => _trackedConnection(
            openInMemoryLocalDatabase(setup: (_) => throw exception),
            (observer) => failedObserver = observer,
          ),
          diagnosticsSink: diagnosticsSink,
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataCorruption>());
        expect(failedObserver!.closeCalls, 1);
        _expectBootstrapFailureCode(
          diagnosticsSink,
          DiagnosticsFailureCode.corruption,
        );
      }
    });

    test('оставляет временные SQLite-ошибки retryable', () async {
      for (final exception in [
        SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_BUSY_RECOVERY,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_BUSY_SNAPSHOT,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_BUSY_TIMEOUT,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlError.SQLITE_LOCKED,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
          message: 'SQLite-файл повреждён',
        ),
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_LOCKED_VTAB,
          message: 'SQLite-файл повреждён',
        ),
      ]) {
        final diagnosticsSink = InMemoryDiagnosticsSink();
        _CloseTrackingObserver? failedObserver;
        final bootstrap = LocalDataBootstrap(
          connectionFactory: () => _trackedConnection(
            openInMemoryLocalDatabase(setup: (_) => throw exception),
            (observer) => failedObserver = observer,
          ),
          diagnosticsSink: diagnosticsSink,
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataRetryableFailure>());
        expect(failedObserver!.closeCalls, 1);
        _expectBootstrapFailureCode(
          diagnosticsSink,
          DiagnosticsFailureCode.unavailable,
        );
      }
    });

    test(
      'не предлагает retry для CANTOPEN, неразрешённых IOERR и unknown',
      () async {
        for (final exception in [
          SqliteException(
            extendedResultCode: SqlError.SQLITE_CANTOPEN,
            message: 'CANARY-личные-данные',
          ),
          SqliteException(
            extendedResultCode: SqlExtendedError.SQLITE_CANTOPEN_ISDIR,
            message: 'CANARY-личные-данные',
          ),
          SqliteException(
            extendedResultCode: SqlError.SQLITE_IOERR,
            message: 'CANARY-личные-данные',
          ),
          SqliteException(
            extendedResultCode: _sqliteIoerrCorruptFs,
            message: 'CANARY-личные-данные',
          ),
          SqliteException(
            extendedResultCode: SqlError.SQLITE_BUSY | (999 << 8),
            message: 'CANARY-личные-данные',
          ),
        ]) {
          final diagnosticsSink = InMemoryDiagnosticsSink();
          _CloseTrackingObserver? failedObserver;
          final bootstrap = LocalDataBootstrap(
            connectionFactory: () => _trackedConnection(
              openInMemoryLocalDatabase(setup: (_) => throw exception),
              (observer) => failedObserver = observer,
            ),
            diagnosticsSink: diagnosticsSink,
          );
          addTearDown(bootstrap.close);

          expect(await bootstrap.open(), isA<LocalDataUnexpectedFailure>());
          expect(failedObserver!.closeCalls, 1);
          _expectBootstrapFailureCode(
            diagnosticsSink,
            DiagnosticsFailureCode.unexpected,
          );
        }
      },
    );

    test('классифицирует IOERR_DATA как non-retryable corruption', () async {
      final diagnosticsSink = InMemoryDiagnosticsSink();
      _CloseTrackingObserver? failedObserver;
      final bootstrap = LocalDataBootstrap(
        connectionFactory: () => _trackedConnection(
          openInMemoryLocalDatabase(
            setup: (_) => throw SqliteException(
              extendedResultCode: SqlExtendedError.SQLITE_IOERR_DATA,
              message: 'CANARY-личные-данные',
            ),
          ),
          (observer) => failedObserver = observer,
        ),
        diagnosticsSink: diagnosticsSink,
      );
      addTearDown(bootstrap.close);

      expect(await bootstrap.open(), isA<LocalDataCorruption>());
      expect(failedObserver!.closeCalls, 1);
      _expectBootstrapFailureCode(
        diagnosticsSink,
        DiagnosticsFailureCode.corruption,
      );
    });

    test('записывает безопасные события bootstrap и миграции', () async {
      final diagnosticsSink = InMemoryDiagnosticsSink();
      final bootstrap = LocalDataBootstrap(
        connectionFactory: openInMemoryLocalDatabase,
        diagnosticsSink: diagnosticsSink,
      );
      addTearDown(bootstrap.close);

      expect(await bootstrap.open(), isA<LocalDataReady>());

      expect(diagnosticsSink.events.map((event) => event.runtimeType), [
        BootstrapDiagnosticsEvent,
        MigrationDiagnosticsEvent,
        MigrationDiagnosticsEvent,
        BootstrapDiagnosticsEvent,
      ]);
      final migrationEvents = diagnosticsSink.events
          .whereType<MigrationDiagnosticsEvent>()
          .toList();
      expect(migrationEvents[0].fromSchemaVersion, 0);
      expect(migrationEvents[0].toSchemaVersion, 1);
      expect(migrationEvents[0].status, isA<DiagnosticsStarted>());
      expect(migrationEvents[1].status, isA<DiagnosticsSucceeded>());
    });

    test('записывает версии и безопасный код несовместимой схемы', () async {
      final databaseFile = await _temporaryDatabaseFile();
      final diagnosticsSink = InMemoryDiagnosticsSink();
      final bootstrap = LocalDataBootstrap(
        connectionFactory: () => openFileBackedLocalDatabase(
          databaseFile,
          setup: (database) => database.execute('PRAGMA user_version = 2'),
        ),
        diagnosticsSink: diagnosticsSink,
      );
      addTearDown(bootstrap.close);

      expect(await bootstrap.open(), isA<LocalDataIncompatibleSchema>());

      final migrationEvent =
          diagnosticsSink.events[2] as MigrationDiagnosticsEvent;
      expect(migrationEvent.fromSchemaVersion, 2);
      expect(migrationEvent.toSchemaVersion, 1);
      expect(
        migrationEvent.status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'безопасный код',
          DiagnosticsFailureCode.incompatibleSchema,
        ),
      );
      expect(
        diagnosticsSink.events[3].status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'безопасный код',
          DiagnosticsFailureCode.incompatibleSchema,
        ),
      );
    });
  });
}

LocalDataBootstrap _bootstrapFor(File databaseFile, {DatabaseSetup? setup}) {
  return LocalDataBootstrap(
    connectionFactory: () =>
        openFileBackedLocalDatabase(databaseFile, setup: setup),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
}

Future<File> _temporaryDatabaseFile() async {
  final directory = await Directory.systemTemp.createTemp('doable_bootstrap_');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/doable.sqlite');
}

ConfiguredLocalDatabaseConnection _trackedConnection(
  ConfiguredLocalDatabaseConnection connection,
  void Function(_CloseTrackingObserver observer) onCreated,
) {
  final observer = _CloseTrackingObserver();
  onCreated(observer);
  return observeConfiguredLocalDatabaseConnection(connection, observer);
}

final class _BoundedVerificationFailureObserver
    extends LocalDatabaseConnectionObserver {
  _BoundedVerificationFailureObserver(this._failure);

  final Object _failure;
  var closeCalls = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_isBoundedVerificationQuery(statement.statements.single)) {
      throw _failure;
    }
  }

  @override
  void beforeClose() {
    closeCalls += 1;
  }

  bool _isBoundedVerificationQuery(String statement) {
    final normalizedStatement = statement.trim().toUpperCase();
    return RegExp(r'^PRAGMA USER_VERSION;?$').hasMatch(normalizedStatement);
  }
}

void _expectBootstrapFailureCode(
  InMemoryDiagnosticsSink diagnosticsSink,
  DiagnosticsFailureCode expectedCode,
) {
  final event = diagnosticsSink.events.last as BootstrapDiagnosticsEvent;
  expect(
    event.status,
    isA<DiagnosticsFailed>().having(
      (status) => status.code,
      'безопасный код',
      expectedCode,
    ),
  );
}

final class _CloseTrackingObserver extends LocalDatabaseConnectionObserver {
  var closeCalls = 0;

  @override
  void beforeClose() {
    closeCalls += 1;
  }
}
