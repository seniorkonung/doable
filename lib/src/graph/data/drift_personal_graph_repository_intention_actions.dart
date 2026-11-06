part of 'drift_personal_graph_repository.dart';

extension _IntentionActionsReading on DriftPersonalGraphRepository {
  Future<IntentionActionsPageResult> _readIntentionActionsPage(
    IntentionActionsQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    final isContinuation = query.cursor != null;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      IntentionActionsPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        isContinuation: isContinuation,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(
          () => _readIntentionActionsPageOnSnapshot(query),
        ),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return IntentionActionsPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyIntentionActionsFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return IntentionActionsPageError(failure);
    }
  }

  Future<IntentionActionsPage> _readIntentionActionsPageOnSnapshot(
    IntentionActionsQuery query,
  ) async {
    final _DriftIntentionActionsCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftIntentionActionsCursor own => own,
      _ => throw StateError('Недопустимый курсор действий намерения.'),
    };
    if (cursor != null &&
        (cursor.intentionId != query.intentionId ||
            cursor.role != query.role ||
            cursor.pageSize != query.pageSize ||
            cursor.revision.compareTo(_currentRevision) !=
                GraphRevisionOrder.same)) {
      throw const _IntentionActionsSnapshotHasExpired();
    }

    final intentionVariable = Variable<String>(
      query.intentionId.toCanonicalString(),
    );
    // Следующая позиция того же пути ищется по первичному ключу строк пути.
    const hasNextPosition =
        'EXISTS (SELECT 1 FROM action_path_items n '
        'WHERE n.action_id = p.action_id AND n.position = p.position + 1)';
    final filters = [
      'p.intention_id = ?',
      switch (query.role) {
        IntentionActionRole.root => 'p.position = 0',
        IntentionActionRole.intermediate =>
          'p.position > 0 AND $hasNextPosition',
        IntentionActionRole.terminal => 'NOT $hasNextPosition',
      },
    ];
    final variables = <Variable>[intentionVariable];
    if (cursor != null) {
      // Сравнение полного ключа продолжает порядок без OFFSET:
      // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
      filters.add(
        '(a.date, COALESCE(a.scheduled_hour, -1), a.creation_sequence) '
        '< (?, ?, ?)',
      );
      variables.addAll([
        Variable<String>(cursor.boundary.date.toCanonicalString()),
        Variable<int>(cursor.boundary.scheduledHour),
        Variable<int>(cursor.boundary.sequence),
      ]);
    }
    const order =
        'a.date DESC, COALESCE(a.scheduled_hour, -1) DESC, '
        'a.creation_sequence DESC';
    // Порядок роли сортируется по полям действий, а корень и число намерений
    // пути читаются только для строк порции.
    final rawRows = await _database
        .customSelect(
          '''SELECT $_actionListItemColumns
         FROM (
           SELECT a.creation_sequence, a.id, a.title, a.description, a.date,
                  a.scheduled_hour, a.priority, a.is_completed
           FROM action_path_items p
           JOIN actions a ON a.id = p.action_id
           WHERE ${filters.join(' AND ')}
           ORDER BY $order
           LIMIT ?
         ) a
         $_actionListItemRootJoins
         ORDER BY $order''',
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
    final items = [
      for (final data in selectedRows) _decodeActionListItem(data),
    ];
    final revision = _currentRevision;
    final nextCursor = hasNext
        ? _DriftIntentionActionsCursor(
            revision: revision,
            intentionId: query.intentionId,
            role: query.role,
            pageSize: query.pageSize,
            boundary: (
              date: items.last.date,
              scheduledHour: switch (items.last.schedule) {
                ActionAllDay() => -1,
                ActionAtHour(:final hour) => hour,
              },
              sequence: requiredStoredInteger(
                selectedRows.last,
                'creation_sequence',
              ),
            ),
          )
        : null;
    if (cursor != null) {
      return IntentionActionsContinuationPage(
        items: items,
        nextCursor: nextCursor,
        revision: revision,
      );
    }

    // Числа ролей читаются на том же снимке, что и первая порция. Намерение
    // встречается в пути не больше одного раза, поэтому строка пути — одно
    // действие.
    final countRow = await _database
        .customSelect(
          '''SELECT COUNT(*) AS total_count,
                COALESCE(SUM(p.position = 0), 0) AS root_count,
                COALESCE(SUM(p.position > 0 AND n.action_id IS NOT NULL), 0)
                  AS intermediate_count,
                COALESCE(SUM(n.action_id IS NULL), 0) AS terminal_count
         FROM action_path_items p
         LEFT JOIN action_path_items n
           ON n.action_id = p.action_id AND n.position = p.position + 1
         WHERE p.intention_id = ?''',
          variables: [intentionVariable],
          readsFrom: {_database.actionPathItems},
        )
        .getSingle();
    final counts = countRow.data;
    return IntentionActionsFirstPage(
      items: items,
      counts: IntentionActionCounts(
        root: requiredStoredInteger(counts, 'root_count'),
        intermediate: requiredStoredInteger(counts, 'intermediate_count'),
        terminal: requiredStoredInteger(counts, 'terminal_count'),
        total: requiredStoredInteger(counts, 'total_count'),
      ),
      nextCursor: nextCursor,
      revision: revision,
    );
  }
}

final class _DriftIntentionActionsCursor implements IntentionActionsCursor {
  const _DriftIntentionActionsCursor({
    required this.revision,
    required this.intentionId,
    required this.role,
    required this.pageSize,
    required this.boundary,
  });

  final GraphRevision revision;
  final IntentionId intentionId;
  final IntentionActionRole role;
  final int pageSize;

  /// Ключ порядка последней отданной строки; «Весь день» — час `-1`.
  final ({CalendarDate date, int scheduledHour, int sequence}) boundary;
}

final class _IntentionActionsSnapshotHasExpired implements Exception {
  const _IntentionActionsSnapshotHasExpired();
}

IntentionActionsReadFailure _classifyIntentionActionsFailure(Object error) {
  if (error is _IntentionActionsSnapshotHasExpired) {
    return const IntentionActionsSnapshotExpired();
  }
  if (error is StoredGraphCorruption) {
    return const IntentionActionsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const IntentionActionsCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionActionsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const IntentionActionsUnexpectedFailure(),
  };
}
