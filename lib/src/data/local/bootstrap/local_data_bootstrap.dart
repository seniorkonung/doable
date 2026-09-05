import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';

import 'local_data_bootstrap_result.dart';
import '../sqlite_failure_classifier.dart';

typedef LocalDataConnectionFactory =
    ConfiguredLocalDatabaseConnection Function();

final class LocalDataBootstrap {
  factory LocalDataBootstrap({
    required LocalDataConnectionFactory connectionFactory,
    required DiagnosticsSink diagnosticsSink,
  }) => LocalDataBootstrap._(connectionFactory, diagnosticsSink);

  LocalDataBootstrap._(this._connectionFactory, this._diagnosticsSink);

  final LocalDataConnectionFactory _connectionFactory;
  final DiagnosticsSink _diagnosticsSink;
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
        _connectionFactory(),
        diagnosticsSink: _diagnosticsSink,
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
    } on Object catch (error) {
      await database?.close();
      final result = _classifyOpeningFailure(error);
      final diagnosticsFailureCode = switch (result) {
        LocalDataIncompatibleSchema() =>
          DiagnosticsFailureCode.incompatibleSchema,
        LocalDataCorruption() => DiagnosticsFailureCode.corruption,
        LocalDataRetryableFailure() => DiagnosticsFailureCode.unavailable,
        LocalDataUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
        LocalDataReady() => throw StateError(
          'Классификация bootstrap не может вернуть готовое хранилище.',
        ),
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
    final cause = unwrapDriftRemoteException(error);
    return switch (cause) {
      IncompatibleLocalDataSchemaException(
        :final expectedSchemaVersion,
        :final detectedSchemaVersion,
      ) =>
        LocalDataIncompatibleSchema(
          expectedSchemaVersion: expectedSchemaVersion,
          detectedSchemaVersion: detectedSchemaVersion,
        ),
      CorruptLocalDataSchemaException() => const LocalDataCorruption(),
      _ => switch (classifySqliteFailure(cause)) {
        SqliteCorruptionFailure() => const LocalDataCorruption(),
        SqliteUnavailableFailure() => const LocalDataRetryableFailure(),
        SqliteConstraintFailure() ||
        SqliteUnexpectedFailure() => const LocalDataUnexpectedFailure(),
      },
    };
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) await opening;
    final database = _database;
    _database = null;
    await database?.close();
  }
}
