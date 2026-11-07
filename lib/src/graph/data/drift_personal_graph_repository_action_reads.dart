part of 'drift_personal_graph_repository.dart';

extension _ActionReading on DriftPersonalGraphRepository {
  Stream<ActionReadResult> _watchAction(ActionId id) => _observeActionRead(
    _ActionWatchRegistration(actionId: id),
    (registration) async {
      final details = await _readActionDetails(id);
      registration.setDependencies(details?.action.path);
      return details;
    },
  );

  Stream<ActionPathStateReadResult> _watchActionPathState(
    ActionDraftPath draft,
  ) {
    // Удалённое без надгробия несёт последние прочитанные данные: надгробия
    // ведутся только для сохранённых путей.
    var known = draft;
    return _observeActionRead(_ActionWatchRegistration(), (registration) async {
      registration.setDependencies(draft.path);
      final path = await _readActionPathState(draft.path, missing: known);
      known = _draftPathOf(path);
      return path;
    });
  }

  /// Наблюдение чтения действия или пути: первое чтение и перечитывание при
  /// подтверждённых изменениях зависимостей [registration]. [read] вызывается
  /// внутри транзакции общего исполнителя графа и обновляет зависимости.
  Stream<GraphResult<GraphSnapshot<T>, ActionReadFailure>>
  _observeActionRead<T>(
    _ActionWatchRegistration registration,
    Future<T> Function(_ActionWatchRegistration registration) read,
  ) {
    var cancelled = false;
    void unregister() => _actionWatchers.remove(registration);

    late final StreamController<
      GraphResult<GraphSnapshot<T>, ActionReadFailure>
    >
    controller;
    Future<GraphResult<GraphSnapshot<T>, ActionReadFailure>>
    readCurrent() async {
      while (true) {
        final result = await _readActionSnapshot(() => read(registration));
        if (cancelled ||
            result
                is! GraphResultSuccess<GraphSnapshot<T>, ActionReadFailure> ||
            result.value.revision.compareTo(_currentRevision) !=
                GraphRevisionOrder.older) {
          return result;
        }
      }
    }

    Future<void> observe() async {
      _actionWatchers.add(registration);
      GraphRevision? lastSuccessfulRevision;
      try {
        var result = await readCurrent();
        if (cancelled) return;
        if (result case GraphResultSuccess(:final value)) {
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
          if (result case GraphResultSuccess(:final value)) {
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
            GraphResultFailure(const ActionReadUnexpectedFailure()),
          );
        }
      } finally {
        unregister();
        if (!cancelled) unawaited(controller.close());
      }
    }

    controller = StreamController(
      onListen: () => unawaited(observe()),
      onCancel: () {
        cancelled = true;
        unregister();
        unawaited(registration.invalidations.close());
      },
    );
    return controller.stream;
  }

  /// Одно чтение в транзакции общего исполнителя графа с диагностикой и
  /// безопасной категорией отказа.
  Future<GraphResult<GraphSnapshot<T>, ActionReadFailure>>
  _readActionSnapshot<T>(Future<T> Function() read) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const ActionReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(
          () async =>
              GraphSnapshot(value: await read(), revision: _currentRevision),
        ),
      );
      _recordDiagnostics(
        ActionReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return GraphResultSuccess(snapshot);
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
      return GraphResultFailure(failure);
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
    for (final registration in List.of(_actionWatchers)) {
      if (affectedActions.contains(registration.actionId) ||
          registration.intentionIds.any(affectedIntentions.contains) ||
          registration.pairs.any(affectedPairs.contains)) {
        registration.invalidations.add(null);
      }
    }
  }

  /// Действие с путём, где каждое намерение и звено несут текущие данные или
  /// данные надгробия, либо `null`, если действия нет. Вызывать только внутри
  /// транзакции общего исполнителя графа.
  Future<ActionDetails?> _readActionDetails(ActionId id) async {
    final action = await _readStoredAction(id);
    if (action == null) return null;
    return ActionDetails(
      action: action,
      path: await _readActionPathState(action.path),
    );
  }

  /// Путь [path] на текущих данных: существующие намерения и связи звеньев
  /// несут текущие данные, удалённые — данные надгробия. Удалённое без
  /// надгробия берёт данные из [missing]; без него у сохранённого пути это
  /// повреждение (ADR-0055). Вызывать только внутри транзакции общего
  /// исполнителя графа.
  Future<ActionSavedPath> _readActionPathState(
    ActionPath path, {
    ActionDraftPath? missing,
  }) async {
    final intentions = path.intentions;
    // Каждая позиция несёт свою пару звена: у пары есть либо связь, либо
    // надгробие (ADR-0055).
    final rows = await _database
        .customSelect(
          '''WITH path_state(position, intention_id, previous_intention_id) AS (
           VALUES ${List.filled(intentions.length, '(?, ?, ?)').join(', ')}
         )
         SELECT p.position, p.intention_id, i.id AS i_id,
                i.title AS i_title, i.description AS i_description,
                i.is_action_ready AS i_is_action_ready,
                i.is_archived AS i_is_archived, i.created_at AS i_created_at,
                i.updated_at AS i_updated_at, d.title AS deleted_title,
                r.creation_sequence, r.id, r.source_intention_id,
                r.related_intention_id, COALESCE(r.type, dr.type) AS type,
                r.priority, r.description, r.is_archived, r.created_at,
                r.updated_at
         FROM path_state p
         LEFT JOIN intentions i ON i.id = p.intention_id
         LEFT JOIN deleted_intentions d ON d.intention_id = p.intention_id
         LEFT JOIN long_term_relations r
           ON r.source_intention_id = p.previous_intention_id
          AND r.related_intention_id = p.intention_id
         LEFT JOIN deleted_relation_pairs dr
           ON dr.source_intention_id = p.previous_intention_id
          AND dr.related_intention_id = p.intention_id
         ORDER BY p.position''',
          variables: [
            for (final (position, id) in intentions.indexed) ...[
              Variable<int>(position),
              Variable<String>(id.toCanonicalString()),
              Variable<String>(
                position == 0
                    ? null
                    : intentions[position - 1].toCanonicalString(),
              ),
            ],
          ],
          readsFrom: {
            _database.intentions,
            _database.deletedIntentions,
            _database.longTermRelations,
            _database.deletedRelationPairs,
          },
        )
        .get();
    if (rows.length != intentions.length) throw const StoredGraphCorruption();
    final missingIntentions = missing?.intentions;
    final read = [
      for (final (position, row) in rows.indexed)
        _decodeActionPathIntention(
          row.data,
          path,
          position,
          missingTitle: missingIntentions?[position].title,
        ),
    ];
    return ActionSavedPath(
      root: read.first,
      steps: [
        for (var position = 1; position < rows.length; position++)
          ActionPathStep(
            link: _decodeActionPathLink(
              rows[position].data,
              missingType: missing?.steps[position - 1].relation,
            ),
            intention: read[position],
          ),
      ],
    );
  }
}

ActionPathIntention _decodeActionPathIntention(
  Map<String, Object?> data,
  ActionPath path,
  int position, {
  required String? missingTitle,
}) {
  if (requiredStoredInteger(data, 'position') != position) {
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
    title: data['deleted_title'] == null && missingTitle != null
        ? missingTitle
        : decodeStoredIntentionTitle(data, 'deleted_title'),
  );
}

ActionPathLink _decodeActionPathLink(
  Map<String, Object?> data, {
  required relation_domain.LongTermRelationType? missingType,
}) {
  if (data['id'] != null) {
    return ExistingActionPathLink(
      StoredLongTermRelation.decode(data).toDomain(),
    );
  }
  if (data['type'] == null && missingType != null) {
    return DeletedActionPathLink(missingType);
  }
  return DeletedActionPathLink(decodeStoredRelationType(data));
}

/// Путь черновика с данными, которые показало чтение [path].
ActionDraftPath _draftPathOf(ActionSavedPath path) => ActionDraftPath(
  root: ActionDraftIntention(id: path.root.id, title: path.root.title),
  steps: [
    for (final step in path.steps)
      ActionDraftPathStep(
        relation: step.link.type,
        intention: ActionDraftIntention(
          id: step.intention.id,
          title: step.intention.title,
        ),
      ),
  ],
);

typedef _IntentionPair = ({IntentionId source, IntentionId related});

final class _ActionWatchRegistration {
  _ActionWatchRegistration({this.actionId});

  /// Наблюдаемое действие; у пути черновика его нет.
  final ActionId? actionId;
  final StreamController<void> invalidations = StreamController<void>();
  Set<IntentionId> intentionIds = const {};
  Set<_IntentionPair> pairs = const {};

  /// Запоминает намерения и пары пути [path], изменения которых требуют
  /// перечитывания.
  void setDependencies(ActionPath? path) {
    final intentions = path?.intentions ?? const [];
    intentionIds = Set.unmodifiable(intentions);
    pairs = Set.unmodifiable({
      for (var position = 1; position < intentions.length; position++)
        (source: intentions[position - 1], related: intentions[position]),
    });
  }
}
