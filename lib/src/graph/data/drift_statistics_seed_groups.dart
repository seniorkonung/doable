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
  final StatisticsPeriodSummary summary;
  final List<ContributionSeedGroup> groups;
}

/// Внутренняя подготовка данных адаптера для подсчёта достижимости.
extension DriftStatisticsSeedGroupsReading on DriftPersonalGraphRepository {
  /// Получает сводку и опорные группы в одной транзакции очереди.
  /// Отказ SQLite или декодирования отклоняет весь снимок с общей
  /// классификацией [StatisticsReadFailure], без частичного результата.
  Future<StatisticsSeedGroupsSnapshot> readStatisticsSeedGroups({
    required StatisticsPeriod period,
    required CalendarDate localDate,
  }) async {
    try {
      // Оба запроса ожидаются до завершения транзакции:
      // https://drift.simonbinder.eu/dart_api/transactions/
      return await _sequencer.run(
        () => _database.transaction(() async {
          final summary = await _readStatisticsSummary(period, localDate);
          // Простой путь гарантирует уникальность опорных намерений выбора.
          // Группировка по id сохраняет самостоятельный вес полных дубликатов.
          // ORDER BY внутри агрегата даёт равным наборам одинаковый ключ:
          // https://www.sqlite.org/lang_aggfunc.html#group_concat
          final rows = await _database
              .customSelect(
                '''WITH seed_rows AS (
                 SELECT c.id AS choice_id, c.selected_intention_id AS seed_id,
                        c.is_completed
                 FROM daily_choices c INDEXED BY daily_choices_date_creation_order
                 WHERE c.choice_date BETWEEN ? AND ?
                 UNION ALL
                 SELECT c.id, r.source_intention_id, c.is_completed
                 FROM daily_choices c INDEXED BY daily_choices_date_creation_order
                 JOIN daily_choice_path_steps s ON s.daily_choice_id = c.id
                 JOIN long_term_relations r ON r.id = s.long_term_relation_id
                 WHERE c.choice_date BETWEEN ? AND ? AND r.is_archived = 1
               ), choice_groups AS (
                 SELECT group_concat(seed_id ORDER BY seed_id) AS seed_key,
                        MAX(is_completed) AS is_completed
                 FROM seed_rows GROUP BY choice_id
               )
               SELECT seed_key, COUNT(*) AS planned,
                      SUM(is_completed) AS contribution
               FROM choice_groups GROUP BY seed_key''',
                variables: [
                  ..._statisticsPeriodVariables(period),
                  ..._statisticsPeriodVariables(period),
                ],
                readsFrom: {
                  _database.dailyChoices,
                  _database.dailyChoicePathSteps,
                  _database.longTermRelations,
                },
              )
              .get();
          final groups = [
            for (final row in rows)
              ContributionSeedGroup(
                seeds: [
                  for (final id in _requiredStoredString(
                    row.data,
                    'seed_key',
                  ).split(','))
                    _decodeStoredRelationIntentionId(id),
                ],
                counts: ContributionCounts(
                  planned: _requiredStoredInteger(row.data, 'planned'),
                  contribution: _requiredStoredInteger(
                    row.data,
                    'contribution',
                  ),
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
