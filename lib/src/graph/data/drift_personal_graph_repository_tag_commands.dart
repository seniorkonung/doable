part of 'drift_personal_graph_repository.dart';

extension _TagCommandExecution on DriftPersonalGraphRepository {
  Future<TagCommandResult> _executeTag(TagCommand command) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagCommandDiagnosticsStage.validation;
    final type = switch (command) {
      CreateTag() => TagCommandDiagnosticsType.create,
      RenameTag() => TagCommandDiagnosticsType.rename,
      DeleteTag() => TagCommandDiagnosticsType.delete,
      AssignTag() => TagCommandDiagnosticsType.assign,
      RemoveTagAssignment() => TagCommandDiagnosticsType.removeAssignment,
    };
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagCommandDiagnosticsEvent(
        commandType: type,
        stage: stage,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final confirmed = await _sequencer.run(() async {
        late _CommittedTagCommand committed;
        try {
          committed = await _database.transaction(
            () => switch (command) {
              CreateTag() => _createTag(
                command,
                onStage: (value) => stage = value,
              ),
              RenameTag() => _renameTag(
                command,
                onStage: (value) => stage = value,
              ),
              DeleteTag() => _deleteTag(
                command,
                onStage: (value) => stage = value,
              ),
              AssignTag() => _assignTag(
                command,
                onStage: (value) => stage = value,
              ),
              RemoveTagAssignment() => _removeTagAssignment(
                command,
                onStage: (value) => stage = value,
              ),
            },
          );
        } on Object catch (error) {
          // После отката индекс имени остаётся окончательным арбитром гонки.
          final conflictingName = switch (command) {
            CreateTag(:final name) || RenameTag(:final name) => name,
            DeleteTag() || AssignTag() || RemoveTagAssignment() => null,
          };
          if (conflictingName != null) {
            if (classifySqliteFailure(error) case SqliteConstraintFailure(
              extendedResultCode: SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
            )) {
              stage = TagCommandDiagnosticsStage.resultRead;
              final occupied = await _findTagByNameKey(
                conflictingName.matchingKey,
              );
              if (occupied != null &&
                  switch (command) {
                    CreateTag() => true,
                    RenameTag(:final tagId) => occupied.id != tagId,
                    DeleteTag() ||
                    AssignTag() ||
                    RemoveTagAssignment() => false,
                  }) {
                throw _TagNameOccupied(occupied.id);
              }
            }
          }
          rethrow;
        }

        if (committed.didMutate) _mutationSequence++;
        final revision = _currentRevision;
        final outcome = committed.toSuccess(revision);
        final result = ConfirmedGraphResult(revision: revision, value: outcome);
        if (committed.didMutate) _notifyGraphWatchersFor(result.changes);
        return result;
      });
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagCommandSucceeded(confirmed);
    } on Object catch (error) {
      final failure = _classifyTagCommandFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagCommandFailed(failure);
    }
  }

  Future<_CommittedTagCommand> _createTag(
    CreateTag command, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    onStage(TagCommandDiagnosticsStage.write);
    final id = _tagIdGenerator.generate();
    await _database
        .into(_database.tags)
        .insert(
          local.TagsCompanion.insert(
            id: id.toCanonicalString(),
            name: command.name.value,
          ),
        );
    onStage(TagCommandDiagnosticsStage.resultRead);
    final tag = await _findTagById(id);
    if (tag == null || tag.name != command.name) {
      throw const _StoredIntentionCorruption();
    }
    return _CommittedTagCreated(tag);
  }

  Future<_CommittedTagCommand> _renameTag(
    RenameTag command, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    final before = await _findTagById(command.tagId);
    if (before == null) throw _TagMissing(command.tagId);
    if (before.name == command.name) return _CommittedTagUnchanged(before);

    onStage(TagCommandDiagnosticsStage.write);
    final rows =
        await (_database.update(
              _database.tags,
            )..where((row) => row.id.equals(command.tagId.toCanonicalString())))
            .write(local.TagsCompanion(name: Value(command.name.value)));
    if (rows != 1) throw _TagMissing(command.tagId);
    onStage(TagCommandDiagnosticsStage.resultRead);
    final after = await _findTagById(command.tagId);
    if (after == null || after.name != command.name) {
      throw const _StoredIntentionCorruption();
    }
    return _CommittedTagRenamed(before: before, after: after);
  }

  Future<_CommittedTagCommand> _deleteTag(
    DeleteTag command, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    if (await _findTagById(command.tagId) == null) {
      throw _TagMissing(command.tagId);
    }
    onStage(TagCommandDiagnosticsStage.write);
    final rows = await (_database.delete(
      _database.tags,
    )..where((row) => row.id.equals(command.tagId.toCanonicalString()))).go();
    if (rows != 1) throw _TagMissing(command.tagId);
    return _CommittedTagDeleted(command.tagId);
  }

  Future<_CommittedTagCommand> _assignTag(
    AssignTag command, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    await _checkAssignmentIdentities(command.tagId, command.target);
    final assignment = command.assignment;
    if (await _assignmentExists(assignment)) {
      return _CommittedTagAssignmentUnchanged(
        assignment,
        TagAssignmentState.assigned,
      );
    }

    final before = await _tagTargetCatalogEntryBefore(command.target);
    onStage(TagCommandDiagnosticsStage.write);
    final tagId = command.tagId.toCanonicalString();
    await _database.into(_database.tagAssignments).insert(
      switch (command.target) {
        IntentionTagTarget(:final intentionId) =>
          local.TagAssignmentsCompanion.insert(
            tagId: tagId,
            intentionId: Value(intentionId.toCanonicalString()),
          ),
        LongTermRelationTagTarget(:final relationId) =>
          local.TagAssignmentsCompanion.insert(
            tagId: tagId,
            longTermRelationId: Value(relationId.toCanonicalString()),
          ),
      },
    );
    return _CommittedTagAssignmentChanged(
      assignment,
      TagAssignmentState.assigned,
      catalogEntries: await _tagTargetCatalogEntries(before, onStage: onStage),
    );
  }

  Future<_CommittedTagCommand> _removeTagAssignment(
    RemoveTagAssignment command, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    await _checkAssignmentIdentities(command.tagId, command.target);
    final assignment = command.assignment;
    if (!await _assignmentExists(assignment)) {
      return _CommittedTagAssignmentUnchanged(
        assignment,
        TagAssignmentState.absent,
      );
    }

    final before = await _tagTargetCatalogEntryBefore(command.target);
    onStage(TagCommandDiagnosticsStage.write);
    final tagId = command.tagId.toCanonicalString();
    final rows =
        await (_database.delete(_database.tagAssignments)..where(
              (row) =>
                  row.tagId.equals(tagId) &
                  switch (command.target) {
                    IntentionTagTarget(:final intentionId) =>
                      row.intentionId.equals(intentionId.toCanonicalString()),
                    LongTermRelationTagTarget(:final relationId) =>
                      row.longTermRelationId.equals(
                        relationId.toCanonicalString(),
                      ),
                  },
            ))
            .go();
    if (rows != 1) throw const _StoredIntentionCorruption();
    return _CommittedTagAssignmentChanged(
      assignment,
      TagAssignmentState.absent,
      catalogEntries: await _tagTargetCatalogEntries(before, onStage: onStage),
    );
  }

  /// Снимок «до» читается до записи пары, поэтому содержит прежний
  /// полный состав собственных тегов намерения.
  Future<_TagTargetCatalogEntryBefore?> _tagTargetCatalogEntryBefore(
    TagTarget target,
  ) async {
    switch (target) {
      case IntentionTagTarget(:final intentionId):
        final stored = await _readCommandSnapshot(intentionId);
        if (stored == null) throw const _StoredIntentionCorruption();
        final counts = await _readVerifiedRelationCounts(intentionId);
        return (
          id: intentionId,
          counts: counts,
          entry: await _catalogEntrySnapshot(stored, counts),
        );
      case LongTermRelationTagTarget():
        return null;
    }
  }

  /// Команда тега не меняет строку намерения и его связи: снимок «после»
  /// отличается от снимка «до» только составом собственных тегов.
  Future<_TagTargetCatalogEntries?> _tagTargetCatalogEntries(
    _TagTargetCatalogEntryBefore? before, {
    required void Function(TagCommandDiagnosticsStage) onStage,
  }) async {
    if (before == null) return null;
    onStage(TagCommandDiagnosticsStage.resultRead);
    final stored = await _readCommandSnapshot(before.id);
    if (stored == null) throw const _StoredIntentionCorruption();
    return (
      before: before.entry,
      after: await _catalogEntrySnapshot(stored, before.counts),
    );
  }

  Future<void> _checkAssignmentIdentities(TagId tagId, TagTarget target) async {
    if (await _findTagById(tagId) == null) throw _TagMissing(tagId);
    final exists = switch (target) {
      IntentionTagTarget(:final intentionId) =>
        await _database
            .customSelect(
              'SELECT 1 FROM intentions WHERE id = ?',
              variables: [Variable<String>(intentionId.toCanonicalString())],
              readsFrom: {_database.intentions},
            )
            .getSingleOrNull(),
      LongTermRelationTagTarget(:final relationId) =>
        await _database
            .customSelect(
              'SELECT 1 FROM long_term_relations WHERE id = ?',
              variables: [Variable<String>(relationId.toCanonicalString())],
              readsFrom: {_database.longTermRelations},
            )
            .getSingleOrNull(),
    };
    if (exists == null) throw _TagTargetMissing(target);
  }

  Future<bool> _assignmentExists(TagAssignment assignment) async {
    final tagId = Variable<String>(assignment.tagId.toCanonicalString());
    final row = switch (assignment.target) {
      IntentionTagTarget(:final intentionId) =>
        await _database
            .customSelect(
              'SELECT 1 FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
              variables: [
                tagId,
                Variable<String>(intentionId.toCanonicalString()),
              ],
              readsFrom: {_database.tagAssignments},
            )
            .getSingleOrNull(),
      LongTermRelationTagTarget(:final relationId) =>
        await _database
            .customSelect(
              'SELECT 1 FROM tag_assignments WHERE tag_id = ? AND long_term_relation_id = ?',
              variables: [
                tagId,
                Variable<String>(relationId.toCanonicalString()),
              ],
              readsFrom: {_database.tagAssignments},
            )
            .getSingleOrNull(),
    };
    return row != null;
  }

  Future<tag_domain.Tag?> _findTagById(TagId id) async {
    final row = await _database
        .customSelect(
          'SELECT id, name FROM tags WHERE id = ?',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.tags},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final tag = _decodeStoredTag(row.data);
    if (tag.id != id) throw const _StoredIntentionCorruption();
    return tag;
  }

  Future<tag_domain.Tag?> _findTagByNameKey(String key) async {
    final row = await _database
        .customSelect(
          'SELECT id, name FROM tags WHERE name_key = ?',
          variables: [Variable<String>(key)],
          readsFrom: {_database.tags},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final tag = _decodeStoredTag(row.data);
    if (tag.name.matchingKey != key) throw const _StoredIntentionCorruption();
    return tag;
  }
}

sealed class _CommittedTagCommand {
  const _CommittedTagCommand();

  bool get didMutate;
  TagCommandSuccess toSuccess(GraphRevision revision);
}

final class _CommittedTagCreated extends _CommittedTagCommand {
  const _CommittedTagCreated(this.tag);
  final tag_domain.Tag tag;

  @override
  bool get didMutate => true;
  @override
  TagCommandSuccess toSuccess(GraphRevision revision) =>
      TagCreated(TagCreatedChange(revision: revision, after: tag));
}

final class _CommittedTagRenamed extends _CommittedTagCommand {
  const _CommittedTagRenamed({required this.before, required this.after});
  final tag_domain.Tag before;
  final tag_domain.Tag after;

  @override
  bool get didMutate => true;
  @override
  TagCommandSuccess toSuccess(GraphRevision revision) => TagRenamed(
    TagRenamedChange(revision: revision, before: before, after: after),
  );
}

final class _CommittedTagUnchanged extends _CommittedTagCommand {
  const _CommittedTagUnchanged(this.tag);
  final tag_domain.Tag tag;

  @override
  bool get didMutate => false;
  @override
  TagCommandSuccess toSuccess(GraphRevision revision) =>
      TagUnchanged(TagUnchangedChange(revision: revision, tag: tag));
}

final class _CommittedTagDeleted extends _CommittedTagCommand {
  const _CommittedTagDeleted(this.id);
  final TagId id;

  @override
  bool get didMutate => true;
  @override
  TagCommandSuccess toSuccess(GraphRevision revision) =>
      TagDeleted(TagDeletedChange(revision: revision, tagId: id));
}

typedef _TagTargetCatalogEntryBefore = ({
  IntentionId id,
  RelationCounts counts,
  IntentionCatalogEntrySnapshot entry,
});

typedef _TagTargetCatalogEntries = ({
  IntentionCatalogEntrySnapshot before,
  IntentionCatalogEntrySnapshot after,
});

final class _CommittedTagAssignmentChanged extends _CommittedTagCommand {
  const _CommittedTagAssignmentChanged(
    this.assignment,
    this.state, {
    required this.catalogEntries,
  });

  final TagAssignment assignment;
  final TagAssignmentState state;

  /// Есть только у назначения намерению.
  final _TagTargetCatalogEntries? catalogEntries;

  @override
  bool get didMutate => true;

  @override
  TagCommandSuccess toSuccess(GraphRevision revision) => TagAssignmentChanged(
    TagAssignmentChangedChange(
      revision: revision,
      assignment: assignment,
      state: state,
    ),
    catalogMutation: switch (catalogEntries) {
      (:final before, :final after) => IntentionCatalogUpdated(
        revision: revision,
        before: before,
        after: after,
      ),
      null => null,
    },
  );
}

final class _CommittedTagAssignmentUnchanged extends _CommittedTagCommand {
  const _CommittedTagAssignmentUnchanged(this.assignment, this.state);

  final TagAssignment assignment;
  final TagAssignmentState state;

  @override
  bool get didMutate => false;

  @override
  TagCommandSuccess toSuccess(GraphRevision revision) => TagAssignmentUnchanged(
    TagAssignmentUnchangedChange(
      revision: revision,
      assignment: assignment,
      state: state,
    ),
  );
}

final class _TagMissing implements Exception {
  const _TagMissing(this.id);
  final TagId id;
}

final class _TagTargetMissing implements Exception {
  const _TagTargetMissing(this.target);
  final TagTarget target;
}

final class _TagNameOccupied implements Exception {
  const _TagNameOccupied(this.id);
  final TagId id;
}

TagCommandFailure _classifyTagCommandFailure(Object error) {
  if (error is _TagMissing) return TagNotFoundFailure(error.id);
  if (error is _TagTargetMissing) {
    return TagTargetNotFoundFailure(error.target);
  }
  if (error is _TagNameOccupied) return TagNameOccupiedFailure(error.id);
  if (error is _StoredIntentionCorruption) return const TagCorruptionFailure();
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagCorruptionFailure(),
    SqliteUnavailableFailure() => const TagUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagUnexpectedFailure(),
  };
}
