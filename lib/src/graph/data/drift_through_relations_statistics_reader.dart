part of 'drift_personal_graph_repository.dart';

/// Подсчёт получает только типизированные данные; очередь и SQLite ему
/// недоступны. Подмена позволяет управлять завершением изолята в проверках.
/// Возвращает неизменяемые количества в порядке вклада, запланированного
/// вклада и идентификатора по убыванию либо передаёт отказ подсчёта.
typedef ContributionReachabilityRunner =
    Future<List<ContributionReachabilityEntry>> Function(
      ContributionRelationGraph graph,
      List<ContributionSeedGroup> groups,
    );

/// Отдельная функция исключает захват репозитория замыканием изолята:
/// https://api.dart.dev/dart-isolate/Isolate/run.html
Future<List<ContributionReachabilityEntry>>
runContributionReachabilityInIsolate(
  ContributionRelationGraph graph,
  List<ContributionSeedGroup> groups,
) => Isolate.run(() => computeContributionReachability(graph, groups));

/// Внутренняя сборка чтения вида «Через связи» за общей границей репозитория.
extension _ThroughRelationsStatisticsReading on DriftPersonalGraphRepository {
  /// Одна попытка: подготовка и названия идут через общую очередь, подсчёт —
  /// вне неё. Устаревание, включая вытеснение кэша, требует новой первой порции.
  /// Курсор связан со всеми условиями [query] и ревизией, включая эпоху.
  Future<StatisticsPageResult> _readThroughRelationsStatisticsPage(
    StatisticsQuery query,
  ) async {
    try {
      if (query.cursor != null) {
        return StatisticsPageSuccess(
          await _statisticsStage(StatisticsReadDiagnosticsStage.titles, () {
            final cursor = query.cursor;
            if (cursor is! _ThroughRelationsStatisticsCursor ||
                !cursor.matches(query)) {
              throw const StatisticsSnapshotExpired();
            }
            final cached = _throughRelationsResults
                .where((entry) => identical(entry.key, cursor.resultKey))
                .firstOrNull;
            if (cached == null) throw const StatisticsSnapshotExpired();
            return _readThroughRelationsSlice(query, cached, cursor.offset);
          }),
        );
      }

      var result = _throughRelationsResults
          .where((entry) => entry.matches(query, _currentRevision))
          .firstOrNull;
      if (result == null) {
        final source = await _statisticsStage(
          StatisticsReadDiagnosticsStage.sourceData,
          () => readStatisticsSeedGroups(
            period: query.period,
            localDate: query.localDate,
          ),
        );
        final graph = await _statisticsStage(
          StatisticsReadDiagnosticsStage.relationSnapshot,
          loadStatisticsRelationSnapshot,
        );
        final entries = await _statisticsStage(
          StatisticsReadDiagnosticsStage.computation,
          () => _statisticsReachabilityRunner(graph, source.groups),
        );
        result = _ThroughRelationsStatisticsResult(query, source, entries);
      }
      final ready = result;
      return StatisticsPageSuccess(
        await _statisticsStage(
          StatisticsReadDiagnosticsStage.titles,
          () => _readThroughRelationsSlice(query, ready, 0),
        ),
      );
    } on Object catch (error) {
      return StatisticsPageError(_classifyStatisticsReadFailure(error));
    }
  }

  Future<StatisticsPage> _readThroughRelationsSlice(
    StatisticsQuery query,
    _ThroughRelationsStatisticsResult result,
    int offset,
  ) => _sequencer.run(() async {
    final page = await _database.transaction(() async {
      if (!result.matches(query, _currentRevision)) {
        throw const StatisticsSnapshotExpired();
      }
      final end = (offset + query.pageSize).clamp(0, result.entries.length);
      final items = await _readStatisticsItems(
        result.entries.sublist(offset, end),
      );
      final nextCursor = end < result.entries.length
          ? _ThroughRelationsStatisticsCursor(query, result.key, end)
          : null;
      return query.cursor == null
          ? StatisticsFirstPage(
              summary: result.summary,
              totalItems: result.entries.length,
              items: items,
              revision: result.revision,
              nextCursor: nextCursor,
            )
          : StatisticsContinuationPage(
              items: items,
              revision: result.revision,
              nextCursor: nextCursor,
            );
    });
    // Две вкладки Главной удерживают по одному периоду. Курсор хранит лишь ключ,
    // поэтому вытесненные количества не остаются в памяти через продолжения.
    _throughRelationsResults.removeWhere(
      (entry) =>
          identical(entry, result) ||
          entry.revision.compareTo(_currentRevision) != GraphRevisionOrder.same,
    );
    _throughRelationsResults.add(result);
    if (_throughRelationsResults.length > 2) {
      _throughRelationsResults.removeAt(0);
    }
    return page;
  });
}

final class _ThroughRelationsStatisticsResult {
  _ThroughRelationsStatisticsResult(
    StatisticsQuery query,
    StatisticsSeedGroupsSnapshot source,
    this.entries,
  ) : period = query.period,
      localDate = query.localDate,
      revision = source.revision,
      summary = source.summary;

  final Object key = Object();
  final StatisticsPeriod period;
  final CalendarDate localDate;
  final GraphRevision revision;
  final StatisticsPeriodSummary summary;
  final List<ContributionReachabilityEntry> entries;

  bool matches(StatisticsQuery query, GraphRevision currentRevision) =>
      period == query.period &&
      localDate == query.localDate &&
      revision.compareTo(currentRevision) == GraphRevisionOrder.same;
}

final class _ThroughRelationsStatisticsCursor implements StatisticsCursor {
  _ThroughRelationsStatisticsCursor(
    StatisticsQuery query,
    this.resultKey,
    this.offset,
  ) : period = query.period,
      view = query.view,
      localDate = query.localDate,
      pageSize = query.pageSize;

  final Object resultKey;
  final int offset;
  final StatisticsPeriod period;
  final StatisticsView view;
  final CalendarDate localDate;
  final int pageSize;

  bool matches(StatisticsQuery query) =>
      period == query.period &&
      view == query.view &&
      localDate == query.localDate &&
      pageSize == query.pageSize;
}
