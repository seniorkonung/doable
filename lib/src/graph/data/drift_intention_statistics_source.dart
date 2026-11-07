part of 'drift_personal_graph_repository.dart';

/// Исходные данные раздела одной ревизии, только внутри адаптера.
/// Названия, описания и полные пути не загружаются. Календарная часть — дата
/// дня для месяца, первое число месяца для года. Подсчёт достижимости и
/// порционирование принадлежат reader, использующему этот снимок.
final class IntentionStatisticsSourceSnapshot {
  IntentionStatisticsSourceSnapshot._({
    required this.revision,
    required this.view,
    required this.periodCounts,
    required this.rootIntentions,
    required this.intermediateIntentions,
    required this.terminalIntentions,
    required this.savedPathDetails,
    required List<IntentionContributionGroup<CalendarDate>> groups,
    required List<ContributionOutgoingRelation> activeOutgoingRelations,
  }) : groups = List.unmodifiable(groups),
       activeOutgoingRelations = List.unmodifiable(activeOutgoingRelations);

  final GraphRevision revision;

  /// Вид запроса либо выбранный по всем действиям намерения.
  final StatisticsView view;
  final ContributionCounts periodCounts;
  final ContributionCounts rootIntentions;
  final ContributionCounts intermediateIntentions;
  final ContributionCounts terminalIntentions;

  /// null для вида «Через связи»: его данные вычисляются по активному графу.
  final IntentionSavedPathStatistics? savedPathDetails;
  final List<IntentionContributionGroup<CalendarDate>> groups;
  final List<ContributionOutgoingRelation> activeOutgoingRelations;
}

/// Агрегаты роли выбранного вида без отображаемых данных.
/// Ключи разбивок соответствуют выбранному виду; строки уже упорядочены.
final class IntentionSavedPathStatistics {
  IntentionSavedPathStatistics._({
    required this.counts,
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

  final ContributionCounts counts;
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

          final view =
              query.view ??
              await _readDefaultIntentionStatisticsView(query.intentionId);
          final periodCounts = await _readStatisticsSummary(query.period);
          final rows = await _readIntentionContributionGroups(query, view);
          final groups = <IntentionContributionGroup<CalendarDate>>[];
          final root = _IntentionStatisticsTotal();
          final intermediate = _IntentionStatisticsTotal();
          final terminal = _IntentionStatisticsTotal();
          final calendar = <CalendarDate, _IntentionStatisticsTotal>{};
          final breakdowns =
              <
                StatisticsBreakdown,
                Map<IntentionId, _IntentionStatisticsTotal>
              >{
                if (view != StatisticsView.throughRelations)
                  for (final breakdown in view.breakdowns) breakdown: {},
              };
          final chosen = _IntentionStatisticsTotal();
          for (final row in rows) {
            final data = row.data;
            final isOnPath = _statisticsFlag(data, 'is_on_path');
            final isRoot = _statisticsFlag(data, 'is_root');
            final isTerminal = _statisticsFlag(data, 'is_terminal');
            final following = _nullableStatisticsId(
              data,
              'following_relation_id',
            );
            if (((isRoot || isTerminal) && !isOnPath) ||
                (following != null && (!isOnPath || isTerminal))) {
              throw const StatisticsDataValidationException();
            }
            final position = !isOnPath
                ? const ContributionOutsidePath()
                : isTerminal
                ? ContributionTerminalOnPath(isRoot: isRoot)
                : ContributionBeforeTerminal(
                    isRoot: isRoot,
                    followingRelationId: following == null
                        ? null
                        : decodeStoredRelationId(following),
                  );
            final counts = ContributionCounts(
              planned: requiredStoredInteger(data, 'planned'),
              contribution: requiredStoredInteger(data, 'contribution'),
            );
            if (counts.planned == 0) {
              throw const StatisticsDataValidationException();
            }
            final part = CalendarDate.parseCanonical(
              requiredStoredString(data, 'calendar_part'),
            );
            if (!query.period.contains(part) ||
                (query.period is StatisticsYear && part.day != 1)) {
              throw const StatisticsDataValidationException();
            }
            final terminalIntention = _nullableStatisticsId(
              data,
              'terminal_intention_id',
            );
            groups.add(
              IntentionContributionGroup(
                seeds: [
                  for (final seed in requiredStoredString(
                    data,
                    'seed_key',
                  ).split(','))
                    decodeStoredIntentionId(seed),
                ],
                terminalIntentionId: terminalIntention == null
                    ? null
                    : decodeStoredIntentionId(terminalIntention),
                calendarPart: part,
                pathPosition: position,
                counts: counts,
              ),
            );
            final roles = {
              if (isRoot) StatisticsView.rootIntentions: root,
              if (isOnPath && !isRoot && !isTerminal)
                StatisticsView.intermediateIntentions: intermediate,
              if (isTerminal) StatisticsView.terminalIntentions: terminal,
            };
            for (final total in roles.values) {
              total.add(counts);
            }
            if (!roles.containsKey(view)) continue;
            chosen.add(counts);
            (calendar[part] ??= _IntentionStatisticsTotal()).add(counts);
            for (final entry in breakdowns.entries) {
              final id = _nullableStatisticsId(data, switch (entry.key) {
                StatisticsBreakdown.rootIntentions => 'breakdown_root_id',
                StatisticsBreakdown.terminalIntentions =>
                  'breakdown_terminal_id',
                StatisticsBreakdown.relations =>
                  throw const StatisticsDataValidationException(),
              });
              if (id == null) continue;
              (entry.value[decodeStoredIntentionId(id)] ??=
                      _IntentionStatisticsTotal())
                  .add(counts);
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
            view: view,
            periodCounts: periodCounts,
            rootIntentions: root.counts,
            intermediateIntentions: intermediate.counts,
            terminalIntentions: terminal.counts,
            savedPathDetails: view == StatisticsView.throughRelations
                ? null
                : IntentionSavedPathStatistics._(
                    counts: chosen.counts,
                    calendarCounts: {
                      for (final entry in calendar.entries)
                        entry.key: entry.value.counts,
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
                  relationId: decodeStoredRelationId(
                    requiredStoredString(row.data, 'id'),
                  ),
                  targetId: decodeStoredIntentionId(
                    requiredStoredString(row.data, 'related_intention_id'),
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

  /// Роль с наибольшим числом действий намерения за всё время, при равенстве
  /// первая в порядке видов. Без них — «Через связи», если активные связи
  /// ведут от намерения к намерению какого-либо пути, иначе корневая роль.
  Future<StatisticsView> _readDefaultIntentionStatisticsView(
    IntentionId intentionId,
  ) async {
    final id = Variable<String>(intentionId.toCanonicalString());
    // Строки намерения находятся по индексу ролей, следующая позиция того же
    // пути — по первичному ключу строк пути.
    final roles = await _database
        .customSelect(
          '''SELECT COALESCE(SUM(p.position = 0), 0) AS root_actions,
                COALESCE(SUM(p.position > 0 AND n.action_id IS NOT NULL), 0)
                  AS intermediate_actions,
                COALESCE(SUM(n.action_id IS NULL), 0) AS terminal_actions
         FROM action_path_items p
           INDEXED BY action_path_items_intention_action
         LEFT JOIN action_path_items n
           ON n.action_id = p.action_id AND n.position = p.position + 1
         WHERE p.intention_id = ?''',
          variables: [id],
          readsFrom: {_database.actionPathItems},
        )
        .getSingle();
    var view = StatisticsView.rootIntentions;
    var most = 0;
    for (final (role, column) in [
      (StatisticsView.rootIntentions, 'root_actions'),
      (StatisticsView.intermediateIntentions, 'intermediate_actions'),
      (StatisticsView.terminalIntentions, 'terminal_actions'),
    ]) {
      final count = requiredStoredInteger(roles.data, column);
      if (count < 0) throw const StatisticsDataValidationException();
      if (count > most) (view, most) = (role, count);
    }
    if (most > 0) return view;
    // UNION отбрасывает уже пройденные намерения, поэтому циклы конечны:
    // https://www.sqlite.org/lang_with.html#recursive_query_examples
    // Активные связи соединяют только существующие намерения. Строки путей
    // ищутся по индексу для каждого достигнутого намерения, а не просмотром.
    final reached = await _database
        .customSelect(
          '''WITH RECURSIVE reachable(id) AS (
               SELECT ?1
               UNION
               SELECT r.related_intention_id
               FROM reachable
               JOIN long_term_relations r ON r.source_intention_id = reachable.id
               WHERE r.is_archived = 0
             )
             SELECT EXISTS (
               SELECT 1 FROM reachable WHERE EXISTS (
                 SELECT 1 FROM action_path_items p
                   INDEXED BY action_path_items_intention_action
                 WHERE p.intention_id = reachable.id
               )
             ) AS reached''',
          variables: [id],
          readsFrom: {_database.longTermRelations, _database.actionPathItems},
        )
        .getSingle();
    return _statisticsFlag(reached.data, 'reached')
        ? StatisticsView.throughRelations
        : StatisticsView.rootIntentions;
  }

  Future<List<QueryRow>> _readIntentionContributionGroups(
    IntentionStatisticsQuery query,
    StatisticsView view,
  ) {
    final calendar = switch (query.period) {
      StatisticsMonth() => 'date',
      StatisticsYear() => "substr(date, 1, 7) || '-01'",
    };
    // Другие намерения пути нужны только разбивкам выбранного вида.
    // Остальные группы не разделяются по неиспользуемым участникам.
    final (breakdownRoot, breakdownTerminal) = switch (view) {
      StatisticsView.rootIntentions => (
        'NULL',
        'CASE WHEN is_root AND NOT is_terminal THEN terminal_id END',
      ),
      StatisticsView.intermediateIntentions => (
        'CASE WHEN is_on_path AND NOT is_root AND NOT is_terminal '
            'THEN root_id END',
        'CASE WHEN is_on_path AND NOT is_root AND NOT is_terminal '
            'THEN terminal_id END',
      ),
      StatisticsView.terminalIntentions => (
        'CASE WHEN is_terminal AND NOT is_root THEN root_id END',
        'NULL',
      ),
      StatisticsView.throughRelations => ('NULL', 'NULL'),
    };
    final through = view == StatisticsView.throughRelations;
    final following = through ? 'next_relation_id' : 'NULL';
    final terminalIntention = through
        ? 'CASE WHEN NOT is_terminal THEN terminal_id END'
        : 'NULL';
    // Следующая позиция того же пути ищется по первичному ключу строк пути,
    // связь пары — по её уникальному ключу. Опорное намерение опускается,
    // если следующее за ним в пути достижимо активной связью их пары и не
    // является рассматриваемым: всё, от чего достижимо опущенное, достигает
    // следующего, в том числе в обход рассматриваемого. Удалённые намерения
    // опорными, корневыми и конечными элементами не бывают. ORDER BY внутри
    // агрегата даёт равным наборам одинаковый ключ:
    // https://www.sqlite.org/lang_aggfunc.html#group_concat
    return _database
        .customSelect(
          '''WITH path_rows AS (
               SELECT a.id AS action_id, a.date, a.is_completed, p.position,
                      p.intention_id, i.id AS existing_id,
                      n.action_id IS NULL AS is_last, r.id AS relation_id,
                      i.id IS NOT NULL AND NOT COALESCE(
                        r.is_archived = 0 AND n.intention_id <> ?1, 0
                      ) AS is_seed
               FROM actions a INDEXED BY actions_date_completion_schedule_order
               JOIN action_path_items p ON p.action_id = a.id
               LEFT JOIN intentions i ON i.id = p.intention_id
               LEFT JOIN action_path_items n
                 ON n.action_id = p.action_id AND n.position = p.position + 1
               LEFT JOIN long_term_relations r
                 ON r.source_intention_id = p.intention_id
                AND r.related_intention_id = n.intention_id
               WHERE a.date BETWEEN ?2 AND ?3
             ), action_bases AS (
               SELECT date, is_completed,
                      MAX(intention_id = ?1) AS is_on_path,
                      MAX(intention_id = ?1 AND position = 0) AS is_root,
                      MAX(intention_id = ?1 AND is_last) AS is_terminal,
                      MAX(CASE WHEN intention_id = ?1 THEN relation_id END)
                        AS next_relation_id,
                      MAX(CASE WHEN position = 0 THEN existing_id END) AS root_id,
                      MAX(CASE WHEN is_last THEN existing_id END) AS terminal_id,
                      group_concat(existing_id ORDER BY existing_id)
                        FILTER (WHERE is_seed) AS seed_key
               FROM path_rows
               GROUP BY action_id, date, is_completed
             )
             SELECT seed_key, is_on_path, is_root, is_terminal,
                    $following AS following_relation_id,
                    $terminalIntention AS terminal_intention_id,
                    $calendar AS calendar_part,
                    $breakdownRoot AS breakdown_root_id,
                    $breakdownTerminal AS breakdown_terminal_id,
                    COUNT(*) AS planned, SUM(is_completed) AS contribution
             FROM action_bases
             WHERE seed_key IS NOT NULL
             GROUP BY seed_key, is_on_path, is_root, is_terminal,
                      following_relation_id, terminal_intention_id,
                      calendar_part, breakdown_root_id, breakdown_terminal_id''',
          variables: [
            Variable<String>(query.intentionId.toCanonicalString()),
            ..._statisticsPeriodVariables(query.period),
          ],
          readsFrom: {
            _database.actions,
            _database.actionPathItems,
            _database.intentions,
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

bool _statisticsFlag(Map<String, Object?> data, String key) =>
    switch (requiredStoredInteger(data, key)) {
      0 => false,
      1 => true,
      _ => throw const StatisticsDataValidationException(),
    };

final class _IntentionStatisticsTotal {
  int planned = 0;
  int contribution = 0;

  void add(ContributionCounts counts) {
    planned += counts.planned;
    contribution += counts.contribution;
  }

  ContributionCounts get counts =>
      ContributionCounts(planned: planned, contribution: contribution);
}

List<ContributionReachabilityEntry> _sortedIntentionStatisticsCounts(
  Map<IntentionId, _IntentionStatisticsTotal> totals,
) =>
    [
      for (final entry in totals.entries)
        (intentionId: entry.key, counts: entry.value.counts),
    ]..sort((a, b) {
      final planned = b.counts.planned.compareTo(a.counts.planned);
      if (planned != 0) return planned;
      final contribution = b.counts.contribution.compareTo(
        a.counts.contribution,
      );
      return contribution != 0
          ? contribution
          : b.intentionId.compareTo(a.intentionId);
    });
