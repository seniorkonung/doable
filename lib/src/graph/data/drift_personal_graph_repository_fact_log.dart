part of 'drift_personal_graph_repository.dart';

extension _GraphFactLogAccess on DriftPersonalGraphRepository {
  /// Позиции выдаёт AUTOINCREMENT, а sqlite_sequence хранит наибольшую
  /// выданную, поэтому позиция сохраняется и после удаления пакетов границей
  /// хранения.
  Future<int> _readCurrentLogPosition() =>
      _sequencer.run(_selectCurrentLogPosition);

  Future<int> _selectCurrentLogPosition() async {
    final row = await _database
        .customSelect(
          "SELECT seq FROM sqlite_sequence WHERE name = 'graph_log_packages'",
        )
        .getSingleOrNull();
    return row?.read<int>('seq') ?? 0;
  }

  Future<List<StoredGraphLogPackage>> _readStoredLogPackages({
    required int after,
    required int upTo,
  }) =>
      _sequencer.run(() => _selectStoredLogPackages(after: after, upTo: upTo));

  Future<List<StoredGraphLogPackage>> _selectStoredLogPackages({
    required int after,
    required int upTo,
  }) async {
    final rows =
        await (_database.select(_database.graphLogPackages)
              ..where(
                (package) =>
                    package.position.isBiggerThanValue(after) &
                    package.position.isSmallerOrEqualValue(upTo),
              )
              ..orderBy([(package) => OrderingTerm.asc(package.position)])
              ..limit(graphFactLogPortionLimit))
            .get();
    return [for (final row in rows) _storedLogPackage(row)];
  }

  /// Хранилище снимков не зависит от данных графа, поэтому строку вне формы
  /// хранения оно получает отказом контракта лога, а не общего декодера.
  Future<GraphRecordPortion> _readGraphRecords(
    GraphRecordOrderKey? after,
  ) async {
    try {
      return await _readGraphRecordPortion(after);
    } on StoredGraphCorruption catch (_, stackTrace) {
      Error.throwWithStackTrace(const GraphRecordCorruption(), stackTrace);
    }
  }

  /// Порция заполняется секциями по порядку файла формата, поэтому неполная
  /// порция дошла до конца последней секции. Транзакция согласует строки
  /// порции, в том числе дневные выборы с шагами их путей, с позицией лога.
  Future<GraphRecordPortion> _readGraphRecordPortion(
    GraphRecordOrderKey? after,
  ) => _sequencer.run(
    () => _database.transaction(() async {
      final position = await _selectCurrentLogPosition();
      final sections = <Future<List<_OrderedRecord>> Function(int limit)>[
        (limit) => _readTagRecords(
          after: after is TagOrderKey ? after.creationSequence : 0,
          limit: limit,
        ),
        (limit) => _readIntentionRecords(
          after: after is IntentionOrderKey ? after : null,
          limit: limit,
        ),
        (limit) => _readTagAssignmentRecords(
          after: after is TagAssignmentOrderKey ? after.creationSequence : 0,
          limit: limit,
        ),
        (limit) => _readRelationRecords(
          after: after is LongTermRelationOrderKey ? after.creationSequence : 0,
          limit: limit,
        ),
        (limit) => _readDailyChoiceRecords(
          after: after is DailyChoiceOrderKey ? after.creationSequence : 0,
          limit: limit,
        ),
      ];
      final firstSection = switch (after) {
        null || TagOrderKey() => 0,
        IntentionOrderKey() => 1,
        TagAssignmentOrderKey() => 2,
        LongTermRelationOrderKey() => 3,
        DailyChoiceOrderKey() => 4,
      };
      final records = <_OrderedRecord>[];
      for (final read in sections.skip(firstSection)) {
        records.addAll(await read(graphFactLogPortionLimit - records.length));
        if (records.length == graphFactLogPortionLimit) break;
      }
      return GraphRecordPortion(
        position: position,
        records: [for (final (_, record) in records) record],
        next: records.length < graphFactLogPortionLimit
            ? null
            : records.last.$1,
      );
    }),
  );

  Future<List<_OrderedRecord>> _readTagRecords({
    required int after,
    required int limit,
  }) async {
    final rows = await _database
        .customSelect(
          '''SELECT creation_sequence, id, name, color, position FROM tags
         WHERE creation_sequence > ?
         ORDER BY creation_sequence
         LIMIT ?''',
          variables: [Variable.withInt(after), Variable.withInt(limit)],
          readsFrom: {_database.tags},
        )
        .get();
    return [
      for (final row in rows)
        (
          TagOrderKey(row.read<int>('creation_sequence')),
          TagRecord(decodeStoredTag(row.data)),
        ),
    ];
  }

  /// Порядок намерений — время создания и идентификатор; отдельное
  /// сравнение времени ограничивает обход индекса этого порядка.
  Future<List<_OrderedRecord>> _readIntentionRecords({
    required IntentionOrderKey? after,
    required int limit,
  }) async {
    final (afterKey, keyVariables) = switch (after) {
      null => ('', const <Variable<Object>>[]),
      IntentionOrderKey(:final createdAt, :final id) => (
        'WHERE created_at >= ? AND (created_at > ? OR id > ?)',
        [
          Variable.withInt(createdAt.value.microsecondsSinceEpoch),
          Variable.withInt(createdAt.value.microsecondsSinceEpoch),
          Variable.withString(id.toCanonicalString()),
        ],
      ),
    };
    final rows = await _database
        .customSelect(
          '''SELECT id, title, description, is_action_ready, is_archived,
                created_at, updated_at
         FROM intentions
         $afterKey
         ORDER BY created_at, id
         LIMIT ?''',
          variables: [...keyVariables, Variable.withInt(limit)],
          readsFrom: {_database.intentions},
        )
        .get();
    return [for (final row in rows) _orderedIntention(row)];
  }

  _OrderedRecord _orderedIntention(QueryRow row) {
    final intention = decodeStoredIntention(row.data);
    return (
      IntentionOrderKey(createdAt: intention.createdAt, id: intention.id),
      IntentionRecord(intention),
    );
  }

  Future<List<_OrderedRecord>> _readTagAssignmentRecords({
    required int after,
    required int limit,
  }) async {
    final rows = await _database
        .customSelect(
          '''SELECT creation_sequence, tag_id, intention_id
         FROM tag_assignments
         WHERE creation_sequence > ?
         ORDER BY creation_sequence
         LIMIT ?''',
          variables: [Variable.withInt(after), Variable.withInt(limit)],
          readsFrom: {_database.tagAssignments},
        )
        .get();
    return [
      for (final row in rows)
        (
          TagAssignmentOrderKey(row.read<int>('creation_sequence')),
          TagAssignmentRecord(decodeStoredTagAssignment(row.data)),
        ),
    ];
  }

  Future<List<_OrderedRecord>> _readRelationRecords({
    required int after,
    required int limit,
  }) async {
    final rows = await _database
        .customSelect(
          '''SELECT creation_sequence, id, source_intention_id,
                related_intention_id, type, priority, description, is_archived
         FROM long_term_relations
         WHERE creation_sequence > ?
         ORDER BY creation_sequence
         LIMIT ?''',
          variables: [Variable.withInt(after), Variable.withInt(limit)],
          readsFrom: {_database.longTermRelations},
        )
        .get();
    final relations = [
      for (final row in rows) StoredLongTermRelation.decode(row.data),
    ];
    return [
      for (final relation in relations)
        (
          LongTermRelationOrderKey(relation.creationSequence),
          storedRelationRecord(relation),
        ),
    ];
  }

  Future<List<_OrderedRecord>> _readDailyChoiceRecords({
    required int after,
    required int limit,
  }) async {
    final rows = await _database
        .customSelect(
          '''SELECT creation_sequence, id, source_intention_id,
                selected_intention_id, choice_date, description, is_completed,
                scheduled_minute, priority
         FROM daily_choices
         WHERE creation_sequence > ?
         ORDER BY creation_sequence
         LIMIT ?''',
          variables: [Variable.withInt(after), Variable.withInt(limit)],
          readsFrom: {_database.dailyChoices},
        )
        .get();
    if (rows.isEmpty) return const [];
    final paths = await readStoredChoicePaths(
      _database,
      choiceIds:
          'SELECT id FROM daily_choices '
          'WHERE creation_sequence > ? AND creation_sequence <= ?',
      variables: [
        Variable.withInt(after),
        Variable.withInt(rows.last.read<int>('creation_sequence')),
      ],
      readsFrom: {_database.dailyChoices},
    );
    return [
      for (final row in rows)
        (
          DailyChoiceOrderKey(row.read<int>('creation_sequence')),
          storedDailyChoiceRecord(decodeStoredDailyChoice(row.data), paths),
        ),
    ];
  }

  Future<GraphSnapshotEntry?> _readSnapshotAtOrBefore(int position) =>
      _sequencer.run(() async {
        final row = await _newestSnapshotQuery(atOrBefore: position)
            .getSingleOrNull();
        return row == null ? null : _snapshotEntry(row);
      });

  Future<Set<String>> _readSnapshotFileNames() => _sequencer.run(() async {
    final snapshots = _database.graphSnapshots;
    final rows = await (_database.selectOnly(
      snapshots,
    )..addColumns([snapshots.fileName])).get();
    return {for (final row in rows) row.read(snapshots.fileName)!};
  });

  Future<void> _registerSnapshot(GraphSnapshotEntry snapshot) =>
      _sequencer.run(() async {
        await _insertSnapshotRow(snapshot);
      });

  /// Вставляет строку реестра снимков и возвращает её номер.
  Future<int> _insertSnapshotRow(GraphSnapshotEntry snapshot) => _database
      .into(_database.graphSnapshots)
      .insert(
        local.GraphSnapshotsCompanion.insert(
          position: snapshot.position,
          fileName: snapshot.fileName,
          byteSize: snapshot.byteSize,
          checksum: snapshot.checksum,
        ),
      );

  /// Позиции копий читает та же транзакция, поэтому копия, записанная до
  /// неё, сохраняет свою историю, а её восстановление воспроизводит пакеты
  /// только после её ближайшего снимка. После удаления пакетов до базового
  /// снимка границы в логе остаются только сохраняемые пакеты «сброс», а
  /// схема не даёт удалить снимок, на который они ссылаются.
  Future<List<String>> _removeHistoryBefore(
    int boundary,
    Iterable<GraphSnapshotEntry> retained,
  ) => _sequencer.run(
    () => _database.transaction(() async {
      final latest = await _newestSnapshotQuery().getSingleOrNull();
      if (latest == null) return const [];
      final backups = _database.graphBackups;
      final oldestBackup = backups.position.min();
      final oldestBackupPosition =
          await (_database.selectOnly(backups)..addColumns([oldestBackup]))
              .map((row) => row.read(oldestBackup))
              .getSingle();
      final base = await _newestSnapshotQuery(
        atOrBefore: min(boundary, oldestBackupPosition ?? boundary),
      ).getSingleOrNull();
      // У копии, сделанной до первого снимка, ближайшего снимка нет.
      final backupSnapshotIds = await _database
          .customSelect(
            '''SELECT DISTINCT (
                 SELECT id FROM graph_snapshots
                 WHERE position <= graph_backups.position
                 ORDER BY position DESC, id DESC
                 LIMIT 1
               ) AS snapshot_id
             FROM graph_backups''',
            readsFrom: {backups, _database.graphSnapshots},
          )
          .map((row) => row.read<int?>('snapshot_id'))
          .get();
      final packages = _database.graphLogPackages;
      if (base != null) {
        await (_database.delete(packages)..where(
              (package) =>
                  package.position.isSmallerOrEqualValue(base.position),
            ))
            .go();
      }
      final resetSnapshots = _database.selectOnly(packages)
        ..addColumns([packages.snapshotId])
        ..where(packages.snapshotId.isNotNull());
      final retainedFileNames = [for (final entry in retained) entry.fileName];
      final removed =
          await (_database.delete(_database.graphSnapshots)..where(
                (snapshot) =>
                    snapshot.id.isNotIn([
                      latest.id,
                      ?base?.id,
                      ...backupSnapshotIds.nonNulls,
                    ]) &
                    snapshot.fileName.isNotIn(retainedFileNames) &
                    snapshot.id.isNotInQuery(resetSnapshots),
              ))
              .goAndReturn();
      return [for (final snapshot in removed) snapshot.fileName];
    }),
  );

  /// Последний снимок, а с [atOrBefore] — ближайший не новее этой позиции;
  /// из снимков одной позиции выбирается зарегистрированный последним.
  Selectable<local.RegisteredGraphSnapshot> _newestSnapshotQuery({
    int? atOrBefore,
  }) {
    final query = _database.select(_database.graphSnapshots)
      ..orderBy([
        (snapshot) => OrderingTerm.desc(snapshot.position),
        (snapshot) => OrderingTerm.desc(snapshot.id),
      ])
      ..limit(1);
    if (atOrBefore != null) {
      query.where(
        (snapshot) => snapshot.position.isSmallerOrEqualValue(atOrBefore),
      );
    }
    return query;
  }
}

/// Запись графа с ключом порядка её строки.
typedef _OrderedRecord = (GraphRecordOrderKey, GraphEntityRecord);

/// Схема гарантирует пакету «изменение» версию формата и факты.
StoredGraphLogPackage _storedLogPackage(local.GraphLogPackage row) =>
    switch (row) {
      local.GraphLogPackage(
        kind: 'change',
        :final position,
        :final formatVersion?,
        :final facts?,
      ) =>
        StoredGraphChangePackage(
          position: position,
          formatVersion: formatVersion,
          facts: facts,
        ),
      local.GraphLogPackage(kind: 'reset', :final position) =>
        StoredGraphResetPackage(position: position),
      _ => throw StateError('Пакет лога вне схемы.'),
    };

GraphSnapshotEntry _snapshotEntry(local.RegisteredGraphSnapshot row) =>
    GraphSnapshotEntry(
      position: row.position,
      fileName: row.fileName,
      byteSize: row.byteSize,
      checksum: row.checksum,
    );
