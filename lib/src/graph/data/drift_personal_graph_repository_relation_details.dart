part of 'drift_personal_graph_repository.dart';

extension _LongTermRelationDetailsReading on DriftPersonalGraphRepository {
  Stream<LongTermRelationReadResult> _watchRelation(
    LongTermRelationId id,
  ) async* {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const LongTermRelationDetailReadDiagnosticsEvent(
        status: DiagnosticsStarted(),
      ),
    );
    final registration = _RelationWatchRegistration(id);
    _relationWatchers.putIfAbsent(id, () => {}).add(registration);

    try {
      final initial = await _readCurrentRelationSnapshot(registration);
      var lastRevision = initial.revision;
      _recordRelationReadSuccess(stopwatch.elapsed);
      yield LongTermRelationReadSuccess(initial);

      await for (final _ in registration.invalidations.stream) {
        final snapshot = await _readCurrentRelationSnapshot(registration);
        if (lastRevision.compareTo(snapshot.revision) ==
            GraphRevisionOrder.same) {
          continue;
        }
        lastRevision = snapshot.revision;
        _recordRelationReadSuccess(stopwatch.elapsed);
        yield LongTermRelationReadSuccess(snapshot);
      }
    } on Object catch (error) {
      final failure = _classifyLongTermRelationReadFailure(error);
      _recordDiagnostics(
        LongTermRelationDetailReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _longTermRelationReadDiagnosticsFailureCode(failure),
          ),
        ),
      );
      yield LongTermRelationReadError(failure);
    } finally {
      final registrations = _relationWatchers[id];
      registrations?.remove(registration);
      if (registrations?.isEmpty ?? false) {
        _relationWatchers.remove(id);
      }
      unawaited(registration.invalidations.close());
    }
  }

  Future<GraphSnapshot<LongTermRelationDetails?>> _readCurrentRelationSnapshot(
    _RelationWatchRegistration registration,
  ) async {
    while (true) {
      final snapshot = await _readRelationSnapshot(registration);
      if (snapshot.revision.compareTo(_currentRevision) !=
          GraphRevisionOrder.older) {
        return snapshot;
      }
    }
  }

  Future<GraphSnapshot<LongTermRelationDetails?>> _readRelationSnapshot(
    _RelationWatchRegistration registration,
  ) => _sequencer.run(
    () => _database.transaction(() async {
      final rawRow = await _database
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
            variables: [Variable<String>(registration.id.toCanonicalString())],
            readsFrom: {_database.longTermRelations},
          )
          .getSingleOrNull();
      if (rawRow == null) {
        registration.participantIds = const {};
        return GraphSnapshot(value: null, revision: _currentRevision);
      }

      final stored = StoredLongTermRelation.decode(rawRow.data);
      final relation = stored.toDomain();
      if (relation.id != registration.id) {
        throw const StoredGraphCorruption();
      }
      final participantIds = {
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      };
      final participants = await _readRelationParticipants(
        participantIds,
        knownActiveCounts: const {},
      );
      registration.participantIds = Set.unmodifiable(participantIds);
      return GraphSnapshot(
        value: LongTermRelationDetails(
          relation: relation,
          source:
              participants[relation.sourceIntentionId] ??
              (throw const StoredGraphCorruption()),
          related:
              participants[relation.relatedIntentionId] ??
              (throw const StoredGraphCorruption()),
          description: stored.description,
          permissions: await _readRelationPermissions(relation.id),
        ),
        revision: _currentRevision,
      );
    }),
  );

  void _recordRelationReadSuccess(Duration duration) {
    _recordDiagnostics(
      LongTermRelationDetailReadDiagnosticsEvent(
        status: DiagnosticsSucceeded(duration),
      ),
    );
  }

  void _notifyRelationWatchersFor(Iterable<GraphChange> changes) {
    final affectedRelationIds = <LongTermRelationId>{};
    final affectedIntentionIds = <IntentionId>{};
    for (final change in changes) {
      switch (change) {
        case IntentionCatalogMutation(:final before, :final after):
          final beforeId = before?.summary.id;
          final afterId = after?.summary.id;
          if (beforeId != null) affectedIntentionIds.add(beforeId);
          if (afterId != null) affectedIntentionIds.add(afterId);
        case LongTermRelationChange(:final id):
          affectedRelationIds.add(id);
        case DailyChoiceChange(
          :final releasedRelationIds,
          :final occupiedRelationIds,
        ):
          affectedRelationIds
            ..addAll(releasedRelationIds)
            ..addAll(occupiedRelationIds);
        case GraphChange():
          break;
      }
    }

    for (final entry in List.of(_relationWatchers.entries)) {
      for (final registration in List.of(entry.value)) {
        if (affectedRelationIds.contains(registration.id) ||
            registration.participantIds.any(affectedIntentionIds.contains)) {
          registration.invalidations.add(null);
        }
      }
    }
  }
}

final class _RelationWatchRegistration {
  _RelationWatchRegistration(this.id);

  final LongTermRelationId id;
  final StreamController<void> invalidations = StreamController<void>();
  Set<IntentionId> participantIds = const {};
}

LongTermRelationReadFailure _classifyLongTermRelationReadFailure(Object error) {
  if (error is StoredGraphCorruption) {
    return const LongTermRelationReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const LongTermRelationReadCorruptionFailure(),
    SqliteUnavailableFailure() =>
      const LongTermRelationReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const LongTermRelationReadUnexpectedFailure(),
  };
}

DiagnosticsFailureCode _longTermRelationReadDiagnosticsFailureCode(
  LongTermRelationReadFailure failure,
) => switch (failure.category) {
  GraphFailureCategory.validation => DiagnosticsFailureCode.validation,
  GraphFailureCategory.notFound => DiagnosticsFailureCode.notFound,
  GraphFailureCategory.conflict => DiagnosticsFailureCode.conflict,
  GraphFailureCategory.unavailable => DiagnosticsFailureCode.unavailable,
  GraphFailureCategory.corruption => DiagnosticsFailureCode.corruption,
  GraphFailureCategory.unexpected => DiagnosticsFailureCode.unexpected,
};
