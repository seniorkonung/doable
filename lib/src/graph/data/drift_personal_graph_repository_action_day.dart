part of 'drift_personal_graph_repository.dart';

extension _ActionDayReading on DriftPersonalGraphRepository {
  Future<ActionDayPageResult> _readActionDayPage(ActionDayQuery query) async {
    final stopwatch = Stopwatch()..start();
    final isContinuation = query.cursor != null;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      ActionDayPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        isContinuation: isContinuation,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(() => _readActionDayPageOnSnapshot(query)),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return ActionDayPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyActionDayFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return ActionDayPageError(failure);
    }
  }

  Future<ActionDayPage> _readActionDayPageOnSnapshot(
    ActionDayQuery query,
  ) async {
    final _DriftActionDayCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftActionDayCursor own => own,
      _ => throw StateError('Недопустимый курсор выдачи дня.'),
    };
    if (cursor != null &&
        (cursor.date != query.date ||
            cursor.section != query.section ||
            cursor.pageSize != query.pageSize ||
            cursor.revision.compareTo(_currentRevision) !=
                GraphRevisionOrder.same)) {
      throw const _ActionDaySnapshotHasExpired();
    }

    final dayVariables = <Variable>[
      Variable<String>(query.date.toCanonicalString()),
      Variable<int>(query.section == ActionDaySection.completed ? 1 : 0),
    ];
    final filters = ['a.date = ?', 'a.is_completed = ?'];
    final variables = [...dayVariables];
    if (cursor != null) {
      // Сравнение полного ключа продолжает порядок без OFFSET:
      // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
      filters.add(
        '(COALESCE(a.scheduled_hour, -1), a.priority, a.creation_sequence) '
        '> (?, ?, ?)',
      );
      variables.addAll([
        Variable<int>(cursor.boundary.scheduledHour),
        Variable<int>(cursor.boundary.priority),
        Variable<int>(cursor.boundary.sequence),
      ]);
    }
    // Корень и число намерений пути читаются по первичному ключу строк пути,
    // без загрузки самого пути.
    final rawRows = await _database
        .customSelect(
          '''SELECT a.creation_sequence, a.id, a.title, a.description, a.date,
                a.scheduled_hour, a.priority, a.is_completed,
                COALESCE(i.title, d.title) AS root_title,
                (SELECT MAX(position) + 1 FROM action_path_items
                 WHERE action_id = a.id) AS path_length
         FROM actions a
         LEFT JOIN action_path_items r
           ON r.action_id = a.id AND r.position = 0
         LEFT JOIN intentions i ON i.id = r.intention_id
         LEFT JOIN deleted_intentions d ON d.intention_id = r.intention_id
         WHERE ${filters.join(' AND ')}
         ORDER BY COALESCE(a.scheduled_hour, -1), a.priority,
                  a.creation_sequence
         LIMIT ?''',
          variables: [...variables, Variable<int>(query.pageSize + 1)],
          readsFrom: {
            _database.actions,
            _database.actionPathItems,
            _database.intentions,
            _database.deletedIntentions,
          },
        )
        .get();
    final hasNext = rawRows.length > query.pageSize;
    final selectedRows = [
      for (final row in rawRows.take(query.pageSize)) row.data,
    ];
    final items = [for (final data in selectedRows) _decodeActionDayItem(data)];
    final revision = _currentRevision;
    final nextCursor = hasNext
        ? _DriftActionDayCursor(
            revision: revision,
            date: query.date,
            section: query.section,
            pageSize: query.pageSize,
            boundary: (
              scheduledHour: switch (items.last.schedule) {
                ActionAllDay() => -1,
                ActionAtHour(:final hour) => hour,
              },
              priority: items.last.priority.level,
              sequence: requiredStoredInteger(
                selectedRows.last,
                'creation_sequence',
              ),
            ),
          )
        : null;
    if (cursor != null) {
      return ActionDayContinuationPage(
        items: items,
        nextCursor: nextCursor,
        revision: revision,
      );
    }

    // Числа секций читаются на том же снимке, что и первая порция.
    final summaryRows = await _database
        .customSelect(
          '''SELECT is_completed, COUNT(*) AS total_count,
                MAX(COALESCE(scheduled_hour, -1)) AS latest_hour
         FROM actions WHERE date = ? GROUP BY is_completed''',
          variables: [dayVariables.first],
          readsFrom: {_database.actions},
        )
        .get();
    var incompleteCount = 0;
    var completedCount = 0;
    var hasTimedActions = false;
    for (final row in summaryRows) {
      final data = row.data;
      final count = requiredStoredInteger(data, 'total_count');
      switch (requiredStoredInteger(data, 'is_completed')) {
        case 0:
          incompleteCount = count;
        case 1:
          completedCount = count;
        default:
          throw const StoredGraphCorruption();
      }
      hasTimedActions =
          hasTimedActions || requiredStoredInteger(data, 'latest_hour') >= 0;
    }
    return ActionDayFirstPage(
      items: items,
      incompleteCount: incompleteCount,
      completedCount: completedCount,
      hasTimedActions: hasTimedActions,
      nextCursor: nextCursor,
      revision: revision,
    );
  }
}

ActionDayItem _decodeActionDayItem(Map<String, Object?> data) {
  final fields = decodeStoredActionFields(data);
  try {
    return ActionDayItem(
      id: fields.id,
      title: fields.title,
      description: fields.description,
      date: fields.date,
      schedule: fields.schedule,
      priority: fields.priority,
      isCompleted: fields.isCompleted,
      rootTitle: decodeStoredIntentionTitle(data, 'root_title'),
      pathIntentionCount: requiredStoredInteger(data, 'path_length'),
    );
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

final class _DriftActionDayCursor implements ActionDayCursor {
  const _DriftActionDayCursor({
    required this.revision,
    required this.date,
    required this.section,
    required this.pageSize,
    required this.boundary,
  });

  final GraphRevision revision;
  final CalendarDate date;
  final ActionDaySection section;
  final int pageSize;

  /// Ключ порядка последней отданной строки; «Весь день» — час `-1`.
  final ({int scheduledHour, int priority, int sequence}) boundary;
}

final class _ActionDaySnapshotHasExpired implements Exception {
  const _ActionDaySnapshotHasExpired();
}

ActionDayReadFailure _classifyActionDayFailure(Object error) {
  if (error is _ActionDaySnapshotHasExpired) {
    return const ActionDaySnapshotExpired();
  }
  if (error is StoredGraphCorruption) return const ActionDayCorruptionFailure();
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const ActionDayCorruptionFailure(),
    SqliteUnavailableFailure() => const ActionDayUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const ActionDayUnexpectedFailure(),
  };
}
