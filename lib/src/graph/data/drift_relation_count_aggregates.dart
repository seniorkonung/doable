import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../data/local/sqlite_relation_integrity_functions.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';

final class RelationCountAggregate {
  const RelationCountAggregate({
    required this.counts,
    required this.hasIntegrityViolation,
  });

  final RelationCounts counts;
  final bool hasIntegrityViolation;
}

/// Получает проверенные агрегаты непосредственных связей внутри SQLite.
final class DriftRelationCountAggregates {
  const DriftRelationCountAggregates(this._database);

  final AppDatabase _database;

  Future<Map<IntentionId, RelationCountAggregate>> read(
    Iterable<IntentionId> intentionIds,
  ) async {
    final requested = <String, IntentionId>{};
    for (final id in intentionIds) {
      requested[id.toCanonicalString()] = id;
    }
    if (requested.isEmpty) return const {};

    final values = List.filled(requested.length, '(?)').join(', ');
    final rows = await _database
        .customSelect(
          _aggregateSql(values),
          variables: [
            for (final serialized in requested.keys)
              Variable<String>(serialized),
          ],
          readsFrom: {_database.intentions, _database.longTermRelations},
        )
        .get();
    final bySerializedId = <String, RelationCountAggregate>{
      for (final row in rows)
        row.read<String>('owner_id'): RelationCountAggregate(
          counts: RelationCounts(
            activeNeedIncoming: row.read<int>('active_need_incoming'),
            activeNeedOutgoing: row.read<int>('active_need_outgoing'),
            activeCanIncoming: row.read<int>('active_can_incoming'),
            activeCanOutgoing: row.read<int>('active_can_outgoing'),
            archivedNeedIncoming: row.read<int>('archived_need_incoming'),
            archivedNeedOutgoing: row.read<int>('archived_need_outgoing'),
            archivedCanIncoming: row.read<int>('archived_can_incoming'),
            archivedCanOutgoing: row.read<int>('archived_can_outgoing'),
          ),
          hasIntegrityViolation: row.read<int>('has_integrity_violation') != 0,
        ),
    };

    return Map.unmodifiable({
      for (final entry in requested.entries)
        entry.value:
            bySerializedId[entry.key] ??
            (throw StateError('SQLite не вернул агрегат намерения.')),
    });
  }
}

String _aggregateSql(String requestedValues) =>
    '''
  /* doable_relation_count_aggregates */
  WITH requested(owner_id) AS (VALUES $requestedValues),
  neighboring AS (
    SELECT
      requested.owner_id AS owner_id,
      1 AS is_outgoing,
      relation.type AS relation_type,
      relation.is_archived AS relation_is_archived,
      CASE WHEN ${_validRelationPredicate('relation', 'source', 'related')}
        THEN 0 ELSE 1 END AS integrity_violation
    FROM requested
    JOIN long_term_relations AS relation
      INDEXED BY long_term_relations_source_group_order
      ON relation.source_intention_id = requested.owner_id
    LEFT JOIN intentions AS source
      ON source.id = relation.source_intention_id
    LEFT JOIN intentions AS related
      ON related.id = relation.related_intention_id

    UNION ALL

    SELECT
      requested.owner_id AS owner_id,
      0 AS is_outgoing,
      relation.type AS relation_type,
      relation.is_archived AS relation_is_archived,
      CASE WHEN ${_validRelationPredicate('relation', 'source', 'related')}
        THEN 0 ELSE 1 END AS integrity_violation
    FROM requested
    JOIN long_term_relations AS relation
      INDEXED BY long_term_relations_related_group_order
      ON relation.related_intention_id = requested.owner_id
    LEFT JOIN intentions AS source
      ON source.id = relation.source_intention_id
    LEFT JOIN intentions AS related
      ON related.id = relation.related_intention_id
  ),
  aggregated AS (
    SELECT
      owner_id,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 0
        AND relation_type = 'need' AND is_outgoing = 0 THEN 1 ELSE 0 END)
        AS active_need_incoming,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 0
        AND relation_type = 'need' AND is_outgoing = 1 THEN 1 ELSE 0 END)
        AS active_need_outgoing,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 0
        AND relation_type = 'can' AND is_outgoing = 0 THEN 1 ELSE 0 END)
        AS active_can_incoming,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 0
        AND relation_type = 'can' AND is_outgoing = 1 THEN 1 ELSE 0 END)
        AS active_can_outgoing,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 1
        AND relation_type = 'need' AND is_outgoing = 0 THEN 1 ELSE 0 END)
        AS archived_need_incoming,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 1
        AND relation_type = 'need' AND is_outgoing = 1 THEN 1 ELSE 0 END)
        AS archived_need_outgoing,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 1
        AND relation_type = 'can' AND is_outgoing = 0 THEN 1 ELSE 0 END)
        AS archived_can_incoming,
      SUM(CASE WHEN integrity_violation = 0 AND relation_is_archived = 1
        AND relation_type = 'can' AND is_outgoing = 1 THEN 1 ELSE 0 END)
        AS archived_can_outgoing,
      MAX(integrity_violation) AS has_integrity_violation
    FROM neighboring
    GROUP BY owner_id
  )
  SELECT
    requested.owner_id AS owner_id,
    COALESCE(aggregated.active_need_incoming, 0) AS active_need_incoming,
    COALESCE(aggregated.active_need_outgoing, 0) AS active_need_outgoing,
    COALESCE(aggregated.active_can_incoming, 0) AS active_can_incoming,
    COALESCE(aggregated.active_can_outgoing, 0) AS active_can_outgoing,
    COALESCE(aggregated.archived_need_incoming, 0) AS archived_need_incoming,
    COALESCE(aggregated.archived_need_outgoing, 0) AS archived_need_outgoing,
    COALESCE(aggregated.archived_can_incoming, 0) AS archived_can_incoming,
    COALESCE(aggregated.archived_can_outgoing, 0) AS archived_can_outgoing,
    COALESCE(aggregated.has_integrity_violation, 0)
      AS has_integrity_violation
  FROM requested
  LEFT JOIN aggregated USING (owner_id)
  ORDER BY requested.owner_id
''';

String _validRelationPredicate(
  String relation,
  String source,
  String related,
) =>
    '''
  typeof($relation.creation_sequence) = 'integer'
  AND $relation.creation_sequence > 0
  AND typeof($relation.id) = 'text'
  AND $relationIdIntegrityFunctionName(CAST($relation.id AS BLOB)) = 1
  AND typeof($relation.source_intention_id) = 'text'
  AND $intentionIdIntegrityFunctionName(
    CAST($relation.source_intention_id AS BLOB)
  ) = 1
  AND typeof($relation.related_intention_id) = 'text'
  AND $intentionIdIntegrityFunctionName(
    CAST($relation.related_intention_id AS BLOB)
  ) = 1
  AND CAST($relation.source_intention_id AS BLOB)
    <> CAST($relation.related_intention_id AS BLOB)
  AND typeof($relation.type) = 'text'
  AND CAST($relation.type AS BLOB) IN (x'6e656564', x'63616e')
  AND typeof($relation.priority) = 'integer'
  AND $relation.priority BETWEEN 1 AND 4
  AND (
    $relation.description IS NULL OR (
      typeof($relation.description) = 'text'
      AND $relationDescriptionIntegrityFunctionName(
        CAST($relation.description AS BLOB)
      ) = 1
    )
  )
  AND typeof($relation.is_archived) = 'integer'
  AND $relation.is_archived IN (0, 1)
  AND $source.id IS NOT NULL
  AND typeof($source.is_archived) = 'integer'
  AND $source.is_archived IN (0, 1)
  AND $related.id IS NOT NULL
  AND typeof($related.is_archived) = 'integer'
  AND $related.is_archived IN (0, 1)
  AND (
    $relation.is_archived = 1 OR (
      $source.is_archived = 0 AND $related.is_archived = 0
    )
  )
''';
