part of 'drift_personal_graph_repository.dart';

extension _GraphBackupRegistryAccess on DriftPersonalGraphRepository {
  /// Список меняют только записи копий в исполнителе репозитория, и каждая
  /// подтверждённая запись сообщает об этом. Поэтому подписка на сигнал
  /// появляется до первого чтения, а записи во время чтения дают одно
  /// следующее чтение.
  Stream<GraphBackupsRead> _watchBackups() {
    late final StreamController<GraphBackupsRead> controller;
    StreamSubscription<void>? changes;
    var isObserving = true;
    var isChanged = true;
    var isReading = false;

    Future<void> readWhileChanged() async {
      isReading = true;
      try {
        while (isChanged && isObserving) {
          isChanged = false;
          final read = await _readBackups();
          if (!isObserving) return;
          controller.add(read);
          if (read is GraphBackupsReadFailed) {
            isObserving = false;
            unawaited(changes?.cancel());
            unawaited(controller.close());
          }
        }
      } finally {
        isReading = false;
      }
    }

    controller = StreamController(
      onListen: () {
        changes = _backupsChanged.stream.listen((_) {
          isChanged = true;
          if (!isReading) unawaited(readWhileChanged());
        });
        unawaited(readWhileChanged());
      },
      onCancel: () {
        isObserving = false;
        return changes?.cancel();
      },
    );
    return controller.stream;
  }

  Future<GraphBackupsRead> _readBackups() async {
    try {
      final rows = await _sequencer.run(
        () => (_database.select(
          _database.graphBackups,
        )..orderBy([(backup) => OrderingTerm.desc(backup.id)])).get(),
      );
      return GraphBackupsReadSucceeded([
        for (final row in rows) _backupEntry(row),
      ]);
    } on Object {
      return const GraphBackupsReadFailed();
    }
  }

  Future<bool> _insertDailyBackup(DateTime dayStart, GraphChangeTally? since) =>
      _writeBackup((madeAt, position) async {
        if (!await _isDailyBackupDue(dayStart, madeAt, position)) return false;
        await _insertBackupRow(GraphBackupKind.daily, madeAt, position, since);
        await _removeBackupsBeforeWindow();
        return true;
      });

  Future<void> _insertManualBackup(GraphChangeTally? since) =>
      _writeBackup((madeAt, position) async {
        await _insertBackupRow(GraphBackupKind.manual, madeAt, position, since);
        return true;
      });

  /// Выполняет [write] одной транзакцией в исполнителе репозитория: момент
  /// копии — показание часов в этой транзакции, а позиция — текущая в ней.
  /// Наблюдатели списка узнают о записи после подтверждения.
  Future<bool> _writeBackup(
    Future<bool> Function(DateTime madeAt, int position) write,
  ) => _sequencer.run(() async {
    final written = await _database.transaction(
      () async => write(_now(), await _selectCurrentLogPosition()),
    );
    if (written) _backupsChanged.add(null);
    return written;
  });

  /// Последняя ежедневная копия сделана в текущий день, если её момент не
  /// раньше [dayStart] и не позже [madeAt]. Копию с моментом позже [madeAt]
  /// сделали до перевода часов назад: иначе после такого перевода ежедневных
  /// копий не было бы до наступления её дня.
  Future<bool> _isDailyBackupDue(
    DateTime dayStart,
    DateTime madeAt,
    int position,
  ) async {
    final last =
        await (_database.select(_database.graphBackups)
              ..where((backup) => backup.kind.equals(_dailyBackupKind))
              ..orderBy([(backup) => OrderingTerm.desc(backup.id)])
              ..limit(1))
            .getSingleOrNull();
    if (last == null) return !(await _selectComposition()).isEmpty;
    final lastMadeAt = _backupMoment(last.madeAt);
    final isToday =
        !lastMadeAt.isBefore(dayStart) && !lastMadeAt.isAfter(madeAt);
    return !isToday && position > last.position;
  }

  Future<void> _insertBackupRow(
    GraphBackupKind kind,
    DateTime madeAt,
    int position,
    GraphChangeTally? since,
  ) async {
    final counts = switch (await _summaryUpTo(position, since)) {
      final GraphChangeCounts counts => counts,
      GraphDataReplaced() => null,
    };
    await _database
        .into(_database.graphBackups)
        .insert(
          local.GraphBackupsCompanion.insert(
            position: position,
            kind: _storedBackupKind(kind),
            madeAt: madeAt.microsecondsSinceEpoch,
            graphReplaced: counts == null,
            addedCount: Value.absentIfNull(counts?.added),
            changedCount: Value.absentIfNull(counts?.changed),
            deletedCount: Value.absentIfNull(counts?.deleted),
          ),
        );
  }

  /// Сводка с последней копии до [position]. Пакеты после конца [since], а
  /// без неё — после позиции последней копии, хранятся: граница хранения
  /// истории не позже самой старой копии.
  ///
  /// Копия без предыдущей сравнивается с пустым графом, а пакеты «сброс» не
  /// ищутся: ранняя история может быть уже сжата.
  Future<GraphChangeSummary> _summaryUpTo(
    int position,
    GraphChangeTally? since,
  ) async {
    final last =
        await (_database.select(_database.graphBackups)
              ..orderBy([(backup) => OrderingTerm.desc(backup.id)])
              ..limit(1))
            .getSingleOrNull();
    if (last == null) {
      final composition = await _selectComposition();
      return GraphChangeCounts(
        added:
            composition.intentionCount +
            composition.relationCount +
            composition.dailyChoiceCount +
            composition.tagCount,
        changed: 0,
        deleted: 0,
      );
    }
    final tally = since ?? GraphChangeTally(after: last.position);
    while (true) {
      final portion = await _selectStoredLogPackages(
        after: tally.position,
        upTo: position,
      );
      if (portion.isEmpty) return tally.summary;
      portion.map(GraphHistoryPackage.decode).forEach(tally.add);
    }
  }

  /// Удаляет копии любого вида, созданные раньше самой старой из
  /// [retainedDailyGraphBackups] последних ежедневных копий.
  Future<void> _removeBackupsBeforeWindow() async {
    final backups = _database.graphBackups;
    final oldestRetained =
        await (_database.selectOnly(backups)
              ..addColumns([backups.id])
              ..where(backups.kind.equals(_dailyBackupKind))
              ..orderBy([OrderingTerm.desc(backups.id)])
              ..limit(1, offset: retainedDailyGraphBackups - 1))
            .map((row) => row.read(backups.id)!)
            .getSingleOrNull();
    if (oldestRetained == null) return;
    await (_database.delete(
      backups,
    )..where((backup) => backup.id.isSmallerThanValue(oldestRetained))).go();
  }
}

const _dailyBackupKind = 'daily';

String _storedBackupKind(GraphBackupKind kind) => switch (kind) {
  GraphBackupKind.daily => _dailyBackupKind,
  GraphBackupKind.manual => 'manual',
  GraphBackupKind.beforeReplacement => 'before_replacement',
};

DateTime _backupMoment(int madeAt) =>
    DateTime.fromMicrosecondsSinceEpoch(madeAt, isUtc: true);

/// Схема гарантирует копии известный вид и либо полную сводку, либо признак
/// замены.
GraphBackupEntry _backupEntry(local.GraphBackup row) => GraphBackupEntry(
  kind: switch (row.kind) {
    _dailyBackupKind => GraphBackupKind.daily,
    'manual' => GraphBackupKind.manual,
    'before_replacement' => GraphBackupKind.beforeReplacement,
    _ => throw StateError('Копия вне схемы.'),
  },
  position: row.position,
  madeAt: _backupMoment(row.madeAt),
  summary: switch (row) {
    local.GraphBackup(graphReplaced: true) => const GraphDataReplaced(),
    local.GraphBackup(
      :final addedCount?,
      :final changedCount?,
      :final deletedCount?,
    ) =>
      GraphChangeCounts(
        added: addedCount,
        changed: changedCount,
        deleted: deletedCount,
      ),
    _ => throw StateError('Копия вне схемы.'),
  },
);
