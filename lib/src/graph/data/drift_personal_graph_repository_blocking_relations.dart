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
    final selectedChoices = <DailyChoiceDetails>[];
    final affected = <IntentionId>{owner};
    for (final reference in command.references) {
      switch (reference) {
        case LongTermBlockingRelationReference(:final id):
          final stored = await _readStoredRelation(id);
          if (stored == null) {
            throw DeleteBlockingRelationsSelectionConflictFailure(
              reference: reference,
              reason: BlockingRelationConflictReason.relationMissing,
            );
          }
          final relation = stored.toDomain();
          if (relation.sourceIntentionId != owner &&
              relation.relatedIntentionId != owner) {
            throw DeleteBlockingRelationsSelectionConflictFailure(
              reference: reference,
              reason: BlockingRelationConflictReason.noLongerBlocking,
            );
          }
          selected.add(relation);
          affected.add(relation.sourceIntentionId);
          affected.add(relation.relatedIntentionId);
        case DailyChoiceBlockingRelationReference(:final id):
          final details = await _readVerifiedDailyChoice(id);
          if (details == null) {
            throw DeleteBlockingRelationsSelectionConflictFailure(
              reference: reference,
              reason: BlockingRelationConflictReason.relationMissing,
            );
          }
          final choice = details.choice;
          if (choice.sourceIntentionId != owner &&
              choice.selectedIntentionId != owner) {
            throw DeleteBlockingRelationsSelectionConflictFailure(
              reference: reference,
              reason: BlockingRelationConflictReason.noLongerBlocking,
            );
          }
          selectedChoices.add(details);
          affected.add(choice.sourceIntentionId);
          affected.add(choice.selectedIntentionId);
      }
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
          throw DeleteBlockingRelationsSelectionConflictFailure.longTerm(
            relationId: relation.id,
            reason: BlockingRelationConflictReason.deletionProhibited,
          );
        }
      }
    }

    // Все зависимости проверены до первой записи, включая шаги выбранных выборов.
    for (final details in selectedChoices) {
      final deletedRows =
          await (_database.delete(_database.dailyChoices)..where(
                (row) => row.id.equals(details.choice.id.toCanonicalString()),
              ))
              .go();
      if (deletedRows != 1) throw const _StoredIntentionCorruption();
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

    for (final details in selectedChoices) {
      final remaining = await _database
          .customSelect(
            '''SELECT COUNT(*) AS remaining_steps FROM daily_choice_path_steps
           WHERE daily_choice_id = ?''',
            variables: [
              Variable<String>(details.choice.id.toCanonicalString()),
            ],
            readsFrom: {_database.dailyChoicePathSteps},
          )
          .getSingle();
      if (remaining.read<int>('remaining_steps') != 0 ||
          await _readVerifiedDailyChoice(details.choice.id) != null) {
        throw const _StoredIntentionCorruption();
      }
    }

    final releasedIds = <LongTermRelationId>{
      for (final details in selectedChoices)
        for (final step in details.path) step.relation.id,
    };
    final releasedPermissions =
        <LongTermRelationId, LongTermRelationPermissions>{};
    final orderedReleased = releasedIds.toList();
    for (var start = 0; start < orderedReleased.length; start += batchSize) {
      releasedPermissions.addAll(
        await _relationCountAggregates.readPermissions(
          orderedReleased.skip(start).take(batchSize),
        ),
      );
    }
    if (releasedPermissions.length != releasedIds.length) {
      throw const _StoredIntentionCorruption();
    }

    return _SelectedBlockingRelationsDeletion(
      relations: selected,
      choices: selectedChoices,
      permissions: releasedPermissions,
      counts: await _readVerifiedRelationCountsFor(affected),
    );
  }
}

final class _SelectedBlockingRelationsDeletion {
  _SelectedBlockingRelationsDeletion({
    required List<relation_domain.LongTermRelation> relations,
    required List<DailyChoiceDetails> choices,
    required Map<LongTermRelationId, LongTermRelationPermissions> permissions,
    required Map<IntentionId, RelationCounts> counts,
  }) : relations = List.unmodifiable(relations),
       choices = List.unmodifiable(choices),
       permissions = Map.unmodifiable(permissions),
       counts = Map.unmodifiable(counts);

  final List<relation_domain.LongTermRelation> relations;
  final List<DailyChoiceDetails> choices;
  final Map<LongTermRelationId, LongTermRelationPermissions> permissions;
  final Map<IntentionId, RelationCounts> counts;

  BlockingRelationsDeleted toSuccess(
    DeleteBlockingRelations command,
    GraphRevision revision,
  ) => BlockingRelationsDeleted(
    command: command,
    revision: revision,
    deletedRelations: relations,
    deletedChoiceChanges: [
      for (final details in choices)
        DailyChoiceChange(
          revision: revision,
          before: details.choice,
          after: null,
          releasedRelationIds: details.path.map((step) => step.relation.id),
          occupiedRelationIds: const [],
          intentionCounts: counts,
          relationPermissions: permissions,
        ),
    ],
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
