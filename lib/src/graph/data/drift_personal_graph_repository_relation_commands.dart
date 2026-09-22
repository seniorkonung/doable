part of 'drift_personal_graph_repository.dart';

extension _LongTermRelationCommandExecution on DriftPersonalGraphRepository {
  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) async {
    final stopwatch = Stopwatch()..start();
    final commandType = _longTermRelationCommandDiagnosticsType(command);

    try {
      final success = await _sequencer.run(() async {
        final committed = await _database.transaction(
          () => switch (command) {
            CreateLongTermRelation() => _createLongTermRelation(command),
            UpdateLongTermRelation() => _updateLongTermRelation(command),
            ArchiveLongTermRelation() => _setLongTermRelationScope(
              relationId: command.relationId,
              scope: relation_domain.RelationScope.archived,
            ),
            RestoreLongTermRelation() => _setLongTermRelationScope(
              relationId: command.relationId,
              scope: relation_domain.RelationScope.active,
            ),
          },
        );
        if (committed.didMutate) {
          _mutationSequence++;
        }
        final revision = _currentRevision;
        final value = committed.toSuccess(revision);
        final result = ConfirmedGraphResult(revision: revision, value: value);
        if (committed.didMutate) {
          _notifyGraphWatchersFor(value.changes);
        }
        return result;
      });
      _recordDiagnostics(
        LongTermRelationCommandDiagnosticsEvent(
          commandType: commandType,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return GraphCommandSucceeded(success);
    } on Object catch (error) {
      final failure = _classifyLongTermRelationCommandFailure(error);
      _recordDiagnostics(
        LongTermRelationCommandDiagnosticsEvent(
          commandType: commandType,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _longTermRelationDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  Future<_CommittedLongTermRelationCreation> _createLongTermRelation(
    CreateLongTermRelation command,
  ) async {
    await _requireRelationParticipant(
      command.sourceIntentionId,
      RelationParticipantRole.source,
      mustBeActive: true,
    );
    await _requireRelationParticipant(
      command.relatedIntentionId,
      RelationParticipantRole.related,
      mustBeActive: true,
    );

    final occupiedRelationId = await _findRelationForPair(
      command.sourceIntentionId,
      command.relatedIntentionId,
    );
    if (occupiedRelationId != null) {
      throw _LongTermRelationPairOccupied(occupiedRelationId);
    }

    final id = _relationIdGenerator.generate();
    final creationSequence = await _database
        .into(_database.longTermRelations)
        .insert(
          local.LongTermRelationsCompanion.insert(
            id: id.toCanonicalString(),
            sourceIntentionId: command.sourceIntentionId.toCanonicalString(),
            relatedIntentionId: command.relatedIntentionId.toCanonicalString(),
            type: switch (command.type) {
              relation_domain.LongTermRelationType.need => 'need',
              relation_domain.LongTermRelationType.can => 'can',
            },
            priority: switch (command.priority) {
              relation_domain.RelationPriority.p1 => 1,
              relation_domain.RelationPriority.p2 => 2,
              relation_domain.RelationPriority.p3 => 3,
              relation_domain.RelationPriority.p4 => 4,
            },
            description: Value(command.description?.value),
            isArchived: const Value(false),
          ),
        );
    final created = relation_domain.LongTermRelation(
      id: id,
      sourceIntentionId: command.sourceIntentionId,
      relatedIntentionId: command.relatedIntentionId,
      type: command.type,
      priority: command.priority,
      scope: relation_domain.RelationScope.active,
      creationSequence: relation_domain.RelationCreationSequence(
        creationSequence,
      ),
    );
    final affectedCounts = await _readVerifiedRelationCountsFor([
      command.sourceIntentionId,
      command.relatedIntentionId,
    ]);
    return _CommittedLongTermRelationCreation(
      relation: created,
      description: command.description,
      affectedCounts: affectedCounts,
    );
  }

  Future<_CommittedLongTermRelationUpdate> _updateLongTermRelation(
    UpdateLongTermRelation command,
  ) async {
    final storedBefore = await _readStoredRelation(command.relationId);
    if (storedBefore == null) {
      throw _LongTermRelationNotFound(command.relationId);
    }
    final before = storedBefore.toDomain();
    final sourceId = _applyRelationFieldPatch(
      before.sourceIntentionId,
      command.patch.sourceIntentionId,
    );
    final relatedId = _applyRelationFieldPatch(
      before.relatedIntentionId,
      command.patch.relatedIntentionId,
    );
    if (sourceId == relatedId) {
      throw const _LongTermRelationSameParticipants();
    }

    final mustBeActive = before.scope == relation_domain.RelationScope.active;
    await _requireRelationParticipant(
      sourceId,
      RelationParticipantRole.source,
      mustBeActive: mustBeActive,
    );
    await _requireRelationParticipant(
      relatedId,
      RelationParticipantRole.related,
      mustBeActive: mustBeActive,
    );
    final occupiedRelationId = await _findRelationForPair(
      sourceId,
      relatedId,
      excludingId: command.relationId,
    );
    if (occupiedRelationId != null) {
      throw _LongTermRelationPairOccupied(occupiedRelationId);
    }

    final type = _applyRelationFieldPatch(before.type, command.patch.type);
    final priority = _applyRelationFieldPatch(
      before.priority,
      command.patch.priority,
    );
    final description = _applyRelationDescriptionPatch(
      storedBefore.description,
      command.patch.description,
    );
    final after = relation_domain.LongTermRelation(
      id: before.id,
      sourceIntentionId: sourceId,
      relatedIntentionId: relatedId,
      type: type,
      priority: priority,
      scope: before.scope,
      creationSequence: before.creationSequence,
    );
    final didMutate = !_sameStoredRelation(
      before: before,
      beforeDescription: storedBefore.description,
      after: after,
      afterDescription: description,
    );
    if (!didMutate) {
      return _CommittedLongTermRelationUpdate(
        before: before,
        relation: after,
        description: description,
        affectedCounts: const {},
        didMutate: false,
      );
    }

    final updatedRows =
        await (_database.update(_database.longTermRelations)..where(
              (row) => row.id.equals(command.relationId.toCanonicalString()),
            ))
            .write(
              local.LongTermRelationsCompanion(
                sourceIntentionId: switch (command.patch.sourceIntentionId) {
                  LongTermRelationFieldUnchanged() => const Value.absent(),
                  LongTermRelationFieldSet(:final value) => Value(
                    value.toCanonicalString(),
                  ),
                },
                relatedIntentionId: switch (command.patch.relatedIntentionId) {
                  LongTermRelationFieldUnchanged() => const Value.absent(),
                  LongTermRelationFieldSet(:final value) => Value(
                    value.toCanonicalString(),
                  ),
                },
                type: switch (command.patch.type) {
                  LongTermRelationFieldUnchanged() => const Value.absent(),
                  LongTermRelationFieldSet(:final value) => Value(
                    _storedRelationType(value),
                  ),
                },
                priority: switch (command.patch.priority) {
                  LongTermRelationFieldUnchanged() => const Value.absent(),
                  LongTermRelationFieldSet(:final value) => Value(
                    _storedRelationPriority(value),
                  ),
                },
                description: switch (command.patch.description) {
                  LongTermRelationDescriptionUnchanged() =>
                    const Value.absent(),
                  LongTermRelationDescriptionCleared() => const Value(null),
                  LongTermRelationDescriptionReplaced(:final value) => Value(
                    value.value,
                  ),
                },
              ),
            );
    if (updatedRows != 1) {
      throw _LongTermRelationNotFound(command.relationId);
    }
    final storedAfter = await _readStoredRelation(command.relationId);
    if (storedAfter == null) throw const _StoredIntentionCorruption();
    final verifiedAfter = storedAfter.toDomain();
    if (!_sameStoredRelation(
      before: after,
      beforeDescription: description,
      after: verifiedAfter,
      afterDescription: storedAfter.description,
    )) {
      throw const _StoredIntentionCorruption();
    }
    final affectedCounts = await _readVerifiedRelationCountsFor({
      before.sourceIntentionId,
      before.relatedIntentionId,
      verifiedAfter.sourceIntentionId,
      verifiedAfter.relatedIntentionId,
    });
    return _CommittedLongTermRelationUpdate(
      before: before,
      relation: verifiedAfter,
      description: storedAfter.description,
      affectedCounts: affectedCounts,
      didMutate: true,
    );
  }

  Future<_CommittedLongTermRelationUpdate> _setLongTermRelationScope({
    required LongTermRelationId relationId,
    required relation_domain.RelationScope scope,
  }) async {
    final storedBefore = await _readStoredRelation(relationId);
    if (storedBefore == null) {
      throw _LongTermRelationNotFound(relationId);
    }
    final before = storedBefore.toDomain();

    if (scope == relation_domain.RelationScope.active) {
      await _requireRelationParticipant(
        before.sourceIntentionId,
        RelationParticipantRole.source,
        mustBeActive: true,
      );
      await _requireRelationParticipant(
        before.relatedIntentionId,
        RelationParticipantRole.related,
        mustBeActive: true,
      );
    }

    final after = relation_domain.LongTermRelation(
      id: before.id,
      sourceIntentionId: before.sourceIntentionId,
      relatedIntentionId: before.relatedIntentionId,
      type: before.type,
      priority: before.priority,
      scope: scope,
      creationSequence: before.creationSequence,
    );
    if (before.scope == scope) {
      return _CommittedLongTermRelationUpdate(
        before: before,
        relation: after,
        description: storedBefore.description,
        affectedCounts: const {},
        didMutate: false,
      );
    }

    final updatedRows =
        await (_database.update(
          _database.longTermRelations,
        )..where((row) => row.id.equals(relationId.toCanonicalString()))).write(
          local.LongTermRelationsCompanion(
            isArchived: Value(scope == relation_domain.RelationScope.archived),
          ),
        );
    if (updatedRows != 1) {
      throw _LongTermRelationNotFound(relationId);
    }

    final storedAfter = await _readStoredRelation(relationId);
    if (storedAfter == null) throw const _StoredIntentionCorruption();
    final verifiedAfter = storedAfter.toDomain();
    if (!_sameStoredRelation(
      before: after,
      beforeDescription: storedBefore.description,
      after: verifiedAfter,
      afterDescription: storedAfter.description,
    )) {
      throw const _StoredIntentionCorruption();
    }
    final affectedCounts = await _readVerifiedRelationCountsFor({
      before.sourceIntentionId,
      before.relatedIntentionId,
    });
    return _CommittedLongTermRelationUpdate(
      before: before,
      relation: verifiedAfter,
      description: storedAfter.description,
      affectedCounts: affectedCounts,
      didMutate: true,
    );
  }

  Future<_StoredRelationGroupRow?> _readStoredRelation(
    LongTermRelationId id,
  ) async {
    final row = await _database
        .customSelect(
          '''
            SELECT
              creation_sequence,
              id,
              source_intention_id,
              related_intention_id,
              type,
              priority,
              description,
              is_archived
            FROM long_term_relations
            WHERE id = ?
          ''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.longTermRelations},
        )
        .getSingleOrNull();
    return row == null ? null : _StoredRelationGroupRow.fromRawRow(row);
  }

  Future<void> _requireRelationParticipant(
    IntentionId id,
    RelationParticipantRole role, {
    required bool mustBeActive,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT is_archived FROM intentions WHERE id = ?',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.intentions},
        )
        .getSingleOrNull();
    if (row == null) throw _LongTermRelationParticipantNotFound(role, id);
    final archivedValue = row.data['is_archived'];
    if (archivedValue is! int || (archivedValue != 0 && archivedValue != 1)) {
      throw const _StoredIntentionCorruption();
    }
    if (mustBeActive && archivedValue == 1) {
      throw _LongTermRelationParticipantArchived(role, id);
    }
  }

  Future<LongTermRelationId?> _findRelationForPair(
    IntentionId sourceId,
    IntentionId relatedId, {
    LongTermRelationId? excludingId,
  }) async {
    final exclusion = excludingId == null ? '' : 'AND id <> ?';
    final row = await _database
        .customSelect(
          '''
            SELECT id
            FROM long_term_relations
            WHERE source_intention_id = ? AND related_intention_id = ?
              $exclusion
          ''',
          variables: [
            Variable<String>(sourceId.toCanonicalString()),
            Variable<String>(relatedId.toCanonicalString()),
            if (excludingId != null)
              Variable<String>(excludingId.toCanonicalString()),
          ],
          readsFrom: {_database.longTermRelations},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final serializedId = row.data['id'];
    if (serializedId is! String) throw const _StoredIntentionCorruption();
    return switch (LongTermRelationId.decode(serializedId)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() =>
        throw const _StoredIntentionCorruption(),
    };
  }
}

sealed class _CommittedLongTermRelationCommand {
  const _CommittedLongTermRelationCommand();

  bool get didMutate;

  LongTermRelationCommandSuccess toSuccess(GraphRevision revision);
}

final class _CommittedLongTermRelationCreation
    extends _CommittedLongTermRelationCommand {
  _CommittedLongTermRelationCreation({
    required this.relation,
    required this.description,
    required Map<IntentionId, RelationCounts> affectedCounts,
  }) : affectedCounts = Map.unmodifiable(affectedCounts);

  final relation_domain.LongTermRelation relation;
  final LongTermRelationDescription? description;
  final Map<IntentionId, RelationCounts> affectedCounts;

  @override
  bool get didMutate => true;

  @override
  LongTermRelationCreated toSuccess(GraphRevision revision) =>
      LongTermRelationCreated(
        relation: relation,
        description: description,
        changes: [
          for (final entry in affectedCounts.entries)
            IntentionRelationCountsChanged(
              revision: revision,
              intentionId: entry.key,
              counts: entry.value,
            ),
          LongTermRelationCreatedChange(revision: revision, relation: relation),
        ],
      );
}

final class _CommittedLongTermRelationUpdate
    extends _CommittedLongTermRelationCommand {
  _CommittedLongTermRelationUpdate({
    required this.before,
    required this.relation,
    required this.description,
    required Map<IntentionId, RelationCounts> affectedCounts,
    required this.didMutate,
  }) : affectedCounts = Map.unmodifiable(affectedCounts);

  final relation_domain.LongTermRelation before;
  final relation_domain.LongTermRelation relation;
  final LongTermRelationDescription? description;
  final Map<IntentionId, RelationCounts> affectedCounts;

  @override
  final bool didMutate;

  @override
  LongTermRelationUpdated toSuccess(GraphRevision revision) =>
      LongTermRelationUpdated(
        before: before,
        relation: relation,
        description: description,
        changes: didMutate
            ? [
                for (final entry in affectedCounts.entries)
                  IntentionRelationCountsChanged(
                    revision: revision,
                    intentionId: entry.key,
                    counts: entry.value,
                  ),
                LongTermRelationUpdatedChange(
                  revision: revision,
                  before: before,
                  after: relation,
                ),
              ]
            : [
                LongTermRelationUnchangedChange(
                  revision: revision,
                  relation: relation,
                ),
              ],
      );
}

LongTermRelationCommandFailure _classifyLongTermRelationCommandFailure(
  Object error,
) {
  if (error case _LongTermRelationPairOccupied(:final relationId)) {
    return LongTermRelationPairOccupiedFailure(relationId);
  }
  if (error case _LongTermRelationNotFound(:final relationId)) {
    return LongTermRelationNotFoundFailure(relationId);
  }
  if (error is _LongTermRelationSameParticipants) {
    return const LongTermRelationCommandValidationFailure(
      CreateLongTermRelationValidationFailure.sameIntention,
    );
  }
  if (error case _LongTermRelationParticipantNotFound(:final role, :final id)) {
    return LongTermRelationParticipantNotFoundFailure(
      role: role,
      intentionId: id,
    );
  }
  if (error case _LongTermRelationParticipantArchived(:final role, :final id)) {
    return LongTermRelationParticipantArchivedFailure(
      role: role,
      intentionId: id,
    );
  }
  if (error is _StoredIntentionCorruption) {
    return const LongTermRelationCorruptionFailure();
  }

  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const LongTermRelationCorruptionFailure(),
    SqliteUnavailableFailure() => const LongTermRelationUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const LongTermRelationUnexpectedFailure(),
  };
}

LongTermRelationCommandDiagnosticsType _longTermRelationCommandDiagnosticsType(
  LongTermRelationCommand command,
) => switch (command) {
  CreateLongTermRelation() => LongTermRelationCommandDiagnosticsType.create,
  UpdateLongTermRelation() => LongTermRelationCommandDiagnosticsType.update,
  ArchiveLongTermRelation() => LongTermRelationCommandDiagnosticsType.archive,
  RestoreLongTermRelation() => LongTermRelationCommandDiagnosticsType.restore,
};

DiagnosticsFailureCode _longTermRelationDiagnosticsFailureCode(
  LongTermRelationCommandFailure failure,
) => switch (failure.category) {
  GraphFailureCategory.validation => DiagnosticsFailureCode.validation,
  GraphFailureCategory.notFound => DiagnosticsFailureCode.notFound,
  GraphFailureCategory.conflict => DiagnosticsFailureCode.conflict,
  GraphFailureCategory.unavailable => DiagnosticsFailureCode.unavailable,
  GraphFailureCategory.corruption => DiagnosticsFailureCode.corruption,
  GraphFailureCategory.unexpected => DiagnosticsFailureCode.unexpected,
};

final class _LongTermRelationPairOccupied implements Exception {
  const _LongTermRelationPairOccupied(this.relationId);

  final LongTermRelationId relationId;
}

final class _LongTermRelationNotFound implements Exception {
  const _LongTermRelationNotFound(this.relationId);

  final LongTermRelationId relationId;
}

final class _LongTermRelationSameParticipants implements Exception {
  const _LongTermRelationSameParticipants();
}

final class _LongTermRelationParticipantNotFound implements Exception {
  const _LongTermRelationParticipantNotFound(this.role, this.id);

  final RelationParticipantRole role;
  final IntentionId id;
}

final class _LongTermRelationParticipantArchived implements Exception {
  const _LongTermRelationParticipantArchived(this.role, this.id);

  final RelationParticipantRole role;
  final IntentionId id;
}

T _applyRelationFieldPatch<T extends Object>(
  T current,
  LongTermRelationFieldPatch<T> patch,
) => switch (patch) {
  LongTermRelationFieldUnchanged() => current,
  LongTermRelationFieldSet(:final value) => value,
};

LongTermRelationDescription? _applyRelationDescriptionPatch(
  LongTermRelationDescription? current,
  LongTermRelationDescriptionPatch patch,
) => switch (patch) {
  LongTermRelationDescriptionUnchanged() => current,
  LongTermRelationDescriptionCleared() => null,
  LongTermRelationDescriptionReplaced(:final value) => value,
};

String _storedRelationType(relation_domain.LongTermRelationType type) =>
    switch (type) {
      relation_domain.LongTermRelationType.need => 'need',
      relation_domain.LongTermRelationType.can => 'can',
    };

int _storedRelationPriority(relation_domain.RelationPriority priority) =>
    switch (priority) {
      relation_domain.RelationPriority.p1 => 1,
      relation_domain.RelationPriority.p2 => 2,
      relation_domain.RelationPriority.p3 => 3,
      relation_domain.RelationPriority.p4 => 4,
    };

bool _sameStoredRelation({
  required relation_domain.LongTermRelation before,
  required LongTermRelationDescription? beforeDescription,
  required relation_domain.LongTermRelation after,
  required LongTermRelationDescription? afterDescription,
}) =>
    before.id == after.id &&
    before.sourceIntentionId == after.sourceIntentionId &&
    before.relatedIntentionId == after.relatedIntentionId &&
    before.type == after.type &&
    before.priority == after.priority &&
    before.scope == after.scope &&
    before.creationSequence == after.creationSequence &&
    beforeDescription == afterDescription;
