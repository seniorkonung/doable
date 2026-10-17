part of 'drift_personal_graph_repository.dart';

extension _GraphFactLogAccess on DriftPersonalGraphRepository {
  /// Позиции выдаёт AUTOINCREMENT, а sqlite_sequence хранит наибольшую
  /// выданную, поэтому позиция сохраняется и после удаления пакетов границей
  /// хранения.
  Future<int> _readCurrentLogPosition() => _sequencer.run(() async {
    final row = await _database
        .customSelect(
          "SELECT seq FROM sqlite_sequence WHERE name = 'graph_log_packages'",
        )
        .getSingleOrNull();
    return row?.read<int>('seq') ?? 0;
  });

  Future<List<StoredGraphFactPackage>> _readStoredFactPackages({
    required int after,
    required int upTo,
  }) => _sequencer.run(() async {
    final packages = _database.graphLogPackages;
    final rows =
        await (_database.select(packages)
              ..where(
                (package) =>
                    package.position.isBiggerThanValue(after) &
                    package.position.isSmallerOrEqualValue(upTo),
              )
              ..orderBy([(package) => OrderingTerm.asc(package.position)])
              ..limit(graphFactLogPortionLimit))
            .get();
    return [for (final row in rows) _storedFactPackage(row)];
  });

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
        await _database
            .into(_database.graphSnapshots)
            .insert(
              local.GraphSnapshotsCompanion.insert(
                position: snapshot.position,
                formatVersion: snapshot.formatVersion,
                fileName: snapshot.fileName,
                byteSize: snapshot.byteSize,
                checksum: snapshot.checksum,
              ),
            );
      });

  Future<List<String>> _removeHistoryBefore(int boundary) => _sequencer.run(
    () => _database.transaction(() async {
      final latest = await _newestSnapshotQuery().getSingleOrNull();
      if (latest == null) return const [];
      final base = await _newestSnapshotQuery(atOrBefore: boundary)
          .getSingleOrNull();
      if (base != null) {
        await (_database.delete(_database.graphLogPackages)..where(
              (package) =>
                  package.position.isSmallerOrEqualValue(base.position),
            ))
            .go();
      }
      final removed =
          await (_database.delete(_database.graphSnapshots)..where(
                (snapshot) => snapshot.id.isNotIn([latest.id, ?base?.id]),
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

/// Пакеты «сброс» пишет только замена графа, а хранилище снимков их пока не
/// читает. Схема гарантирует пакету «изменение» версию формата и факты.
StoredGraphFactPackage _storedFactPackage(local.GraphLogPackage row) =>
    switch (row) {
      local.GraphLogPackage(
        kind: 'change',
        :final position,
        :final formatVersion?,
        :final facts?,
      ) =>
        StoredGraphFactPackage(
          position: position,
          formatVersion: formatVersion,
          facts: facts,
        ),
      _ => throw StateError('Пакет лога не является пакетом «изменение».'),
    };

GraphSnapshotEntry _snapshotEntry(local.RegisteredGraphSnapshot row) =>
    GraphSnapshotEntry(
      position: row.position,
      formatVersion: row.formatVersion,
      fileName: row.fileName,
      byteSize: row.byteSize,
      checksum: row.checksum,
    );
