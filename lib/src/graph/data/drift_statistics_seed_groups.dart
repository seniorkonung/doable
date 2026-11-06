part of 'drift_personal_graph_repository.dart';

/// Исходные данные подсчёта Главной на одной общей ревизии личного графа.
/// Снимок остаётся внутри адаптера и не содержит отображаемых данных и путей.
final class StatisticsSeedGroupsSnapshot {
  StatisticsSeedGroupsSnapshot({
    required this.revision,
    required this.summary,
    required List<ContributionSeedGroup> groups,
  }) : groups = List.unmodifiable(groups);

  final GraphRevision revision;
  final ContributionCounts summary;
  final List<ContributionSeedGroup> groups;
}

/// Внутренняя подготовка данных адаптера для подсчёта достижимости.
extension DriftStatisticsSeedGroupsReading on DriftPersonalGraphRepository {
  /// Получает сводку и опорные группы в одной транзакции очереди.
  /// Отказ SQLite или декодирования отклоняет весь снимок с общей
  /// классификацией [StatisticsReadFailure], без частичного результата.
  Future<StatisticsSeedGroupsSnapshot> readStatisticsSeedGroups({
    required StatisticsPeriod period,
  }) async {
    try {
      // Оба запроса ожидаются до завершения транзакции:
      // https://drift.simonbinder.eu/dart_api/transactions/
      return await _sequencer.run(
        () => _database.transaction(() async {
          final summary = await _readStatisticsSummary(period);
          // Опорные намерения действия — существующие намерения его пути.
          // Намерение, за которым в пути идёт следующее по активной связи их
          // пары, опускается: всё, от чего достижимо оно, достижимо и через
          // следующее, а само оно достигает следующего этой связью. Активная
          // связь существует только между существующими намерениями.
          // Уникальность намерения в пути и группировка по id сохраняют
          // самостоятельный вес полных дубликатов. ORDER BY внутри агрегата
          // даёт равным наборам одинаковый ключ:
          // https://www.sqlite.org/lang_aggfunc.html#group_concat
          final rows = await _database
              .customSelect(
                '''WITH seed_rows AS (
                 SELECT a.id AS action_id, p.intention_id AS seed_id,
                        a.is_completed
                 FROM actions a INDEXED BY actions_date_completion_schedule_order
                 JOIN action_path_items p ON p.action_id = a.id
                 JOIN intentions i ON i.id = p.intention_id
                 WHERE a.date BETWEEN ? AND ? AND NOT EXISTS (
                   SELECT 1 FROM action_path_items n
                   JOIN long_term_relations r
                     ON r.source_intention_id = p.intention_id
                    AND r.related_intention_id = n.intention_id
                   WHERE n.action_id = p.action_id
                     AND n.position = p.position + 1
                     AND r.is_archived = 0
                 )
               ), action_groups AS (
                 SELECT group_concat(seed_id ORDER BY seed_id) AS seed_key,
                        MAX(is_completed) AS is_completed
                 FROM seed_rows GROUP BY action_id
               )
               SELECT seed_key, COUNT(*) AS planned,
                      SUM(is_completed) AS contribution
               FROM action_groups GROUP BY seed_key''',
                variables: _statisticsPeriodVariables(period),
                readsFrom: {
                  _database.actions,
                  _database.actionPathItems,
                  _database.intentions,
                  _database.longTermRelations,
                },
              )
              .get();
          final groups = [
            for (final row in rows)
              ContributionSeedGroup(
                seeds: [
                  for (final id in requiredStoredString(
                    row.data,
                    'seed_key',
                  ).split(','))
                    decodeStoredIntentionId(id),
                ],
                counts: ContributionCounts(
                  planned: requiredStoredInteger(row.data, 'planned'),
                  contribution: requiredStoredInteger(row.data, 'contribution'),
                ),
              ),
          ];
          return StatisticsSeedGroupsSnapshot(
            revision: _currentRevision,
            summary: summary,
            groups: groups,
          );
        }),
      );
    } on Object catch (error) {
      throw _classifyStatisticsReadFailure(error);
    }
  }
}
