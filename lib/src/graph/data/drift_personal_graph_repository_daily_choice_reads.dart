part of 'drift_personal_graph_repository.dart';

extension _DailyChoiceReading on DriftPersonalGraphRepository {
  Stream<DailyChoiceReadResult> _watchDailyChoice(DailyChoiceId id) {
    final registration = _DailyChoiceWatchRegistration(id);
    var cancelled = false;
    void unregister() {
      final registrations = _dailyChoiceWatchers[id];
      registrations?.remove(registration);
      if (registrations?.isEmpty ?? false) {
        _dailyChoiceWatchers.remove(id);
      }
    }

    late final StreamController<DailyChoiceReadResult> controller;
    Future<DailyChoiceReadResult> readCurrent() async {
      while (true) {
        final result = await _readDailyChoice(id, registration: registration);
        if (cancelled ||
            result is! DailyChoiceReadSuccess ||
            result.value.revision.compareTo(_currentRevision) !=
                GraphRevisionOrder.older) {
          return result;
        }
      }
    }

    Future<void> observe() async {
      _dailyChoiceWatchers.putIfAbsent(id, () => {}).add(registration);
      GraphRevision? lastSuccessfulRevision;
      try {
        var result = await readCurrent();
        if (cancelled) return;
        if (result case DailyChoiceReadSuccess(:final value)) {
          lastSuccessfulRevision = value.revision;
        }
        controller.add(result);

        await for (final _ in registration.invalidations.stream) {
          if (lastSuccessfulRevision?.compareTo(_currentRevision)
              case GraphRevisionOrder.same) {
            continue;
          }
          result = await readCurrent();
          if (cancelled) return;
          if (result case DailyChoiceReadSuccess(:final value)) {
            if (lastSuccessfulRevision?.compareTo(value.revision)
                case GraphRevisionOrder.same || GraphRevisionOrder.newer) {
              continue;
            }
            lastSuccessfulRevision = value.revision;
          }
          controller.add(result);
        }
      } on Object {
        if (!cancelled) {
          controller.add(
            const DailyChoiceReadError(DailyChoiceReadUnexpectedFailure()),
          );
        }
      } finally {
        unregister();
        if (!cancelled) unawaited(controller.close());
      }
    }

    controller = StreamController<DailyChoiceReadResult>(
      onListen: () => unawaited(observe()),
      onCancel: () {
        cancelled = true;
        unregister();
        unawaited(registration.invalidations.close());
      },
    );
    return controller.stream;
  }

  Future<DailyChoiceReadResult> _readDailyChoice(
    DailyChoiceId id, {
    _DailyChoiceWatchRegistration? registration,
  }) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const DailyChoiceReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          final details = await _readVerifiedDailyChoice(id);
          registration?.setDependencies(details);
          return GraphSnapshot(value: details, revision: _currentRevision);
        }),
      );
      _recordDiagnostics(
        DailyChoiceReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return DailyChoiceReadSuccess(snapshot);
    } on Object catch (error) {
      final failure = error is StoredGraphCorruption
          ? const DailyChoiceReadCorruptionFailure()
          : switch (classifySqliteFailure(error)) {
              SqliteCorruptionFailure() =>
                const DailyChoiceReadCorruptionFailure(),
              SqliteUnavailableFailure() =>
                const DailyChoiceReadUnavailableFailure(),
              SqliteConstraintFailure() ||
              SqliteStorageFullFailure() ||
              SqliteUnexpectedFailure() =>
                const DailyChoiceReadUnexpectedFailure(),
            };
      _recordDiagnostics(
        DailyChoiceReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return DailyChoiceReadError(failure);
    }
  }

  void _notifyDailyChoiceWatchersFor(Iterable<GraphChange> changes) {
    final affectedChoices = <DailyChoiceId>{};
    final affectedIntentions = <IntentionId>{};
    final affectedRelations = <LongTermRelationId>{};
    for (final change in changes) {
      switch (change) {
        case DailyChoiceChange(:final before, :final after):
          affectedChoices.add((after ?? before)!.id);
        case IntentionCatalogMutation(:final before, :final after):
          final beforeId = before?.summary.id;
          final afterId = after?.summary.id;
          if (beforeId != null) affectedIntentions.add(beforeId);
          if (afterId != null) affectedIntentions.add(afterId);
        case LongTermRelationChange(:final id):
          affectedRelations.add(id);
        case GraphChange():
          break;
      }
    }
    for (final registrations in List.of(_dailyChoiceWatchers.values)) {
      for (final registration in List.of(registrations)) {
        if (affectedChoices.contains(registration.id) ||
            registration.intentionIds.any(affectedIntentions.contains) ||
            registration.relationIds.any(affectedRelations.contains)) {
          registration.invalidations.add(null);
        }
      }
    }
  }

  /// Вызывать только внутри транзакции общего исполнителя графа.
  Future<DailyChoiceDetails?> _readVerifiedDailyChoice(DailyChoiceId id) async {
    final choiceRow = await _database
        .customSelect(
          '''SELECT creation_sequence, id, source_intention_id,
                selected_intention_id, choice_date, description, is_completed,
                scheduled_minute, priority
         FROM daily_choices WHERE id = ?''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.dailyChoices},
        )
        .getSingleOrNull();
    if (choiceRow == null) return null;
    final choice = decodeStoredDailyChoice(choiceRow.data);
    if (choice.id != id) throw const StoredGraphCorruption();

    final stepRows = await _database
        .customSelect(
          '''SELECT id, daily_choice_id, long_term_relation_id, previous_step_id
         FROM daily_choice_path_steps WHERE daily_choice_id = ?''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.dailyChoicePathSteps},
        )
        .get();
    final steps = [
      for (final row in stepRows) decodeStoredChoicePathStep(row.data),
    ];
    if (steps.isEmpty) throw const StoredGraphCorruption();

    final relationIds = steps.map((step) => step.relationId).toSet();
    final orderedRelationIds = relationIds.toList();
    final relations = <LongTermRelationId, StoredLongTermRelation>{};
    for (var start = 0; start < orderedRelationIds.length; start += 400) {
      final batch = orderedRelationIds.skip(start).take(400).toList();
      final rows = await _database
          .customSelect(
            '''SELECT creation_sequence, id, source_intention_id,
                  related_intention_id, type, priority, description, is_archived
           FROM long_term_relations
           WHERE id IN (${List.filled(batch.length, '?').join(',')})''',
            variables: [
              for (final relationId in batch)
                Variable<String>(relationId.toCanonicalString()),
            ],
            readsFrom: {_database.longTermRelations},
          )
          .get();
      for (final row in rows) {
        final stored = StoredLongTermRelation.decode(row.data);
        if (!relationIds.contains(stored.id) ||
            relations.containsKey(stored.id)) {
          throw const StoredGraphCorruption();
        }
        relations[stored.id] = stored;
      }
    }
    if (relations.length != relationIds.length) {
      throw const StoredGraphCorruption();
    }

    final intentionIds = <IntentionId>{
      choice.sourceIntentionId,
      choice.selectedIntentionId,
      for (final relation in relations.values) ...[
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      ],
    };
    final orderedIntentionIds = intentionIds.toList();
    final intentions = <IntentionId, domain.Intention>{};
    for (var start = 0; start < orderedIntentionIds.length; start += 400) {
      final batch = orderedIntentionIds.skip(start).take(400).toList();
      final rows = await _database
          .customSelect(
            '''SELECT id, title, description, is_action_ready, is_archived,
                  created_at, updated_at FROM intentions
           WHERE id IN (${List.filled(batch.length, '?').join(',')})''',
            variables: [
              for (final intentionId in batch)
                Variable<String>(intentionId.toCanonicalString()),
            ],
            readsFrom: {_database.intentions},
          )
          .get();
      for (final row in rows) {
        final intention = decodeStoredIntention(row.data);
        if (!intentionIds.contains(intention.id) ||
            intentions.containsKey(intention.id)) {
          throw const StoredGraphCorruption();
        }
        intentions[intention.id] = intention;
      }
    }
    if (intentions.length != intentionIds.length) {
      throw const StoredGraphCorruption();
    }
    final path = _validateStoredChoicePath(
      choice: choice,
      steps: steps,
      relations: relations,
      intentions: intentions,
    );
    return DailyChoiceDetails(
      choice: choice,
      source: intentions[choice.sourceIntentionId]!,
      selected: intentions[choice.selectedIntentionId]!,
      path: path,
    );
  }
}

final class _DailyChoiceWatchRegistration {
  _DailyChoiceWatchRegistration(this.id);

  final DailyChoiceId id;
  final StreamController<void> invalidations = StreamController<void>();
  Set<IntentionId> intentionIds = const {};
  Set<LongTermRelationId> relationIds = const {};

  void setDependencies(DailyChoiceDetails? details) {
    intentionIds = details == null
        ? const {}
        : Set.unmodifiable({
            details.source.id,
            details.selected.id,
            for (final step in details.path) ...[
              step.source.id,
              step.related.id,
            ],
          });
    relationIds = details == null
        ? const {}
        : Set.unmodifiable({for (final step in details.path) step.relation.id});
  }
}
