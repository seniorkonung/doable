part of 'drift_personal_graph_repository.dart';

enum _PathRoleStatisticsView { root, intermediate, terminal }

extension _StatisticsReading on DriftPersonalGraphRepository {
  Future<StatisticsPageResult> _readStatisticsPage(
    StatisticsQuery query,
    _PathRoleStatisticsView view,
  ) async {
    var stage = StatisticsReadDiagnosticsStage.sourceData;
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      StatisticsReadDiagnosticsEvent(
        readType: StatisticsReadDiagnosticsType.homePage,
        stage: stage,
        status: status,
      ),
    );
    record(const DiagnosticsStarted());
    try {
      // Все чтения снимка ожидаются внутри одной транзакции Drift:
      // https://drift.simonbinder.eu/dart_api/transactions/
      final page = await _sequencer.run(
        () => _database.transaction(() async {
          final cursor = switch (query.cursor) {
            null => null,
            final _DriftStatisticsCursor own
                when own.matches(query, _currentRevision) =>
              own,
            _ => throw const StatisticsSnapshotExpired(),
          };
          final summary = cursor == null
              ? await _readStatisticsSummary(query.period)
              : null;
          final aggregate = _statisticsAggregate(
            view,
            includeTotal: cursor == null,
          );
          final variables = _statisticsPeriodVariables(query.period);
          // Сравнение полного ключа сохраняет порядок равных вкладов:
          // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
          final boundary = cursor == null
              ? ''
              : 'HAVING (planned, contribution, intention_id) < (?, ?, ?)';
          final rows = await _database
              .customSelect(
                '''$aggregate $boundary
             ORDER BY planned DESC, contribution DESC, intention_id DESC
             LIMIT ?''',
                variables: [
                  ...variables,
                  if (cursor != null) ...[
                    Variable<int>(cursor.counts.planned),
                    Variable<int>(cursor.counts.contribution),
                    Variable<String>(cursor.intentionId.toCanonicalString()),
                  ],
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {
                  _database.actions,
                  _database.actionPathItems,
                  _database.intentions,
                },
              )
              .get();
          int? totalItems;
          if (cursor == null) {
            totalItems = rows.isEmpty
                ? 0
                : requiredStoredInteger(rows.first.data, 'total_items');
            if (totalItems < 0) throw const StatisticsDataValidationException();
          }
          final counts = [
            for (final row in rows)
              (
                intentionId: decodeStoredIntentionId(
                  requiredStoredString(row.data, 'intention_id'),
                ),
                counts: ContributionCounts(
                  planned: requiredStoredInteger(row.data, 'planned'),
                  contribution: requiredStoredInteger(row.data, 'contribution'),
                ),
              ),
          ];
          record(DiagnosticsSucceeded(stopwatch.elapsed));
          stage = StatisticsReadDiagnosticsStage.titles;
          stopwatch.reset();
          record(const DiagnosticsStarted());
          final selected = counts.take(query.pageSize).toList(growable: false);
          final items = await _readStatisticsItems(selected);
          final revision = _currentRevision;
          final nextCursor = rows.length > query.pageSize
              ? _DriftStatisticsCursor(
                  query: query,
                  revision: revision,
                  intentionId: selected.last.intentionId,
                  counts: selected.last.counts,
                )
              : null;
          return cursor == null
              ? StatisticsFirstPage(
                  summary: summary!,
                  totalItems: totalItems!,
                  items: items,
                  revision: revision,
                  nextCursor: nextCursor,
                )
              : StatisticsContinuationPage(
                  items: items,
                  revision: revision,
                  nextCursor: nextCursor,
                );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return StatisticsPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyStatisticsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: switch (failure) {
            StatisticsSnapshotExpired() => DiagnosticsFailureCode.conflict,
            StatisticsIntentionNotFoundFailure() =>
              DiagnosticsFailureCode.notFound,
            StatisticsReadUnavailableFailure() =>
              DiagnosticsFailureCode.unavailable,
            StatisticsReadCorruptionFailure() =>
              DiagnosticsFailureCode.corruption,
            StatisticsReadUnexpectedFailure() =>
              DiagnosticsFailureCode.unexpected,
          },
        ),
      );
      return StatisticsPageError(failure);
    }
  }

  Future<T> _statisticsStage<T>(
    StatisticsReadDiagnosticsStage stage,
    Future<T> Function() read, {
    StatisticsReadDiagnosticsType readType =
        StatisticsReadDiagnosticsType.homePage,
  }) async {
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      StatisticsReadDiagnosticsEvent(
        readType: readType,
        stage: stage,
        status: status,
      ),
    );
    record(const DiagnosticsStarted());
    try {
      final result = await read();
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return result;
    } on Object catch (error) {
      final failure = _classifyStatisticsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: switch (failure) {
            StatisticsSnapshotExpired() => DiagnosticsFailureCode.conflict,
            StatisticsIntentionNotFoundFailure() =>
              DiagnosticsFailureCode.notFound,
            StatisticsReadUnavailableFailure() =>
              DiagnosticsFailureCode.unavailable,
            StatisticsReadCorruptionFailure() =>
              DiagnosticsFailureCode.corruption,
            StatisticsReadUnexpectedFailure() =>
              DiagnosticsFailureCode.unexpected,
          },
        ),
      );
      throw failure;
    }
  }

  Future<List<StatisticsItem>> _readStatisticsItems(
    List<ContributionReachabilityEntry> selected,
  ) async {
    final items = <StatisticsItem>[];
    if (selected.isNotEmpty) {
      final titles = await _database
          .customSelect(
            '''SELECT id, title, is_archived FROM intentions
         WHERE id IN (${List.filled(selected.length, '?').join(', ')})''',
            variables: [
              for (final row in selected)
                Variable<String>(row.intentionId.toCanonicalString()),
            ],
            readsFrom: {_database.intentions},
          )
          .get();
      final byId = {
        for (final row in titles)
          decodeStoredIntentionId(requiredStoredString(row.data, 'id')): row,
      };
      for (final counted in selected) {
        final row = byId[counted.intentionId];
        if (row == null) throw const StoredGraphCorruption();
        items.add(
          StatisticsItem(
            id: counted.intentionId,
            title: requiredStoredString(row.data, 'title'),
            archiveState: decodeStoredIntentionArchiveState(
              row.data,
              'is_archived',
            ),
            counts: counted.counts,
          ),
        );
      }
    }
    return items;
  }

  /// Сводка считает действия периода, а не их засчитывания намерениям,
  /// поэтому не зависит от вида и от удаления намерений их путей.
  Future<ContributionCounts> _readStatisticsSummary(
    StatisticsPeriod period,
  ) async {
    // Группы дат и выполнения читаются из индекса дня. Декодирование проверяет
    // необходимые значения, не материализуя действия и их пути.
    final rows = await _database
        .customSelect(
          '''SELECT date, is_completed, COUNT(*) AS planned
         FROM actions INDEXED BY actions_date_completion_schedule_order
         WHERE date BETWEEN ? AND ?
         GROUP BY date, is_completed''',
          variables: _statisticsPeriodVariables(period),
          readsFrom: {_database.actions},
        )
        .get();
    var planned = 0;
    var contribution = 0;
    for (final row in rows) {
      decodeStoredActionDate(row.data);
      final completed = decodeStoredActionCompletion(row.data);
      final count = requiredStoredInteger(row.data, 'planned');
      if (count <= 0) throw const StatisticsDataValidationException();
      planned += count;
      if (completed) contribution += count;
    }
    return ContributionCounts(planned: planned, contribution: contribution);
  }
}

List<Variable> _statisticsPeriodVariables(StatisticsPeriod period) => [
  Variable<String>(period.firstDate.toCanonicalString()),
  Variable<String>(period.lastDate.toCanonicalString()),
];

String _statisticsAggregate(
  _PathRoleStatisticsView view, {
  required bool includeTotal,
}) {
  // Следующая позиция того же пути ищется по первичному ключу строк пути.
  const hasNextPosition =
      'EXISTS (SELECT 1 FROM action_path_items n '
      'WHERE n.action_id = p.action_id AND n.position = p.position + 1)';
  final role = switch (view) {
    _PathRoleStatisticsView.root => 'p.position = 0',
    _PathRoleStatisticsView.intermediate =>
      'p.position > 0 AND $hasNextPosition',
    _PathRoleStatisticsView.terminal => 'NOT $hasNextPosition',
  };
  // Намерение встречается в пути не больше одного раза, поэтому COUNT считает
  // самостоятельные действия, включая полные дубликаты. Соединение с
  // намерениями исключает удалённые, не передавая их роль соседям.
  // Окно считает группы до LIMIT, без повторной агрегации всех строк:
  // https://www.sqlite.org/windowfunctions.html#aggregate_window_functions
  final total = includeTotal ? ', COUNT(*) OVER() AS total_items' : '';
  return '''SELECT p.intention_id AS intention_id, COUNT(*) AS planned,
              SUM(a.is_completed) AS contribution $total
            FROM actions a INDEXED BY actions_date_completion_schedule_order
            JOIN action_path_items p ON p.action_id = a.id
            JOIN intentions i ON i.id = p.intention_id
            WHERE a.date BETWEEN ? AND ? AND $role
            GROUP BY p.intention_id''';
}

final class _DriftStatisticsCursor implements StatisticsCursor {
  _DriftStatisticsCursor({
    required StatisticsQuery query,
    required this.revision,
    required this.intentionId,
    required this.counts,
  }) : period = query.period,
       view = query.view,
       pageSize = query.pageSize;

  final StatisticsPeriod period;
  final StatisticsView view;
  final int pageSize;
  final GraphRevision revision;
  final IntentionId intentionId;
  final ContributionCounts counts;

  bool matches(StatisticsQuery query, GraphRevision currentRevision) =>
      period == query.period &&
      view == query.view &&
      pageSize == query.pageSize &&
      revision.compareTo(currentRevision) == GraphRevisionOrder.same;
}

StatisticsReadFailure _classifyStatisticsReadFailure(Object error) {
  if (error is StatisticsReadFailure) return error;
  if (error is StoredGraphCorruption ||
      error is StatisticsDataValidationException ||
      error is CalendarDateValidationException ||
      error is IntentionTextValidationException) {
    return const StatisticsReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const StatisticsReadCorruptionFailure(),
    SqliteUnavailableFailure() => const StatisticsReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const StatisticsReadUnexpectedFailure(),
  };
}
