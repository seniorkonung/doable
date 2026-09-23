part of 'drift_personal_graph_repository.dart';

extension _SelectedRelationsReading on DriftPersonalGraphRepository {
  Future<SelectedRelationsReadResult> _readSelectedRelations(
    SelectedRelationsQuery query, {
    _SelectedRelationsWatchRegistration? registration,
  }) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const SelectedRelationsReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(
          () => _readSelectedRelationsSnapshot(query, registration),
        ),
      );
      _recordDiagnostics(
        SelectedRelationsReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return SelectedRelationsReadSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifySelectedRelationsReadFailure(error);
      _recordDiagnostics(
        SelectedRelationsReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _selectedRelationsReadDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return SelectedRelationsReadError(failure);
    }
  }

  Future<GraphSnapshot<SelectedRelationsSnapshot>>
  _readSelectedRelationsSnapshot(
    SelectedRelationsQuery query,
    _SelectedRelationsWatchRegistration? registration,
  ) async {
    final selected = <LongTermRelationId, _StoredRelationGroupRow>{};
    final ids = query.relationIds.toList(growable: false);
    const batchSize = 400;
    for (var start = 0; start < ids.length; start += batchSize) {
      final end = start + batchSize < ids.length
          ? start + batchSize
          : ids.length;
      final batch = ids.sublist(start, end);
      final placeholders = List.filled(batch.length, '?').join(', ');
      final rows = await _database
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
              WHERE id IN ($placeholders)
            ''',
            variables: [
              for (final id in batch) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.longTermRelations},
          )
          .get();
      for (final rawRow in rows) {
        final row = _StoredRelationGroupRow.fromRawRow(rawRow);
        if (!query.relationIds.contains(row.id) ||
            selected.containsKey(row.id)) {
          throw const _StoredIntentionCorruption();
        }
        selected[row.id] = row;
      }
    }

    final present = <LongTermRelationId, _StoredRelationGroupRow>{};
    final participantIds = <IntentionId>{};
    for (final entry in selected.entries) {
      final relation = entry.value.toDomain();
      participantIds
        ..add(relation.sourceIntentionId)
        ..add(relation.relatedIntentionId);
      if (relation.sourceIntentionId == query.intentionId ||
          relation.relatedIntentionId == query.intentionId) {
        present[entry.key] = entry.value;
      }
    }
    final participants = await _readRelationParticipants(
      participantIds,
      knownActiveCounts: const {},
    );
    final permissions = <LongTermRelationId, LongTermRelationPermissions>{};
    const permissionBatchSize = 400;
    final presentIds = present.keys.toList(growable: false);
    for (
      var start = 0;
      start < presentIds.length;
      start += permissionBatchSize
    ) {
      final end = start + permissionBatchSize < presentIds.length
          ? start + permissionBatchSize
          : presentIds.length;
      permissions.addAll(
        await _relationCountAggregates.readPermissions(
          presentIds.sublist(start, end),
        ),
      );
    }
    final entries = <LongTermRelationId, SelectedRelationEntry>{};
    for (final id in query.relationIds) {
      final row = present[id];
      if (row == null) {
        entries[id] = selected.containsKey(id)
            ? SelectedRelationNoLongerBlocking(id)
            : SelectedRelationMissing(id);
        continue;
      }
      final relation = row.toDomain();
      entries[id] = SelectedRelationPresent(
        LongTermRelationDetails(
          relation: relation,
          source:
              participants[relation.sourceIntentionId] ??
              (throw const _StoredIntentionCorruption()),
          related:
              participants[relation.relatedIntentionId] ??
              (throw const _StoredIntentionCorruption()),
          description: row.description,
          permissions:
              permissions[id] ?? (throw const _StoredIntentionCorruption()),
        ),
      );
    }
    registration?.participantIds = Set.unmodifiable(participantIds);
    return GraphSnapshot(
      value: SelectedRelationsSnapshot(query: query, entries: entries),
      revision: _currentRevision,
    );
  }

  Stream<SelectedRelationsReadResult> _watchSelectedRelations(
    SelectedRelationsQuery query,
  ) async* {
    final registration = _SelectedRelationsWatchRegistration(query.relationIds);
    _selectedRelationsWatchers.add(registration);
    GraphRevision? lastSuccessfulRevision;
    try {
      var result = await _readSelectedRelations(
        query,
        registration: registration,
      );
      if (result case SelectedRelationsReadSuccess(:final value)) {
        lastSuccessfulRevision = value.revision;
      }
      yield result;

      await for (final _ in registration.invalidations.stream) {
        if (lastSuccessfulRevision?.compareTo(_currentRevision)
            case GraphRevisionOrder.same) {
          continue;
        }
        result = await _readSelectedRelations(
          query,
          registration: registration,
        );
        if (result case SelectedRelationsReadSuccess(:final value)) {
          if (lastSuccessfulRevision?.compareTo(value.revision)
              case GraphRevisionOrder.same || GraphRevisionOrder.newer) {
            continue;
          }
          lastSuccessfulRevision = value.revision;
        }
        yield result;
      }
    } finally {
      _selectedRelationsWatchers.remove(registration);
      unawaited(registration.invalidations.close());
    }
  }

  void _notifySelectedRelationsWatchersFor(Iterable<GraphChange> changes) {
    final affectedRelations = <LongTermRelationId>{};
    final affectedParticipants = <IntentionId>{};
    for (final change in changes) {
      switch (change) {
        case IntentionRelationCountsChanged(:final intentionId):
          affectedParticipants.add(intentionId);
        case IntentionCatalogMutation(:final before, :final after):
          final beforeId = before?.summary.id;
          final afterId = after?.summary.id;
          if (beforeId != null) affectedParticipants.add(beforeId);
          if (afterId != null) affectedParticipants.add(afterId);
        case LongTermRelationChange(:final id):
          affectedRelations.add(id);
        case GraphChange():
          break;
      }
    }
    for (final registration in List.of(_selectedRelationsWatchers)) {
      if (registration.relationIds.any(affectedRelations.contains) ||
          registration.participantIds.any(affectedParticipants.contains)) {
        registration.invalidations.add(null);
      }
    }
  }
}

final class _SelectedRelationsWatchRegistration {
  _SelectedRelationsWatchRegistration(this.relationIds);

  final Set<LongTermRelationId> relationIds;
  final StreamController<void> invalidations = StreamController<void>();
  Set<IntentionId> participantIds = const {};
}

SelectedRelationsReadFailure _classifySelectedRelationsReadFailure(
  Object error,
) {
  if (error is _StoredIntentionCorruption) {
    return const SelectedRelationsReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const SelectedRelationsReadCorruptionFailure(),
    SqliteUnavailableFailure() =>
      const SelectedRelationsReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const SelectedRelationsReadUnexpectedFailure(),
  };
}

DiagnosticsFailureCode _selectedRelationsReadDiagnosticsFailureCode(
  SelectedRelationsReadFailure failure,
) => switch (failure.category) {
  GraphFailureCategory.validation => DiagnosticsFailureCode.validation,
  GraphFailureCategory.notFound => DiagnosticsFailureCode.notFound,
  GraphFailureCategory.conflict => DiagnosticsFailureCode.conflict,
  GraphFailureCategory.unavailable => DiagnosticsFailureCode.unavailable,
  GraphFailureCategory.corruption => DiagnosticsFailureCode.corruption,
  GraphFailureCategory.unexpected => DiagnosticsFailureCode.unexpected,
};
