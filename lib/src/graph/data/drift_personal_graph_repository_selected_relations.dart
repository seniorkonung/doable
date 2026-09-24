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

    final selectedChoices = <DailyChoiceId, DailyChoiceCatalogItem>{};
    final choiceIds = query.dailyChoiceIds.toList(growable: false);
    for (var start = 0; start < choiceIds.length; start += batchSize) {
      final batch = choiceIds
          .skip(start)
          .take(batchSize)
          .toList(growable: false);
      final rows = await _database
          .customSelect(
            '''SELECT creation_sequence, id, source_intention_id,
                  selected_intention_id, choice_date, description, is_completed
               FROM daily_choices
               WHERE id IN (${List.filled(batch.length, '?').join(', ')})''',
            variables: [
              for (final id in batch) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.dailyChoices},
          )
          .get();
      final choices = <DailyChoice>[];
      for (final row in rows) {
        final id = switch (DailyChoiceId.decode(
          _requiredStoredString(row.data, 'id'),
        )) {
          DailyChoiceIdDecodingSuccess(:final id) => id,
          InvalidDailyChoiceIdDecoding() =>
            throw const _StoredIntentionCorruption(),
        };
        if (!query.dailyChoiceIds.contains(id) ||
            selectedChoices.containsKey(id)) {
          throw const _StoredIntentionCorruption();
        }
        choices.add(_decodeStoredDailyChoice(row, id));
      }
      for (final item in await _verifyDailyChoiceCatalogItems(choices)) {
        if (selectedChoices.containsKey(item.id)) {
          throw const _StoredIntentionCorruption();
        }
        selectedChoices[item.id] = item;
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
    for (final item in selectedChoices.values) {
      if (item.source.id == query.intentionId ||
          item.selected.id == query.intentionId) {
        participantIds
          ..add(item.source.id)
          ..add(item.selected.id);
      }
    }
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
    final entries = <BlockingRelationReference, SelectedRelationEntry>{};
    for (final reference in query.references) {
      switch (reference) {
        case LongTermBlockingRelationReference(:final id):
          final row = present[id];
          if (row == null) {
            entries[reference] = selected.containsKey(id)
                ? SelectedRelationNoLongerBlocking(id)
                : SelectedRelationMissing(id);
            continue;
          }
          final relation = row.toDomain();
          entries[reference] = SelectedRelationPresent(
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
        case DailyChoiceBlockingRelationReference(:final id):
          final item = selectedChoices[id];
          entries[reference] = item == null
              ? SelectedDailyChoiceMissing(id)
              : item.source.id == query.intentionId ||
                    item.selected.id == query.intentionId
              ? SelectedDailyChoicePresent(item)
              : SelectedDailyChoiceNoLongerBlocking(id);
      }
    }
    registration?.participantIds = Set.unmodifiable(participantIds);
    return GraphSnapshot(
      value: SelectedRelationsSnapshot.mixed(
        query: query,
        entriesByReference: entries,
      ),
      revision: _currentRevision,
    );
  }

  Stream<SelectedRelationsReadResult> _watchSelectedRelations(
    SelectedRelationsQuery query,
  ) async* {
    final registration = _SelectedRelationsWatchRegistration(
      query.relationIds,
      query.dailyChoiceIds,
    );
    _selectedRelationsWatchers.add(registration);
    GraphRevision? lastSuccessfulRevision;
    try {
      var result = await _readCurrentSelectedRelations(
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
        result = await _readCurrentSelectedRelations(
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

  Future<SelectedRelationsReadResult> _readCurrentSelectedRelations(
    SelectedRelationsQuery query, {
    required _SelectedRelationsWatchRegistration registration,
  }) async {
    while (true) {
      final result = await _readSelectedRelations(
        query,
        registration: registration,
      );
      if (result is! SelectedRelationsReadSuccess ||
          result.value.revision.compareTo(_currentRevision) !=
              GraphRevisionOrder.older) {
        return result;
      }
    }
  }

  void _notifySelectedRelationsWatchersFor(Iterable<GraphChange> changes) {
    final affectedRelations = <LongTermRelationId>{};
    final affectedChoices = <DailyChoiceId>{};
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
        case DailyChoiceChange(
          :final before,
          :final after,
          :final releasedRelationIds,
          :final occupiedRelationIds,
        ):
          affectedChoices.add((after ?? before)!.id);
          affectedRelations
            ..addAll(releasedRelationIds)
            ..addAll(occupiedRelationIds);
        case GraphChange():
          break;
      }
    }
    for (final registration in List.of(_selectedRelationsWatchers)) {
      if (registration.relationIds.any(affectedRelations.contains) ||
          registration.dailyChoiceIds.any(affectedChoices.contains) ||
          registration.participantIds.any(affectedParticipants.contains)) {
        registration.invalidations.add(null);
      }
    }
  }
}

final class _SelectedRelationsWatchRegistration {
  _SelectedRelationsWatchRegistration(this.relationIds, this.dailyChoiceIds);

  final Set<LongTermRelationId> relationIds;
  final Set<DailyChoiceId> dailyChoiceIds;
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
