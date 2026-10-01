part of 'drift_personal_graph_repository.dart';

extension _TaggedIntentionsReading on DriftPersonalGraphRepository {
  Future<TaggedIntentionsPageResult> _readTaggedIntentionsPage(
    TaggedIntentionsQuery query,
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
              (cursor is! _DriftTaggedIntentionsCursor ||
                  !cursor.matches(query, _epoch))) {
            throw const _InvalidTaggedIntentionsCursor();
          }
          if (cursor is _DriftTaggedIntentionsCursor &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TaggedIntentionsSnapshotHasExpired();
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
            throw const _TaggedIntentionsTagMissing();
          }
          _checkTaggedTextEncoding(tagRow.data);
          final tag = _decodeStoredTag(tagRow.data);
          if (tag.id != query.tagId) throw const _StoredIntentionCorruption();
          if (cursor is _DriftTaggedIntentionsCursor &&
              cursor.storageVersion != storageVersion) {
            throw const _TaggedIntentionsSnapshotHasExpired();
          }
          if (cursor == null) {
            // Курсор свидетельствует о проверке ссылок всего выбранного тега
            // только для этой эпохи, ревизии и версии хранилища.
            await _checkTaggedIntentionReferences(query.tagId);
          }

          final boundary = cursor is _DriftTaggedIntentionsCursor
              ? cursor.boundarySequence
              : null;
          final archiveFlag = query.scope == TaggedIntentionsScope.archived
              ? 1
              : 0;
          final rows = await _database
              .customSelect(
                '''SELECT a.creation_sequence AS assignment_sequence,
                 a.intention_id AS assigned_intention_id,
                 i.id AS intention_id, i.title AS intention_title,
                 i.is_archived AS intention_archived,
                 CASE WHEN substr(a.intention_id, 1, 1) = char(65279)
                   OR substr(i.title, 1, 1) = char(65279)
                   THEN 1 ELSE 0 END AS has_leading_bom
               FROM tag_assignments a
               JOIN intentions i ON i.id = a.intention_id
               WHERE a.tag_id = ?
                 ${boundary == null ? '' : 'AND a.creation_sequence > ?'}
                 AND i.is_archived = ?
               ORDER BY a.creation_sequence ASC LIMIT ?''',
                variables: [
                  Variable<String>(query.tagId.toCanonicalString()),
                  if (boundary != null) Variable<int>(boundary),
                  Variable<int>(archiveFlag),
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {_database.tagAssignments, _database.intentions},
              )
              .get();
          var previousSequence = boundary ?? 0;
          final decoded = <TaggedIntention>[];
          for (final row in rows) {
            final sequence = _requiredStoredInteger(
              row.data,
              'assignment_sequence',
            );
            if (sequence <= previousSequence) {
              throw const _StoredIntentionCorruption();
            }
            previousSequence = sequence;
            decoded.add(_decodeTaggedIntention(row.data));
          }
          final revision = _currentRevision;
          return TaggedIntentionsPage(
            tag: tag,
            scope: query.scope,
            items: decoded.take(query.pageSize).toList(),
            pageSize: query.pageSize,
            nextCursor: decoded.length > query.pageSize
                ? _DriftTaggedIntentionsCursor(
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
      return TaggedIntentionsPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyTaggedIntentionsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TaggedIntentionsPageError(failure);
    }
  }

  Future<void> _checkTaggedIntentionReferences(TagId tagId) async {
    final broken = await _database
        .customSelect(
          '''
      SELECT 1 FROM tag_assignments a
      LEFT JOIN intentions i ON i.id = a.intention_id
      WHERE a.tag_id = ? AND (
        i.id IS NULL
        OR typeof(i.is_archived) <> 'integer' OR i.is_archived NOT IN (0, 1)
      ) LIMIT 1
    ''',
          variables: [Variable<String>(tagId.toCanonicalString())],
          readsFrom: {_database.tagAssignments, _database.intentions},
        )
        .getSingleOrNull();
    if (broken != null) throw const _StoredIntentionCorruption();
  }
}

TaggedIntention _decodeTaggedIntention(Map<String, Object?> data) {
  _checkTaggedTextEncoding(data);
  final assignedIntention = _requiredStoredString(
    data,
    'assigned_intention_id',
  );
  final id = _decodeTaggedIntentionId(assignedIntention);
  if (_requiredStoredString(data, 'intention_id') != assignedIntention) {
    throw const _StoredIntentionCorruption();
  }
  return TaggedIntention(
    id: id,
    title: _strictTaggedTitle(data, 'intention_title'),
    archiveState: switch (_requiredStoredInteger(data, 'intention_archived')) {
      0 => domain.IntentionArchiveState.active,
      1 => domain.IntentionArchiveState.archived,
      _ => throw const _StoredIntentionCorruption(),
    },
  );
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

final class _DriftTaggedIntentionsCursor implements TaggedIntentionsCursor {
  const _DriftTaggedIntentionsCursor({
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
  final TaggedIntentionsScope scope;
  final int pageSize;
  final GraphRevision revision;
  final _TagReadStorageVersion storageVersion;
  final int boundarySequence;

  bool matches(TaggedIntentionsQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) &&
      tagId == query.tagId &&
      scope == query.scope &&
      pageSize == query.pageSize;
}

final class _InvalidTaggedIntentionsCursor implements Exception {
  const _InvalidTaggedIntentionsCursor();
}

final class _TaggedIntentionsSnapshotHasExpired implements Exception {
  const _TaggedIntentionsSnapshotHasExpired();
}

final class _TaggedIntentionsTagMissing implements Exception {
  const _TaggedIntentionsTagMissing();
}

TaggedIntentionsReadFailure _classifyTaggedIntentionsReadFailure(Object error) {
  if (error is _InvalidTaggedIntentionsCursor) {
    return const TaggedIntentionsInvalidCursor();
  }
  if (error is _TaggedIntentionsSnapshotHasExpired) {
    return const TaggedIntentionsSnapshotExpired();
  }
  if (error is _TaggedIntentionsTagMissing) {
    return const TaggedIntentionsTagNotFound();
  }
  if (error is _StoredIntentionCorruption ||
      error is TaggedIntentionsPageValidationException ||
      error is IntentionTextValidationException ||
      unwrapDriftRemoteException(error) is FormatException) {
    return const TaggedIntentionsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TaggedIntentionsCorruptionFailure(),
    SqliteUnavailableFailure() => const TaggedIntentionsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TaggedIntentionsUnexpectedFailure(),
  };
}
