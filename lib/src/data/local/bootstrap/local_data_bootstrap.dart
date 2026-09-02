import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_data_bootstrap_result.dart';

typedef LocalDataExecutorFactory = QueryExecutor Function();

final class LocalDataBootstrap {
  factory LocalDataBootstrap({
    required LocalDataExecutorFactory executorFactory,
    required DiagnosticsSink diagnosticsSink,
    InitialSchemaObjectCreated? onInitialSchemaObjectCreated,
  }) => LocalDataBootstrap._(
    executorFactory,
    diagnosticsSink,
    onInitialSchemaObjectCreated,
  );

  LocalDataBootstrap._(
    this._executorFactory,
    this._diagnosticsSink,
    this._onInitialSchemaObjectCreated,
  );

  final LocalDataExecutorFactory _executorFactory;
  final DiagnosticsSink _diagnosticsSink;
  final InitialSchemaObjectCreated? _onInitialSchemaObjectCreated;
  AppDatabase? _database;
  Future<LocalDataBootstrapResult>? _opening;

  Future<LocalDataBootstrapResult> open() {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return Future.value(LocalDataReady(existingDatabase));
    }
    final existingOpening = _opening;
    if (existingOpening != null) {
      return existingOpening;
    }

    late final Future<LocalDataBootstrapResult> opening;
    opening = _open().whenComplete(() {
      if (identical(_opening, opening)) _opening = null;
    });
    _opening = opening;
    return opening;
  }

  Future<LocalDataBootstrapResult> _open() async {
    final stopwatch = Stopwatch()..start();
    _diagnosticsSink.record(
      const BootstrapDiagnosticsEvent(
        schemaVersion: AppDatabase.currentSchemaVersion,
        status: DiagnosticsStarted(),
      ),
    );

    AppDatabase? database;
    try {
      database = AppDatabase(
        _executorFactory(),
        diagnosticsSink: _diagnosticsSink,
        onInitialSchemaObjectCreated: _onInitialSchemaObjectCreated,
      );
      await database.open();
      _database = database;
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return LocalDataReady(database);
    } on IncompatibleLocalDataSchemaException catch (error) {
      await database?.close();
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: DiagnosticsFailureCode.incompatibleSchema,
          ),
        ),
      );
      return LocalDataIncompatibleSchema(
        expectedSchemaVersion: error.expectedSchemaVersion,
        detectedSchemaVersion: error.detectedSchemaVersion,
      );
    } on CorruptLocalDataSchemaException {
      await database?.close();
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: DiagnosticsFailureCode.corruption,
          ),
        ),
      );
      return const LocalDataCorruption();
    } on Object catch (error) {
      await database?.close();
      final result = _classifyOpeningFailure(error);
      final diagnosticsFailureCode = switch (result) {
        LocalDataCorruption() => DiagnosticsFailureCode.corruption,
        LocalDataRetryableFailure() => DiagnosticsFailureCode.unavailable,
        _ => throw StateError('Неожиданный результат классификации bootstrap.'),
      };
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: diagnosticsFailureCode,
          ),
        ),
      );
      return result;
    }
  }

  static LocalDataBootstrapResult _classifyOpeningFailure(Object error) {
    if (error case SqliteException(
      resultCode: SqlError.SQLITE_CORRUPT || SqlError.SQLITE_NOTADB,
    )) {
      return const LocalDataCorruption();
    }
    return const LocalDataRetryableFailure();
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) await opening;
    final database = _database;
    _database = null;
    await database?.close();
  }
}
