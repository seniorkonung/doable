part of 'drift_personal_graph_repository.dart';

const _pathCandidateRelationColumns = '''
  r.creation_sequence, r.id, r.source_intention_id, r.related_intention_id,
  r.type, r.priority, r.description, r.is_archived, r.created_at,
  r.updated_at''';

extension _PathCandidatesReading on DriftPersonalGraphRepository {
  Future<PathCandidatesResult> _readPathCandidates(
    PathCandidatesQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    final isContinuation = query.cursor != null;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      PathCandidatesReadDiagnosticsEvent(
        pageSize: query.pageSize,
        isContinuation: isContinuation,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final read = await _sequencer.run(
        () => _database.transaction(() => _readPathCandidatesOnSnapshot(query)),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return PathCandidatesSuccess(read);
    } on Object catch (error) {
      final failure = _classifyPathCandidatesFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return PathCandidatesError(failure);
    }
  }

  Future<PathCandidatesRead> _readPathCandidatesOnSnapshot(
    PathCandidatesQuery query,
  ) async {
    final _DriftPathCandidatesCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftPathCandidatesCursor own => own,
      _ => throw StateError('Недопустимый курсор кандидатов пути.'),
    };
    if (cursor != null) {
      if (!_samePathDraft(cursor.draft, query.draft) ||
          cursor.half != query.half ||
          cursor.pageSize != query.pageSize ||
          cursor.revision.compareTo(_currentRevision) !=
              GraphRevisionOrder.same) {
        throw const _PathCandidatesSnapshotHasExpired();
      }
      // На той же ревизии участок тот же, поэтому продолжение его не
      // перечитывает.
      final (:items, :boundary) = await _readPathCandidateRows(
        segmentIds: cursor.segmentIds,
        half: query.half,
        pageSize: query.pageSize,
        after: cursor.boundary,
      );
      return PathCandidatesContinuationPage(
        items: items,
        nextCursor: boundary == null ? null : cursor.continuedAt(boundary),
        revision: cursor.revision,
      );
    }

    final revision = _currentRevision;
    final segment = await _readPathSegment(query.draft);
    if (segment == null) return EmptyPathSegment(revision: revision);
    final segmentIds = [
      segment.root.id,
      for (final step in segment.steps) step.intention.id,
    ];
    final counts = await _readPathCandidateCounts(segmentIds);
    final (:items, :boundary) = await _readPathCandidateRows(
      segmentIds: segmentIds,
      half: query.half,
      pageSize: query.pageSize,
      after: null,
    );
    return PathCandidatesFirstPage(
      segment: segment,
      counts: counts,
      items: items,
      nextCursor: boundary == null
          ? null
          : _DriftPathCandidatesCursor(
              revision: revision,
              draft: query.draft,
              half: query.half,
              pageSize: query.pageSize,
              segmentIds: segmentIds,
              boundary: boundary,
            ),
      revision: revision,
    );
  }

  /// Участок от корневого намерения черновика до первого разрыва либо
  /// `null`, если корневое удалено или в архиве.
  Future<PathSegment?> _readPathSegment(ActionPath draft) async {
    final intentions = draft.intentions;
    // Каждая позиция несёт свою пару звена, поэтому намерение и связь
    // находятся поиском по ключу без соединения позиций между собой.
    final rows = await _database
        .customSelect(
          '''WITH draft(position, intention_id, previous_intention_id) AS (
           VALUES ${List.filled(intentions.length, '(?, ?, ?)').join(', ')}
         )
         SELECT d.position, i.id AS i_id, i.title AS i_title,
                i.description AS i_description,
                i.kind AS i_kind,
                i.is_archived AS i_is_archived, i.created_at AS i_created_at,
                i.updated_at AS i_updated_at, $_pathCandidateRelationColumns
         FROM draft d
         LEFT JOIN intentions i ON i.id = d.intention_id
         LEFT JOIN long_term_relations r
           ON r.source_intention_id = d.previous_intention_id
          AND r.related_intention_id = d.intention_id''',
          variables: [
            for (final (position, id) in intentions.indexed) ...[
              Variable<int>(position),
              Variable<String>(id.toCanonicalString()),
              Variable<String>(
                position == 0
                    ? null
                    : intentions[position - 1].toCanonicalString(),
              ),
            ],
          ],
          readsFrom: {_database.intentions, _database.longTermRelations},
        )
        .get();
    final byPosition = {
      for (final row in rows)
        requiredStoredInteger(row.data, 'position'): row.data,
    };
    if (byPosition.length != intentions.length) {
      throw const StoredGraphCorruption();
    }

    domain.Intention? activeIntentionAt(int position) {
      final data = byPosition[position]!;
      if (data['i_id'] == null) return null;
      final intention = decodeStoredIntention(data, 'i_');
      if (intention.id != intentions[position]) {
        throw const StoredGraphCorruption();
      }
      return switch (intention.archiveState) {
        domain.IntentionArchiveState.active => intention,
        domain.IntentionArchiveState.archived => null,
      };
    }

    final root = activeIntentionAt(0);
    if (root == null) return null;
    final steps = <PathSegmentStep>[];
    for (var position = 1; position < intentions.length; position++) {
      final data = byPosition[position]!;
      if (data['id'] == null) break;
      final relation = StoredLongTermRelation.decode(data).toDomain();
      if (relation.sourceIntentionId != intentions[position - 1] ||
          relation.relatedIntentionId != intentions[position]) {
        throw const StoredGraphCorruption();
      }
      if (relation.scope == relation_domain.RelationScope.archived) break;
      // Активная связь требует активных участников (триггеры схемы).
      final intention =
          activeIntentionAt(position) ?? (throw const StoredGraphCorruption());
      steps.add(PathSegmentStep(relation: relation, intention: intention));
    }
    return PathSegment(root: root, steps: steps);
  }

  /// Числа обеих половин: все активные связи группы последнего намерения по
  /// индексу группы без чтения строк, за вычетом связей к намерениям участка.
  /// Унарный плюс оставляет для вычитаемого только индекс уникальной пары,
  /// чтобы оно читало строки участка, а не всю группу.
  Future<PathCandidateCounts> _readPathCandidateCounts(
    List<IntentionId> segmentIds,
  ) async {
    final last = Variable<String>(segmentIds.last.toCanonicalString());
    final excluded = [
      for (final id in segmentIds) Variable<String>(id.toCanonicalString()),
    ];
    final placeholders = List.filled(excluded.length, '?').join(', ');
    String countOf(String type) =>
        '''(SELECT COUNT(*) FROM long_term_relations
             INDEXED BY long_term_relations_source_group_order
           WHERE source_intention_id = ? AND type = '$type'
             AND is_archived = 0)
         - (SELECT COUNT(*) FROM long_term_relations
           WHERE source_intention_id = ?
             AND related_intention_id IN ($placeholders)
             AND +type = '$type' AND +is_archived = 0)''';
    final row = await _database
        .customSelect(
          'SELECT ${countOf('need')} AS need_count, '
          '${countOf('can')} AS can_count',
          variables: [
            for (var half = 0; half < 2; half++) ...[last, last, ...excluded],
          ],
          readsFrom: {_database.longTermRelations},
        )
        .getSingle();
    return PathCandidateCounts(
      need: requiredStoredInteger(row.data, 'need_count'),
      can: requiredStoredInteger(row.data, 'can_count'),
    );
  }

  /// Порция кандидатов после [after] и ключ её последней строки, если за ней
  /// есть ещё строки.
  Future<({List<PathCandidate> items, _PathCandidateBoundary? boundary})>
  _readPathCandidateRows({
    required List<IntentionId> segmentIds,
    required relation_domain.LongTermRelationType half,
    required int pageSize,
    required _PathCandidateBoundary? after,
  }) async {
    final type = switch (half) {
      relation_domain.LongTermRelationType.need => 'need',
      relation_domain.LongTermRelationType.can => 'can',
    };
    final placeholders = List.filled(segmentIds.length, '?').join(', ');
    // Сравнение полного ключа продолжает порядок без OFFSET:
    // https://www.sqlite.org/rowvalue.html#scrolling_window_queries
    final keyFilter = after == null
        ? ''
        : 'AND (r.priority, r.creation_sequence) > (?, ?)';
    final rawRows = await _database
        .customSelect(
          '''SELECT $_pathCandidateRelationColumns,
                i.title AS i_title, i.is_archived AS i_is_archived
         FROM long_term_relations r
           INDEXED BY long_term_relations_source_group_order
         JOIN intentions i ON i.id = r.related_intention_id
         WHERE r.source_intention_id = ? AND r.type = ? AND r.is_archived = 0
           AND r.related_intention_id NOT IN ($placeholders)
           $keyFilter
         ORDER BY r.priority, r.creation_sequence
         LIMIT ?''',
          variables: [
            Variable<String>(segmentIds.last.toCanonicalString()),
            Variable<String>(type),
            for (final id in segmentIds)
              Variable<String>(id.toCanonicalString()),
            if (after != null) ...[
              Variable<int>(after.priority),
              Variable<int>(after.creationSequence),
            ],
            Variable<int>(pageSize + 1),
          ],
          readsFrom: {_database.longTermRelations, _database.intentions},
        )
        .get();
    final items = [
      for (final row in rawRows.take(pageSize))
        _decodePathCandidate(row.data, segmentIds.last, half),
    ];
    if (rawRows.length <= pageSize) return (items: items, boundary: null);
    final last = rawRows[pageSize - 1].data;
    return (
      items: items,
      boundary: (
        priority: requiredStoredInteger(last, 'priority'),
        creationSequence: requiredStoredInteger(last, 'creation_sequence'),
      ),
    );
  }
}

PathCandidate _decodePathCandidate(
  Map<String, Object?> data,
  IntentionId source,
  relation_domain.LongTermRelationType half,
) {
  final relation = StoredLongTermRelation.decode(data).toDomain();
  // Активная связь требует активных участников (триггеры схемы).
  if (relation.sourceIntentionId != source ||
      relation.type != half ||
      relation.scope != relation_domain.RelationScope.active ||
      decodeStoredIntentionArchiveState(data, 'i_is_archived') !=
          domain.IntentionArchiveState.active) {
    throw const StoredGraphCorruption();
  }
  return PathCandidate(
    relation: relation,
    title: decodeStoredIntentionTitle(data, 'i_title'),
  );
}

bool _samePathDraft(ActionPath a, ActionPath b) {
  if (a.intentions.length != b.intentions.length) return false;
  for (var index = 0; index < a.intentions.length; index++) {
    if (a.intentions[index] != b.intentions[index]) return false;
  }
  return true;
}

typedef _PathCandidateBoundary = ({int priority, int creationSequence});

final class _DriftPathCandidatesCursor implements PathCandidatesCursor {
  const _DriftPathCandidatesCursor({
    required this.revision,
    required this.draft,
    required this.half,
    required this.pageSize,
    required this.segmentIds,
    required this.boundary,
  });

  final GraphRevision revision;
  final ActionPath draft;
  final relation_domain.LongTermRelationType half;
  final int pageSize;

  /// Намерения участка первой порции; последнее — источник кандидатов.
  final List<IntentionId> segmentIds;

  /// Ключ порядка последней отданной строки.
  final _PathCandidateBoundary boundary;

  _DriftPathCandidatesCursor continuedAt(_PathCandidateBoundary boundary) =>
      _DriftPathCandidatesCursor(
        revision: revision,
        draft: draft,
        half: half,
        pageSize: pageSize,
        segmentIds: segmentIds,
        boundary: boundary,
      );
}

final class _PathCandidatesSnapshotHasExpired implements Exception {
  const _PathCandidatesSnapshotHasExpired();
}

PathCandidatesReadFailure _classifyPathCandidatesFailure(Object error) {
  if (error is _PathCandidatesSnapshotHasExpired) {
    return const PathCandidatesSnapshotExpired();
  }
  if (error is StoredGraphCorruption) {
    return const PathCandidatesCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const PathCandidatesCorruptionFailure(),
    SqliteUnavailableFailure() => const PathCandidatesUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const PathCandidatesUnexpectedFailure(),
  };
}
