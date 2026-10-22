part of 'drift_personal_graph_repository.dart';

extension _TagReading on DriftPersonalGraphRepository {
  /// Получает полные собственные назначения запрошенных намерений.
  /// Вызывается внутри транзакции и последовательного исполнения чтения или команды.
  Future<Map<IntentionId, List<tag_domain.Tag>>> _readIntentionTags(
    List<IntentionId> intentionIds,
  ) async {
    if (intentionIds.isEmpty) return const {};
    final requested = {
      for (final id in intentionIds) id.toCanonicalString(): id,
    };
    final rows = await _database
        .customSelect(
          '''SELECT a.intention_id, a.tag_id AS assigned_tag_id,
         t.id, t.name, t.color, t.position
       FROM tag_assignments a JOIN tags t ON t.id = a.tag_id
       WHERE a.intention_id IN (${List.filled(requested.length, '?').join(', ')})
       ORDER BY a.intention_id ASC, t.position ASC''',
          variables: [for (final id in requested.keys) Variable<String>(id)],
          readsFrom: {_database.tags, _database.tagAssignments},
        )
        .get();
    final tags = {for (final id in intentionIds) id: <tag_domain.Tag>[]};
    for (final row in rows) {
      final id = requested[requiredStoredString(row.data, 'intention_id')];
      if (id == null) throw const StoredGraphCorruption();
      tags[id]!.add(_decodeAssignedTag(row.data));
    }
    return tags;
  }

  Future<TagAssignmentStatusResult> _readTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagAssignmentStatusReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          stage = TagReadDiagnosticsStage.read;
          final row = await _database
              .customSelect(
                '''SELECT EXISTS(SELECT 1 FROM tags WHERE id = ?) AS tag_exists,
                 EXISTS(SELECT 1 FROM intentions WHERE id = ?) AS intention_exists,
                 EXISTS(SELECT 1 FROM tag_assignments
                   WHERE tag_id = ? AND intention_id = ?) AS is_assigned''',
                variables: [
                  Variable<String>(tagId.toCanonicalString()),
                  Variable<String>(intentionId.toCanonicalString()),
                  Variable<String>(tagId.toCanonicalString()),
                  Variable<String>(intentionId.toCanonicalString()),
                ],
                readsFrom: {
                  _database.tags,
                  _database.intentions,
                  _database.tagAssignments,
                },
              )
              .getSingle();
          final tagExists = requiredStoredInteger(row.data, 'tag_exists');
          final intentionExists = requiredStoredInteger(
            row.data,
            'intention_exists',
          );
          final assigned = requiredStoredInteger(row.data, 'is_assigned');
          if ((tagExists != 0 && tagExists != 1) ||
              (intentionExists != 0 && intentionExists != 1) ||
              (assigned != 0 && assigned != 1)) {
            throw const StoredGraphCorruption();
          }
          if (tagExists == 0) throw const _TagStatusTagMissing();
          if (intentionExists == 0) throw const _TagReadIntentionMissing();
          return GraphSnapshot(
            value: assigned == 1,
            revision: _currentRevision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagAssignmentStatusSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyTagAssignmentStatusFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagAssignmentStatusError(failure);
    }
  }

  Future<TagCatalogResult> _readTagCatalog(TagCatalogMode mode) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagCatalogReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          stage = TagReadDiagnosticsStage.read;
          final intentionId = switch (mode) {
            TagCatalogBrowseMode() => null,
            TagCatalogSelectionMode(:final intentionId) => intentionId,
          };
          if (intentionId != null) {
            await _validateTagReadIntention(intentionId);
          }
          final rows = await _database
              .customSelect(
                intentionId == null
                    ? '''SELECT id, name, color, position FROM tags
                   ORDER BY position ASC'''
                    : '''SELECT t.id, t.name, t.color, t.position,
                   EXISTS(SELECT 1 FROM tag_assignments a WHERE a.tag_id = t.id AND a.intention_id = ?) AS is_assigned
                   FROM tags t
                   ORDER BY t.position ASC''',
                variables: [
                  if (intentionId != null)
                    Variable<String>(intentionId.toCanonicalString()),
                ],
                readsFrom: {
                  _database.tags,
                  if (intentionId != null) _database.tagAssignments,
                },
              )
              .get();
          final decoded = <tag_domain.Tag>[];
          final selectionRows = <TagSelectionRow>[];
          for (final row in rows) {
            final tag = decodeStoredTag(row.data);
            decoded.add(tag);
            if (intentionId != null) {
              final assigned = requiredStoredInteger(row.data, 'is_assigned');
              if (assigned != 0 && assigned != 1) {
                throw const StoredGraphCorruption();
              }
              selectionRows.add(
                TagSelectionRow(tag: tag, isAssigned: assigned == 1),
              );
            }
          }
          final revision = _currentRevision;
          return intentionId == null
              ? TagCatalogSnapshot(items: decoded, revision: revision)
              : TagCatalogSnapshot.selection(
                  intentionId: intentionId,
                  rows: selectionRows,
                  revision: revision,
                );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagCatalogSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyTagCatalogReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagCatalogError(failure);
    }
  }

  Future<TagAssignmentsResult> _readTagAssignments(
    IntentionId intentionId,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagAssignmentsReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          stage = TagReadDiagnosticsStage.read;
          await _validateTagReadIntention(intentionId);
          final rows = await _database
              .customSelect(
                '''SELECT a.tag_id AS assigned_tag_id, t.id, t.name, t.color,
                 t.position
               FROM tag_assignments a JOIN tags t ON t.id = a.tag_id
               WHERE a.intention_id = ?
               ORDER BY t.position ASC''',
                variables: [Variable<String>(intentionId.toCanonicalString())],
                readsFrom: {_database.tags, _database.tagAssignments},
              )
              .get();
          final tags = [for (final row in rows) _decodeAssignedTag(row.data)];
          final revision = _currentRevision;
          return TagAssignmentsSnapshot(
            intentionId: intentionId,
            items: tags,
            revision: revision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagAssignmentsSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyTagAssignmentsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagAssignmentsError(failure);
    }
  }

  Future<void> _validateTagReadIntention(IntentionId intentionId) async {
    final exists = await _database
        .customSelect(
          'SELECT 1 FROM intentions WHERE id = ?',
          variables: [Variable<String>(intentionId.toCanonicalString())],
          readsFrom: {_database.intentions},
        )
        .getSingleOrNull();
    if (exists == null) throw const _TagReadIntentionMissing();
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
                  'SELECT id, name, color, position FROM tags WHERE id = ?',
                  variables: [Variable<String>(id.toCanonicalString())],
                  readsFrom: {_database.tags},
                )
                .getSingleOrNull();
            final tag = row == null ? null : decodeStoredTag(row.data);
            if (tag != null && tag.id != id) {
              throw const StoredGraphCorruption();
            }
            return GraphSnapshot(value: tag, revision: _currentRevision);
          }),
        );
        if (previous case final old?) {
          if (old.revision.compareTo(snapshot.revision) ==
                  GraphRevisionOrder.same &&
              old.value?.id == snapshot.value?.id &&
              old.value?.name == snapshot.value?.name &&
              old.value?.color == snapshot.value?.color) {
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

/// Существование тега гарантирует схема: внешний ключ не допускает назначения
/// без тега.
tag_domain.Tag _decodeAssignedTag(Map<String, Object?> data) {
  final tag = decodeStoredTag(data);
  if (requiredStoredString(data, 'assigned_tag_id') !=
      tag.id.toCanonicalString()) {
    throw const StoredGraphCorruption();
  }
  return tag;
}

final class _TagReadIntentionMissing implements Exception {
  const _TagReadIntentionMissing();
}

final class _TagStatusTagMissing implements Exception {
  const _TagStatusTagMissing();
}

TagAssignmentStatusFailure _classifyTagAssignmentStatusFailure(Object error) {
  if (error is _TagStatusTagMissing) {
    return const TagAssignmentStatusTagNotFound();
  }
  if (error is _TagReadIntentionMissing) {
    return const TagAssignmentStatusIntentionNotFound();
  }
  if (error is StoredGraphCorruption) {
    return const TagAssignmentStatusCorruption();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagAssignmentStatusCorruption(),
    SqliteUnavailableFailure() => const TagAssignmentStatusUnavailable(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const TagAssignmentStatusUnexpected(),
  };
}

TagCatalogReadFailure _classifyTagCatalogReadFailure(Object error) {
  if (error is _TagReadIntentionMissing) {
    return const TagCatalogIntentionNotFound();
  }
  if (error is StoredGraphCorruption) {
    return const TagCatalogCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagCatalogCorruptionFailure(),
    SqliteUnavailableFailure() => const TagCatalogUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const TagCatalogUnexpectedFailure(),
  };
}

TagAssignmentsReadFailure _classifyTagAssignmentsReadFailure(Object error) {
  if (error is _TagReadIntentionMissing) {
    return const TagAssignmentsIntentionNotFound();
  }
  if (error is StoredGraphCorruption) {
    return const TagAssignmentsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagAssignmentsCorruptionFailure(),
    SqliteUnavailableFailure() => const TagAssignmentsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const TagAssignmentsUnexpectedFailure(),
  };
}

TagReadFailure _classifyTagReadFailure(Object error) {
  if (error is StoredGraphCorruption) {
    return const TagReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagReadCorruptionFailure(),
    SqliteUnavailableFailure() => const TagReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const TagReadUnexpectedFailure(),
  };
}
