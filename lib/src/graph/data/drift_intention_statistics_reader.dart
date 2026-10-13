part of 'drift_personal_graph_repository.dart';

/// Подмена управляет завершением подсчёта в проверках. Входы не содержат
/// SQLite, репозиторий или пользовательский текст.
typedef IntentionContributionRunner =
    Future<IntentionContributionResult<CalendarDate>> Function(
      ContributionRelationGraph graph,
      IntentionId intentionId,
      List<IntentionContributionGroup<CalendarDate>> groups,
      List<ContributionOutgoingRelation> activeOutgoingRelations,
    );

/// Отдельная функция не захватывает соединение замыканием изолята:
/// https://api.dart.dev/dart-isolate/Isolate/run.html
Future<IntentionContributionResult<CalendarDate>>
runIntentionContributionInIsolate(
  ContributionRelationGraph graph,
  IntentionId intentionId,
  List<IntentionContributionGroup<CalendarDate>> groups,
  List<ContributionOutgoingRelation> activeOutgoingRelations,
) => Isolate.run(
  () => computeIntentionContribution(
    graph: graph,
    intentionId: intentionId,
    groups: groups,
    activeOutgoingRelations: activeOutgoingRelations,
  ),
);

/// Внутренняя сборка чтений раздела и разбивок за общей границей репозитория.
extension _IntentionStatisticsReading on DriftPersonalGraphRepository {
  /// Одна согласованная попытка. null означает отсутствие намерения;
  /// остальные отказы передаются как [StatisticsReadFailure], без повторов.
  Future<IntentionStatisticsSection?> _readIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) async {
    Future<T> stage<T>(
      StatisticsReadDiagnosticsStage stage,
      Future<T> Function() read,
    ) => _statisticsStage(
      stage,
      read,
      readType: StatisticsReadDiagnosticsType.intentionSection,
    );

    var result = _intentionStatisticsResults
        .where((entry) => entry.matches(query, _currentRevision))
        .firstOrNull;
    final fromCache = result != null;
    if (result == null) {
      final source = await stage(
        StatisticsReadDiagnosticsStage.sourceData,
        () => readIntentionStatisticsSource(query),
      );
      if (source == null) return null;
      final graph = await stage(
        StatisticsReadDiagnosticsStage.relationSnapshot,
        loadStatisticsRelationSnapshot,
      );
      final contribution = await stage(
        StatisticsReadDiagnosticsStage.computation,
        () => _intentionStatisticsRunner(
          graph,
          query.intentionId,
          source.groups,
          source.activeOutgoingRelations,
        ),
      );
      result = _IntentionStatisticsResult(query, source, contribution);
    }
    final ready = result;
    return stage(
      StatisticsReadDiagnosticsStage.titles,
      () => _sequencer.run(() async {
        // Все названия обеих разбивок ожидаются в одной транзакции:
        // https://drift.simonbinder.eu/dart_api/transactions/
        final section = await _database.transaction(() async {
          _requireIntentionStatisticsRevision(ready);
          if (fromCache && !_intentionStatisticsResults.contains(ready)) {
            throw const StatisticsSnapshotExpired();
          }
          Future<StatisticsBreakdownFirstPage<StatisticsItem>> intentions(
            _IntentionItemsBreakdown breakdown,
          ) => _IntentionItemsCursor(
            query,
            ready.key,
            0,
            breakdown,
          ).read(this, ready);
          final uncompleted = ready.summary.uncompleted;
          final details = switch (query.view) {
            StatisticsView.sourceIntentions => IntentionStatisticsSourceDetails(
              uncompleted: uncompleted,
              selectedActions: await intentions(
                _IntentionItemsBreakdown.selectedActions,
              ),
            ),
            StatisticsView.intermediateIntentions =>
              IntentionStatisticsIntermediateDetails(
                uncompleted: uncompleted,
                sourceIntentions: await intentions(
                  _IntentionItemsBreakdown.sourceIntentions,
                ),
                selectedActions: await intentions(
                  _IntentionItemsBreakdown.selectedActions,
                ),
              ),
            StatisticsView.selectedActions =>
              IntentionStatisticsSelectedDetails(
                uncompleted: uncompleted,
                sourceIntentions: await intentions(
                  _IntentionItemsBreakdown.sourceIntentions,
                ),
              ),
            StatisticsView.throughRelations =>
              IntentionStatisticsThroughRelationsDetails(
                uncompleted: uncompleted,
                explicitPathChoices: ready.throughRelations.explicitPathChoices,
                relations: await _IntentionRelationsCursor(
                  query,
                  ready.key,
                  0,
                ).read(this, ready),
                selectedActions: await intentions(
                  _IntentionItemsBreakdown.selectedActions,
                ),
              ),
          };
          return IntentionStatisticsSection(
            query: query,
            revision: ready.revision,
            cards: ready.cards,
            periodCounts: ready.periodCounts,
            details: details,
            calendar: ready.calendar,
          );
        });
        _rememberIntentionStatistics(ready);
        return section;
      }),
    );
  }

  /// Курсор задаёт все условия и тип строки. Проверка кэша и ревизии идёт
  /// внутри очереди до чтения названий; вытеснение не вызывает пересчёта.
  Future<StatisticsBreakdownContinuationPage<T>>
  _readIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) =>
      _statisticsStage(
        StatisticsReadDiagnosticsStage.titles,
        () => _sequencer.run(() async {
          final page = await _database.transaction(() async {
            if (cursor is! _IntentionStatisticsCursor<T>) {
              throw const StatisticsSnapshotExpired();
            }
            final result = _intentionStatisticsResults
                .where((entry) => identical(entry.key, cursor.resultKey))
                .firstOrNull;
            if (result == null) throw const StatisticsSnapshotExpired();
            _requireIntentionStatisticsRevision(result);
            final slice = await cursor.read(this, result);
            return (
              result,
              StatisticsBreakdownContinuationPage<T>(
                items: slice.items,
                nextCursor: slice.nextCursor,
                revision: result.revision,
              ),
            );
          });
          _rememberIntentionStatistics(page.$1);
          return page.$2;
        }),
        readType: StatisticsReadDiagnosticsType.breakdown,
      );

  void _requireIntentionStatisticsRevision(_IntentionStatisticsResult result) {
    if (result.revision.compareTo(_currentRevision) !=
        GraphRevisionOrder.same) {
      throw const StatisticsSnapshotExpired();
    }
  }

  void _rememberIntentionStatistics(_IntentionStatisticsResult result) {
    _intentionStatisticsResults.removeWhere(
      (entry) =>
          identical(entry, result) ||
          entry.revision.compareTo(_currentRevision) != GraphRevisionOrder.same,
    );
    _intentionStatisticsResults.add(result);
    // Как у Главной, удерживаются два последних результата. Число страниц
    // в истории не увеличивает кэш: вытесненный курсор требует нового раздела.
    if (_intentionStatisticsResults.length > 2) {
      _intentionStatisticsResults.removeAt(0);
    }
  }

  Future<List<StatisticsRelationItem>> _readStatisticsRelationItems(
    List<ContributionRelationEntry> selected,
  ) async {
    if (selected.isEmpty) return const [];
    final rows = await _database
        .customSelect(
          '''SELECT r.id, r.is_archived, i.id AS intention_id,
                i.title, i.is_archived AS intention_archived
         FROM long_term_relations r
         JOIN intentions i ON i.id = r.related_intention_id
         WHERE r.id IN (${List.filled(selected.length, '?').join(', ')})''',
          variables: [
            for (final row in selected)
              Variable<String>(row.relationId.toCanonicalString()),
          ],
          readsFrom: {_database.longTermRelations, _database.intentions},
        )
        .get();
    final byId = {
      for (final row in rows)
        _decodeStoredRelationId(_requiredStoredString(row.data, 'id')):
            row.data,
    };
    return [
      for (final counted in selected)
        _statisticsRelationItem(counted, byId[counted.relationId]),
    ];
  }
}

StatisticsRelationItem _statisticsRelationItem(
  ContributionRelationEntry counted,
  Map<String, Object?>? row,
) {
  if (row == null) throw const StatisticsDataValidationException();
  return StatisticsRelationItem(
    id: counted.relationId,
    scope: switch (_requiredStoredInteger(row, 'is_archived')) {
      0 => relation_domain.RelationScope.active,
      1 => relation_domain.RelationScope.archived,
      _ => throw const StatisticsDataValidationException(),
    },
    relatedIntention: StatisticsItem(
      id: _decodeStoredRelationIntentionId(
        _requiredStoredString(row, 'intention_id'),
      ),
      title: _requiredStoredString(row, 'title'),
      archiveState: switch (_requiredStoredInteger(row, 'intention_archived')) {
        0 => domain.IntentionArchiveState.active,
        1 => domain.IntentionArchiveState.archived,
        _ => throw const StatisticsDataValidationException(),
      },
      counts: counted.counts,
    ),
  );
}

final class _IntentionStatisticsResult {
  _IntentionStatisticsResult(
    this.query,
    IntentionStatisticsSourceSnapshot source,
    this.throughRelations,
  ) : revision = source.revision,
      periodCounts = source.periodSummary.counts,
      cards = IntentionStatisticsCards(
        sourceIntentions: source.sourceIntentions,
        intermediateIntentions: source.intermediateIntentions,
        selectedActions: source.selectedActions,
        throughRelations: throughRelations.summary.counts,
      ),
      savedPath = source.savedPathDetails;

  final Object key = Object();
  final IntentionStatisticsQuery query;
  final GraphRevision revision;
  final ContributionCounts periodCounts;
  final IntentionStatisticsCards cards;
  final IntentionSavedPathStatistics? savedPath;
  final IntentionContributionResult<CalendarDate> throughRelations;

  StatisticsPeriodSummary get summary =>
      savedPath?.summary ?? throughRelations.summary;

  IntentionStatisticsCalendar get calendar {
    final counts = savedPath?.calendarCounts ?? throughRelations.calendarCounts;
    return switch (query.period) {
      final StatisticsMonth month => IntentionStatisticsMonthCalendar(
        period: month,
        statuses: {
          for (final entry in counts.entries)
            entry.key: entry.value.uncompleted == 0
                ? DailyChoiceDayStatus.allCompleted
                : DailyChoiceDayStatus.hasIncomplete,
        },
      ),
      final StatisticsYear year => IntentionStatisticsYearCalendar(
        period: year,
        months: [
          for (var month = 1; month <= 12; month++)
            counts[CalendarDate.fromParts(year.year, month, 1)] ??
                ContributionCounts(planned: 0, contribution: 0),
        ],
      ),
    };
  }

  bool matches(IntentionStatisticsQuery other, GraphRevision currentRevision) =>
      query.intentionId == other.intentionId &&
      query.period == other.period &&
      query.view == other.view &&
      query.localDate == other.localDate &&
      revision.compareTo(currentRevision) == GraphRevisionOrder.same;
}

/// Курсор хранит условия и ключ, но ни количества, ни замыкание с результатом.
sealed class _IntentionStatisticsCursor<T>
    implements StatisticsBreakdownCursor<T> {
  const _IntentionStatisticsCursor(this.query, this.resultKey, this.offset);
  final IntentionStatisticsQuery query;
  final Object resultKey;
  final int offset;

  Future<StatisticsBreakdownFirstPage<T>> read(
    DriftPersonalGraphRepository repository,
    _IntentionStatisticsResult result,
  );
}

enum _IntentionItemsBreakdown { sourceIntentions, selectedActions }

final class _IntentionItemsCursor
    extends _IntentionStatisticsCursor<StatisticsItem> {
  const _IntentionItemsCursor(
    super.query,
    super.resultKey,
    super.offset,
    this.breakdown,
  );
  final _IntentionItemsBreakdown breakdown;

  @override
  Future<StatisticsBreakdownFirstPage<StatisticsItem>> read(
    DriftPersonalGraphRepository repository,
    _IntentionStatisticsResult result,
  ) async {
    final kind = switch (breakdown) {
      _IntentionItemsBreakdown.sourceIntentions =>
        StatisticsBreakdown.sourceIntentions,
      _IntentionItemsBreakdown.selectedActions =>
        StatisticsBreakdown.selectedActions,
    };
    final entries = switch (result.savedPath) {
      final saved? => saved.breakdowns[kind]!,
      null => result.throughRelations.selectedActions,
    };
    final end = (offset + query.pageSize).clamp(0, entries.length);
    return StatisticsBreakdownFirstPage(
      items: await repository._readStatisticsItems(
        entries.sublist(offset, end),
      ),
      totalItems: entries.length,
      nextCursor: end < entries.length
          ? _IntentionItemsCursor(query, resultKey, end, breakdown)
          : null,
    );
  }
}

final class _IntentionRelationsCursor
    extends _IntentionStatisticsCursor<StatisticsRelationItem> {
  const _IntentionRelationsCursor(super.query, super.resultKey, super.offset);

  @override
  Future<StatisticsBreakdownFirstPage<StatisticsRelationItem>> read(
    DriftPersonalGraphRepository repository,
    _IntentionStatisticsResult result,
  ) async {
    final entries = result.throughRelations.relations;
    final end = (offset + query.pageSize).clamp(0, entries.length);
    return StatisticsBreakdownFirstPage(
      items: await repository._readStatisticsRelationItems(
        entries.sublist(offset, end),
      ),
      totalItems: entries.length,
      nextCursor: end < entries.length
          ? _IntentionRelationsCursor(query, resultKey, end)
          : null,
    );
  }
}
