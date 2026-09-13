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
  Future<void>? _closing;
  var _lifecycle = _LocalDataBootstrapLifecycle.open;

  Future<LocalDataBootstrapResult> open() {
    if (_lifecycle != _LocalDataBootstrapLifecycle.open) {
      throw StateError(
        'Нельзя открыть локальные данные после начала закрытия bootstrap.',
      );
    }

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
    recordDiagnosticsSafely(
      _diagnosticsSink,
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
      recordDiagnosticsSafely(
        _diagnosticsSink,
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
      recordDiagnosticsSafely(
        _diagnosticsSink,
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

  Future<void> close() {
    final existingClosing = _closing;
    if (existingClosing != null) return existingClosing;

    _lifecycle = _LocalDataBootstrapLifecycle.closing;
    final closing = _close();
    _closing = closing;
    return closing;
  }

  Future<void> _close() async {
    final opening = _opening;
    try {
      if (opening != null) await opening;
      final database = _database;
      _database = null;
      await database?.close();
    } finally {
      _lifecycle = _LocalDataBootstrapLifecycle.closed;
    }
  }
}

enum _LocalDataBootstrapLifecycle { open, closing, closed }
