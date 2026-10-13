part of 'drift_personal_graph_repository.dart';

/// Исходные данные раздела одной ревизии, только внутри адаптера.
/// Названия, описания и полные пути не загружаются. Календарная часть — дата
/// дня для месяца, первое число месяца для года. Подсчёт достижимости и
/// порционирование принадлежат reader, использующему этот снимок.
final class IntentionStatisticsSourceSnapshot {
  IntentionStatisticsSourceSnapshot._({
    required this.revision,
    required this.periodSummary,
    required this.sourceIntentions,
    required this.intermediateIntentions,
    required this.selectedActions,
    required this.savedPathDetails,
    required List<IntentionContributionGroup<CalendarDate>> groups,
    required List<ContributionOutgoingRelation> activeOutgoingRelations,
  }) : groups = List.unmodifiable(groups),
       activeOutgoingRelations = List.unmodifiable(activeOutgoingRelations);

  final GraphRevision revision;
  final StatisticsPeriodSummary periodSummary;
  final ContributionCounts sourceIntentions;
  final ContributionCounts intermediateIntentions;
  final ContributionCounts selectedActions;

  /// null для вида «Через связи»: его данные вычисляются по активному графу.
  final IntentionSavedPathStatistics? savedPathDetails;
  final List<IntentionContributionGroup<CalendarDate>> groups;
  final List<ContributionOutgoingRelation> activeOutgoingRelations;
}

/// Агрегаты выбранного вида по сохранённому пути без отображаемых данных.
/// Ключи разбивок соответствуют выбранному виду; строки уже упорядочены.
final class IntentionSavedPathStatistics {
  IntentionSavedPathStatistics._({
    required this.summary,
    required Map<CalendarDate, ContributionCounts> calendarCounts,
    required Map<StatisticsBreakdown, List<ContributionReachabilityEntry>>
    breakdowns,
  }) : calendarCounts = Map.unmodifiable(calendarCounts),
       breakdowns = Map.unmodifiable({
         for (final entry in breakdowns.entries)
           entry.key: List<ContributionReachabilityEntry>.unmodifiable(
             entry.value,
           ),
       });

  final StatisticsPeriodSummary summary;
  final Map<CalendarDate, ContributionCounts> calendarCounts;
  final Map<StatisticsBreakdown, List<ContributionReachabilityEntry>>
  breakdowns;
}

extension DriftIntentionStatisticsSourceReading
    on DriftPersonalGraphRepository {
  /// null означает отсутствие намерения, а не пустую статистику.
  /// Все остальные отказы отклоняют снимок целиком по общей классификации.
  Future<IntentionStatisticsSourceSnapshot?> readIntentionStatisticsSource(
    IntentionStatisticsQuery query,
  ) async {
    try {
      // Все запросы ожидаются внутри одной транзакции общей очереди:
      // https://drift.simonbinder.eu/dart_api/transactions/
      return await _sequencer.run(
        () => _database.transaction(() async {
          final exists = await _database
              .customSelect(
                'SELECT 1 FROM intentions WHERE id = ?',
                variables: [
                  Variable<String>(query.intentionId.toCanonicalString()),
                ],
                readsFrom: {_database.intentions},
              )
              .getSingleOrNull();
          if (exists == null) return null;

          // Общая сводка также проверяет исходные даты и выполнение до того,
          // как SQL свернёт их до календарных частей и суммарных весов.
          final periodSummary = await _readStatisticsSummary(
            query.period,
            query.localDate,
          );
          final rows = await _readIntentionContributionGroups(query);
          final groups = <IntentionContributionGroup<CalendarDate>>[];
          final source = _IntentionStatisticsTotal();
          final intermediate = _IntentionStatisticsTotal();
          final selected = _IntentionStatisticsTotal();
          final calendar = <CalendarDate, _IntentionStatisticsTotal>{};
          final breakdowns =
              <
                StatisticsBreakdown,
                Map<IntentionId, _IntentionStatisticsTotal>
              >{
                if (query.view != StatisticsView.throughRelations)
                  for (final breakdown in query.view.breakdowns) breakdown: {},
              };
          final chosen = _IntentionStatisticsTotal();
          for (final row in rows) {
            final data = row.data;
            final action = _decodeStoredRelationIntentionId(
              _requiredStoredString(data, 'selected_intention_id'),
            );
            final predecessor = _nullableStatisticsId(data, 'predecessor_id');
            final following = _nullableStatisticsId(
              data,
              'following_relation_id',
            );
            final position = action == query.intentionId
                ? const ContributionSelectedOnPath()
                : following == null
                ? const ContributionOutsidePath()
                : ContributionBeforeSelectedAction(
                    predecessorId: predecessor == null
                        ? null
                        : _decodeStoredRelationIntentionId(predecessor),
                    followingRelationId: _decodeStoredRelationId(following),
                  );
            final archivedSeeds = _nullableStatisticsId(
              data,
              'archived_seed_key',
            );
            final summary = StatisticsPeriodSummary(
              counts: ContributionCounts(
                planned: _requiredStoredInteger(data, 'planned'),
                contribution: _requiredStoredInteger(data, 'contribution'),
              ),
              uncompleted: UncompletedSplit(
                missed: _requiredStoredInteger(data, 'missed'),
                upcoming: _requiredStoredInteger(data, 'upcoming'),
              ),
            );
            if (summary.counts.planned == 0) {
              throw const StatisticsDataValidationException();
            }
            final part = CalendarDate.parseCanonical(
              _requiredStoredString(data, 'calendar_part'),
            );
            if (!query.period.contains(part) ||
                (query.period is StatisticsYear && part.day != 1)) {
              throw const StatisticsDataValidationException();
            }
            groups.add(
              IntentionContributionGroup(
                seeds: [
                  action,
                  if (archivedSeeds != null)
                    for (final seed in archivedSeeds.split(','))
                      _decodeStoredRelationIntentionId(seed),
                ],
                selectedActionId: action,
                calendarPart: part,
                pathPosition: position,
                summary: summary,
              ),
            );
            final (role, total) = switch (position) {
              ContributionOutsidePath() => (null, null),
              ContributionSelectedOnPath() => (
                StatisticsView.selectedActions,
                selected,
              ),
              ContributionBeforeSelectedAction(predecessorId: null) => (
                StatisticsView.sourceIntentions,
                source,
              ),
              ContributionBeforeSelectedAction() => (
                StatisticsView.intermediateIntentions,
                intermediate,
              ),
            };
            total?.add(summary);
            if (role != query.view) continue;
            chosen.add(summary);
            (calendar[part] ??= _IntentionStatisticsTotal()).add(summary);
            for (final entry in breakdowns.entries) {
              final id = switch (entry.key) {
                StatisticsBreakdown.sourceIntentions =>
                  _decodeStoredRelationIntentionId(
                    _requiredStoredString(data, 'breakdown_source_id'),
                  ),
                StatisticsBreakdown.selectedActions => action,
                StatisticsBreakdown.relations =>
                  throw const StatisticsDataValidationException(),
              };
              (entry.value[id] ??= _IntentionStatisticsTotal()).add(summary);
            }
          }
          final outgoing = await _database
              .customSelect(
                '''SELECT id, related_intention_id FROM long_term_relations
             WHERE source_intention_id = ? AND is_archived = 0''',
                variables: [
                  Variable<String>(query.intentionId.toCanonicalString()),
                ],
                readsFrom: {_database.longTermRelations},
              )
              .get();
          return IntentionStatisticsSourceSnapshot._(
            revision: _currentRevision,
            periodSummary: periodSummary,
            sourceIntentions: source.summary.counts,
            intermediateIntentions: intermediate.summary.counts,
            selectedActions: selected.summary.counts,
            savedPathDetails: query.view == StatisticsView.throughRelations
                ? null
                : IntentionSavedPathStatistics._(
                    summary: chosen.summary,
                    calendarCounts: {
                      for (final entry in calendar.entries)
                        entry.key: entry.value.summary.counts,
                    },
                    breakdowns: {
                      for (final entry in breakdowns.entries)
                        entry.key: _sortedIntentionStatisticsCounts(
                          entry.value,
                        ),
                    },
                  ),
            groups: groups,
            activeOutgoingRelations: [
              for (final row in outgoing)
                (
                  relationId: _decodeStoredRelationId(
                    _requiredStoredString(row.data, 'id'),
                  ),
                  targetId: _decodeStoredRelationIntentionId(
                    _requiredStoredString(row.data, 'related_intention_id'),
                  ),
                ),
            ],
          );
        }),
      );
    } on Object catch (error) {
      throw _classifyStatisticsReadFailure(error);
    }
  }

  Future<List<QueryRow>> _readIntentionContributionGroups(
    IntentionStatisticsQuery query,
  ) {
    final calendar = switch (query.period) {
      StatisticsMonth() => 'choice_date',
      StatisticsYear() => "substr(choice_date, 1, 7) || '-01'",
    };
    // Исходное намерение нужно только для выбранной разбивки. Остальные
    // группы не разделяются по неиспользуемому исходному участнику.
    final breakdownSource = switch (query.view) {
      StatisticsView.intermediateIntentions => 'CASE WHEN following_relation_id IS NOT NULL AND predecessor_id IS NOT NULL THEN source_intention_id END',
      StatisticsView.selectedActions =>
        'CASE WHEN selected_intention_id = ?1 THEN source_intention_id END',
      StatisticsView.sourceIntentions ||
      StatisticsView.throughRelations => 'NULL',
    };
    // Простой сохранённый путь гарантирует единственных соседей X. Сначала
    // извлекаем их из шагов, затем группируем самостоятельные выборы. Сортировка
    // архивных оснований даёт одинаковый ключ независимо от порядка шагов:
    // https://www.sqlite.org/lang_aggfunc.html#group_concat
    // Уточнённый набор однозначно задан старым набором и предшественником X;
    // его строит computeIntentionContribution, без повторного чтения пути.
    return _database
        .customSelect(
          '''WITH choice_bases AS (
        SELECT c.id, c.source_intention_id, c.selected_intention_id,
               c.choice_date, c.is_completed,
               group_concat(r.source_intention_id ORDER BY r.source_intention_id)
                 FILTER (WHERE r.is_archived = 1) AS archived_seed_key,
               MAX(CASE WHEN r.related_intention_id = ?1 THEN r.source_intention_id END) AS predecessor_id,
               MAX(CASE WHEN r.source_intention_id = ?1 THEN r.id END) AS following_relation_id
        FROM daily_choices c INDEXED BY daily_choices_date_creation_order
        JOIN daily_choice_path_steps s ON s.daily_choice_id = c.id
        JOIN long_term_relations r ON r.id = s.long_term_relation_id
        WHERE c.choice_date BETWEEN ?2 AND ?3
        GROUP BY c.id
      )
      SELECT selected_intention_id, archived_seed_key, predecessor_id,
             following_relation_id, $calendar AS calendar_part,
             $breakdownSource AS breakdown_source_id,
             COUNT(*) AS planned, SUM(is_completed) AS contribution,
             SUM(CASE WHEN is_completed = 0 AND choice_date < ?4 THEN 1 ELSE 0 END) AS missed,
             SUM(CASE WHEN is_completed = 0 AND choice_date >= ?4 THEN 1 ELSE 0 END) AS upcoming
      FROM choice_bases
      GROUP BY selected_intention_id, archived_seed_key, predecessor_id,
               following_relation_id, calendar_part, breakdown_source_id''',
          variables: [
            Variable<String>(query.intentionId.toCanonicalString()),
            ..._statisticsPeriodVariables(query.period),
            Variable<String>(query.localDate.toCanonicalString()),
          ],
          readsFrom: {
            _database.dailyChoices,
            _database.dailyChoicePathSteps,
            _database.longTermRelations,
          },
        )
        .get();
  }
}

String? _nullableStatisticsId(Map<String, Object?> data, String key) =>
    switch (data[key]) {
      null => null,
      final String value => value,
      _ => throw const StatisticsDataValidationException(),
    };

final class _IntentionStatisticsTotal {
  int planned = 0;
  int contribution = 0;
  int missed = 0;
  int upcoming = 0;

  void add(StatisticsPeriodSummary summary) {
    planned += summary.counts.planned;
    contribution += summary.counts.contribution;
    missed += summary.uncompleted.missed;
    upcoming += summary.uncompleted.upcoming;
  }

  StatisticsPeriodSummary get summary => StatisticsPeriodSummary(
    counts: ContributionCounts(planned: planned, contribution: contribution),
    uncompleted: UncompletedSplit(missed: missed, upcoming: upcoming),
  );
}

List<ContributionReachabilityEntry> _sortedIntentionStatisticsCounts(
  Map<IntentionId, _IntentionStatisticsTotal> totals,
) =>
    [
      for (final entry in totals.entries)
        (intentionId: entry.key, counts: entry.value.summary.counts),
    ]..sort((a, b) {
      final contribution = b.counts.contribution.compareTo(
        a.counts.contribution,
      );
      if (contribution != 0) return contribution;
      final planned = b.counts.planned.compareTo(a.counts.planned);
      return planned != 0 ? planned : b.intentionId.compareTo(a.intentionId);
    });
