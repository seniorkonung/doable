part of 'drift_personal_graph_repository.dart';

extension _RelationGroupPageReading on DriftPersonalGraphRepository {
  Future<RelationGroupPageResult> _readRelationGroupPage(
    RelationGroupPageQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    final isContinuation = query.cursor != null;
    void record(DiagnosticsStatus status, {bool requiresNewSnapshot = false}) {
      _recordDiagnostics(switch (query) {
        DailyChoiceGroupQuery() => DailyChoiceGroupPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          isContinuation: isContinuation,
          requiresNewSnapshot: requiresNewSnapshot,
          status: status,
        ),
        RelationGroupQuery() => RelationGroupPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          isContinuation: isContinuation,
          requiresNewSnapshot: requiresNewSnapshot,
          status: status,
        ),
      });
    }

    record(const DiagnosticsStarted());

    try {
      final page = await _sequencer.run(
        () => _database.transaction(
          () => _readRelationGroupPageOnCurrentSnapshot(query),
        ),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return RelationGroupPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyRelationGroupReadFailure(error, query);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _relationGroupDiagnosticsFailureCode(failure),
        ),
        requiresNewSnapshot: failure is RelationGroupSnapshotExpired,
      );
      return RelationGroupPageFailure(failure);
    }
  }

  Future<RelationGroupPage> _readRelationGroupPageOnCurrentSnapshot(
    RelationGroupPageQuery query,
  ) => switch (query) {
    RelationGroupQuery() => _readLongTermRelationGroupPageOnCurrentSnapshot(
      query,
    ),
    DailyChoiceGroupQuery() => _readDailyChoiceGroupPageOnCurrentSnapshot(
      query,
    ),
  };

  Future<RelationGroupPage> _readLongTermRelationGroupPageOnCurrentSnapshot(
    RelationGroupQuery query,
  ) async {
    final _DriftRelationGroupCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftRelationGroupCursor own => own,
      _ => throw StateError('Недопустимый курсор группы связей.'),
    };
    if (cursor == null) {
      await _requireRelationGroupOwner(query.intentionId);
      final counts = await _readVerifiedRelationCounts(query.intentionId);
      final rows = await _readRelationGroupRows(query, cursor: null);
      final items = await _rehydrateRelationGroupItems(
        rows.take(query.pageSize),
        query,
        knownActiveCounts: {query.intentionId: counts.active},
      );
      final hasNextPage = rows.length > query.pageSize;
      final expectedCount = counts.forGroup(
        scope: query.scope,
        type: query.type,
        direction: query.direction,
      );
      _verifyRelationGroupProgress(
        returnedCount: items.length,
        expectedCount: expectedCount,
        hasNextPage: hasNextPage,
      );
      final revision = _currentRevision;
      return RelationGroupFirstPage(
        items: items,
        counts: counts,
        nextCursor: hasNextPage
            ? _relationGroupCursorAt(
                items.last.relation,
                revision: revision,
                expectedCount: expectedCount,
                returnedCount: items.length,
                ownerActiveRelationCount: counts.active,
              )
            : null,
        revision: revision,
      );
    }

    if (cursor.revision.compareTo(_currentRevision) !=
        GraphRevisionOrder.same) {
      throw const _RelationGroupSnapshotHasExpired();
    }

    await _requireRelationGroupOwner(query.intentionId);
    final rows = await _readRelationGroupRows(query, cursor: cursor);
    final items = await _rehydrateRelationGroupItems(
      rows.take(query.pageSize),
      query,
      knownActiveCounts: {query.intentionId: cursor.ownerActiveRelationCount},
    );
    final hasNextPage = rows.length > query.pageSize;
    final returnedCount = cursor.returnedCount + items.length;
    _verifyRelationGroupProgress(
      returnedCount: returnedCount,
      expectedCount: cursor.expectedCount,
      hasNextPage: hasNextPage,
    );
    return RelationGroupContinuationPage(
      items: items,
      nextCursor: hasNextPage
          ? _relationGroupCursorAt(
              items.last.relation,
              revision: cursor.revision,
              expectedCount: cursor.expectedCount,
              returnedCount: returnedCount,
              ownerActiveRelationCount: cursor.ownerActiveRelationCount,
            )
          : null,
      revision: cursor.revision,
    );
  }

  Future<RelationGroupPage> _readDailyChoiceGroupPageOnCurrentSnapshot(
    DailyChoiceGroupQuery query,
  ) async {
    final _DriftDailyChoiceGroupCursor? cursor = switch (query.cursor) {
      null => null,
      final _DriftDailyChoiceGroupCursor own => own,
      _ => throw StateError('Недопустимый курсор группы дневных выборов.'),
    };
    if (cursor != null &&
        cursor.revision.compareTo(_currentRevision) !=
            GraphRevisionOrder.same) {
      throw const _RelationGroupSnapshotHasExpired();
    }

    await _requireRelationGroupOwner(query.intentionId);
    final counts = cursor == null
        ? await _readVerifiedRelationCounts(query.intentionId)
        : null;
    final rawRows = await _readDailyChoiceGroupRows(query, cursor: cursor);
    final selectedRows = rawRows.take(query.pageSize).toList(growable: false);
    final choices = <DailyChoice>[];
    for (final row in selectedRows) {
      if (_requiredStoredInteger(row.data, 'creation_sequence') <= 0) {
        throw const StoredGraphCorruption();
      }
      final id = switch (DailyChoiceId.decode(
        _requiredStoredString(row.data, 'id'),
      )) {
        DailyChoiceIdDecodingSuccess(:final id) => id,
        InvalidDailyChoiceIdDecoding() => throw const StoredGraphCorruption(),
      };
      final choice = _decodeStoredDailyChoice(row, id);
      final directParticipant = switch (query.role) {
        DailyChoiceRelationRole.source => choice.sourceIntentionId,
        DailyChoiceRelationRole.selected => choice.selectedIntentionId,
      };
      if (directParticipant != query.intentionId) {
        throw const StoredGraphCorruption();
      }
      choices.add(choice);
    }
    final items = await _verifyDailyChoiceCatalogItems(choices);
    final hasNextPage = rawRows.length > query.pageSize;
    final expectedCount =
        counts?.forSelection(query.group) ?? cursor!.expectedCount;
    final returnedCount = (cursor?.returnedCount ?? 0) + items.length;
    _verifyRelationGroupProgress(
      returnedCount: returnedCount,
      expectedCount: expectedCount,
      hasNextPage: hasNextPage,
    );
    final revision = _currentRevision;
    final nextCursor = hasNextPage
        ? _DriftDailyChoiceGroupCursor(
            revision: revision,
            boundaryDate: _requiredStoredString(
              selectedRows.last.data,
              'choice_date',
            ),
            boundaryCreationSequence: _requiredStoredInteger(
              selectedRows.last.data,
              'creation_sequence',
            ),
            expectedCount: expectedCount,
            returnedCount: returnedCount,
          )
        : null;
    return cursor == null
        ? DailyChoiceGroupFirstPage(
            items: items,
            counts: counts!,
            nextCursor: nextCursor,
            revision: revision,
          )
        : DailyChoiceGroupContinuationPage(
            items: items,
            nextCursor: nextCursor,
            revision: revision,
          );
  }

  Future<List<QueryRow>> _readDailyChoiceGroupRows(
    DailyChoiceGroupQuery query, {
    required _DriftDailyChoiceGroupCursor? cursor,
  }) {
    final (ownerColumn, indexName) = switch (query.role) {
      DailyChoiceRelationRole.source => (
        'source_intention_id',
        'daily_choices_source_date_creation_order',
      ),
      DailyChoiceRelationRole.selected => (
        'selected_intention_id',
        'daily_choices_selected_date_creation_order',
      ),
    };
    final continuation = cursor == null
        ? ''
        : '''AND (choice_date < ? OR
          (choice_date = ? AND creation_sequence < ?))''';
    return _database
        .customSelect(
          '''SELECT creation_sequence, id, source_intention_id,
              selected_intention_id, choice_date, description, is_completed,
              scheduled_minute, priority
           FROM daily_choices INDEXED BY $indexName
           WHERE $ownerColumn = ? $continuation
           ORDER BY choice_date DESC, creation_sequence DESC LIMIT ?''',
          variables: [
            Variable<String>(query.intentionId.toCanonicalString()),
            if (cursor != null) ...[
              Variable<String>(cursor.boundaryDate),
              Variable<String>(cursor.boundaryDate),
              Variable<int>(cursor.boundaryCreationSequence),
            ],
            Variable<int>(query.pageSize + 1),
          ],
          readsFrom: {_database.dailyChoices},
        )
        .get();
  }

  Future<void> _requireRelationGroupOwner(IntentionId id) async {
    final row = await _database
        .customSelect(
          'SELECT 1 FROM intentions WHERE id = ?',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.intentions},
        )
        .getSingleOrNull();
    if (row == null) throw const _IntentionNotFound();
  }

  Future<List<QueryRow>> _readRelationGroupRows(
    RelationGroupQuery query, {
    required _DriftRelationGroupCursor? cursor,
  }) {
    final ownerColumn = switch (query.direction) {
      relation_domain.RelationDirection.incoming => 'related_intention_id',
      relation_domain.RelationDirection.outgoing => 'source_intention_id',
    };
    final indexName = switch (query.direction) {
      relation_domain.RelationDirection.incoming =>
        'long_term_relations_related_group_order',
      relation_domain.RelationDirection.outgoing =>
        'long_term_relations_source_group_order',
    };
    final type = switch (query.type) {
      relation_domain.LongTermRelationType.need => 'need',
      relation_domain.LongTermRelationType.can => 'can',
    };
    final scope = switch (query.scope) {
      relation_domain.RelationScope.active => 0,
      relation_domain.RelationScope.archived => 1,
    };
    final continuation = cursor == null
        ? ''
        : '''
          AND (
            priority > ? OR
            (priority = ? AND creation_sequence > ?)
          )
        ''';
    return _database
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
            FROM long_term_relations INDEXED BY $indexName
            WHERE
              $ownerColumn = ? AND
              type = ? AND
              is_archived = ?
              $continuation
            ORDER BY priority, creation_sequence
            LIMIT ?
          ''',
          variables: [
            Variable<String>(query.intentionId.toCanonicalString()),
            Variable<String>(type),
            Variable<int>(scope),
            if (cursor != null) ...[
              Variable<int>(cursor.boundaryPriority),
              Variable<int>(cursor.boundaryPriority),
              Variable<int>(cursor.boundaryCreationSequence),
            ],
            Variable<int>(query.pageSize + 1),
          ],
          readsFrom: {_database.longTermRelations},
        )
        .get();
  }

  Future<List<LongTermRelationSummary>> _rehydrateRelationGroupItems(
    Iterable<QueryRow> rawRows,
    RelationGroupQuery query, {
    required Map<IntentionId, int> knownActiveCounts,
  }) async {
    final rows = [
      for (final rawRow in rawRows) _StoredRelationGroupRow.fromRawRow(rawRow),
    ];
    final relations = [for (final row in rows) row.toDomain()];
    for (final relation in relations) {
      final ownerId = switch (query.direction) {
        relation_domain.RelationDirection.incoming =>
          relation.relatedIntentionId,
        relation_domain.RelationDirection.outgoing =>
          relation.sourceIntentionId,
      };
      if (ownerId != query.intentionId ||
          relation.type != query.type ||
          relation.scope != query.scope) {
        throw const StoredGraphCorruption();
      }
    }

    final participantIds = <IntentionId>{
      for (final relation in relations) ...[
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      ],
    };
    final participants = await _readRelationParticipants(
      participantIds,
      knownActiveCounts: knownActiveCounts,
    );
    return List.unmodifiable([
      for (var index = 0; index < relations.length; index++)
        LongTermRelationSummary(
          relation: relations[index],
          source:
              participants[relations[index].sourceIntentionId] ??
              (throw const StoredGraphCorruption()),
          related:
              participants[relations[index].relatedIntentionId] ??
              (throw const StoredGraphCorruption()),
          hasDescription: rows[index].hasDescription,
        ),
    ]);
  }

  Future<Map<IntentionId, RelationParticipantSummary>>
  _readRelationParticipants(
    Set<IntentionId> ids, {
    required Map<IntentionId, int> knownActiveCounts,
  }) async {
    if (ids.isEmpty) return const {};
    final orderedIds = ids.toList(growable: false);
    final validatedRows =
        <({IntentionId intentionId, _StoredIntentionDetail stored})>[];
    const batchSize = 400;
    for (var start = 0; start < orderedIds.length; start += batchSize) {
      final end = start + batchSize < orderedIds.length
          ? start + batchSize
          : orderedIds.length;
      final intentions = _database.intentions;
      final query = _database.selectOnly(intentions)
        ..addColumns([
          intentions.id,
          intentions.title,
          intentions.description,
          intentions.isActionReady,
          intentions.isArchived,
          intentions.createdAt,
          intentions.updatedAt,
        ])
        ..where(
          intentions.id.isIn([
            for (final id in orderedIds.sublist(start, end))
              id.toCanonicalString(),
          ]),
        );
      validatedRows.addAll([
        for (final row in await query.get()) _validateCatalogRow(row),
      ]);
    }
    final idsWithoutKnownCount = ids.difference(knownActiveCounts.keys.toSet());
    final counts = await _readVerifiedRelationCountsFor(idsWithoutKnownCount);
    final activeCounts = <IntentionId, int>{
      for (final entry in knownActiveCounts.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
      for (final entry in counts.entries) entry.key: entry.value.active,
    };
    return Map.unmodifiable({
      for (final row in validatedRows)
        row.intentionId: RelationParticipantSummary(
          id: row.intentionId,
          title: row.stored.title,
          archiveState: row.stored.archiveState,
          activeRelationCount:
              activeCounts[row.intentionId] ??
              (throw const StoredGraphCorruption()),
        ),
    });
  }

  _DriftRelationGroupCursor _relationGroupCursorAt(
    relation_domain.LongTermRelation boundary, {
    required GraphRevision revision,
    required int expectedCount,
    required int returnedCount,
    required int ownerActiveRelationCount,
  }) => _DriftRelationGroupCursor(
    revision: revision,
    boundaryPriority: switch (boundary.priority) {
      relation_domain.RelationPriority.p1 => 1,
      relation_domain.RelationPriority.p2 => 2,
      relation_domain.RelationPriority.p3 => 3,
      relation_domain.RelationPriority.p4 => 4,
    },
    boundaryCreationSequence: boundary.creationSequence.value,
    expectedCount: expectedCount,
    returnedCount: returnedCount,
    ownerActiveRelationCount: ownerActiveRelationCount,
  );
}

void _verifyRelationGroupProgress({
  required int returnedCount,
  required int expectedCount,
  required bool hasNextPage,
}) {
  final invalid = hasNextPage
      ? returnedCount >= expectedCount
      : returnedCount != expectedCount;
  if (invalid) throw const StoredGraphCorruption();
}

final class _StoredRelationGroupRow {
  const _StoredRelationGroupRow({
    required this.creationSequence,
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    required this.scope,
    required this.description,
  });

  factory _StoredRelationGroupRow.fromRawRow(QueryRow row) {
    final data = row.data;
    final creationSequence = _requiredStoredInteger(data, 'creation_sequence');
    if (creationSequence <= 0) throw const StoredGraphCorruption();
    final id = _decodeStoredRelationId(_requiredStoredString(data, 'id'));
    final sourceIntentionId = _decodeStoredRelationIntentionId(
      _requiredStoredString(data, 'source_intention_id'),
    );
    final relatedIntentionId = _decodeStoredRelationIntentionId(
      _requiredStoredString(data, 'related_intention_id'),
    );
    final type = switch (_requiredStoredString(data, 'type')) {
      'need' => relation_domain.LongTermRelationType.need,
      'can' => relation_domain.LongTermRelationType.can,
      _ => throw const StoredGraphCorruption(),
    };
    final priority = switch (_requiredStoredInteger(data, 'priority')) {
      1 => relation_domain.RelationPriority.p1,
      2 => relation_domain.RelationPriority.p2,
      3 => relation_domain.RelationPriority.p3,
      4 => relation_domain.RelationPriority.p4,
      _ => throw const StoredGraphCorruption(),
    };
    final scope = switch (_requiredStoredInteger(data, 'is_archived')) {
      0 => relation_domain.RelationScope.active,
      1 => relation_domain.RelationScope.archived,
      _ => throw const StoredGraphCorruption(),
    };
    final description = data['description'];
    if (description != null && description is! String) {
      throw const StoredGraphCorruption();
    }
    LongTermRelationDescription? verifiedDescription;
    if (description case final String value) {
      try {
        verifiedDescription = LongTermRelationDescription.fromInput(value);
        if (verifiedDescription == null) {
          throw const StoredGraphCorruption();
        }
      } on LongTermRelationTextValidationException {
        throw const StoredGraphCorruption();
      }
    }

    return _StoredRelationGroupRow(
      creationSequence: creationSequence,
      id: id,
      sourceIntentionId: sourceIntentionId,
      relatedIntentionId: relatedIntentionId,
      type: type,
      priority: priority,
      scope: scope,
      description: verifiedDescription,
    );
  }

  final int creationSequence;
  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final relation_domain.LongTermRelationType type;
  final relation_domain.RelationPriority priority;
  final relation_domain.RelationScope scope;
  final LongTermRelationDescription? description;

  bool get hasDescription => description != null;

  relation_domain.LongTermRelation toDomain() {
    try {
      return relation_domain.LongTermRelation(
        id: id,
        sourceIntentionId: sourceIntentionId,
        relatedIntentionId: relatedIntentionId,
        type: type,
        priority: priority,
        scope: scope,
        creationSequence: relation_domain.RelationCreationSequence(
          creationSequence,
        ),
      );
    } on relation_domain.LongTermRelationValidationException {
      throw const StoredGraphCorruption();
    } on relation_domain.RelationCreationSequenceValidationException {
      throw const StoredGraphCorruption();
    }
  }
}

final class _DriftRelationGroupCursor implements RelationGroupCursor {
  const _DriftRelationGroupCursor({
    required this.revision,
    required this.boundaryPriority,
    required this.boundaryCreationSequence,
    required this.expectedCount,
    required this.returnedCount,
    required this.ownerActiveRelationCount,
  });

  final GraphRevision revision;
  final int boundaryPriority;
  final int boundaryCreationSequence;
  final int expectedCount;
  final int returnedCount;
  final int ownerActiveRelationCount;
}

final class _DriftDailyChoiceGroupCursor implements RelationGroupCursor {
  const _DriftDailyChoiceGroupCursor({
    required this.revision,
    required this.boundaryDate,
    required this.boundaryCreationSequence,
    required this.expectedCount,
    required this.returnedCount,
  });

  final GraphRevision revision;
  final String boundaryDate;
  final int boundaryCreationSequence;
  final int expectedCount;
  final int returnedCount;
}

RelationGroupReadFailure _classifyRelationGroupReadFailure(
  Object error,
  RelationGroupPageQuery query,
) {
  if (error is _RelationGroupSnapshotHasExpired) {
    return const RelationGroupSnapshotExpired();
  }
  if (error is _IntentionNotFound) {
    return RelationGroupIntentionNotFoundFailure(query.intentionId);
  }
  if (error is StoredGraphCorruption) {
    return const RelationGroupCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const RelationGroupCorruptionFailure(),
    SqliteUnavailableFailure() => const RelationGroupUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const RelationGroupUnexpectedFailure(),
  };
}

DiagnosticsFailureCode _relationGroupDiagnosticsFailureCode(
  RelationGroupReadFailure failure,
) => switch (failure.category) {
  GraphFailureCategory.validation => DiagnosticsFailureCode.validation,
  GraphFailureCategory.notFound => DiagnosticsFailureCode.notFound,
  GraphFailureCategory.conflict => DiagnosticsFailureCode.conflict,
  GraphFailureCategory.unavailable => DiagnosticsFailureCode.unavailable,
  GraphFailureCategory.corruption => DiagnosticsFailureCode.corruption,
  GraphFailureCategory.unexpected => DiagnosticsFailureCode.unexpected,
};

String _requiredStoredString(Map<String, Object?> data, String column) {
  final value = data[column];
  if (value is String) return value;
  throw const StoredGraphCorruption();
}

int _requiredStoredInteger(Map<String, Object?> data, String column) {
  final value = data[column];
  if (value is int) return value;
  throw const StoredGraphCorruption();
}

LongTermRelationId _decodeStoredRelationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() =>
        throw const StoredGraphCorruption(),
    };

IntentionId _decodeStoredRelationIntentionId(String value) =>
    switch (IntentionId.decode(value)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const StoredGraphCorruption(),
    };

final class _RelationGroupSnapshotHasExpired implements Exception {
  const _RelationGroupSnapshotHasExpired();
}
