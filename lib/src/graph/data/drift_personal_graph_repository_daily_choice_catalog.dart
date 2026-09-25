part of 'drift_personal_graph_repository.dart';

extension _DailyChoiceCatalogReading on DriftPersonalGraphRepository {
  Future<DailyChoiceCatalogPageResult> _readDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    final isContinuation = query.cursor != null;
    _recordDiagnostics(
      DailyChoiceCatalogPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        isContinuation: isContinuation,
        status: const DiagnosticsStarted(),
      ),
    );
    try {
      final page = await _sequencer.run(
        () => _database.transaction(
          () => _readDailyChoiceCatalogPageOnSnapshot(query),
        ),
      );
      _recordDiagnostics(
        DailyChoiceCatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          isContinuation: isContinuation,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return DailyChoiceCatalogPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyDailyChoiceCatalogFailure(error);
      _recordDiagnostics(
        DailyChoiceCatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          isContinuation: isContinuation,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return DailyChoiceCatalogPageError(failure);
    }
  }

  Future<DailyChoiceCatalogPage> _readDailyChoiceCatalogPageOnSnapshot(
    DailyChoiceCatalogQuery query,
  ) async {
    final cursor = query.cursor;
    if (cursor != null &&
        (cursor is! _DriftDailyChoiceCatalogCursor ||
            !cursor.matches(query, _epoch))) {
      throw const _InvalidDailyChoiceCatalogCursor();
    }
    if (cursor is _DriftDailyChoiceCatalogCursor &&
        cursor.revision.compareTo(_currentRevision) !=
            GraphRevisionOrder.same) {
      throw const _DailyChoiceCatalogSnapshotHasExpired();
    }

    final filters = <String>[];
    final variables = <Variable>[];
    if (query.date case final date?) {
      filters.add('choice_date = ?');
      variables.add(Variable<String>(date.toCanonicalString()));
    }
    if (query.isCompleted case final completed?) {
      filters.add('is_completed = ?');
      variables.add(Variable<int>(completed ? 1 : 0));
    }
    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final totalCount = cursor is! _DriftDailyChoiceCatalogCursor
        ? _requiredStoredInteger(
            (await _database
                    .customSelect(
                      'SELECT COUNT(*) AS total_count FROM daily_choices $where',
                      variables: variables,
                      readsFrom: {_database.dailyChoices},
                    )
                    .getSingle())
                .data,
            'total_count',
          )
        : cursor.expectedCount;

    final pageFilters = [...filters];
    final pageVariables = [...variables];
    if (cursor is _DriftDailyChoiceCatalogCursor) {
      pageFilters.add('''(choice_date < ? OR
        (choice_date = ? AND creation_sequence < ?))''');
      pageVariables.addAll([
        Variable<String>(cursor.boundaryDate),
        Variable<String>(cursor.boundaryDate),
        Variable<int>(cursor.boundarySequence),
      ]);
    }
    final pageWhere = pageFilters.isEmpty
        ? ''
        : 'WHERE ${pageFilters.join(' AND ')}';
    final rawRows = await _database
        .customSelect(
          '''SELECT creation_sequence, id, source_intention_id,
                selected_intention_id, choice_date, description, is_completed
         FROM daily_choices $pageWhere
         ORDER BY choice_date DESC, creation_sequence DESC LIMIT ?''',
          variables: [...pageVariables, Variable<int>(query.pageSize + 1)],
          readsFrom: {_database.dailyChoices},
        )
        .get();
    final hasNext = rawRows.length > query.pageSize;
    final selectedRows = rawRows.take(query.pageSize).toList();
    final choices = [
      for (final row in selectedRows)
        _decodeStoredDailyChoice(row, switch (DailyChoiceId.decode(
          _requiredStoredString(row.data, 'id'),
        )) {
          DailyChoiceIdDecodingSuccess(:final id) => id,
          InvalidDailyChoiceIdDecoding() =>
            throw const _StoredIntentionCorruption(),
        }),
    ];
    final items = await _verifyDailyChoiceCatalogItems(choices);
    final returnedCount =
        (cursor is _DriftDailyChoiceCatalogCursor ? cursor.returnedCount : 0) +
        items.length;
    if (hasNext ? returnedCount >= totalCount : returnedCount != totalCount) {
      throw const _StoredIntentionCorruption();
    }
    final revision = _currentRevision;
    final nextCursor = hasNext
        ? _DriftDailyChoiceCatalogCursor(
            epoch: _epoch,
            revision: revision,
            date: query.date,
            isCompleted: query.isCompleted,
            pageSize: query.pageSize,
            boundaryDate: _requiredStoredString(
              selectedRows.last.data,
              'choice_date',
            ),
            boundarySequence: _requiredStoredInteger(
              selectedRows.last.data,
              'creation_sequence',
            ),
            expectedCount: totalCount,
            returnedCount: returnedCount,
          )
        : null;
    return cursor == null
        ? DailyChoiceCatalogFirstPage(
            items: items,
            totalCount: totalCount,
            nextCursor: nextCursor,
            revision: revision,
          )
        : DailyChoiceCatalogContinuationPage(
            items: items,
            nextCursor: nextCursor,
            revision: revision,
          );
  }

  Future<List<DailyChoiceCatalogItem>> _verifyDailyChoiceCatalogItems(
    List<DailyChoice> choices,
  ) async {
    if (choices.isEmpty) return const [];
    final choiceIds = [
      for (final choice in choices) choice.id.toCanonicalString(),
    ];
    final selectedChoiceIds = choices.map((choice) => choice.id).toSet();
    final stepRows = await _database
        .customSelect(
          '''SELECT id, daily_choice_id, long_term_relation_id, previous_step_id
         FROM daily_choice_path_steps
         WHERE daily_choice_id IN (${List.filled(choiceIds.length, '?').join(',')})''',
          variables: [for (final id in choiceIds) Variable<String>(id)],
          readsFrom: {_database.dailyChoicePathSteps},
        )
        .get();
    final stepsByChoice = <DailyChoiceId, List<ChoicePathStep>>{};
    final relationIds = <LongTermRelationId>{};
    for (final row in stepRows) {
      final step = _decodeStoredChoiceStep(row);
      if (!selectedChoiceIds.contains(step.dailyChoiceId)) {
        throw const _StoredIntentionCorruption();
      }
      stepsByChoice.putIfAbsent(step.dailyChoiceId, () => []).add(step);
      relationIds.add(step.relationId);
    }
    final relations =
        <LongTermRelationId, ({IntentionId source, IntentionId related})>{};
    final orderedRelationIds = relationIds.toList();
    for (var start = 0; start < orderedRelationIds.length; start += 400) {
      final batch = orderedRelationIds.skip(start).take(400).toList();
      final rows = await _database
          .customSelect(
            '''SELECT id, source_intention_id, related_intention_id
           FROM long_term_relations
           WHERE id IN (${List.filled(batch.length, '?').join(',')})''',
            variables: [
              for (final id in batch) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.longTermRelations},
          )
          .get();
      for (final row in rows) {
        final data = row.data;
        final id = _decodeStoredRelationId(_requiredStoredString(data, 'id'));
        if (!relationIds.contains(id) || relations.containsKey(id)) {
          throw const _StoredIntentionCorruption();
        }
        relations[id] = (
          source: _decodeStoredRelationIntentionId(
            _requiredStoredString(data, 'source_intention_id'),
          ),
          related: _decodeStoredRelationIntentionId(
            _requiredStoredString(data, 'related_intention_id'),
          ),
        );
      }
    }
    if (relations.length != relationIds.length) {
      throw const _StoredIntentionCorruption();
    }

    final participantIds = <IntentionId>{
      for (final choice in choices) ...[
        choice.sourceIntentionId,
        choice.selectedIntentionId,
      ],
    };
    final allIntentionIds = <IntentionId>{
      ...participantIds,
      for (final relation in relations.values) ...[
        relation.source,
        relation.related,
      ],
    };
    final foundIds = <IntentionId>{};
    final participants = <IntentionId, DailyChoiceCatalogParticipant>{};
    final orderedIds = participantIds.toList();
    for (var start = 0; start < orderedIds.length; start += 400) {
      final batch = orderedIds.skip(start).take(400).toList();
      final rows = await _database
          .customSelect(
            '''SELECT id, title, is_action_ready, is_archived
           FROM intentions
           WHERE id IN (${List.filled(batch.length, '?').join(',')})''',
            variables: [
              for (final id in batch) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.intentions},
          )
          .get();
      for (final row in rows) {
        final data = row.data;
        final id = _decodeStoredRelationIntentionId(
          _requiredStoredString(data, 'id'),
        );
        if (!participantIds.contains(id) || !foundIds.add(id)) {
          throw const _StoredIntentionCorruption();
        }
        final title = _requiredStoredString(data, 'title');
        final readiness = switch (_requiredStoredInteger(
          data,
          'is_action_ready',
        )) {
          0 => domain.IntentionReadiness.notReady,
          1 => domain.IntentionReadiness.ready,
          _ => throw const _StoredIntentionCorruption(),
        };
        final archiveState = switch (_requiredStoredInteger(
          data,
          'is_archived',
        )) {
          0 => domain.IntentionArchiveState.active,
          1 => domain.IntentionArchiveState.archived,
          _ => throw const _StoredIntentionCorruption(),
        };
        try {
          final participant = DailyChoiceCatalogParticipant(
            id: id,
            title: title,
            readiness: readiness,
            archiveState: archiveState,
          );
          if (participant.title != title) {
            throw const _StoredIntentionCorruption();
          }
          participants[id] = participant;
        } on IntentionTextValidationException {
          throw const _StoredIntentionCorruption();
        }
      }
    }
    final intermediateIds = allIntentionIds.difference(participantIds);
    final orderedIntermediateIds = intermediateIds.toList();
    for (var start = 0; start < orderedIntermediateIds.length; start += 400) {
      final batch = orderedIntermediateIds.skip(start).take(400).toList();
      final rows = await _database
          .customSelect(
            '''SELECT id FROM intentions
           WHERE id IN (${List.filled(batch.length, '?').join(',')})''',
            variables: [
              for (final id in batch) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.intentions},
          )
          .get();
      for (final row in rows) {
        final id = _decodeStoredRelationIntentionId(
          _requiredStoredString(row.data, 'id'),
        );
        if (!intermediateIds.contains(id) || !foundIds.add(id)) {
          throw const _StoredIntentionCorruption();
        }
      }
    }
    if (foundIds.length != allIntentionIds.length) {
      throw const _StoredIntentionCorruption();
    }
    return List.unmodifiable([
      for (final choice in choices)
        _catalogItemFor(
          choice,
          stepsByChoice[choice.id] ?? const [],
          relations,
          foundIds,
          participants,
        ),
    ]);
  }
}

DailyChoiceCatalogItem _catalogItemFor(
  DailyChoice choice,
  List<ChoicePathStep> steps,
  Map<LongTermRelationId, ({IntentionId source, IntentionId related})>
  relations,
  Set<IntentionId> intentionIds,
  Map<IntentionId, DailyChoiceCatalogParticipant> participants,
) {
  _validateStoredChoicePathLinks(
    choice: choice,
    steps: steps,
    relations: relations,
    intentionIds: intentionIds,
  );
  return DailyChoiceCatalogItem(
    id: choice.id,
    source:
        participants[choice.sourceIntentionId] ??
        (throw const _StoredIntentionCorruption()),
    selected:
        participants[choice.selectedIntentionId] ??
        (throw const _StoredIntentionCorruption()),
    date: choice.date,
    isCompleted: choice.isCompleted,
  );
}

final class _DriftDailyChoiceCatalogCursor implements DailyChoiceCatalogCursor {
  const _DriftDailyChoiceCatalogCursor({
    required this.epoch,
    required this.revision,
    required this.date,
    required this.isCompleted,
    required this.pageSize,
    required this.boundaryDate,
    required this.boundarySequence,
    required this.expectedCount,
    required this.returnedCount,
  });

  final _GraphEpoch epoch;
  final GraphRevision revision;
  final CalendarDate? date;
  final bool? isCompleted;
  final int pageSize;
  final String boundaryDate;
  final int boundarySequence;
  final int expectedCount;
  final int returnedCount;

  bool matches(DailyChoiceCatalogQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) &&
      date == query.date &&
      isCompleted == query.isCompleted &&
      pageSize == query.pageSize;
}

final class _InvalidDailyChoiceCatalogCursor implements Exception {
  const _InvalidDailyChoiceCatalogCursor();
}

final class _DailyChoiceCatalogSnapshotHasExpired implements Exception {
  const _DailyChoiceCatalogSnapshotHasExpired();
}

DailyChoiceCatalogReadFailure _classifyDailyChoiceCatalogFailure(Object error) {
  if (error is _InvalidDailyChoiceCatalogCursor) {
    return const DailyChoiceCatalogValidationFailure();
  }
  if (error is _DailyChoiceCatalogSnapshotHasExpired) {
    return const DailyChoiceCatalogSnapshotExpired();
  }
  if (error is _StoredIntentionCorruption ||
      error is DailyChoiceCatalogPageValidationException) {
    return const DailyChoiceCatalogCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const DailyChoiceCatalogCorruptionFailure(),
    SqliteUnavailableFailure() => const DailyChoiceCatalogUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const DailyChoiceCatalogUnexpectedFailure(),
  };
}
