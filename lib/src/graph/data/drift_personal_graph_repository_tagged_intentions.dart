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
          final _DriftTaggedIntentionsCursor? cursor = switch (query.cursor) {
            null => null,
            final _DriftTaggedIntentionsCursor own => own,
            _ => throw StateError('Недопустимый курсор помеченных намерений.'),
          };
          if (cursor != null &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TaggedIntentionsSnapshotHasExpired();
          }

          stage = TagReadDiagnosticsStage.read;
          final tagRow = await _database
              .customSelect(
                'SELECT id, name FROM tags WHERE id = ?',
                variables: [Variable<String>(query.tagId.toCanonicalString())],
                readsFrom: {_database.tags},
              )
              .getSingleOrNull();
          if (tagRow == null) throw const _TaggedIntentionsTagMissing();
          final tag = decodeStoredTag(tagRow.data);
          if (tag.id != query.tagId) throw const StoredGraphCorruption();

          final boundary = cursor?.boundarySequence;
          final archiveFlag = query.scope == TaggedIntentionsScope.archived
              ? 1
              : 0;
          final rows = await _database
              .customSelect(
                '''SELECT a.creation_sequence AS assignment_sequence,
                 a.intention_id AS assigned_intention_id,
                 i.id AS intention_id, i.title AS intention_title,
                 i.is_archived AS intention_archived
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
            final sequence = requiredStoredInteger(
              row.data,
              'assignment_sequence',
            );
            if (sequence <= previousSequence) {
              throw const StoredGraphCorruption();
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
                    revision: revision,
                    boundarySequence: requiredStoredInteger(
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
}

TaggedIntention _decodeTaggedIntention(Map<String, Object?> data) {
  final assignedIntention = requiredStoredString(data, 'assigned_intention_id');
  final id = decodeStoredIntentionId(assignedIntention);
  if (requiredStoredString(data, 'intention_id') != assignedIntention) {
    throw const StoredGraphCorruption();
  }
  return TaggedIntention(
    id: id,
    title: decodeStoredIntentionTitle(data, 'intention_title'),
    archiveState: decodeStoredIntentionArchiveState(data, 'intention_archived'),
  );
}

final class _DriftTaggedIntentionsCursor implements TaggedIntentionsCursor {
  const _DriftTaggedIntentionsCursor({
    required this.revision,
    required this.boundarySequence,
  });

  final GraphRevision revision;
  final int boundarySequence;
}

final class _TaggedIntentionsSnapshotHasExpired implements Exception {
  const _TaggedIntentionsSnapshotHasExpired();
}

final class _TaggedIntentionsTagMissing implements Exception {
  const _TaggedIntentionsTagMissing();
}

TaggedIntentionsReadFailure _classifyTaggedIntentionsReadFailure(Object error) {
  if (error is _TaggedIntentionsSnapshotHasExpired) {
    return const TaggedIntentionsSnapshotExpired();
  }
  if (error is _TaggedIntentionsTagMissing) {
    return const TaggedIntentionsTagNotFound();
  }
  if (error is StoredGraphCorruption ||
      error is TaggedIntentionsPageValidationException ||
      unwrapDriftRemoteException(error) is FormatException) {
    return const TaggedIntentionsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TaggedIntentionsCorruptionFailure(),
    SqliteUnavailableFailure() => const TaggedIntentionsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const TaggedIntentionsUnexpectedFailure(),
  };
}
