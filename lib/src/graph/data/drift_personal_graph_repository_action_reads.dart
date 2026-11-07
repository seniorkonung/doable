part of 'drift_personal_graph_repository.dart';

extension _ActionReading on DriftPersonalGraphRepository {
  Stream<ActionReadResult> _watchAction(ActionId id) {
    final registration = _ActionWatchRegistration(id);
    var cancelled = false;
    void unregister() {
      final registrations = _actionWatchers[id];
      registrations?.remove(registration);
      if (registrations?.isEmpty ?? false) _actionWatchers.remove(id);
    }

    late final StreamController<ActionReadResult> controller;
    Future<ActionReadResult> readCurrent() async {
      while (true) {
        final result = await _readAction(id, registration);
        if (cancelled ||
            result is! ActionReadSuccess ||
            result.value.revision.compareTo(_currentRevision) !=
                GraphRevisionOrder.older) {
          return result;
        }
      }
    }

    Future<void> observe() async {
      _actionWatchers.putIfAbsent(id, () => {}).add(registration);
      GraphRevision? lastSuccessfulRevision;
      try {
        var result = await readCurrent();
        if (cancelled) return;
        if (result case ActionReadSuccess(:final value)) {
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
          if (result case ActionReadSuccess(:final value)) {
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
          controller.add(const ActionReadError(ActionReadUnexpectedFailure()));
        }
      } finally {
        unregister();
        if (!cancelled) unawaited(controller.close());
      }
    }

    controller = StreamController<ActionReadResult>(
      onListen: () => unawaited(observe()),
      onCancel: () {
        cancelled = true;
        unregister();
        unawaited(registration.invalidations.close());
      },
    );
    return controller.stream;
  }

  Future<ActionReadResult> _readAction(
    ActionId id,
    _ActionWatchRegistration registration,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const ActionReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          final details = await _readActionDetails(id);
          registration.setDependencies(details);
          return GraphSnapshot(value: details, revision: _currentRevision);
        }),
      );
      _recordDiagnostics(
        ActionReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ActionReadSuccess(snapshot);
    } on Object catch (error) {
      final failure = error is StoredGraphCorruption
          ? const ActionReadCorruptionFailure()
          : switch (classifySqliteFailure(error)) {
              SqliteCorruptionFailure() => const ActionReadCorruptionFailure(),
              SqliteUnavailableFailure() =>
                const ActionReadUnavailableFailure(),
              SqliteConstraintFailure() ||
              SqliteStorageFullFailure() ||
              SqliteUnexpectedFailure() => const ActionReadUnexpectedFailure(),
            };
      _recordDiagnostics(
        ActionReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _graphCommandDiagnosticsFailureCode(failure),
          ),
        ),
      );
      return ActionReadError(failure);
    }
  }

  void _notifyActionWatchersFor(Iterable<GraphChange> changes) {
    final affectedActions = <ActionId>{};
    final affectedIntentions = <IntentionId>{};
    final affectedPairs = <_IntentionPair>{};
    void addPair(relation_domain.LongTermRelation? relation) {
      if (relation == null) return;
      affectedPairs.add((
        source: relation.sourceIntentionId,
        related: relation.relatedIntentionId,
      ));
    }

    for (final change in changes) {
      switch (change) {
        case ActionChange(:final before, :final after):
          affectedActions.add((after ?? before)!.id);
        case IntentionCatalogMutation(:final before, :final after):
          final beforeId = before?.summary.id;
          final afterId = after?.summary.id;
          if (beforeId != null) affectedIntentions.add(beforeId);
          if (afterId != null) affectedIntentions.add(afterId);
        case LongTermRelationChange(:final before, :final after):
          addPair(before);
          addPair(after);
        case GraphChange():
          break;
      }
    }
    for (final registrations in List.of(_actionWatchers.values)) {
      for (final registration in List.of(registrations)) {
        if (affectedActions.contains(registration.id) ||
            registration.intentionIds.any(affectedIntentions.contains) ||
            registration.pairs.any(affectedPairs.contains)) {
          registration.invalidations.add(null);
        }
      }
    }
  }

  /// Действие с путём, где каждое намерение и звено несут текущие данные или
  /// данные надгробия, либо `null`, если действия нет. Вызывать только внутри
  /// транзакции общего исполнителя графа.
  Future<ActionDetails?> _readActionDetails(ActionId id) async {
    final action = await _readStoredAction(id);
    if (action == null) return null;
    final actionId = Variable<String>(id.toCanonicalString());

    final intentionRows = await _database
        .customSelect(
          '''SELECT p.position, p.intention_id, i.id AS i_id,
                i.title AS i_title, i.description AS i_description,
                i.is_action_ready AS i_is_action_ready,
                i.is_archived AS i_is_archived, i.created_at AS i_created_at,
                i.updated_at AS i_updated_at, d.title AS deleted_title
         FROM action_path_items p
         LEFT JOIN intentions i ON i.id = p.intention_id
         LEFT JOIN deleted_intentions d ON d.intention_id = p.intention_id
         WHERE p.action_id = ? ORDER BY p.position''',
          variables: [actionId],
          readsFrom: {
            _database.actionPathItems,
            _database.intentions,
            _database.deletedIntentions,
          },
        )
        .get();
    final intentions = [
      for (final (position, row) in intentionRows.indexed)
        _decodeActionPathIntention(row.data, action.path, position),
    ];
    if (intentions.length != action.path.intentions.length) {
      throw const StoredGraphCorruption();
    }

    // Звено определяет пара соседних намерений: у пары есть либо связь, либо
    // надгробие (ADR-0055).
    final linkRows = await _database
        .customSelect(
          '''SELECT p.position, r.creation_sequence, r.id,
                r.source_intention_id, r.related_intention_id,
                COALESCE(r.type, d.type) AS type, r.priority, r.description,
                r.is_archived, r.created_at, r.updated_at
         FROM action_path_items p
         LEFT JOIN long_term_relations r
           ON r.source_intention_id = p.previous_intention_id
          AND r.related_intention_id = p.intention_id
         LEFT JOIN deleted_relation_pairs d
           ON d.source_intention_id = p.previous_intention_id
          AND d.related_intention_id = p.intention_id
         WHERE p.action_id = ? AND p.position > 0 ORDER BY p.position''',
          variables: [actionId],
          readsFrom: {
            _database.actionPathItems,
            _database.longTermRelations,
            _database.deletedRelationPairs,
          },
        )
        .get();
    if (linkRows.length != intentions.length - 1) {
      throw const StoredGraphCorruption();
    }
    final steps = [
      for (final (index, row) in linkRows.indexed)
        ActionPathStep(
          link: _decodeActionPathLink(row.data, index + 1),
          intention: intentions[index + 1],
        ),
    ];
    return ActionDetails(
      action: action,
      path: ActionSavedPath(root: intentions.first, steps: steps),
    );
  }
}

ActionPathIntention _decodeActionPathIntention(
  Map<String, Object?> data,
  ActionPath path,
  int position,
) {
  if (requiredStoredInteger(data, 'position') != position ||
      position >= path.intentions.length) {
    throw const StoredGraphCorruption();
  }
  final id = path.intentions[position];
  if (decodeStoredIntentionId(requiredStoredString(data, 'intention_id')) !=
      id) {
    throw const StoredGraphCorruption();
  }
  if (data['i_id'] != null) {
    return ExistingActionPathIntention(decodeStoredIntention(data, 'i_'));
  }
  return DeletedActionPathIntention(
    id: id,
    title: decodeStoredIntentionTitle(data, 'deleted_title'),
  );
}

ActionPathLink _decodeActionPathLink(Map<String, Object?> data, int position) {
  if (requiredStoredInteger(data, 'position') != position) {
    throw const StoredGraphCorruption();
  }
  if (data['id'] != null) {
    return ExistingActionPathLink(
      StoredLongTermRelation.decode(data).toDomain(),
    );
  }
  return DeletedActionPathLink(decodeStoredRelationType(data));
}

typedef _IntentionPair = ({IntentionId source, IntentionId related});

final class _ActionWatchRegistration {
  _ActionWatchRegistration(this.id);

  final ActionId id;
  final StreamController<void> invalidations = StreamController<void>();
  Set<IntentionId> intentionIds = const {};
  Set<_IntentionPair> pairs = const {};

  void setDependencies(ActionDetails? details) {
    final intentions = details?.action.path.intentions ?? const [];
    intentionIds = Set.unmodifiable(intentions);
    pairs = Set.unmodifiable({
      for (var position = 1; position < intentions.length; position++)
        (source: intentions[position - 1], related: intentions[position]),
    });
  }
}
