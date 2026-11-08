part of 'drift_personal_graph_repository.dart';

/// Каскад по текущему состоянию затронул бы другие намерения иначе, чем
/// ожидаемый состав выбранного варианта (D7, ADR-0057).
final class _CascadeCompositionConflict implements Exception {
  const _CascadeCompositionConflict();
}

/// После записи каскада активное вспомогательное намерение осталось без
/// активной входящей связи: состав разошёлся с сохранённым графом.
final class _IntentionKindInvariantViolation implements Exception {
  const _IntentionKindInvariantViolation();
}

/// Предел числа идентификаторов в одном выражении: запрос связей повторяет
/// часть дважды и остаётся под пределом переменных SQLite.
const _cascadeChunkSize = 400;

/// Записанное архивирование каскада: строки каталога каждого намерения, у
/// которого изменились архивное состояние или вид, — в порядке записи, — и
/// архивированные связи с абсолютными количествами связей затронутых
/// намерений и соседей (ADR-0011).
final class _ArchiveCascadeWrite {
  _ArchiveCascadeWrite({
    required Map<IntentionId, _IntentionCatalogChange> intentions,
    required List<_CascadedRelationArchive> relations,
    required Map<IntentionId, RelationCounts> counts,
  }) : intentions = Map.unmodifiable(intentions),
       relations = List.unmodifiable(relations),
       counts = Map.unmodifiable(counts);

  final Map<IntentionId, _IntentionCatalogChange> intentions;
  final List<_CascadedRelationArchive> relations;
  final Map<IntentionId, RelationCounts> counts;

  List<IntentionCatalogUpdated> catalogMutations(GraphRevision revision) => [
    for (final change in intentions.values)
      IntentionCatalogUpdated(
        revision: revision,
        before: change.before,
        after: change.after,
      ),
  ];

  List<GraphChange> relationChanges(GraphRevision revision) => [
    for (final relation in relations) relation.toChange(revision),
    for (final entry in counts.entries)
      IntentionRelationCountsChanged(
        revision: revision,
        intentionId: entry.key,
        counts: entry.value,
      ),
  ];
}

extension _CascadeCommandExecution on DriftPersonalGraphRepository {
  /// Архивирует намерение по выбранному варианту каскада. Уже архивное
  /// намерение не меняется.
  Future<_CommittedIntentionCommand> _archiveIntentionCascade(
    ArchiveIntention command,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readCommandSnapshot(command.id);
    if (storedBefore == null) throw const _IntentionNotFound();
    if (storedBefore.intention.archiveState ==
        domain.IntentionArchiveState.archived) {
      return _CommittedIntentionUnchanged(
        intention: storedBefore.intention,
        entry: await _catalogEntrySnapshot(storedBefore),
      );
    }
    final planner = await _cascadePlannerInTransaction();
    final executed = _requireExpectedVariant(
      planner.planArchive(PlannedIntention(command.id)),
      command.execution,
    );
    final write = await _writeArchiveCascade(
      intentions: [command.id, ...executed.departing],
      relation: null,
      promoted: executed.promoted,
      clock: clock,
    );
    final stored = await _readCommandSnapshot(command.id);
    if (stored == null) throw const StoredGraphCorruption();
    return _CommittedIntentionArchiveCascade(
      intention: stored.intention,
      write: write,
      executed: executed,
    );
  }

  /// Архивирует связь по выбранному варианту каскада. Уже архивная связь не
  /// меняется.
  Future<_CommittedLongTermRelationCommand> _archiveRelationCascade(
    ArchiveLongTermRelation command,
    _GraphWriteClock clock,
  ) async {
    final relationId = command.relationId;
    final storedBefore = await _readStoredRelation(relationId);
    if (storedBefore == null) throw _LongTermRelationNotFound(relationId);
    final before = storedBefore.toDomain();
    if (before.scope == relation_domain.RelationScope.archived) {
      return _CommittedLongTermRelationUpdate(
        before: before,
        relation: before,
        description: storedBefore.description,
        affectedCounts: const {},
        didMutate: false,
      );
    }
    final planner = await _cascadePlannerInTransaction();
    final executed = _requireExpectedVariant(
      planner.planArchive(
        PlannedRelation(
          source: before.sourceIntentionId,
          related: before.relatedIntentionId,
        ),
      ),
      command.execution,
    );
    final write = await _writeArchiveCascade(
      intentions: executed.departing,
      relation: relationId,
      promoted: executed.promoted,
      clock: clock,
    );
    final archived = write.relations
        .singleWhere((relation) => relation.before.id == relationId)
        .archived;
    final storedAfter = await _readStoredRelation(relationId);
    if (storedAfter == null ||
        !_sameStoredRelation(
          before: archived,
          beforeDescription: storedBefore.description,
          after: storedAfter.toDomain(),
          afterDescription: storedAfter.description,
        )) {
      throw const StoredGraphCorruption();
    }
    return _CommittedRelationArchiveCascade(
      before: before,
      relation: archived,
      description: storedAfter.description,
      write: write,
      executed: executed,
    );
  }

  /// Планировщик над индексом удержания текущей ревизии. Вызывается в
  /// транзакции команды, поэтому состав относится к состоянию, которое
  /// команда меняет.
  Future<IntentionCascadePlanner> _cascadePlannerInTransaction() async {
    final index = await _holdingIndexInTransaction();
    return IntentionCascadePlanner(
      graph: index.graph,
      indexes: index.indexes,
      ids: index.ids,
      held: index.held,
    );
  }

  /// Записывает архивирование [intentions] со всеми их активными связями и
  /// связи [relation], а [promoted] делает главными. Связи пишутся раньше
  /// намерений (D8), и каждая изменённая строка получает одно показание
  /// [clock]. После записи проверяется инвариант вида по намерениям, которые
  /// остались активными на другом конце архивированных связей.
  Future<_ArchiveCascadeWrite> _writeArchiveCascade({
    required List<IntentionId> intentions,
    required LongTermRelationId? relation,
    required List<IntentionId> promoted,
    required _GraphWriteClock clock,
  }) async {
    final changed = [...intentions, ...promoted];
    final before = await _catalogEntrySnapshots(changed);
    final archivedAt = relation_domain.RelationTimestamp(clock.read());
    final storedAt = archivedAt.value.microsecondsSinceEpoch;

    final relations = <LongTermRelationId, relation_domain.LongTermRelation>{};
    for (final chunk in _cascadeChunks(intentions)) {
      final placeholders = _placeholders(chunk.length);
      await _collectActiveRelations(
        relations,
        '''(relation.source_intention_id IN ($placeholders) OR
            relation.related_intention_id IN ($placeholders))''',
        [
          for (final id in [...chunk, ...chunk]) id.toCanonicalString(),
        ],
      );
    }
    if (relation != null) {
      await _collectActiveRelations(relations, 'relation.id = ?', [
        relation.toCanonicalString(),
      ]);
    }
    await _updateCascadeRows(
      '''UPDATE long_term_relations SET is_archived = 1, updated_at = ?
         WHERE is_archived = 0 AND id IN''',
      [for (final id in relations.keys) id.toCanonicalString()],
      storedAt,
      _database.longTermRelations,
    );
    await _updateCascadeRows(
      '''UPDATE intentions SET is_archived = 1, updated_at = ?
         WHERE is_archived = 0 AND id IN''',
      [for (final id in intentions) id.toCanonicalString()],
      storedAt,
      _database.intentions,
    );
    await _updateCascadeRows(
      '''UPDATE intentions SET kind = 'main', updated_at = ?
         WHERE is_archived = 0 AND kind = 'supporting' AND id IN''',
      [for (final id in promoted) id.toCanonicalString()],
      storedAt,
      _database.intentions,
    );

    final archived = intentions.toSet();
    final ends = <IntentionId>{
      for (final relation in relations.values) ...[
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      ],
    };
    await _requireKindInvariant(ends.difference(archived));
    final after = await _catalogEntrySnapshots(changed);
    return _ArchiveCascadeWrite(
      intentions: {
        for (final id in changed) id: (before: before[id]!, after: after[id]!),
      },
      relations: [
        for (final relation in relations.values)
          _CascadedRelationArchive(relation, archivedAt),
      ],
      counts: await _readVerifiedRelationCountsFor({...changed, ...ends}),
    );
  }

  /// Добавляет в [relations] активные связи, отобранные условием [where].
  Future<void> _collectActiveRelations(
    Map<LongTermRelationId, relation_domain.LongTermRelation> relations,
    String where,
    List<String> ids,
  ) async {
    final rows = await _database
        .customSelect(
          '''SELECT relation.creation_sequence, relation.id,
                    relation.source_intention_id,
                    relation.related_intention_id, relation.type,
                    relation.priority, relation.is_archived,
                    relation.created_at, relation.updated_at
             FROM long_term_relations AS relation
             WHERE relation.is_archived = 0 AND $where''',
          variables: [for (final id in ids) Variable<String>(id)],
          readsFrom: {_database.longTermRelations},
        )
        .get();
    for (final row in rows) {
      final relation = StoredLongTermRelation.decode(row.data).toDomain();
      relations[relation.id] = relation;
    }
  }

  /// Выполняет [statement], оканчивающийся `IN`, частями канонических [ids] с показанием
  /// времени [storedAt]. Каждая строка должна измениться: иначе состав
  /// разошёлся с сохранённым графом.
  Future<void> _updateCascadeRows(
    String statement,
    List<String> ids,
    int storedAt,
    TableInfo<Table, Object?> table,
  ) async {
    for (final chunk in _cascadeChunks(ids)) {
      final updated = await _database.customUpdate(
        '$statement (${_placeholders(chunk.length)})',
        variables: [
          Variable<int>(storedAt),
          for (final id in chunk) Variable<String>(id),
        ],
        updates: {table},
        updateKind: UpdateKind.update,
      );
      if (updated != chunk.length) throw const StoredGraphCorruption();
    }
  }

  /// Активное вспомогательное намерение среди [ids] должно иметь активную
  /// входящую связь (D4).
  Future<void> _requireKindInvariant(Set<IntentionId> ids) async {
    for (final chunk in _cascadeChunks(ids.toList(growable: false))) {
      final violations = await _database
          .customSelect(
            '''SELECT 1 FROM intentions AS intention
               WHERE intention.id IN (${_placeholders(chunk.length)}) AND
                     intention.kind = 'supporting' AND
                     intention.is_archived = 0 AND
                     NOT EXISTS (
                       SELECT 1 FROM long_term_relations AS relation
                       WHERE relation.related_intention_id = intention.id AND
                             relation.is_archived = 0
                     )
               LIMIT 1''',
            variables: [
              for (final id in chunk) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.intentions, _database.longTermRelations},
          )
          .get();
      if (violations.isNotEmpty) {
        throw const _IntentionKindInvariantViolation();
      }
    }
  }

  /// Строки каталога [ids], прочитанные частями.
  Future<Map<IntentionId, IntentionCatalogEntrySnapshot>>
  _catalogEntrySnapshots(List<IntentionId> ids) async {
    final snapshots = <IntentionId, IntentionCatalogEntrySnapshot>{};
    for (final chunk in _cascadeChunks(ids)) {
      final rows = await _database
          .customSelect(
            '''SELECT id, title, title_search_key, description, kind,
                      is_archived, created_at, updated_at
               FROM intentions
               WHERE id IN (${_placeholders(chunk.length)})''',
            variables: [
              for (final id in chunk) Variable<String>(id.toCanonicalString()),
            ],
            readsFrom: {_database.intentions},
          )
          .get();
      final tags = await _readIntentionTags(chunk);
      for (final row in rows) {
        final stored = _StoredIntentionCommandSnapshot.fromRow(row.data);
        final intention = stored.intention;
        snapshots[intention.id] = _DriftIntentionCatalogEntrySnapshot(
          summary: _rehydrateSummary(
            intention,
            stored.titleSearchKey,
            tags[intention.id] ?? (throw const StoredGraphCorruption()),
          ),
          storedTitleSearchKey: stored.titleSearchKey,
        );
      }
    }
    if (snapshots.length != ids.toSet().length) {
      throw const StoredGraphCorruption();
    }
    return snapshots;
  }
}

/// Выбранный вариант [plan], если он затрагивает те же намерения, что и
/// ожидаемый состав [execution]. Сравниваются множества намерений; порядок
/// показа и числа связей производны и в сравнение не входят.
C _requireExpectedVariant<C extends CascadeComposition>(
  CascadePlan<C> plan,
  CascadeExecution<C> execution,
) {
  final actual = switch (execution.choice) {
    CascadeChoice.withSupporting => plan.withSupporting,
    CascadeChoice.onlyThis => plan.onlyThis,
  };
  if (!_sameAffectedIntentions(actual, execution.expected)) {
    throw const _CascadeCompositionConflict();
  }
  return actual;
}

bool _sameAffectedIntentions(
  CascadeComposition actual,
  CascadeComposition expected,
) => switch ((actual, expected)) {
  (
    final ArchiveCascadeComposition actual,
    final ArchiveCascadeComposition expected,
  ) =>
    _sameIds(actual.departing, expected.departing) &&
        _sameIds(actual.promoted, expected.promoted),
  (
    final DeleteCascadeComposition actual,
    final DeleteCascadeComposition expected,
  ) =>
    _sameIds(actual.departing, expected.departing) &&
        _sameIds(actual.promoted, expected.promoted) &&
        _sameIds(actual.archivedByInvariant, expected.archivedByInvariant),
  (
    final RestoreCascadeComposition actual,
    final RestoreCascadeComposition expected,
  ) =>
    _sameIds(actual.restored, expected.restored) &&
        actual.returnedAsMain == expected.returnedAsMain,
  _ => false,
};

bool _sameIds(List<IntentionId> actual, List<IntentionId> expected) {
  final expectedSet = expected.toSet();
  return actual.length == expectedSet.length &&
      actual.every(expectedSet.contains);
}

Iterable<List<T>> _cascadeChunks<T>(List<T> ids) sync* {
  for (var start = 0; start < ids.length; start += _cascadeChunkSize) {
    yield ids.sublist(start, min(start + _cascadeChunkSize, ids.length));
  }
}

String _placeholders(int count) => List.filled(count, '?').join(', ');

final class _CommittedIntentionArchiveCascade
    extends _CommittedIntentionCommand {
  const _CommittedIntentionArchiveCascade({
    required this.intention,
    required this.write,
    required this.executed,
  });

  final domain.Intention intention;
  final _ArchiveCascadeWrite write;
  final ArchiveCascadeComposition executed;

  @override
  IntentionId get intentionId => intention.id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) {
    // Предмет записан первым, поэтому первая мутация каталога — его.
    final [subject, ...others] = write.catalogMutations(revision);
    return IntentionSaved(
      intention,
      catalogMutation: subject,
      additionalCatalogMutations: others,
      additionalChanges: [
        ...write.relationChanges(revision),
        IntentionHoldingChanged(revision: revision),
        CascadeOutcome(revision: revision, executed: executed),
      ],
    );
  }
}

final class _CommittedRelationArchiveCascade
    extends _CommittedLongTermRelationCommand {
  const _CommittedRelationArchiveCascade({
    required this.before,
    required this.relation,
    required this.description,
    required this.write,
    required this.executed,
  });

  final relation_domain.LongTermRelation before;
  final relation_domain.LongTermRelation relation;
  final LongTermRelationDescription? description;
  final _ArchiveCascadeWrite write;
  final ArchiveCascadeComposition executed;

  @override
  bool get didMutate => true;

  @override
  LongTermRelationUpdated toSuccess(GraphRevision revision) =>
      LongTermRelationUpdated(
        before: before,
        relation: relation,
        description: description,
        changes: [
          ...write.relationChanges(revision),
          ...write.catalogMutations(revision),
          IntentionHoldingChanged(revision: revision),
          CascadeOutcome(revision: revision, executed: executed),
        ],
      );
}
