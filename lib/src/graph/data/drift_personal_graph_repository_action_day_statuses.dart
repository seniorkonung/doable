part of 'drift_personal_graph_repository.dart';

extension _ActionDayStatusesReading on DriftPersonalGraphRepository {
  Future<ActionDayStatusesReadResult> _readActionDayStatuses(
    ActionDayStatusQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const ActionDayStatusesReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(
          () => _readActionDayStatusesOnSnapshot(query),
        ),
      );
      _recordDiagnostics(
        ActionDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ActionDayStatusesReadSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyActionDayStatusesFailure(error);
      _recordDiagnostics(
        ActionDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return ActionDayStatusesReadError(failure);
    }
  }

  Future<GraphSnapshot<ActionDayStatuses>> _readActionDayStatusesOnSnapshot(
    ActionDayStatusQuery query,
  ) async {
    final first = query.firstDate.toCanonicalString();
    final last = query.lastDate.toCanonicalString();
    final rows = await _database
        .customSelect(
          '''SELECT date, MIN(is_completed) AS all_completed
         FROM actions INDEXED BY actions_date_completion_schedule_order
         WHERE date BETWEEN ? AND ?
         GROUP BY date''',
          variables: [Variable<String>(first), Variable<String>(last)],
          readsFrom: {_database.actions},
        )
        .get();
    final statuses = <CalendarDate, ActionDayStatus>{};
    for (final row in rows) {
      final date = decodeStoredActionDate(row.data);
      final storedDate = date.toCanonicalString();
      if (storedDate.compareTo(first) < 0 || storedDate.compareTo(last) > 0) {
        throw const StoredGraphCorruption();
      }
      statuses[date] = switch (requiredStoredInteger(
        row.data,
        'all_completed',
      )) {
        0 => ActionDayStatus.hasIncomplete,
        1 => ActionDayStatus.allCompleted,
        _ => throw const StoredGraphCorruption(),
      };
    }
    return GraphSnapshot(
      value: ActionDayStatuses(query: query, statuses: statuses),
      revision: _currentRevision,
    );
  }
}

ActionDayStatusesReadFailure _classifyActionDayStatusesFailure(Object error) {
  if (error is StoredGraphCorruption) {
    return const ActionDayStatusesCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const ActionDayStatusesCorruptionFailure(),
    SqliteUnavailableFailure() => const ActionDayStatusesUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const ActionDayStatusesUnexpectedFailure(),
  };
}
