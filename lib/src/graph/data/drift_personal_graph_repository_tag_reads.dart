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
          '''SELECT a.intention_id, a.long_term_relation_id,
         a.tag_id AS assigned_tag_id,
         a.tag_creation_sequence AS creation_sequence,
         t.creation_sequence AS actual_tag_creation_sequence, t.id, t.name,
         CASE WHEN substr(t.id, 1, 1) = char(65279)
           OR substr(t.name, 1, 1) = char(65279)
           THEN 1 ELSE 0 END AS has_leading_bom
       FROM tag_assignments a LEFT JOIN tags t ON t.id = a.tag_id
       WHERE a.intention_id IN (${List.filled(requested.length, '?').join(', ')})
       ORDER BY a.intention_id ASC, a.tag_creation_sequence ASC''',
          variables: [for (final id in requested.keys) Variable<String>(id)],
          readsFrom: {_database.tags, _database.tagAssignments},
        )
        .get();
    final tags = {for (final id in intentionIds) id: <tag_domain.Tag>[]};
    final previousSequences = <IntentionId, int>{};
    for (final row in rows) {
      final id = requested[_requiredStoredString(row.data, 'intention_id')];
      if (id == null) throw const _StoredIntentionCorruption();
      final assigned = _decodeStoredTagAssignment(
        row.data,
        previousSequences[id] ?? 0,
      );
      previousSequences[id] = assigned.sequence;
      tags[id]!.add(assigned.tag);
    }
    return tags;
  }

  Future<TagAssignmentStatusResult> _readTagAssignmentStatus(
    TagId tagId,
    TagTarget target,
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
          final targetSql = switch (target) {
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
          stage = TagReadDiagnosticsStage.read;
          final row = await _database
              .customSelect(
                '''SELECT EXISTS(SELECT 1 FROM tags WHERE id = ?) AS tag_exists,
                 EXISTS(SELECT 1 FROM ${targetSql.table} WHERE id = ?) AS target_exists,
                 EXISTS(SELECT 1 FROM tag_assignments
                   WHERE tag_id = ? AND ${targetSql.assignmentColumn} = ?) AS is_assigned''',
                variables: [
                  Variable<String>(tagId.toCanonicalString()),
                  Variable<String>(targetSql.id),
                  Variable<String>(tagId.toCanonicalString()),
                  Variable<String>(targetSql.id),
                ],
                readsFrom: {_database.tags, _database.tagAssignments},
              )
              .getSingle();
          final tagExists = _requiredStoredInteger(row.data, 'tag_exists');
          final targetExists = _requiredStoredInteger(
            row.data,
            'target_exists',
          );
          final assigned = _requiredStoredInteger(row.data, 'is_assigned');
          if ((tagExists != 0 && tagExists != 1) ||
              (targetExists != 0 && targetExists != 1) ||
              (assigned != 0 && assigned != 1) ||
              (assigned == 1 && (tagExists == 0 || targetExists == 0))) {
            throw const _StoredIntentionCorruption();
          }
          if (tagExists == 0) throw const _TagStatusTagMissing();
          if (targetExists == 0) throw const _TagReadTargetMissing();
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
          final selectionTarget = switch (mode) {
            TagCatalogBrowseMode() => null,
            TagCatalogSelectionMode(:final target) => target,
          };
          final targetSql = selectionTarget == null
              ? null
              : await _validatedTagReadTarget(
                  selectionTarget,
                  checkAssignmentReferences: true,
                );
          final rows = await _database
              .customSelect(
                targetSql == null
                    ? '''SELECT creation_sequence, id, name FROM tags
                   ORDER BY creation_sequence ASC'''
                    : '''SELECT t.creation_sequence, t.id, t.name,
                   EXISTS(SELECT 1 FROM tag_assignments a WHERE a.tag_id = t.id AND a.${targetSql.assignmentColumn} = ?) AS is_assigned
                   FROM tags t
                   ORDER BY t.creation_sequence ASC''',
                variables: [
                  if (targetSql != null) Variable<String>(targetSql.id),
                ],
                readsFrom: {
                  _database.tags,
                  if (targetSql != null) _database.tagAssignments,
                },
              )
              .get();
          var previousSequence = 0;
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
          final revision = _currentRevision;
          return selectionTarget == null
              ? TagCatalogSnapshot(items: decoded, revision: revision)
              : TagCatalogSnapshot.selection(
                  target: selectionTarget,
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

  Future<TagAssignmentsResult> _readTagAssignments(TagTarget recipient) async {
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
          final target = await _validatedTagReadTarget(
            recipient,
            checkAssignmentReferences: true,
          );
          final rows = await _database
              .customSelect(
                '''SELECT a.intention_id, a.long_term_relation_id,
                 a.tag_id AS assigned_tag_id,
                 a.tag_creation_sequence AS creation_sequence,
                 t.creation_sequence AS actual_tag_creation_sequence, t.id, t.name,
                 CASE WHEN substr(t.id, 1, 1) = char(65279)
                   OR substr(t.name, 1, 1) = char(65279)
                   THEN 1 ELSE 0 END AS has_leading_bom
               FROM tag_assignments a JOIN tags t ON t.id = a.tag_id
               WHERE a.${target.assignmentColumn} = ?
               ORDER BY a.tag_creation_sequence ASC''',
                variables: [Variable<String>(target.id)],
                readsFrom: {_database.tags, _database.tagAssignments},
              )
              .get();
          var previousSequence = 0;
          final tags = <tag_domain.Tag>[];
          for (final row in rows) {
            final assigned = _decodeStoredTagAssignment(
              row.data,
              previousSequence,
            );
            previousSequence = assigned.sequence;
            tags.add(assigned.tag);
          }
          final revision = _currentRevision;
          return TagAssignmentsSnapshot(
            target: recipient,
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
    // Маркер живёт на физическом соединении, включая соединения из изолята.
    // CREATE TABLE AS SELECT не увеличивает total_changes() и не меняет граф.
    await _database.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS doable_catalog_connection AS '
      'SELECT hex(randomblob(16)) AS connection_id',
    );
    final row = await _database
        .customSelect(
          'SELECT connection_id, total_changes() AS connection_changes, '
          'data_version FROM pragma_data_version, temp.doable_catalog_connection',
        )
        .getSingle();
    return (
      connectionId: _requiredStoredString(row.data, 'connection_id'),
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

({int sequence, tag_domain.Tag tag}) _decodeStoredTagAssignment(
  Map<String, Object?> data,
  int previousSequence,
) {
  final sequence = _requiredStoredInteger(data, 'creation_sequence');
  // SQLite удаляет начальный BOM при декодировании; проверяем исходный TEXT.
  if (_requiredStoredInteger(data, 'has_leading_bom') != 0 ||
      sequence <= previousSequence ||
      sequence !=
          _requiredStoredInteger(data, 'actual_tag_creation_sequence') ||
      (data['intention_id'] == null) ==
          (data['long_term_relation_id'] == null)) {
    throw const _StoredIntentionCorruption();
  }
  final tag = _decodeStoredTag(data);
  if (_requiredStoredString(data, 'assigned_tag_id') !=
      tag.id.toCanonicalString()) {
    throw const _StoredIntentionCorruption();
  }
  return (sequence: sequence, tag: tag);
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

typedef _TagReadStorageVersion = ({
  String connectionId,
  int connectionChanges,
  int dataVersion,
});

final class _TagReadTargetMissing implements Exception {
  const _TagReadTargetMissing();
}

final class _TagStatusTagMissing implements Exception {
  const _TagStatusTagMissing();
}

TagAssignmentStatusFailure _classifyTagAssignmentStatusFailure(Object error) {
  if (error is _TagStatusTagMissing) {
    return const TagAssignmentStatusTagNotFound();
  }
  if (error is _TagReadTargetMissing) {
    return const TagAssignmentStatusTargetNotFound();
  }
  if (error is _StoredIntentionCorruption) {
    return const TagAssignmentStatusCorruption();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagAssignmentStatusCorruption(),
    SqliteUnavailableFailure() => const TagAssignmentStatusUnavailable(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagAssignmentStatusUnexpected(),
  };
}

TagCatalogReadFailure _classifyTagCatalogReadFailure(Object error) {
  if (error is _TagReadTargetMissing) {
    return const TagCatalogTargetNotFound();
  }
  if (error is _StoredIntentionCorruption) {
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
  if (error is _TagReadTargetMissing) {
    return const TagAssignmentsTargetNotFound();
  }
  if (error is _StoredIntentionCorruption) {
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
