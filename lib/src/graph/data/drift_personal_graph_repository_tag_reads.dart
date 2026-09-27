part of 'drift_personal_graph_repository.dart';

extension _TagReading on DriftPersonalGraphRepository {
  Future<TagCatalogPageResult> _readTagCatalogPage(
    TagCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagCatalogPageReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(() async {
          final cursor = query.cursor;
          if (cursor != null &&
              (cursor is! _DriftTagCatalogCursor ||
                  !cursor.matches(query, _epoch))) {
            throw const _InvalidTagCatalogCursor();
          }
          if (cursor is _DriftTagCatalogCursor &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TagCatalogSnapshotHasExpired();
          }
          stage = TagReadDiagnosticsStage.read;
          final selectionTarget = switch (query.mode) {
            TagCatalogBrowseMode() => null,
            TagCatalogSelectionMode(:final target) => target,
          };
          final storageVersion = selectionTarget == null
              ? null
              : await _tagReadStorageVersion();
          final storageChanged =
              cursor is _DriftTagCatalogCursor &&
              cursor.storageVersion != storageVersion;
          final targetSql = selectionTarget == null
              ? null
              : await _validatedTagReadTarget(
                  selectionTarget,
                  checkAssignmentReferences: cursor == null || storageChanged,
                );
          if (storageChanged) throw const _TagCatalogSnapshotHasExpired();
          final boundary = cursor is _DriftTagCatalogCursor
              ? cursor.boundarySequence
              : null;
          final rows = await _database
              .customSelect(
                targetSql == null
                    ? '''SELECT creation_sequence, id, name FROM tags
                   ${boundary == null ? '' : 'WHERE creation_sequence > ?'}
                   ORDER BY creation_sequence ASC LIMIT ?'''
                    : '''SELECT t.creation_sequence, t.id, t.name,
                   EXISTS(SELECT 1 FROM tag_assignments a WHERE a.tag_id = t.id AND a.${targetSql.assignmentColumn} = ?) AS is_assigned
                   FROM tags t
                   ${boundary == null ? '' : 'WHERE t.creation_sequence > ?'}
                   ORDER BY t.creation_sequence ASC LIMIT ?''',
                variables: [
                  if (targetSql != null) Variable<String>(targetSql.id),
                  if (boundary != null) Variable<int>(boundary),
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {
                  _database.tags,
                  if (targetSql != null) _database.tagAssignments,
                },
              )
              .get();
          var previousSequence = boundary ?? 0;
          final decoded = <tag_domain.Tag>[];
          final selectionRows = <TagSelectionRow>[];
          for (final row in rows) {
            final sequence = _requiredStoredInteger(
              row.data,
              'creation_sequence',
            );
            if (sequence <= previousSequence) {
              throw const _StoredIntentionCorruption();
            }
            previousSequence = sequence;
            final tag = _decodeStoredTag(row.data);
            decoded.add(tag);
            if (targetSql != null) {
              final assigned = _requiredStoredInteger(row.data, 'is_assigned');
              if (assigned != 0 && assigned != 1) {
                throw const _StoredIntentionCorruption();
              }
              selectionRows.add(
                TagSelectionRow(tag: tag, isAssigned: assigned == 1),
              );
            }
          }
          final hasNext = decoded.length > query.pageSize;
          final revision = _currentRevision;
          final nextCursor = hasNext
              ? _DriftTagCatalogCursor(
                  epoch: _epoch,
                  mode: query.mode,
                  revision: revision,
                  pageSize: query.pageSize,
                  storageVersion: storageVersion,
                  boundarySequence: _requiredStoredInteger(
                    rows[query.pageSize - 1].data,
                    'creation_sequence',
                  ),
                )
              : null;
          return selectionTarget == null
              ? TagCatalogPage(
                  items: decoded.take(query.pageSize).toList(),
                  pageSize: query.pageSize,
                  nextCursor: nextCursor,
                  revision: revision,
                )
              : TagCatalogPage.selection(
                  target: selectionTarget,
                  rows: selectionRows.take(query.pageSize).toList(),
                  pageSize: query.pageSize,
                  nextCursor: nextCursor,
                  revision: revision,
                );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagCatalogPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyTagCatalogReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagCatalogPageError(failure);
    }
  }

  Future<TagAssignmentsPageResult> _readTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagAssignmentsPageReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(() async {
          final cursor = query.cursor;
          if (cursor != null &&
              (cursor is! _DriftTagAssignmentsCursor ||
                  !cursor.matches(query, _epoch))) {
            throw const _InvalidTagAssignmentsCursor();
          }
          if (cursor is _DriftTagAssignmentsCursor &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TagAssignmentsSnapshotHasExpired();
          }
          stage = TagReadDiagnosticsStage.read;
          final storageVersion = await _tagReadStorageVersion();
          final storageChanged =
              cursor is _DriftTagAssignmentsCursor &&
              cursor.storageVersion != storageVersion;
          final target = await _validatedTagReadTarget(
            query.target,
            checkAssignmentReferences: cursor == null || storageChanged,
          );
          if (storageChanged) throw const _TagAssignmentsSnapshotHasExpired();
          final boundary = cursor is _DriftTagAssignmentsCursor
              ? cursor.boundarySequence
              : null;
          final rows = await _database
              .customSelect(
                '''SELECT a.tag_creation_sequence AS creation_sequence,
                 t.creation_sequence AS actual_tag_creation_sequence, t.id, t.name
               FROM tag_assignments a JOIN tags t ON t.id = a.tag_id
               WHERE a.${target.assignmentColumn} = ?
                 ${boundary == null ? '' : 'AND a.tag_creation_sequence > ?'}
               ORDER BY a.tag_creation_sequence ASC LIMIT ?''',
                variables: [
                  Variable<String>(target.id),
                  if (boundary != null) Variable<int>(boundary),
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {_database.tags, _database.tagAssignments},
              )
              .get();
          var previousSequence = boundary ?? 0;
          final tags = <tag_domain.Tag>[];
          for (final row in rows) {
            final sequence = _requiredStoredInteger(
              row.data,
              'creation_sequence',
            );
            if (sequence <= previousSequence) {
              throw const _StoredIntentionCorruption();
            }
            if (sequence !=
                _requiredStoredInteger(
                  row.data,
                  'actual_tag_creation_sequence',
                )) {
              throw const _StoredIntentionCorruption();
            }
            previousSequence = sequence;
            tags.add(_decodeStoredTag(row.data));
          }
          final revision = _currentRevision;
          return TagAssignmentsPage(
            target: query.target,
            items: tags.take(query.pageSize).toList(),
            pageSize: query.pageSize,
            nextCursor: tags.length > query.pageSize
                ? _DriftTagAssignmentsCursor(
                    epoch: _epoch,
                    target: query.target,
                    revision: revision,
                    pageSize: query.pageSize,
                    storageVersion: storageVersion,
                    boundarySequence: _requiredStoredInteger(
                      rows[query.pageSize - 1].data,
                      'creation_sequence',
                    ),
                  )
                : null,
            revision: revision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagAssignmentsPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyTagAssignmentsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagAssignmentsPageError(failure);
    }
  }

  Future<_TagReadTargetSql> _validatedTagReadTarget(
    TagTarget target, {
    required bool checkAssignmentReferences,
  }) async {
    final sql = switch (target) {
      IntentionTagTarget(:final intentionId) => _TagReadTargetSql(
        table: 'intentions',
        assignmentColumn: 'intention_id',
        id: intentionId.toCanonicalString(),
      ),
      LongTermRelationTagTarget(:final relationId) => _TagReadTargetSql(
        table: 'long_term_relations',
        assignmentColumn: 'long_term_relation_id',
        id: relationId.toCanonicalString(),
      ),
    };
    final exists = await _database
        .customSelect(
          'SELECT 1 FROM ${sql.table} WHERE id = ?',
          variables: [Variable<String>(sql.id)],
        )
        .getSingleOrNull();
    if (exists == null) {
      final dangling = await _database
          .customSelect(
            'SELECT 1 FROM tag_assignments WHERE ${sql.assignmentColumn} = ? LIMIT 1',
            variables: [Variable<String>(sql.id)],
            readsFrom: {_database.tagAssignments},
          )
          .getSingleOrNull();
      if (dangling != null) throw const _StoredIntentionCorruption();
      throw const _TagReadTargetMissing();
    }
    if (checkAssignmentReferences) {
      final orphan = await _database
          .customSelect(
            '''SELECT 1 FROM tag_assignments a LEFT JOIN tags t ON t.id = a.tag_id
         WHERE a.${sql.assignmentColumn} = ? AND t.id IS NULL LIMIT 1''',
            variables: [Variable<String>(sql.id)],
            readsFrom: {_database.tags, _database.tagAssignments},
          )
          .getSingleOrNull();
      if (orphan != null) throw const _StoredIntentionCorruption();
    }
    return sql;
  }

  Future<_TagReadStorageVersion> _tagReadStorageVersion() async {
    final row = await _database
        .customSelect(
          'SELECT total_changes() AS connection_changes, data_version FROM pragma_data_version',
        )
        .getSingle();
    return (
      connectionChanges: _requiredStoredInteger(row.data, 'connection_changes'),
      dataVersion: _requiredStoredInteger(row.data, 'data_version'),
    );
  }

  Stream<TagReadResult> _watchTag(TagId id) async* {
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagDetailReadDiagnosticsEvent(
        stage: TagReadDiagnosticsStage.read,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    GraphSnapshot<tag_domain.Tag?>? previous;
    try {
      await for (final _
          in _database
              .customSelect(
                'SELECT id FROM tags WHERE id = ?',
                variables: [Variable<String>(id.toCanonicalString())],
                readsFrom: {_database.tags},
              )
              .watch()) {
        final snapshot = await _sequencer.run(
          () => _database.transaction(() async {
            final row = await _database
                .customSelect(
                  'SELECT id, name FROM tags WHERE id = ?',
                  variables: [Variable<String>(id.toCanonicalString())],
                  readsFrom: {_database.tags},
                )
                .getSingleOrNull();
            final tag = row == null ? null : _decodeStoredTag(row.data);
            if (tag != null && tag.id != id) {
              throw const _StoredIntentionCorruption();
            }
            return GraphSnapshot(value: tag, revision: _currentRevision);
          }),
        );
        if (previous case final old?) {
          if (old.revision.compareTo(snapshot.revision) ==
                  GraphRevisionOrder.same &&
              old.value?.id == snapshot.value?.id &&
              old.value?.name == snapshot.value?.name) {
            continue;
          }
        }
        previous = snapshot;
        record(DiagnosticsSucceeded(stopwatch.elapsed));
        yield TagReadSuccess(snapshot);
      }
    } on Object catch (error) {
      final failure = _classifyTagReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      yield TagReadError(failure);
    }
  }
}

tag_domain.Tag _decodeStoredTag(Map<String, Object?> data) {
  final id = switch (TagId.decode(_requiredStoredString(data, 'id'))) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw const _StoredIntentionCorruption(),
  };
  try {
    return tag_domain.Tag(
      id: id,
      name: TagName.fromStored(_requiredStoredString(data, 'name')),
    );
  } on TagNameValidationException {
    throw const _StoredIntentionCorruption();
  }
}

final class _DriftTagCatalogCursor implements TagCatalogCursor {
  const _DriftTagCatalogCursor({
    required this.epoch,
    required this.mode,
    required this.revision,
    required this.pageSize,
    required this.storageVersion,
    required this.boundarySequence,
  });

  final _GraphEpoch epoch;
  final TagCatalogMode mode;
  final GraphRevision revision;
  final int pageSize;
  final _TagReadStorageVersion? storageVersion;
  final int boundarySequence;

  bool matches(TagCatalogQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) &&
      mode == query.mode &&
      pageSize == query.pageSize;
}

final class _TagReadTargetSql {
  const _TagReadTargetSql({
    required this.table,
    required this.assignmentColumn,
    required this.id,
  });

  final String table;
  final String assignmentColumn;
  final String id;
}

typedef _TagReadStorageVersion = ({int connectionChanges, int dataVersion});

final class _DriftTagAssignmentsCursor implements TagAssignmentsCursor {
  const _DriftTagAssignmentsCursor({
    required this.epoch,
    required this.target,
    required this.revision,
    required this.pageSize,
    required this.storageVersion,
    required this.boundarySequence,
  });

  final _GraphEpoch epoch;
  final TagTarget target;
  final GraphRevision revision;
  final int pageSize;
  final _TagReadStorageVersion storageVersion;
  final int boundarySequence;

  bool matches(TagAssignmentsQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) &&
      target == query.target &&
      pageSize == query.pageSize;
}

final class _TagReadTargetMissing implements Exception {
  const _TagReadTargetMissing();
}

final class _InvalidTagAssignmentsCursor implements Exception {
  const _InvalidTagAssignmentsCursor();
}

final class _TagAssignmentsSnapshotHasExpired implements Exception {
  const _TagAssignmentsSnapshotHasExpired();
}

final class _InvalidTagCatalogCursor implements Exception {
  const _InvalidTagCatalogCursor();
}

final class _TagCatalogSnapshotHasExpired implements Exception {
  const _TagCatalogSnapshotHasExpired();
}

TagCatalogReadFailure _classifyTagCatalogReadFailure(Object error) {
  if (error is _TagReadTargetMissing) {
    return const TagCatalogTargetNotFound();
  }
  if (error is _InvalidTagCatalogCursor) {
    return const TagCatalogInvalidCursor();
  }
  if (error is _TagCatalogSnapshotHasExpired) {
    return const TagCatalogSnapshotExpired();
  }
  if (error is _StoredIntentionCorruption ||
      error is TagCatalogPageValidationException) {
    return const TagCatalogCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagCatalogCorruptionFailure(),
    SqliteUnavailableFailure() => const TagCatalogUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagCatalogUnexpectedFailure(),
  };
}

TagAssignmentsReadFailure _classifyTagAssignmentsReadFailure(Object error) {
  if (error is _InvalidTagAssignmentsCursor) {
    return const TagAssignmentsInvalidCursor();
  }
  if (error is _TagAssignmentsSnapshotHasExpired) {
    return const TagAssignmentsSnapshotExpired();
  }
  if (error is _TagReadTargetMissing) {
    return const TagAssignmentsTargetNotFound();
  }
  if (error is _StoredIntentionCorruption ||
      error is TagAssignmentsPageValidationException) {
    return const TagAssignmentsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagAssignmentsCorruptionFailure(),
    SqliteUnavailableFailure() => const TagAssignmentsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagAssignmentsUnexpectedFailure(),
  };
}

TagReadFailure _classifyTagReadFailure(Object error) {
  if (error is _StoredIntentionCorruption) {
    return const TagReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagReadCorruptionFailure(),
    SqliteUnavailableFailure() => const TagReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagReadUnexpectedFailure(),
  };
}
