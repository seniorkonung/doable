part of 'drift_personal_graph_repository.dart';

extension _BlockingRelationsDeletion on DriftPersonalGraphRepository {
  Future<DeleteBlockingRelationsResult> _executeDeleteBlockingRelations(
    DeleteBlockingRelations command,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const BlockingRelationsDeleteDiagnosticsEvent(
        status: DiagnosticsStarted(),
      ),
    );
    try {
      final confirmed = await _sequencer.run(() async {
        final revision = _DriftGraphRevision(_epoch, _mutationSequence + 1);
        final value = await _database.transaction(() async {
          final deleted = await _deleteSelectedBlockingRelations(command);
          return deleted.toSuccess(command, revision);
        });
        _mutationSequence++;
        final result = ConfirmedGraphResult(revision: revision, value: value);
        _notifyGraphWatchersFor(value.changes);
        return result;
      });
      _recordDiagnostics(
        BlockingRelationsDeleteDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return GraphCommandSucceeded(confirmed);
    } on Object catch (error) {
      final failure = _classifyBlockingRelationsDeleteFailure(error);
      _recordDiagnostics(
        BlockingRelationsDeleteDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  Future<_SelectedBlockingRelationsDeletion> _deleteSelectedBlockingRelations(
    DeleteBlockingRelations command,
  ) async {
    final owner = command.intentionId;
    final exists = await _database
        .customSelect(
          'SELECT 1 FROM intentions WHERE id = ?',
          variables: [Variable<String>(owner.toCanonicalString())],
          readsFrom: {_database.intentions},
        )
        .getSingleOrNull();
    if (exists == null) {
      throw DeleteBlockingRelationsIntentionNotFoundFailure(owner);
    }

    final selected = <relation_domain.LongTermRelation>[];
    final affected = <IntentionId>{owner};
    for (final id in command.relationIds) {
      final stored = await _readStoredRelation(id);
      if (stored == null) {
        throw DeleteBlockingRelationsSelectionConflictFailure(
          relationId: id,
          reason: BlockingRelationConflictReason.relationMissing,
        );
      }
      final relation = stored.toDomain();
      if (relation.sourceIntentionId != owner &&
          relation.relatedIntentionId != owner) {
        throw DeleteBlockingRelationsSelectionConflictFailure(
          relationId: id,
          reason: BlockingRelationConflictReason.noLongerBlocking,
        );
      }
      selected.add(relation);
      affected.add(relation.sourceIntentionId);
      affected.add(relation.relatedIntentionId);
    }

    const batchSize = 400;
    for (var start = 0; start < selected.length; start += batchSize) {
      final end = start + batchSize < selected.length
          ? start + batchSize
          : selected.length;
      final batch = selected.sublist(start, end);
      final permissions = await _relationCountAggregates.readPermissions(
        batch.map((relation) => relation.id),
      );
      for (final relation in batch) {
        final permission = permissions[relation.id];
        if (permission == null) throw const _StoredIntentionCorruption();
        if (!permission.canDelete) {
          throw DeleteBlockingRelationsSelectionConflictFailure(
            relationId: relation.id,
            reason: BlockingRelationConflictReason.deletionProhibited,
          );
        }
      }
    }

    for (var start = 0; start < selected.length; start += batchSize) {
      final end = start + batchSize < selected.length
          ? start + batchSize
          : selected.length;
      final batch = selected.sublist(start, end);
      final placeholders = List.filled(batch.length, '?').join(', ');
      final deletedRows = await _database.customUpdate(
        'DELETE FROM long_term_relations WHERE id IN ($placeholders)',
        variables: [
          for (final relation in batch)
            Variable<String>(relation.id.toCanonicalString()),
        ],
        updates: {_database.longTermRelations},
      );
      if (deletedRows != batch.length) {
        throw StateError('Количество удалённых связей не совпало с выбором.');
      }
    }

    return _SelectedBlockingRelationsDeletion(
      relations: selected,
      counts: await _readVerifiedRelationCountsFor(affected),
    );
  }
}

final class _SelectedBlockingRelationsDeletion {
  _SelectedBlockingRelationsDeletion({
    required List<relation_domain.LongTermRelation> relations,
    required Map<IntentionId, RelationCounts> counts,
  }) : relations = List.unmodifiable(relations),
       counts = Map.unmodifiable(counts);

  final List<relation_domain.LongTermRelation> relations;
  final Map<IntentionId, RelationCounts> counts;

  BlockingRelationsDeleted toSuccess(
    DeleteBlockingRelations command,
    GraphRevision revision,
  ) => BlockingRelationsDeleted(
    command: command,
    revision: revision,
    deletedRelations: relations,
    counts: counts,
  );
}

DeleteBlockingRelationsFailure _classifyBlockingRelationsDeleteFailure(
  Object error,
) {
  if (error
      case final DeleteBlockingRelationsIntentionNotFoundFailure failure) {
    return failure;
  }
  if (error
      case final DeleteBlockingRelationsSelectionConflictFailure failure) {
    return failure;
  }
  if (error is _StoredIntentionCorruption) {
    return const DeleteBlockingRelationsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() =>
      const DeleteBlockingRelationsCorruptionFailure(),
    SqliteUnavailableFailure() =>
      const DeleteBlockingRelationsUnavailableFailure(),
    SqliteConstraintFailure() || SqliteUnexpectedFailure() =>
      const DeleteBlockingRelationsUnexpectedFailure(),
  };
}
