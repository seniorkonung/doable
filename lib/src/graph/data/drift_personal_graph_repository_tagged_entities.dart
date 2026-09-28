part of 'drift_personal_graph_repository.dart';

extension _TaggedEntitiesReading on DriftPersonalGraphRepository {
  Future<TaggedEntitiesPageResult> _readTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TaggedEntitiesPageReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(() async {
          final cursor = query.cursor;
          if (cursor != null &&
              (cursor is! _DriftTaggedEntitiesCursor ||
                  !cursor.matches(query, _epoch))) {
            throw const _InvalidTaggedEntitiesCursor();
          }
          if (cursor is _DriftTaggedEntitiesCursor &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TaggedEntitiesSnapshotHasExpired();
          }

          stage = TagReadDiagnosticsStage.read;
          final storageVersion = await _tagReadStorageVersion();
          final tagRow = await _database
              .customSelect(
                '''SELECT id, name,
                   CASE WHEN substr(name, 1, 1) = char(65279) THEN 1 ELSE 0 END AS has_leading_bom
                   FROM tags WHERE id = ?''',
                variables: [Variable<String>(query.tagId.toCanonicalString())],
                readsFrom: {_database.tags},
              )
              .getSingleOrNull();
          if (tagRow == null) {
            final dangling = await _database
                .customSelect(
                  'SELECT 1 FROM tag_assignments WHERE tag_id = ? LIMIT 1',
                  variables: [
                    Variable<String>(query.tagId.toCanonicalString()),
                  ],
                  readsFrom: {_database.tagAssignments},
                )
                .getSingleOrNull();
            if (dangling != null) throw const _StoredIntentionCorruption();
            throw const _TaggedEntitiesTagMissing();
          }
          _checkTaggedTextEncoding(tagRow.data);
          final tag = _decodeStoredTag(tagRow.data);
          if (tag.id != query.tagId) throw const _StoredIntentionCorruption();
          if (cursor is _DriftTaggedEntitiesCursor &&
              cursor.storageVersion != storageVersion) {
            throw const _TaggedEntitiesSnapshotHasExpired();
          }
          if (cursor == null) {
            // Курсор свидетельствует о проверке ссылок всего выбранного тега
            // только для этой эпохи, ревизии и версии хранилища.
            await _checkTaggedEntityReferences(query.tagId);
          }

          final boundary = cursor is _DriftTaggedEntitiesCursor
              ? cursor.boundarySequence
              : null;
          final archiveFlag = query.scope == TaggedEntitiesScope.archived
              ? 1
              : 0;
          final rows = await _database
              .customSelect(
                '''SELECT a.creation_sequence AS assignment_sequence,
                 a.intention_id AS assigned_intention_id,
                 a.long_term_relation_id AS assigned_relation_id,
                 i.id AS intention_id, i.title AS intention_title,
                 i.is_archived AS intention_archived,
                 r.id AS relation_id, r.type AS relation_type,
                 r.is_archived AS relation_archived,
                 r.source_intention_id, r.related_intention_id,
                 source.id AS source_id, source.title AS source_title,
                 related.id AS related_id, related.title AS related_title,
                 CASE WHEN substr(a.intention_id, 1, 1) = char(65279)
                   OR substr(a.long_term_relation_id, 1, 1) = char(65279)
                   OR substr(r.source_intention_id, 1, 1) = char(65279)
                   OR substr(r.related_intention_id, 1, 1) = char(65279)
                   OR substr(r.type, 1, 1) = char(65279)
                   OR substr(i.title, 1, 1) = char(65279)
                   OR substr(source.title, 1, 1) = char(65279)
                   OR substr(related.title, 1, 1) = char(65279)
                   THEN 1 ELSE 0 END AS has_leading_bom
               FROM tag_assignments a
               LEFT JOIN intentions i ON i.id = a.intention_id
               LEFT JOIN long_term_relations r ON r.id = a.long_term_relation_id
               LEFT JOIN intentions source ON source.id = r.source_intention_id
               LEFT JOIN intentions related ON related.id = r.related_intention_id
               WHERE a.tag_id = ?
                 ${boundary == null ? '' : 'AND a.creation_sequence > ?'}
                 AND ((a.intention_id IS NOT NULL AND i.is_archived = ?)
                   OR (a.long_term_relation_id IS NOT NULL AND r.is_archived = ?))
               ORDER BY a.creation_sequence ASC LIMIT ?''',
                variables: [
                  Variable<String>(query.tagId.toCanonicalString()),
                  if (boundary != null) Variable<int>(boundary),
                  Variable<int>(archiveFlag),
                  Variable<int>(archiveFlag),
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {
                  _database.tagAssignments,
                  _database.intentions,
                  _database.longTermRelations,
                },
              )
              .get();
          var previousSequence = boundary ?? 0;
          final decoded = <TaggedEntity>[];
          for (final row in rows) {
            final sequence = _requiredStoredInteger(
              row.data,
              'assignment_sequence',
            );
            if (sequence <= previousSequence) {
              throw const _StoredIntentionCorruption();
            }
            previousSequence = sequence;
            decoded.add(_decodeTaggedEntity(row.data));
          }
          final revision = _currentRevision;
          return TaggedEntitiesPage(
            tag: tag,
            scope: query.scope,
            items: decoded.take(query.pageSize).toList(),
            pageSize: query.pageSize,
            nextCursor: decoded.length > query.pageSize
                ? _DriftTaggedEntitiesCursor(
                    epoch: _epoch,
                    tagId: query.tagId,
                    scope: query.scope,
                    pageSize: query.pageSize,
                    revision: revision,
                    storageVersion: storageVersion,
                    boundarySequence: _requiredStoredInteger(
                      rows[query.pageSize - 1].data,
                      'assignment_sequence',
                    ),
                  )
                : null,
            revision: revision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TaggedEntitiesPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyTaggedEntitiesReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TaggedEntitiesPageError(failure);
    }
  }

  Future<void> _checkTaggedEntityReferences(TagId tagId) async {
    final broken = await _database
        .customSelect(
          '''
      SELECT 1 FROM tag_assignments a
      LEFT JOIN intentions i ON i.id = a.intention_id
      LEFT JOIN long_term_relations r ON r.id = a.long_term_relation_id
      LEFT JOIN intentions source ON source.id = r.source_intention_id
      LEFT JOIN intentions related ON related.id = r.related_intention_id
      WHERE a.tag_id = ? AND (
        (a.intention_id IS NULL AND a.long_term_relation_id IS NULL)
        OR (a.intention_id IS NOT NULL AND a.long_term_relation_id IS NOT NULL)
        OR (a.intention_id IS NOT NULL AND i.id IS NULL)
        OR (a.intention_id IS NOT NULL AND
          (typeof(i.is_archived) <> 'integer' OR i.is_archived NOT IN (0, 1)))
        OR (a.long_term_relation_id IS NOT NULL AND
          (r.id IS NULL OR source.id IS NULL OR related.id IS NULL
            OR typeof(r.is_archived) <> 'integer' OR r.is_archived NOT IN (0, 1)))
      ) LIMIT 1
    ''',
          variables: [Variable<String>(tagId.toCanonicalString())],
          readsFrom: {
            _database.tagAssignments,
            _database.intentions,
            _database.longTermRelations,
          },
        )
        .getSingleOrNull();
    if (broken != null) throw const _StoredIntentionCorruption();
  }
}

TaggedEntity _decodeTaggedEntity(Map<String, Object?> data) {
  _checkTaggedTextEncoding(data);
  final assignedIntention = data['assigned_intention_id'];
  final assignedRelation = data['assigned_relation_id'];
  if (assignedIntention is String && assignedRelation == null) {
    final id = _decodeTaggedIntentionId(assignedIntention);
    if (_requiredStoredString(data, 'intention_id') != assignedIntention) {
      throw const _StoredIntentionCorruption();
    }
    return TaggedIntention(
      id: id,
      title: _strictTaggedTitle(data, 'intention_title'),
      archiveState: switch (_requiredStoredInteger(
        data,
        'intention_archived',
      )) {
        0 => domain.IntentionArchiveState.active,
        1 => domain.IntentionArchiveState.archived,
        _ => throw const _StoredIntentionCorruption(),
      },
    );
  }
  if (assignedRelation is String && assignedIntention == null) {
    final id = _decodeStoredRelationId(assignedRelation);
    if (_requiredStoredString(data, 'relation_id') != assignedRelation) {
      throw const _StoredIntentionCorruption();
    }
    for (final (foreignKey, joinedId) in [
      ('source_intention_id', 'source_id'),
      ('related_intention_id', 'related_id'),
    ]) {
      final reference = _requiredStoredString(data, foreignKey);
      _decodeTaggedIntentionId(reference);
      if (_requiredStoredString(data, joinedId) != reference) {
        throw const _StoredIntentionCorruption();
      }
    }
    return TaggedLongTermRelation(
      id: id,
      type: switch (_requiredStoredString(data, 'relation_type')) {
        'need' => relation_domain.LongTermRelationType.need,
        'can' => relation_domain.LongTermRelationType.can,
        _ => throw const _StoredIntentionCorruption(),
      },
      sourceTitle: _strictTaggedTitle(data, 'source_title'),
      relatedTitle: _strictTaggedTitle(data, 'related_title'),
      scope: switch (_requiredStoredInteger(data, 'relation_archived')) {
        0 => relation_domain.RelationScope.active,
        1 => relation_domain.RelationScope.archived,
        _ => throw const _StoredIntentionCorruption(),
      },
    );
  }
  throw const _StoredIntentionCorruption();
}

void _checkTaggedTextEncoding(Map<String, Object?> data) {
  // Декодер SQLite удаляет начальный BOM; проверяем исходный TEXT до этого.
  if (_requiredStoredInteger(data, 'has_leading_bom') != 0) {
    throw const _StoredIntentionCorruption();
  }
}

String _strictTaggedTitle(Map<String, Object?> data, String column) {
  final value = _requiredStoredString(data, column);
  if (IntentionText.normalizeTitle(value) != value) {
    throw const _StoredIntentionCorruption();
  }
  return value;
}

IntentionId _decodeTaggedIntentionId(String value) =>
    switch (IntentionId.decode(value)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const _StoredIntentionCorruption(),
    };

final class _DriftTaggedEntitiesCursor implements TaggedEntitiesCursor {
  const _DriftTaggedEntitiesCursor({
    required this.epoch,
    required this.tagId,
    required this.scope,
    required this.pageSize,
    required this.revision,
    required this.storageVersion,
    required this.boundarySequence,
  });

  final _GraphEpoch epoch;
  final TagId tagId;
  final TaggedEntitiesScope scope;
  final int pageSize;
  final GraphRevision revision;
  final _TagReadStorageVersion storageVersion;
  final int boundarySequence;

  bool matches(TaggedEntitiesQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) &&
      tagId == query.tagId &&
      scope == query.scope &&
      pageSize == query.pageSize;
}

final class _InvalidTaggedEntitiesCursor implements Exception {
  const _InvalidTaggedEntitiesCursor();
}

final class _TaggedEntitiesSnapshotHasExpired implements Exception {
  const _TaggedEntitiesSnapshotHasExpired();
}

final class _TaggedEntitiesTagMissing implements Exception {
  const _TaggedEntitiesTagMissing();
}

TaggedEntitiesReadFailure _classifyTaggedEntitiesReadFailure(Object error) {
  if (error is _InvalidTaggedEntitiesCursor) {
    return const TaggedEntitiesInvalidCursor();
  }
  if (error is _TaggedEntitiesSnapshotHasExpired) {
    return const TaggedEntitiesSnapshotExpired();
  }
  if (error is _TaggedEntitiesTagMissing) {
    return const TaggedEntitiesTagNotFound();
  }
  if (error is _StoredIntentionCorruption ||
      error is TaggedEntitiesPageValidationException ||
      error is IntentionTextValidationException ||
      unwrapDriftRemoteException(error) is FormatException) {
    return const TaggedEntitiesCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TaggedEntitiesCorruptionFailure(),
    SqliteUnavailableFailure() => const TaggedEntitiesUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TaggedEntitiesUnexpectedFailure(),
  };
}
