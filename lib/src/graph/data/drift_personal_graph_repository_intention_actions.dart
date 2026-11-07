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
    final variables = <Variable>[];
    // Сравнение полного ключа продолжает порядок без OFFSET:
    // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
    final keyFilter = cursor == null
        ? ''
        : ' AND (order_date, order_hour, order_sequence) < (?, ?, ?)';
    // Каждая хранимая роль — упорядоченный диапазон индекса роли, а слияние
    // диапазонов сохраняет порядок без сортировки строк намерения.
    final ranges = <String>[];
    for (final stored in _StoredActionPathRole.of(query.role)) {
      ranges.add(
        'SELECT action_id, order_date, order_hour, order_sequence '
        'FROM action_path_items '
        "WHERE intention_id = ? AND role = '${stored.name}'$keyFilter",
      );
      variables.add(intentionVariable);
      if (cursor != null) {
        variables.addAll([
          Variable<String>(cursor.boundary.date.toCanonicalString()),
          Variable<int>(cursor.boundary.scheduledHour),
          Variable<int>(cursor.boundary.sequence),
        ]);
      }
    }
    // Поля действий, корень и число намерений пути читаются только для строк
    // порции.
    final rawRows = await _database
        .customSelect(
          '''SELECT $_actionListItemColumns
         FROM (
           ${ranges.join(' UNION ALL ')}
           ORDER BY order_date DESC, order_hour DESC, order_sequence DESC
           LIMIT ?
         ) k
         JOIN actions a ON a.id = k.action_id
         $_actionListItemRootJoins
         ORDER BY k.order_date DESC, k.order_hour DESC,
                  k.order_sequence DESC''',
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
                COALESCE(SUM(role IN ('root', 'single')), 0) AS root_count,
                COALESCE(SUM(role = 'intermediate'), 0) AS intermediate_count,
                COALESCE(SUM(role IN ('terminal', 'single')), 0)
                  AS terminal_count
         FROM action_path_items
         WHERE intention_id = ?''',
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

/// Хранимая роль строки пути. Намерение пути из одного намерения —
/// «единственное»: оно входит и в корневые, и в конечные.
enum _StoredActionPathRole {
  root,
  intermediate,
  terminal,
  single;

  static _StoredActionPathRole at(int position, int length) =>
      switch (position) {
        0 when length == 1 => single,
        0 => root,
        _ when position == length - 1 => terminal,
        _ => intermediate,
      };

  static List<_StoredActionPathRole> of(IntentionActionRole role) =>
      switch (role) {
        IntentionActionRole.root => const [root, single],
        IntentionActionRole.intermediate => const [intermediate],
        IntentionActionRole.terminal => const [terminal, single],
      };
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
