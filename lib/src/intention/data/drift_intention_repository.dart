import '../../data/local/app_database.dart' as local;
import '../../data/local/sqlite_failure_classifier.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import '../application/intention_command.dart';
import '../application/intention_id_generator.dart';
import '../application/intention_repository.dart';
import '../application/intention_result.dart';
import '../domain/intention.dart' as domain;
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';

final class DriftIntentionRepository implements IntentionRepository {
  DriftIntentionRepository(
    this._database,
    IntentionIdGenerator idGenerator,
    DateTime Function() now,
    this._diagnosticsSink,
  );

  final local.AppDatabase _database;
  final DiagnosticsSink _diagnosticsSink;

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => const ResultFailure(IntentionUnexpectedFailure());

  @override
  Stream<Result<domain.Intention?>> watchById(IntentionId id) async* {
    final stopwatch = Stopwatch()..start();
    _diagnosticsSink.record(
      const IntentionDetailReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );

    try {
      final query = _database.select(_database.intentions)
        ..where((row) => row.id.equals(id.toCanonicalString()));
      await for (final row in query.watchSingleOrNull()) {
        final intention = row == null ? null : _rehydrate(row);
        _diagnosticsSink.record(
          IntentionDetailReadDiagnosticsEvent(
            status: DiagnosticsSucceeded(stopwatch.elapsed),
          ),
        );
        yield ResultSuccess(intention);
      }
    } on Object catch (error) {
      final failure = _classifyDetailReadFailure(error);
      _diagnosticsSink.record(
        IntentionDetailReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      yield ResultFailure(failure);
    }
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(
    IntentionCommand command,
  ) async => const ResultFailure(IntentionUnexpectedFailure());

  domain.Intention _rehydrate(local.Intention row) {
    final id = switch (IntentionId.decode(row.id)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const _StoredIntentionCorruption(),
    };

    try {
      final title = IntentionText.normalizeTitle(row.title);
      final description = row.description == null
          ? null
          : IntentionText.normalizeDescription(row.description!);
      if (title != row.title ||
          description != row.description ||
          row.titleSearchKey != title.toLowerCase()) {
        throw const _StoredIntentionCorruption();
      }
      final createdAt = domain.IntentionTimestamp(
        DateTime.fromMicrosecondsSinceEpoch(row.createdAt, isUtc: true),
      );
      final updatedAt = domain.IntentionTimestamp(
        DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
      );
      return domain.Intention(
        id: id,
        title: title,
        description: description,
        readiness: row.isActionReady
            ? domain.IntentionReadiness.ready
            : domain.IntentionReadiness.notReady,
        archiveState: row.isArchived
            ? domain.IntentionArchiveState.archived
            : domain.IntentionArchiveState.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } on Object catch (error) {
      if (error is IntentionTextValidationException ||
          error is domain.IntentionTimestampOrderException ||
          error is ArgumentError ||
          error is RangeError) {
        throw const _StoredIntentionCorruption();
      }
      rethrow;
    }
  }
}

IntentionFailure _classifyDetailReadFailure(Object error) {
  if (error is _StoredIntentionCorruption) {
    return const IntentionCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const IntentionCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const IntentionUnexpectedFailure(),
  };
}

DiagnosticsFailureCode _diagnosticsFailureCode(IntentionFailure failure) =>
    switch (failure) {
      IntentionValidationFailure() => DiagnosticsFailureCode.validation,
      IntentionNotFoundFailure() => DiagnosticsFailureCode.notFound,
      IntentionConflictFailure() => DiagnosticsFailureCode.conflict,
      IntentionUnavailableFailure() => DiagnosticsFailureCode.unavailable,
      IntentionCorruptionFailure() => DiagnosticsFailureCode.corruption,
      IntentionUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
    };

final class _StoredIntentionCorruption implements Exception {
  const _StoredIntentionCorruption();
}
