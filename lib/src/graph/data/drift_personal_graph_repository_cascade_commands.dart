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

/// Связи, которые каскад читает у затронутых намерений.
enum _CascadeRelationSelection {
  /// Любого архивного состояния: удаление.
  any,

  /// Активные: архивирование.
  active,

  /// Архивные, оба участника которых активны: восстановление.
  archivedBetweenActive,
}

/// Записанный каскад: удалённые намерения со строками каталога до удаления,
/// строки каталога каждого оставшегося намерения, у которого изменились
/// архивное состояние или вид, — в порядке записи, — удалённые связи, связи,
/// у которых изменилось архивное состояние, и абсолютные количества связей
/// затронутых оставшихся намерений и соседей (ADR-0011).
final class _CascadeWrite {
  _CascadeWrite({
    required Map<IntentionId, IntentionCatalogEntrySnapshot> deleted,
    required Map<IntentionId, _IntentionCatalogChange> intentions,
    required List<relation_domain.LongTermRelation> deletedRelations,
    required List<_CascadedRelationScopeChange> relations,
    required Map<IntentionId, RelationCounts> counts,
  }) : deleted = Map.unmodifiable(deleted),
       intentions = Map.unmodifiable(intentions),
       deletedRelations = List.unmodifiable(deletedRelations),
       relations = List.unmodifiable(relations),
       counts = Map.unmodifiable(counts);

  final Map<IntentionId, IntentionCatalogEntrySnapshot> deleted;
  final Map<IntentionId, _IntentionCatalogChange> intentions;
  final List<relation_domain.LongTermRelation> deletedRelations;
  final List<_CascadedRelationScopeChange> relations;
  final Map<IntentionId, RelationCounts> counts;

  /// Удалённые намерения раньше изменённых, каждые — в порядке записи.
  List<IntentionCatalogMutation> catalogMutations(GraphRevision revision) => [
    for (final entry in deleted.values)
      IntentionCatalogDeleted(revision: revision, entry: entry),
    for (final change in intentions.values)
      IntentionCatalogUpdated(
        revision: revision,
        before: change.before,
        after: change.after,
      ),
  ];

  List<GraphChange> relationChanges(GraphRevision revision) => [
    for (final relation in deletedRelations)
      LongTermRelationDeletedChange(revision: revision, relation: relation),
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
    final write = await _writeCascade(
      archived: [command.id, ...executed.departing],
      promoted: executed.promoted,
      clock: clock,
    );
    final stored = await _readCommandSnapshot(command.id);
    if (stored == null) throw const StoredGraphCorruption();
    return _CommittedIntentionCascadeUpdate(
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
    final write = await _writeCascade(
      archived: executed.departing,
      archivedRelation: relationId,
      promoted: executed.promoted,
      clock: clock,
    );
    final archived = write.relations
        .singleWhere((relation) => relation.before.id == relationId)
        .after;
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
    return _CommittedRelationCascadeUpdate(
      before: before,
      relation: archived,
      description: storedAfter.description,
      write: write,
      executed: executed,
    );
  }

  /// Удаляет намерение по выбранному варианту каскада и архивирует активные
  /// вспомогательные намерения, оставшиеся без активной входящей связи.
  Future<_CommittedIntentionCommand> _deleteIntentionCascade(
    DeleteIntention command,
    _GraphWriteClock clock,
  ) async {
    if (await _readCommandSnapshot(command.id) == null) {
      throw const _IntentionNotFound();
    }
    final planner = await _cascadePlannerInTransaction();
    final executed = _requireExpectedVariant(
      planner.planDelete(PlannedIntention(command.id)),
      command.execution,
    );
    final write = await _writeCascade(
      deleted: [command.id, ...executed.departing],
      archived: executed.archivedByInvariant,
      promoted: executed.promoted,
      clock: clock,
    );
    return _CommittedIntentionDeleteCascade(
      id: command.id,
      write: write,
      executed: executed,
    );
  }

  /// Удаляет связь по выбранному варианту каскада и архивирует активные
  /// вспомогательные намерения, оставшиеся без активной входящей связи.
  Future<_CommittedLongTermRelationCommand> _deleteRelationCascade(
    DeleteLongTermRelation command,
    _GraphWriteClock clock,
  ) async {
    final relationId = command.relationId;
    final stored = await _readStoredRelation(relationId);
    if (stored == null) throw _LongTermRelationNotFound(relationId);
    final relation = stored.toDomain();
    final planner = await _cascadePlannerInTransaction();
    final executed = _requireExpectedVariant(
      planner.planDelete(
        PlannedRelation(
          source: relation.sourceIntentionId,
          related: relation.relatedIntentionId,
        ),
      ),
      command.execution,
    );
    final write = await _writeCascade(
      deleted: executed.departing,
      deletedRelation: relationId,
      archived: executed.archivedByInvariant,
      promoted: executed.promoted,
      clock: clock,
    );
    return _CommittedRelationDeleteCascade(
      relation: write.deletedRelations.singleWhere(
        (deleted) => deleted.id == relationId,
      ),
      write: write,
      executed: executed,
    );
  }

  /// Восстанавливает намерение по выбранному варианту каскада. Уже активное
  /// намерение не меняется.
  Future<_CommittedIntentionCommand> _restoreIntentionCascade(
    RestoreIntention command,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readCommandSnapshot(command.id);
    if (storedBefore == null) throw const _IntentionNotFound();
    if (storedBefore.intention.archiveState ==
        domain.IntentionArchiveState.active) {
      return _CommittedIntentionUnchanged(
        intention: storedBefore.intention,
        entry: await _catalogEntrySnapshot(storedBefore),
      );
    }
    final planner = await _cascadePlannerInTransaction();
    final executed = _requireExpectedVariant(
      planner.planRestore(PlannedIntention(command.id)),
      command.execution,
    );
    final write = await _writeRestoreCascade(
      restored: [command.id, ...executed.restored],
      returnedAsMain: executed.returnedAsMain,
      clock: clock,
    );
    final stored = await _readCommandSnapshot(command.id);
    if (stored == null) throw const StoredGraphCorruption();
    return _CommittedIntentionCascadeUpdate(
      intention: stored.intention,
      write: write,
      executed: executed,
    );
  }

  /// Восстанавливает связь по выбранному варианту каскада вместе с её
  /// архивными участниками. Уже активная связь не меняется.
  Future<_CommittedLongTermRelationCommand> _restoreRelationCascade(
    RestoreLongTermRelation command,
    _GraphWriteClock clock,
  ) async {
    final relationId = command.relationId;
    final storedBefore = await _readStoredRelation(relationId);
    if (storedBefore == null) throw _LongTermRelationNotFound(relationId);
    final before = storedBefore.toDomain();
    if (before.scope == relation_domain.RelationScope.active) {
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
      planner.planRestore(
        PlannedRelation(
          source: before.sourceIntentionId,
          related: before.relatedIntentionId,
        ),
      ),
      command.execution,
    );
    final write = await _writeRestoreCascade(
      restored: executed.restored,
      restoredRelation: relationId,
      returnedAsMain: executed.returnedAsMain,
      clock: clock,
    );
    final restored = write.relations
        .singleWhere((relation) => relation.before.id == relationId)
        .after;
    final storedAfter = await _readStoredRelation(relationId);
    if (storedAfter == null ||
        !_sameStoredRelation(
          before: restored,
          beforeDescription: storedBefore.description,
          after: storedAfter.toDomain(),
          afterDescription: storedAfter.description,
        )) {
      throw const StoredGraphCorruption();
    }
    return _CommittedRelationCascadeUpdate(
      before: before,
      relation: restored,
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

  /// Записывает каскад в порядке, которого требуют триггеры (D8): удаляет
  /// намерения [deleted] со всеми их связями и назначениями тегов и связь
  /// [deletedRelation], делает [promoted] главными и архивирует [archived]
  /// со всеми их активными связями и связь [archivedRelation]. Связи
  /// пишутся раньше намерений, и каждая изменённая строка получает одно
  /// показание [clock]. После записи проверяется инвариант вида по
  /// намерениям, которые остались на другом конце затронутых связей.
  Future<_CascadeWrite> _writeCascade({
    List<IntentionId> deleted = const [],
    LongTermRelationId? deletedRelation,
    required List<IntentionId> archived,
    LongTermRelationId? archivedRelation,
    required List<IntentionId> promoted,
    required _GraphWriteClock clock,
  }) async {
    final deletedBefore = await _catalogEntrySnapshots(deleted);
    final changed = [...archived, ...promoted];
    final changedBefore = await _catalogEntrySnapshots(changed);
    final changedAt = relation_domain.RelationTimestamp(clock.read());
    final storedAt = changedAt.value.microsecondsSinceEpoch;

    final deletedRelations = await _collectRelationsOf(
      deleted,
      _CascadeRelationSelection.any,
      also: deletedRelation,
    );
    await _deleteCascadeRows(
      _database.longTermRelations,
      (relation) => relation.id,
      [for (final id in deletedRelations.keys) id.toCanonicalString()],
    );
    await _deleteCascadeRows(
      _database.intentions,
      (intention) => intention.id,
      [for (final id in deleted) id.toCanonicalString()],
    );
    await _updateCascadeRows(
      '''UPDATE intentions SET kind = 'main', updated_at = ?
         WHERE kind = 'supporting' AND id IN''',
      [for (final id in promoted) id.toCanonicalString()],
      storedAt,
      _database.intentions,
    );
    final archivedRelations = await _collectRelationsOf(
      archived,
      _CascadeRelationSelection.active,
      also: archivedRelation,
    );
    await _updateCascadeRows(
      '''UPDATE long_term_relations SET is_archived = 1, updated_at = ?
         WHERE is_archived = 0 AND id IN''',
      [for (final id in archivedRelations.keys) id.toCanonicalString()],
      storedAt,
      _database.longTermRelations,
    );
    await _updateCascadeRows(
      '''UPDATE intentions SET is_archived = 1, updated_at = ?
         WHERE is_archived = 0 AND id IN''',
      [for (final id in archived) id.toCanonicalString()],
      storedAt,
      _database.intentions,
    );

    final ends = <IntentionId>{
      for (final relation in [
        ...deletedRelations.values,
        ...archivedRelations.values,
      ]) ...[relation.sourceIntentionId, relation.relatedIntentionId],
    }.difference(deleted.toSet());
    await _requireKindInvariant(ends.difference(archived.toSet()));
    final changedAfter = await _catalogEntrySnapshots(changed);
    return _CascadeWrite(
      deleted: deletedBefore,
      intentions: {
        for (final id in changed)
          id: (before: changedBefore[id]!, after: changedAfter[id]!),
      },
      deletedRelations: deletedRelations.values.toList(),
      relations: [
        for (final relation in archivedRelations.values)
          _CascadedRelationScopeChange(
            relation,
            relation_domain.RelationScope.archived,
            changedAt,
          ),
      ],
      counts: await _readVerifiedRelationCountsFor({...changed, ...ends}),
    );
  }

  /// Записывает восстановление в порядке, которого требуют триггеры (D8):
  /// возвращает намерения [restored] и делает [returnedAsMain] главным, затем
  /// возвращает архивные связи [restored] с активными намерениями и связь
  /// [restoredRelation]. Каждая изменённая строка получает одно показание
  /// [clock]. После записи проверяется инвариант вида по вернувшимся
  /// намерениям и участникам вернувшихся связей.
  Future<_CascadeWrite> _writeRestoreCascade({
    required List<IntentionId> restored,
    LongTermRelationId? restoredRelation,
    required IntentionId? returnedAsMain,
    required _GraphWriteClock clock,
  }) async {
    final restoredBefore = await _catalogEntrySnapshots(restored);
    final changedAt = relation_domain.RelationTimestamp(clock.read());
    final storedAt = changedAt.value.microsecondsSinceEpoch;

    await _updateCascadeRows(
      '''UPDATE intentions SET is_archived = 0, updated_at = ?
         WHERE is_archived = 1 AND id IN''',
      [for (final id in restored) id.toCanonicalString()],
      storedAt,
      _database.intentions,
    );
    await _updateCascadeRows(
      '''UPDATE intentions SET kind = 'main', updated_at = ?
         WHERE kind = 'supporting' AND id IN''',
      [?returnedAsMain?.toCanonicalString()],
      storedAt,
      _database.intentions,
    );
    final restoredRelations = await _collectRelationsOf(
      restored,
      _CascadeRelationSelection.archivedBetweenActive,
      also: restoredRelation,
    );
    await _updateCascadeRows(
      '''UPDATE long_term_relations SET is_archived = 0, updated_at = ?
         WHERE is_archived = 1 AND id IN''',
      [for (final id in restoredRelations.keys) id.toCanonicalString()],
      storedAt,
      _database.longTermRelations,
    );

    final ends = <IntentionId>{
      for (final relation in restoredRelations.values) ...[
        relation.sourceIntentionId,
        relation.relatedIntentionId,
      ],
    };
    await _requireKindInvariant({...restored, ...ends});
    final restoredAfter = await _catalogEntrySnapshots(restored);
    return _CascadeWrite(
      deleted: const {},
      intentions: {
        for (final id in restored)
          id: (before: restoredBefore[id]!, after: restoredAfter[id]!),
      },
      deletedRelations: const [],
      relations: [
        for (final relation in restoredRelations.values)
          _CascadedRelationScopeChange(
            relation,
            relation_domain.RelationScope.active,
            changedAt,
          ),
      ],
      counts: await _readVerifiedRelationCountsFor({...restored, ...ends}),
    );
  }

  /// Связи намерений [intentions] и связь [also], отобранные по
  /// [selection], в порядке их чтения.
  Future<Map<LongTermRelationId, relation_domain.LongTermRelation>>
  _collectRelationsOf(
    List<IntentionId> intentions,
    _CascadeRelationSelection selection, {
    required LongTermRelationId? also,
  }) async {
    final relations = <LongTermRelationId, relation_domain.LongTermRelation>{};
    final scope = switch (selection) {
      _CascadeRelationSelection.any => '',
      _CascadeRelationSelection.active => 'relation.is_archived = 0 AND',
      _CascadeRelationSelection.archivedBetweenActive =>
        '''relation.is_archived = 1 AND
           EXISTS (SELECT 1 FROM intentions AS source
                   WHERE source.id = relation.source_intention_id AND
                         source.is_archived = 0) AND
           EXISTS (SELECT 1 FROM intentions AS related
                   WHERE related.id = relation.related_intention_id AND
                         related.is_archived = 0) AND''',
    };
    Future<void> collect(String where, List<String> ids) async {
      final rows = await _database
          .customSelect(
            '''SELECT relation.creation_sequence, relation.id,
                      relation.source_intention_id,
                      relation.related_intention_id, relation.type,
                      relation.priority, relation.is_archived,
                      relation.created_at, relation.updated_at
               FROM long_term_relations AS relation
               WHERE $scope $where''',
            variables: [for (final id in ids) Variable<String>(id)],
            readsFrom: {_database.longTermRelations, _database.intentions},
          )
          .get();
      for (final row in rows) {
        final relation = StoredLongTermRelation.decode(row.data).toDomain();
        relations[relation.id] = relation;
      }
    }

    for (final chunk in _cascadeChunks(intentions)) {
      final placeholders = _placeholders(chunk.length);
      await collect(
        '''(relation.source_intention_id IN ($placeholders) OR
            relation.related_intention_id IN ($placeholders))''',
        [
          for (final id in [...chunk, ...chunk]) id.toCanonicalString(),
        ],
      );
    }
    if (also != null) {
      await collect('relation.id = ?', [also.toCanonicalString()]);
    }
    return relations;
  }

  /// Выполняет [statement], оканчивающийся `IN`, частями канонических [ids]
  /// с показанием времени [storedAt]. Каждая строка должна измениться:
  /// иначе состав разошёлся с сохранённым графом.
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

  /// Удаляет строки [table] с каноническими [ids] частями. Каждая строка
  /// должна удалиться: иначе состав разошёлся с сохранённым графом.
  Future<void> _deleteCascadeRows<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<String> Function(T row) id,
    List<String> ids,
  ) async {
    for (final chunk in _cascadeChunks(ids)) {
      final deleted = await (_database.delete(
        table,
      )..where((row) => id(row).isIn(chunk))).go();
      if (deleted != chunk.length) throw const StoredGraphCorruption();
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

/// Архивирование или восстановление намерения по варианту каскада.
final class _CommittedIntentionCascadeUpdate<C extends CascadeComposition>
    extends _CommittedIntentionCommand {
  const _CommittedIntentionCascadeUpdate({
    required this.intention,
    required this.write,
    required this.executed,
  });

  final domain.Intention intention;
  final _CascadeWrite write;
  final C executed;

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

/// Архивирование или восстановление связи по варианту каскада.
final class _CommittedRelationCascadeUpdate<C extends CascadeComposition>
    extends _CommittedLongTermRelationCommand {
  const _CommittedRelationCascadeUpdate({
    required this.before,
    required this.relation,
    required this.description,
    required this.write,
    required this.executed,
  });

  final relation_domain.LongTermRelation before;
  final relation_domain.LongTermRelation relation;
  final LongTermRelationDescription? description;
  final _CascadeWrite write;
  final C executed;

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

final class _CommittedIntentionDeleteCascade
    extends _CommittedIntentionCommand {
  const _CommittedIntentionDeleteCascade({
    required this.id,
    required this.write,
    required this.executed,
  });

  final IntentionId id;
  final _CascadeWrite write;
  final DeleteCascadeComposition executed;

  @override
  IntentionId get intentionId => id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) {
    // Предмет удалён первым, поэтому первая мутация каталога — его.
    final [subject, ...others] = write.catalogMutations(revision);
    return IntentionDeleted(
      id,
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

final class _CommittedRelationDeleteCascade
    extends _CommittedLongTermRelationCommand {
  const _CommittedRelationDeleteCascade({
    required this.relation,
    required this.write,
    required this.executed,
  });

  final relation_domain.LongTermRelation relation;
  final _CascadeWrite write;
  final DeleteCascadeComposition executed;

  @override
  bool get didMutate => true;

  @override
  LongTermRelationDeleted toSuccess(GraphRevision revision) =>
      LongTermRelationDeleted(
        relation: relation,
        changes: [
          ...write.relationChanges(revision),
          ...write.catalogMutations(revision),
          IntentionHoldingChanged(revision: revision),
          CascadeOutcome(revision: revision, executed: executed),
        ],
      );
}
