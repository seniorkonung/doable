part of 'drift_personal_graph_repository.dart';

extension _DailyChoiceDayStatusesReading on DriftPersonalGraphRepository {
  Future<DailyChoiceDayStatusesReadResult> _readDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const DailyChoiceDayStatusesReadDiagnosticsEvent(
        status: DiagnosticsStarted(),
      ),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(
          () => _readDailyChoiceDayStatusesOnSnapshot(query),
        ),
      );
      _recordDiagnostics(
        DailyChoiceDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return DailyChoiceDayStatusesReadSuccess(snapshot);
    } on Object catch (error) {
      final code =
          error is StoredGraphCorruption ||
              error is CalendarDateValidationException
          ? DiagnosticsFailureCode.corruption
          : switch (classifySqliteFailure(error)) {
              SqliteCorruptionFailure() => DiagnosticsFailureCode.corruption,
              SqliteUnavailableFailure() => DiagnosticsFailureCode.unavailable,
              SqliteConstraintFailure() ||
              SqliteUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
            };
      _recordDiagnostics(
        DailyChoiceDayStatusesReadDiagnosticsEvent(
          status: DiagnosticsFailed(duration: stopwatch.elapsed, code: code),
        ),
      );
      return const DailyChoiceDayStatusesReadError(
        DailyChoiceDayStatusesReadFailure(),
      );
    }
  }

  Future<GraphSnapshot<DailyChoiceDayStatuses>>
  _readDailyChoiceDayStatusesOnSnapshot(DailyChoiceDayStatusQuery query) async {
    final first = query.firstDate.toCanonicalString();
    final last = query.lastDate.toCanonicalString();
    final rows = await _database
        .customSelect(
          '''SELECT choice_date, MIN(is_completed) AS all_completed
         FROM daily_choices INDEXED BY daily_choices_date_creation_order
         WHERE choice_date BETWEEN ? AND ?
         GROUP BY choice_date''',
          variables: [Variable<String>(first), Variable<String>(last)],
          readsFrom: {_database.dailyChoices},
        )
        .get();
    final statuses = <CalendarDate, DailyChoiceDayStatus>{};
    for (final row in rows) {
      final storedDate = _requiredStoredString(row.data, 'choice_date');
      final date = CalendarDate.parseCanonical(storedDate);
      if (storedDate.compareTo(first) < 0 || storedDate.compareTo(last) > 0) {
        throw const StoredGraphCorruption();
      }
      statuses[date] = switch (_requiredStoredInteger(
        row.data,
        'all_completed',
      )) {
        0 => DailyChoiceDayStatus.hasIncomplete,
        1 => DailyChoiceDayStatus.allCompleted,
        _ => throw const StoredGraphCorruption(),
      };
    }
    return GraphSnapshot(
      value: DailyChoiceDayStatuses(query: query, statuses: statuses),
      revision: _currentRevision,
    );
  }
}
