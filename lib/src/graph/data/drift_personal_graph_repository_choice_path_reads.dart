part of 'drift_personal_graph_repository.dart';

extension _ChoicePathContinuationReading on DriftPersonalGraphRepository {
  Future<ChoicePathContinuationResult> _readChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = ChoicePathContinuationReadStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      ChoicePathContinuationReadDiagnosticsEvent(
        stage: stage,
        pageSize: query.pageSize,
        isContinuation: query.cursor != null,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(
          () => _readChoicePathPageOnSnapshot(query, () {
            record(DiagnosticsSucceeded(stopwatch.elapsed));
            stopwatch.reset();
            stage = ChoicePathContinuationReadStage.read;
            record(const DiagnosticsStarted());
          }),
        ),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return ChoicePathContinuationSuccess(page);
    } on Object catch (error) {
      final failure = _classifyChoicePathReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return ChoicePathContinuationError(failure);
    }
  }

  Future<ChoicePathContinuationsPage> _readChoicePathPageOnSnapshot(
    ChoicePathContinuationQuery query,
    void Function() onValidated,
  ) async {
    final _DriftChoicePathCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftChoicePathCursor own => own,
      _ => throw StateError('Недопустимый курсор продолжений пути.'),
    };
    if (cursor != null &&
        cursor.revision.compareTo(_currentRevision) !=
            GraphRevisionOrder.same) {
      throw const _ChoicePathSnapshotHasExpired();
    }

    final draft = query.draft;
    final isBottomUp = draft.direction == ChoicePathDraftDirection.bottomUp;
    final visited = <IntentionId>[
      draft.startingIntentionId,
      for (final step in draft.steps)
        isBottomUp ? step.sourceIntentionId : step.relatedIntentionId,
    ];
    final visitedJson = jsonEncode([
      for (final id in visited) id.toCanonicalString(),
    ]);
    final intentionRows = await _database
        .customSelect(
          '''SELECT id, title, description, is_action_ready, is_archived,
                    created_at, updated_at
             FROM intentions WHERE id IN (SELECT value FROM json_each(?))''',
          variables: [Variable<String>(visitedJson)],
          readsFrom: {_database.intentions},
        )
        .get();
    final intentions = <IntentionId, domain.Intention>{};
    for (final row in intentionRows) {
      final intention = decodeStoredIntention(row.data);
      intentions[intention.id] = intention;
    }
    if (!intentions.containsKey(draft.startingIntentionId) ||
        !intentions.containsKey(draft.currentIntentionId)) {
      throw const _ChoicePathIntentionNotFound();
    }
    if (intentions.length != visited.length ||
        intentions.values.any(
          (intention) =>
              intention.archiveState != domain.IntentionArchiveState.active,
        )) {
      throw const _ChoicePathSnapshotHasExpired();
    }
    if (isBottomUp &&
        intentions[draft.startingIntentionId]!.readiness !=
            domain.IntentionReadiness.ready) {
      throw const _ChoicePathSnapshotHasExpired();
    }

    if (draft.steps.isNotEmpty) {
      final relationRows = await _database
          .customSelect(
            '''SELECT creation_sequence, id, source_intention_id,
                      related_intention_id, type, priority, description,
                      is_archived
               FROM long_term_relations
               WHERE id IN (SELECT value FROM json_each(?))''',
            variables: [
              Variable<String>(
                jsonEncode([
                  for (final step in draft.steps)
                    step.relationId.toCanonicalString(),
                ]),
              ),
            ],
            readsFrom: {_database.longTermRelations},
          )
          .get();
      final relations = <LongTermRelationId, StoredLongTermRelation>{};
      for (final row in relationRows) {
        final relation = StoredLongTermRelation.decode(row.data);
        relations[relation.id] = relation;
      }
      if (relations.length != draft.steps.length) {
        throw const _ChoicePathSnapshotHasExpired();
      }
      for (final step in draft.steps) {
        final actual = relations[step.relationId];
        if (actual == null ||
            actual.sourceIntentionId != step.sourceIntentionId ||
            actual.relatedIntentionId != step.relatedIntentionId ||
            actual.type != step.type ||
            actual.scope != relation_domain.RelationScope.active) {
          throw const _ChoicePathSnapshotHasExpired();
        }
      }
    }

    onValidated();

    // Рекурсивный набор верхнего обхода хранит только вершины: UNION
    // завершает циклы без перечисления путей.
    final boundary = cursor != null
        ? '''AND (CASE WHEN r.type = 'need' THEN 0 ELSE 1 END,
                   r.priority, r.creation_sequence) > (?, ?, ?)'''
        : '';
    final candidatesSql = isBottomUp
        ? '''WITH visited(id) AS (SELECT value FROM json_each(?))
             SELECT r.creation_sequence, r.id, r.source_intention_id,
                    r.related_intention_id, r.type, r.priority,
                    r.description, r.is_archived
             FROM long_term_relations r
             JOIN intentions source ON source.id = r.source_intention_id
             WHERE r.related_intention_id = ? AND r.is_archived = 0
               AND source.is_archived = 0
               AND r.source_intention_id NOT IN (SELECT id FROM visited)'''
        : '''WITH RECURSIVE
               visited(id) AS (SELECT value FROM json_each(?)),
               reachable(id) AS (
                 SELECT id FROM intentions
                 WHERE is_archived = 0 AND is_action_ready = 1
                   AND id NOT IN (SELECT id FROM visited)
                 UNION
                 SELECT r.source_intention_id
                 FROM long_term_relations r
                 JOIN reachable next ON next.id = r.related_intention_id
                 JOIN intentions source ON source.id = r.source_intention_id
                 WHERE r.is_archived = 0 AND source.is_archived = 0
                   AND r.source_intention_id NOT IN (SELECT id FROM visited)
               )
             SELECT r.creation_sequence, r.id, r.source_intention_id,
                    r.related_intention_id, r.type, r.priority,
                    r.description, r.is_archived
             FROM long_term_relations r
             JOIN reachable ON reachable.id = r.related_intention_id
             WHERE r.source_intention_id = ? AND r.is_archived = 0''';
    final rawRows = await _database
        .customSelect(
          '''$candidatesSql
             $boundary
             ORDER BY CASE WHEN r.type = 'need' THEN 0 ELSE 1 END,
                      r.priority, r.creation_sequence
             LIMIT ?''',
          variables: [
            Variable<String>(visitedJson),
            Variable<String>(draft.currentIntentionId.toCanonicalString()),
            if (cursor != null) ...[
              Variable<int>(cursor.boundaryGroup),
              Variable<int>(cursor.boundaryPriority),
              Variable<int>(cursor.boundaryCreationSequence),
            ],
            Variable<int>(query.pageSize + 1),
          ],
          readsFrom: {_database.intentions, _database.longTermRelations},
        )
        .get();
    final stored = [
      for (final row in rawRows) StoredLongTermRelation.decode(row.data),
    ];
    if (stored.any(
      (row) =>
          (isBottomUp
              ? row.relatedIntentionId != draft.currentIntentionId ||
                    visited.contains(row.sourceIntentionId)
              : row.sourceIntentionId != draft.currentIntentionId ||
                    visited.contains(row.relatedIntentionId)) ||
          row.scope != relation_domain.RelationScope.active ||
          row.sourceIntentionId == row.relatedIntentionId,
    )) {
      throw const StoredGraphCorruption();
    }
    final pageRows = stored.take(query.pageSize).toList(growable: false);
    final participants = await _readRelationParticipants({
      for (final row in pageRows) ...[
        row.sourceIntentionId,
        row.relatedIntentionId,
      ],
    });
    final items = [
      for (final row in pageRows)
        LongTermRelationSummary(
          relation: row.toDomain(),
          source:
              participants[row.sourceIntentionId] ??
              (throw const StoredGraphCorruption()),
          related:
              participants[row.relatedIntentionId] ??
              (throw const StoredGraphCorruption()),
          hasDescription: row.hasDescription,
        ),
    ];
    if (items.any(
      (item) =>
          (isBottomUp ? item.source : item.related).archiveState !=
          domain.IntentionArchiveState.active,
    )) {
      throw const StoredGraphCorruption();
    }
    final revision = _currentRevision;
    return ChoicePathContinuationsPage(
      draft: draft,
      current: intentions[draft.currentIntentionId]!,
      items: items,
      nextCursor: stored.length > query.pageSize
          ? _DriftChoicePathCursor.fromBoundary(
              revision: revision,
              boundary: pageRows.last,
            )
          : null,
      revision: revision,
    );
  }
}

final class _DriftChoicePathCursor implements ChoicePathContinuationCursor {
  _DriftChoicePathCursor.fromBoundary({
    required this.revision,
    required StoredLongTermRelation boundary,
  }) : boundaryGroup =
           boundary.type == relation_domain.LongTermRelationType.need ? 0 : 1,
       boundaryPriority = boundary.priority.index + 1,
       boundaryCreationSequence = boundary.creationSequence;

  final GraphRevision revision;
  final int boundaryGroup;
  final int boundaryPriority;
  final int boundaryCreationSequence;
}

final class _ChoicePathSnapshotHasExpired implements Exception {
  const _ChoicePathSnapshotHasExpired();
}

final class _ChoicePathIntentionNotFound implements Exception {
  const _ChoicePathIntentionNotFound();
}

ChoicePathContinuationFailure _classifyChoicePathReadFailure(Object error) {
  if (error is _ChoicePathSnapshotHasExpired) {
    return const ChoicePathContinuationSnapshotExpired();
  }
  if (error is _ChoicePathIntentionNotFound) {
    return const ChoicePathContinuationIntentionNotFoundFailure();
  }
  if (error is StoredGraphCorruption) {
    return const ChoicePathContinuationCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() =>
      const ChoicePathContinuationCorruptionFailure(),
    SqliteUnavailableFailure() =>
      const ChoicePathContinuationUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() =>
      const ChoicePathContinuationUnexpectedFailure(),
  };
}
