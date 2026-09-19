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
          },
        );
        _mutationSequence++;
        final revision = _currentRevision;
        final value = committed.toSuccess(revision);
        final result = ConfirmedGraphResult(revision: revision, value: value);
        _notifyIntentionWatchersFor(value.changes);
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
    await _requireActiveRelationParticipant(
      command.sourceIntentionId,
      RelationParticipantRole.source,
    );
    await _requireActiveRelationParticipant(
      command.relatedIntentionId,
      RelationParticipantRole.related,
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

  Future<void> _requireActiveRelationParticipant(
    IntentionId id,
    RelationParticipantRole role,
  ) async {
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
    if (archivedValue == 1) {
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
    final serializedId = row.data['id'];
    if (serializedId is! String) throw const _StoredIntentionCorruption();
    return switch (LongTermRelationId.decode(serializedId)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() =>
        throw const _StoredIntentionCorruption(),
    };
  }
}

final class _CommittedLongTermRelationCreation {
  _CommittedLongTermRelationCreation({
    required this.relation,
    required this.description,
    required Map<IntentionId, RelationCounts> affectedCounts,
  }) : affectedCounts = Map.unmodifiable(affectedCounts);

  final relation_domain.LongTermRelation relation;
  final LongTermRelationDescription? description;
  final Map<IntentionId, RelationCounts> affectedCounts;

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

LongTermRelationCommandFailure _classifyLongTermRelationCommandFailure(
  Object error,
) {
  if (error case _LongTermRelationPairOccupied(:final relationId)) {
    return LongTermRelationPairOccupiedFailure(relationId);
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
