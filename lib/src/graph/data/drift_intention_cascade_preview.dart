part of 'drift_personal_graph_repository.dart';

/// Состав, прочитанный на [revision], которому недостаёт только названий
/// намерений [mentioned].
typedef _PlannedCascadePreview = ({
  GraphRevision revision,
  Set<IntentionId> mentioned,
  CascadePreview Function(Map<IntentionId, String> titles) withTitles,
});

/// Предпросмотр завершается отказом [failure] без дальнейших этапов.
final class _CascadePreviewRejection implements Exception {
  const _CascadePreviewRejection(this.failure);

  final CascadePreviewFailure failure;
}

extension _IntentionCascadePreviewReading on DriftPersonalGraphRepository {
  /// Индекс удержания строится вне очереди записи (ADR-0056), состав
  /// вычисляется одной транзакцией очереди, а названия читаются короткими
  /// транзакциями частями. Каждая часть подтверждает, что ревизия
  /// не изменилась, поэтому весь ответ относится к одной ревизии.
  Future<CascadePreviewResult> _previewCascade(
    CascadeSubject subject,
    CascadeOperation operation,
  ) async {
    try {
      final index = await _cascadePreviewStage(
        IntentionCascadePreviewDiagnosticsStage.holdingIndex,
        _loadIntentionHoldingIndex,
      );
      final planned = await _cascadePreviewStage(
        IntentionCascadePreviewDiagnosticsStage.composition,
        () => _sequencer.run(
          () => _database.transaction(
            () => _planCascadePreview(index, subject, operation),
          ),
        ),
      );
      final titles = await _cascadePreviewStage(
        IntentionCascadePreviewDiagnosticsStage.titles,
        () => _readCascadePreviewTitles(planned.revision, planned.mentioned),
      );
      return planned.withTitles(titles);
    } on Object catch (error) {
      return _cascadePreviewFailure(error);
    }
  }

  /// Вызывается в транзакции очереди: команда не может подтвердиться между
  /// проверкой индекса, чтением предмета и чтением признака путей.
  Future<_PlannedCascadePreview> _planCascadePreview(
    _IntentionHoldingIndex index,
    CascadeSubject subject,
    CascadeOperation operation,
  ) async {
    if (index.sequence != _lastHoldingChangeSequence) {
      throw const _CascadePreviewRejection(CascadePreviewExpired());
    }
    final revision = _currentRevision;
    final planner = IntentionCascadePlanner(
      graph: index.graph,
      indexes: index.indexes,
      ids: index.ids,
      held: index.held,
    );
    final CascadePlanningSubject planned;
    final bool archived;
    switch (subject) {
      case IntentionCascadeSubject(:final intentionId):
        final row = await _readCascadePreviewSubjectRow(
          'SELECT is_archived FROM intentions WHERE id = ?',
          intentionId.toCanonicalString(),
          _database.intentions,
        );
        planned = PlannedIntention(intentionId);
        archived =
            decodeStoredIntentionArchiveState(row, 'is_archived') ==
            domain.IntentionArchiveState.archived;
      case RelationCascadeSubject(:final relationId):
        final row = await _readCascadePreviewSubjectRow(
          '''SELECT source_intention_id, related_intention_id, is_archived
             FROM long_term_relations WHERE id = ?''',
          relationId.toCanonicalString(),
          _database.longTermRelations,
        );
        planned = PlannedRelation(
          source: decodeStoredIntentionId(
            requiredStoredString(row, 'source_intention_id'),
          ),
          related: decodeStoredIntentionId(
            requiredStoredString(row, 'related_intention_id'),
          ),
        );
        archived =
            decodeStoredRelationScope(row) ==
            relation_domain.RelationScope.archived;
    }
    final applicable = switch (operation) {
      CascadeOperation.archive => !archived,
      CascadeOperation.restore => archived,
      CascadeOperation.delete => true,
    };
    if (!applicable) {
      throw const _CascadePreviewRejection(
        CascadePreviewOperationInapplicable(),
      );
    }

    _PlannedCascadePreview preview<C extends CascadeComposition>(
      CascadePlan<C> plan,
      CascadePreview<C> Function(Map<IntentionId, String> titles) build,
    ) => (
      revision: revision,
      mentioned: {
        ..._listedIntentions(plan.withSupporting),
        ..._listedIntentions(plan.onlyThis),
      },
      withTitles: build,
    );

    switch (operation) {
      case CascadeOperation.archive:
        final plan = planner.planArchive(planned);
        return preview(
          plan,
          (titles) => ArchiveCascadePreview(
            revision: revision,
            plan: plan,
            titles: titles,
          ),
        );
      case CascadeOperation.restore:
        final plan = planner.planRestore(planned);
        return preview(
          plan,
          (titles) => RestoreCascadePreview(
            revision: revision,
            plan: plan,
            titles: titles,
          ),
        );
      case CascadeOperation.delete:
        final plan = planner.planDelete(planned);
        switch (subject) {
          case IntentionCascadeSubject(:final intentionId):
            final isInActionPath = await _isInActionPath(intentionId);
            return preview(
              plan,
              (titles) => IntentionDeleteCascadePreview(
                revision: revision,
                plan: plan,
                titles: titles,
                isInActionPath: isInActionPath,
              ),
            );
          case RelationCascadeSubject():
            return preview(
              plan,
              (titles) => RelationDeleteCascadePreview(
                revision: revision,
                plan: plan,
                titles: titles,
              ),
            );
        }
    }
  }

  Future<Map<String, Object?>> _readCascadePreviewSubjectRow(
    String query,
    String id,
    TableInfo<Table, Object?> table,
  ) async {
    final rows = await _database
        .customSelect(
          query,
          variables: [Variable<String>(id)],
          readsFrom: {table},
        )
        .get();
    if (rows.isEmpty) {
      throw const _CascadePreviewRejection(CascadePreviewSubjectNotFound());
    }
    return rows.single.data;
  }

  /// Проверка существования по индексу пар намерения и действия не читает
  /// ни действий, ни их путей.
  Future<bool> _isInActionPath(IntentionId intentionId) async {
    final row = await _database
        .customSelect(
          '''SELECT EXISTS (
               SELECT 1 FROM action_path_items
               INDEXED BY action_path_items_intention_action
               WHERE intention_id = ?
             ) AS in_path''',
          variables: [Variable<String>(intentionId.toCanonicalString())],
          readsFrom: {_database.actionPathItems},
        )
        .getSingle();
    return requiredStoredInteger(row.data, 'in_path') == 1;
  }

  /// Каждая часть занимает отдельную транзакцию очереди (ADR-0026) и
  /// умещается в предел переменных SQLite.
  Future<Map<IntentionId, String>> _readCascadePreviewTitles(
    GraphRevision revision,
    Set<IntentionId> mentioned,
  ) async {
    final ids = mentioned.toList(growable: false);
    final titles = <IntentionId, String>{};
    const batchSize = 400;
    for (var start = 0; start < ids.length; start += batchSize) {
      final batch = ids.sublist(start, min(start + batchSize, ids.length));
      final rows = await _sequencer.run(() {
        if (_currentRevision.compareTo(revision) != GraphRevisionOrder.same) {
          throw const _CascadePreviewRejection(CascadePreviewExpired());
        }
        return _database.transaction(
          () => _database
              .customSelect(
                '''SELECT id, title FROM intentions
                   WHERE id IN (${List.filled(batch.length, '?').join(', ')})''',
                variables: [
                  for (final id in batch)
                    Variable<String>(id.toCanonicalString()),
                ],
                readsFrom: {_database.intentions},
              )
              .get(),
        );
      });
      for (final row in rows) {
        titles[decodeStoredIntentionId(requiredStoredString(row.data, 'id'))] =
            decodeStoredIntentionTitle(row.data, 'title');
      }
    }
    // Состав взят из годного индекса этой ревизии, а удаление намерения
    // индекс сбрасывает: недостающее название означает повреждение.
    if (titles.length != mentioned.length) throw const StoredGraphCorruption();
    return titles;
  }

  Future<T> _cascadePreviewStage<T>(
    IntentionCascadePreviewDiagnosticsStage stage,
    Future<T> Function() run,
  ) async {
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      IntentionCascadePreviewDiagnosticsEvent(stage: stage, status: status),
    );
    record(const DiagnosticsStarted());
    try {
      final result = await run();
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return result;
    } on Object catch (error) {
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: switch (_cascadePreviewFailure(error)) {
            CascadePreviewSubjectNotFound() => DiagnosticsFailureCode.notFound,
            CascadePreviewOperationInapplicable() =>
              DiagnosticsFailureCode.validation,
            CascadePreviewExpired() => DiagnosticsFailureCode.conflict,
            CascadePreviewUnavailable() => DiagnosticsFailureCode.unavailable,
            CascadePreviewCorruption() => DiagnosticsFailureCode.corruption,
            CascadePreviewUnexpected() => DiagnosticsFailureCode.unexpected,
          },
        ),
      );
      rethrow;
    }
  }
}

Iterable<IntentionId> _listedIntentions(CascadeComposition composition) =>
    switch (composition) {
      ArchiveCascadeComposition() => [
        ...composition.departing,
        ...composition.promoted,
        ...composition.mainsLosingRelation,
      ],
      DeleteCascadeComposition() => [
        ...composition.departing,
        ...composition.promoted,
        ...composition.archivedByInvariant,
        ...composition.mainsLosingRelation,
      ],
      RestoreCascadeComposition() => composition.restored,
    };

CascadePreviewFailure _cascadePreviewFailure(Object error) {
  if (error is _CascadePreviewRejection) return error.failure;
  if (error is _IntentionHoldingIndexExpired) {
    return const CascadePreviewExpired();
  }
  if (error is StoredGraphCorruption ||
      error is IntentionHoldingGraphIncomplete) {
    return const CascadePreviewCorruption();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const CascadePreviewCorruption(),
    SqliteUnavailableFailure() => const CascadePreviewUnavailable(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const CascadePreviewUnexpected(),
  };
}
