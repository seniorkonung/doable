import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('LocalDataBootstrap', () {
    test(
      'открывает новую базу и предоставляет её только в результате ready',
      () async {
        final bootstrap = LocalDataBootstrap(
          executorFactory: NativeDatabase.memory,
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
        executorFactory: () {
          createdExecutors += 1;
          return NativeDatabase.memory();
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
      'закрывает неготовый executor и допускает явную повторную попытку',
      () async {
        QueryExecutor? failedExecutor;
        var attempts = 0;
        final bootstrap = LocalDataBootstrap(
          executorFactory: () {
            attempts += 1;
            if (attempts == 1) {
              return failedExecutor = NativeDatabase.memory(
                setup: (_) => throw StateError('Недоступное хранилище'),
              );
            }
            return NativeDatabase.memory();
          },
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(bootstrap.close);

        expect(await bootstrap.open(), isA<LocalDataRetryableFailure>());
        await expectLater(
          failedExecutor!.ensureOpen(_NoopQueryExecutorUser()),
          throwsStateError,
        );

        expect(await bootstrap.open(), isA<LocalDataReady>());
      },
    );

    test('записывает безопасные события bootstrap и миграции', () async {
      final diagnosticsSink = InMemoryDiagnosticsSink();
      final bootstrap = LocalDataBootstrap(
        executorFactory: NativeDatabase.memory,
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
        executorFactory: () => NativeDatabase(
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
    executorFactory: () => NativeDatabase(databaseFile, setup: setup),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
}

Future<File> _temporaryDatabaseFile() async {
  final directory = await Directory.systemTemp.createTemp('doable_bootstrap_');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/doable.sqlite');
}

final class _NoopQueryExecutorUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
