import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart';

import 'local_data_bootstrap_result.dart';

typedef LocalDataExecutorFactory = QueryExecutor Function();

final class LocalDataBootstrap {
  LocalDataBootstrap({
    required LocalDataExecutorFactory executorFactory,
    required DiagnosticsSink diagnosticsSink,
  }) : _executorFactory = executorFactory,
       _diagnosticsSink = diagnosticsSink;

  final LocalDataExecutorFactory _executorFactory;
  final DiagnosticsSink _diagnosticsSink;
  AppDatabase? _database;

  Future<LocalDataBootstrapResult> open() async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return LocalDataReady(existingDatabase);
    }

    final stopwatch = Stopwatch()..start();
    _diagnosticsSink.record(
      const BootstrapDiagnosticsEvent(
        schemaVersion: AppDatabase.currentSchemaVersion,
        status: DiagnosticsStarted(),
      ),
    );

    final database = AppDatabase(_executorFactory());
    try {
      await database.open();
      _database = database;
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return LocalDataReady(database);
    } on Object {
      await database.close();
      _diagnosticsSink.record(
        BootstrapDiagnosticsEvent(
          schemaVersion: AppDatabase.currentSchemaVersion,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: DiagnosticsFailureCode.unavailable,
          ),
        ),
      );
      return const LocalDataRetryableFailure();
    }
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}
