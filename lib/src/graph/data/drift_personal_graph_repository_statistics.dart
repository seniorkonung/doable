part of 'drift_personal_graph_repository.dart';

extension _StatisticsReading on DriftPersonalGraphRepository {
  Future<StatisticsPageResult> _readStatisticsPage(
    StatisticsQuery query,
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
              ? await _readStatisticsSummary(query.period, query.localDate)
              : null;
          final aggregate = _statisticsAggregate(
            query.view,
            includeTotal: cursor == null,
          );
          final variables = _statisticsPeriodVariables(query.period);
          // Сравнение полного ключа сохраняет порядок равных вкладов:
          // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
          final boundary = cursor == null
              ? ''
              : 'HAVING (contribution, planned, intention_id) < (?, ?, ?)';
          final rows = await _database
              .customSelect(
                '''$aggregate $boundary
             ORDER BY contribution DESC, planned DESC, intention_id DESC
             LIMIT ?''',
                variables: [
                  ...variables,
                  if (cursor != null) ...[
                    Variable<int>(cursor.counts.contribution),
                    Variable<int>(cursor.counts.planned),
                    Variable<String>(cursor.intentionId.toCanonicalString()),
                  ],
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {
                  _database.dailyChoices,
                  _database.dailyChoicePathSteps,
                  _database.longTermRelations,
                },
              )
              .get();
          int? totalItems;
          if (cursor == null) {
            totalItems = rows.isEmpty
                ? 0
                : _requiredStoredInteger(rows.first.data, 'total_items');
            if (totalItems < 0) throw const StatisticsDataValidationException();
          }
          final counts = [
            for (final row in rows)
              (
                intentionId: _decodeStoredRelationIntentionId(
                  _requiredStoredString(row.data, 'intention_id'),
                ),
                counts: ContributionCounts(
                  planned: _requiredStoredInteger(row.data, 'planned'),
                  contribution: _requiredStoredInteger(
                    row.data,
                    'contribution',
                  ),
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
          _decodeStoredRelationIntentionId(
            _requiredStoredString(row.data, 'id'),
          ): row,
      };
      for (final counted in selected) {
        final row = byId[counted.intentionId];
        if (row == null) throw const _StoredIntentionCorruption();
        items.add(
          StatisticsItem(
            id: counted.intentionId,
            title: _requiredStoredString(row.data, 'title'),
            archiveState: switch (_requiredStoredInteger(
              row.data,
              'is_archived',
            )) {
              0 => domain.IntentionArchiveState.active,
              1 => domain.IntentionArchiveState.archived,
              _ => throw const _StoredIntentionCorruption(),
            },
            counts: counted.counts,
          ),
        );
      }
    }
    return items;
  }

  Future<StatisticsPeriodSummary> _readStatisticsSummary(
    StatisticsPeriod period,
    CalendarDate localDate,
  ) async {
    // Группы дат и выполнения ограничены календарным периодом. Декодирование
    // проверяет необходимые значения, не материализуя выборы и их пути.
    final rows = await _database
        .customSelect(
          '''SELECT choice_date, is_completed, COUNT(*) AS planned,
           SUM(CASE WHEN is_completed = 0 AND choice_date < ? THEN 1 ELSE 0 END) AS missed,
           SUM(CASE WHEN is_completed = 0 AND choice_date >= ? THEN 1 ELSE 0 END) AS upcoming
         FROM daily_choices INDEXED BY daily_choices_date_creation_order
         WHERE choice_date BETWEEN ? AND ?
         GROUP BY choice_date, is_completed''',
          variables: [
            Variable<String>(localDate.toCanonicalString()),
            Variable<String>(localDate.toCanonicalString()),
            ..._statisticsPeriodVariables(period),
          ],
          readsFrom: {_database.dailyChoices},
        )
        .get();
    var planned = 0;
    var contribution = 0;
    var missed = 0;
    var upcoming = 0;
    for (final row in rows) {
      CalendarDate.parseCanonical(
        _requiredStoredString(row.data, 'choice_date'),
      );
      final completed = switch (_requiredStoredInteger(
        row.data,
        'is_completed',
      )) {
        0 => false,
        1 => true,
        _ => throw const _StoredIntentionCorruption(),
      };
      final count = _requiredStoredInteger(row.data, 'planned');
      final group = StatisticsPeriodSummary(
        counts: ContributionCounts(
          planned: count,
          contribution: completed ? count : 0,
        ),
        uncompleted: UncompletedSplit(
          missed: _requiredStoredInteger(row.data, 'missed'),
          upcoming: _requiredStoredInteger(row.data, 'upcoming'),
        ),
      );
      planned += group.counts.planned;
      contribution += group.counts.contribution;
      missed += group.uncompleted.missed;
      upcoming += group.uncompleted.upcoming;
    }
    return StatisticsPeriodSummary(
      counts: ContributionCounts(planned: planned, contribution: contribution),
      uncompleted: UncompletedSplit(missed: missed, upcoming: upcoming),
    );
  }
}

List<Variable> _statisticsPeriodVariables(StatisticsPeriod period) => [
  Variable<String>(period.firstDate.toCanonicalString()),
  Variable<String>(period.lastDate.toCanonicalString()),
];

String _statisticsAggregate(StatisticsView view, {required bool includeTotal}) {
  final id = switch (view) {
    StatisticsView.sourceIntentions => 'c.source_intention_id',
    StatisticsView.intermediateIntentions => 'r.related_intention_id',
    StatisticsView.selectedActions => 'c.selected_intention_id',
  };
  final path = view == StatisticsView.intermediateIntentions
      ? '''JOIN daily_choice_path_steps s ON s.daily_choice_id = c.id
         JOIN long_term_relations r ON r.id = s.long_term_relation_id'''
      : '';
  final intermediate = view == StatisticsView.intermediateIntentions
      ? 'AND r.related_intention_id <> c.selected_intention_id'
      : '';
  // Простой сохранённый путь содержит промежуточное намерение один раз.
  // COUNT учитывает самостоятельные выборы, включая полные дубликаты.
  // Окно считает группы до LIMIT, без повторной агрегации всех шагов:
  // https://www.sqlite.org/windowfunctions.html#aggregate_window_functions
  final total = includeTotal ? ', COUNT(*) OVER() AS total_items' : '';
  return '''SELECT $id AS intention_id, COUNT(*) AS planned,
              SUM(c.is_completed) AS contribution $total
            FROM daily_choices c INDEXED BY daily_choices_date_creation_order
            $path
            WHERE c.choice_date BETWEEN ? AND ? $intermediate
            GROUP BY $id''';
}

final class _DriftStatisticsCursor implements StatisticsCursor {
  _DriftStatisticsCursor({
    required StatisticsQuery query,
    required this.revision,
    required this.intentionId,
    required this.counts,
  }) : period = query.period,
       view = query.view,
       localDate = query.localDate,
       pageSize = query.pageSize;

  final StatisticsPeriod period;
  final StatisticsView view;
  final CalendarDate localDate;
  final int pageSize;
  final GraphRevision revision;
  final IntentionId intentionId;
  final ContributionCounts counts;

  bool matches(StatisticsQuery query, GraphRevision currentRevision) =>
      period == query.period &&
      view == query.view &&
      localDate == query.localDate &&
      pageSize == query.pageSize &&
      revision.compareTo(currentRevision) == GraphRevisionOrder.same;
}

StatisticsReadFailure _classifyStatisticsReadFailure(Object error) {
  if (error is StatisticsReadFailure) return error;
  if (error is _StoredIntentionCorruption ||
      error is StatisticsDataValidationException ||
      error is CalendarDateValidationException ||
      error is IntentionTextValidationException) {
    return const StatisticsReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const StatisticsReadCorruptionFailure(),
    SqliteUnavailableFailure() => const StatisticsReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const StatisticsReadUnexpectedFailure(),
  };
}
