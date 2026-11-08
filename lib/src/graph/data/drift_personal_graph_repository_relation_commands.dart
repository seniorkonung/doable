part of 'drift_personal_graph_repository.dart';

/// Состояние связи до каскада, архивное состояние и показание времени,
/// записанные каскадом. Изменение получает ревизию только после
/// подтверждения каскада.
final class _CascadedRelationScopeChange {
  const _CascadedRelationScopeChange(this.before, this.scope, this.changedAt);

  final relation_domain.LongTermRelation before;
  final relation_domain.RelationScope scope;
  final relation_domain.RelationTimestamp changedAt;

  relation_domain.LongTermRelation get after =>
      relation_domain.LongTermRelation(
        id: before.id,
        sourceIntentionId: before.sourceIntentionId,
        relatedIntentionId: before.relatedIntentionId,
        type: before.type,
        priority: before.priority,
        scope: scope,
        creationSequence: before.creationSequence,
        createdAt: before.createdAt,
        updatedAt: changedAt,
      );

  LongTermRelationUpdatedChange toChange(GraphRevision revision) =>
      LongTermRelationUpdatedChange(
        revision: revision,
        before: before,
        after: after,
      );
}

extension _LongTermRelationCommandExecution on DriftPersonalGraphRepository {
  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) async {
    final stopwatch = Stopwatch()..start();
    final commandType = _longTermRelationCommandDiagnosticsType(command);

    try {
      final success = await _writeGraph<LongTermRelationCommandSuccess>(
        (clock) => switch (command) {
          AddLongTermRelations() => _addLongTermRelations(command, clock),
          UpdateLongTermRelation() => _updateLongTermRelation(command, clock),
          ArchiveLongTermRelation() => _archiveRelationCascade(command, clock),
          RestoreLongTermRelation() => _restoreRelationCascade(command, clock),
          DeleteLongTermRelation() => _deleteRelationCascade(command, clock),
        },
      );
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
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  /// Создаёт связи пачки в порядке набора. Вызывается внутри транзакции
  /// команды: отказ на любом месте набора откатывает всю пачку.
  ///
  /// Группа задаёт участников, поэтому намерение страницы и каждый кандидат
  /// проверяются в своей роли. Все связи получают одно показание времени, а
  /// последовательность создания растёт в порядке набора.
  Future<_CommittedLongTermRelationsAddition> _addLongTermRelations(
    AddLongTermRelations command,
    _GraphWriteClock clock,
  ) async {
    final pageIsSource =
        command.group.direction == relation_domain.RelationDirection.outgoing;
    final (pageRole, candidateRole) = pageIsSource
        ? (RelationParticipantRole.source, RelationParticipantRole.related)
        : (RelationParticipantRole.related, RelationParticipantRole.source);
    await _requireRelationParticipant(
      command.pageIntentionId,
      pageRole,
      mustBeActive: true,
    );

    final pairs = <({IntentionId source, IntentionId related})>[];
    for (final candidateId in command.candidateIds) {
      await _requireRelationParticipant(
        candidateId,
        candidateRole,
        mustBeActive: true,
      );
      final pair = pageIsSource
          ? (source: command.pageIntentionId, related: candidateId)
          : (source: candidateId, related: command.pageIntentionId);
      final occupiedRelationId = await _findRelationForPair(
        pair.source,
        pair.related,
      );
      if (occupiedRelationId != null) {
        throw _LongTermRelationPairOccupied(occupiedRelationId);
      }
      pairs.add(pair);
    }

    final createdAt = relation_domain.RelationTimestamp(clock.read());
    final storedCreatedAt = createdAt.value.microsecondsSinceEpoch;
    final relations = <relation_domain.LongTermRelation>[];
    for (final pair in pairs) {
      final id = _relationIdGenerator.generate();
      final creationSequence = await _database
          .into(_database.longTermRelations)
          .insert(
            local.LongTermRelationsCompanion.insert(
              id: id.toCanonicalString(),
              sourceIntentionId: pair.source.toCanonicalString(),
              relatedIntentionId: pair.related.toCanonicalString(),
              type: _storedRelationType(command.group.type),
              priority: _storedRelationPriority(
                relation_domain.RelationPriority.p4,
              ),
              isArchived: const Value(false),
              createdAt: storedCreatedAt,
              updatedAt: storedCreatedAt,
            ),
          );
      relations.add(
        relation_domain.LongTermRelation(
          id: id,
          sourceIntentionId: pair.source,
          relatedIntentionId: pair.related,
          type: command.group.type,
          priority: relation_domain.RelationPriority.p4,
          scope: relation_domain.RelationScope.active,
          creationSequence: relation_domain.RelationCreationSequence(
            creationSequence,
          ),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
    }
    final kindChanges = <_IntentionCatalogChange>[];
    for (final candidateId in command.candidateIds) {
      if (command.supportingCandidateIds.contains(candidateId)) {
        final change = await _makeSupportingWithRelation(candidateId, clock);
        if (change != null) kindChanges.add(change);
      }
    }
    final affectedCounts = await _readVerifiedRelationCountsFor([
      command.pageIntentionId,
      ...command.candidateIds,
    ]);
    return _CommittedLongTermRelationsAddition(
      relations: relations,
      affectedCounts: affectedCounts,
      kindChanges: kindChanges,
    );
  }

  /// Делает вспомогательным кандидата, входящую связь которого команда уже
  /// записала. Уже вспомогательное намерение не меняется.
  Future<_IntentionCatalogChange?> _makeSupportingWithRelation(
    IntentionId id,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const StoredGraphCorruption();
    if (storedBefore.intention.kind == domain.IntentionKind.supporting) {
      return null;
    }
    final before = await _catalogEntrySnapshot(storedBefore);
    await (_database.update(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).write(
      local.IntentionsCompanion(
        kind: Value(domain.IntentionKind.supporting.name),
        updatedAt: Value(clock.read().microsecondsSinceEpoch),
      ),
    );
    final stored = await _readCommandSnapshot(id);
    if (stored == null) throw const StoredGraphCorruption();
    return (before: before, after: await _catalogEntrySnapshot(stored));
  }

  Future<_CommittedLongTermRelationUpdate> _updateLongTermRelation(
    UpdateLongTermRelation command,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readStoredRelation(command.relationId);
    if (storedBefore == null) {
      throw _LongTermRelationNotFound(command.relationId);
    }
    final before = storedBefore.toDomain();

    final type = _applyRelationFieldPatch(before.type, command.patch.type);
    final priority = _applyRelationFieldPatch(
      before.priority,
      command.patch.priority,
    );
    if (before.scope == relation_domain.RelationScope.archived &&
        type != before.type) {
      throw _LongTermRelationArchivedTypeChange(before.id);
    }
    final description = _applyRelationDescriptionPatch(
      storedBefore.description,
      command.patch.description,
    );
    final after = relation_domain.LongTermRelation(
      id: before.id,
      sourceIntentionId: before.sourceIntentionId,
      relatedIntentionId: before.relatedIntentionId,
      type: type,
      priority: priority,
      scope: before.scope,
      creationSequence: before.creationSequence,
      createdAt: before.createdAt,
      updatedAt: before.updatedAt,
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
                updatedAt: Value(clock.read().microsecondsSinceEpoch),
              ),
            );
    if (updatedRows != 1) {
      throw _LongTermRelationNotFound(command.relationId);
    }
    final storedAfter = await _readStoredRelation(command.relationId);
    if (storedAfter == null) throw const StoredGraphCorruption();
    final verifiedAfter = storedAfter.toDomain();
    if (!_sameStoredRelation(
      before: after,
      beforeDescription: description,
      after: verifiedAfter,
      afterDescription: storedAfter.description,
    )) {
      throw const StoredGraphCorruption();
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

  Future<StoredLongTermRelation?> _readStoredRelation(
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
              is_archived,
              created_at,
              updated_at
            FROM long_term_relations
            WHERE id = ?
          ''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.longTermRelations},
        )
        .getSingleOrNull();
    return row == null ? null : StoredLongTermRelation.decode(row.data);
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
    final archiveState = decodeStoredIntentionArchiveState(
      row.data,
      'is_archived',
    );
    if (mustBeActive && archiveState == domain.IntentionArchiveState.archived) {
      throw _LongTermRelationParticipantArchived(role, id);
    }
  }

  Future<LongTermRelationId?> _findRelationForPair(
    IntentionId sourceId,
    IntentionId relatedId,
  ) async {
    final row = await _database
        .customSelect(
          '''
            SELECT id
            FROM long_term_relations
            WHERE source_intention_id = ? AND related_intention_id = ?
          ''',
          variables: [
            Variable<String>(sourceId.toCanonicalString()),
            Variable<String>(relatedId.toCanonicalString()),
          ],
          readsFrom: {_database.longTermRelations},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return decodeStoredRelationId(requiredStoredString(row.data, 'id'));
  }
}

sealed class _CommittedLongTermRelationCommand
    implements _GraphWrite<LongTermRelationCommandSuccess> {
  const _CommittedLongTermRelationCommand();
}

/// Строка каталога намерения до и после изменения, подтверждаемого ревизией
/// команды.
typedef _IntentionCatalogChange = ({
  IntentionCatalogEntrySnapshot before,
  IntentionCatalogEntrySnapshot after,
});

final class _CommittedLongTermRelationsAddition
    extends _CommittedLongTermRelationCommand {
  _CommittedLongTermRelationsAddition({
    required Iterable<relation_domain.LongTermRelation> relations,
    required Map<IntentionId, RelationCounts> affectedCounts,
    required Iterable<_IntentionCatalogChange> kindChanges,
  }) : relations = List.unmodifiable(relations),
       affectedCounts = Map.unmodifiable(affectedCounts),
       kindChanges = List.unmodifiable(kindChanges);

  final List<relation_domain.LongTermRelation> relations;
  final Map<IntentionId, RelationCounts> affectedCounts;

  /// Кандидаты, ставшие вспомогательными вместе со своими связями.
  final List<_IntentionCatalogChange> kindChanges;

  @override
  bool get didMutate => true;

  @override
  LongTermRelationsAdded toSuccess(GraphRevision revision) =>
      LongTermRelationsAdded(
        relations: relations,
        changes: [
          for (final entry in affectedCounts.entries)
            IntentionRelationCountsChanged(
              revision: revision,
              intentionId: entry.key,
              counts: entry.value,
            ),
          for (final relation in relations)
            LongTermRelationCreatedChange(
              revision: revision,
              relation: relation,
            ),
          for (final change in kindChanges)
            IntentionCatalogUpdated(
              revision: revision,
              before: change.before,
              after: change.after,
            ),
          IntentionHoldingChanged(revision: revision),
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
                IntentionHoldingChanged(revision: revision),
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
  if (error is _CascadeCompositionConflict) {
    return const LongTermRelationCascadeConflictFailure();
  }
  if (error case _LongTermRelationPairOccupied(:final relationId)) {
    return LongTermRelationPairOccupiedFailure(relationId);
  }
  if (error case _LongTermRelationArchivedTypeChange(:final relationId)) {
    return LongTermRelationArchivedTypeChangeFailure(relationId);
  }
  if (error case _LongTermRelationNotFound(:final relationId)) {
    return LongTermRelationNotFoundFailure(relationId);
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
  if (error is StoredGraphCorruption) {
    return const LongTermRelationCorruptionFailure();
  }

  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const LongTermRelationCorruptionFailure(),
    SqliteUnavailableFailure() => const LongTermRelationUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const LongTermRelationUnexpectedFailure(),
  };
}

LongTermRelationCommandDiagnosticsType _longTermRelationCommandDiagnosticsType(
  LongTermRelationCommand command,
) => switch (command) {
  AddLongTermRelations() => LongTermRelationCommandDiagnosticsType.create,
  UpdateLongTermRelation() => LongTermRelationCommandDiagnosticsType.update,
  ArchiveLongTermRelation() => LongTermRelationCommandDiagnosticsType.archive,
  RestoreLongTermRelation() => LongTermRelationCommandDiagnosticsType.restore,
  DeleteLongTermRelation() => LongTermRelationCommandDiagnosticsType.delete,
};

DiagnosticsFailureCode _graphCommandDiagnosticsFailureCode(
  GraphCommandFailure failure,
) => switch (failure.category) {
  _ when failure is LongTermRelationCascadeConflictFailure =>
    DiagnosticsFailureCode.cascadeConflict,
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

final class _LongTermRelationArchivedTypeChange implements Exception {
  const _LongTermRelationArchivedTypeChange(this.relationId);

  final LongTermRelationId relationId;
}

final class _LongTermRelationNotFound implements Exception {
  const _LongTermRelationNotFound(this.relationId);

  final LongTermRelationId relationId;
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
