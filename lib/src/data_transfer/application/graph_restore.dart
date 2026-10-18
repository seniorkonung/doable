import 'dart:async';

import '../../data/local/sqlite_failure_classifier.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_change_summary.dart';
import '../../graph_snapshots/graph_log_compaction.dart';
import '../../graph_snapshots/graph_snapshot_store.dart';
import 'graph_replacement.dart';

/// Что изменилось в графе с резервной копии до текущего состояния.
sealed class GraphChangesSinceBackup {
  const GraphChangesSinceBackup();
}

/// Изменения посчитаны по фактам лога между позицией копии и текущей: числа
/// добавленных, изменённых и удалённых сущностей, нулевые без изменений, или
/// признак замены графа.
final class GraphChangesSinceBackupCounted extends GraphChangesSinceBackup {
  const GraphChangesSinceBackupCounted(this.summary);

  final GraphChangeSummary summary;
}

/// Изменения не посчитаны: копии уже нет или подсчёт отказал. Это не
/// отсутствие изменений.
final class GraphChangesSinceBackupUncounted extends GraphChangesSinceBackup {
  const GraphChangesSinceBackupUncounted();
}

/// Фаза восстановления копии.
enum GraphRestorePhase {
  /// Состояние копии пишется в снимок замены; команды графа принимаются.
  snapshotWrite,

  /// Граф заменяется снимком замены в монопольном режиме координатора.
  replacement,
}

/// Ход восстановления копии: фаза и доля обработанных в ней записей от 0 до 1.
final class GraphRestoreProgress {
  const GraphRestoreProgress(this.phase, this.share);

  final GraphRestorePhase phase;
  final double share;
}

/// Восстановление резервной копии атомарной заменой всего графа её
/// состоянием (ADR-0036).
///
/// Фаза 1 под отметкой чтения истории проверяет, что копия ещё хранится, и
/// пишет её состояние в снимок замены в отдельном изоляте; команды графа в это
/// время подтверждаются как обычно. Фаза 2 заменяет граф этим снимком в
/// монопольном режиме координатора, а прежнее состояние транзакция замены
/// сохраняет копией перед заменой.
final class GraphRestore {
  GraphRestore({
    required this._backups,
    required this._compaction,
    required this._replacement,
    required this._snapshotFiles,
  });

  final GraphBackupRegistry _backups;

  /// Сжатие лога фактов, которое ведёт отметки чтения истории и пишет снимок
  /// замены.
  final GraphLogCompaction _compaction;
  final GraphReplacement _replacement;

  /// Завершается, когда из каталога снимков удалены незарегистрированные
  /// файлы прежних запусков. Снимок замены пишется только после этого, иначе
  /// очистка удалила бы его до регистрации.
  final Future<void> _snapshotFiles;

  /// Считает изменения графа с копии [backup] до текущего состояния по тем же
  /// правилам, что и сводки копий, — только по фактам пакетов лога.
  ///
  /// Копия ищется в реестре под отметкой чтения истории, поэтому найденная
  /// копия сохраняет пакеты после своей позиции до конца подсчёта. Копия,
  /// которой уже нет, и отказ подсчёта дают
  /// [GraphChangesSinceBackupUncounted].
  Future<GraphChangesSinceBackup> countChangesSince(
    GraphBackupEntry backup,
  ) async {
    try {
      return await _compaction.readHistory((history) async {
        if (!await _isStored(backup)) {
          return const GraphChangesSinceBackupUncounted();
        }
        final tally = await GraphChangeTally.ofRange(
          history,
          after: backup.position,
          upTo: await history.readCurrentPosition(),
        );
        return GraphChangesSinceBackupCounted(tally.summary);
      });
    } on Object {
      return const GraphChangesSinceBackupUncounted();
    }
  }

  /// Заменяет граф состоянием копии [backup]; саму замену выполняет
  /// [exclusive] принятого координатором восстановления.
  ///
  /// [onProgress] получает ход обеих фаз. Завершение [cancelled] прекращает
  /// запись снимка замены между записями, а замену — между пакетами
  /// операторов, откатывая её транзакцию. Копия, которую к началу
  /// восстановления уже удалило окно хранения, даёт отказ. Нехватка места на
  /// устройстве в любой фазе даёт [GraphBackupRestoreStorageFull]. После
  /// отказа и отмены граф, копии и реестр снимков остаются прежними, а файл
  /// снимка замены удаляется.
  Future<GraphBackupRestoreOutcome> restore(
    GraphBackupEntry backup,
    GraphExclusiveReplacement exclusive, {
    required void Function(GraphRestoreProgress progress) onProgress,
    required Future<void> cancelled,
  }) async {
    var isCancelled = false;
    unawaited(cancelled.then((_) => isCancelled = true));
    UnregisteredGraphSnapshot? snapshot;
    try {
      await _snapshotFiles;
      final written = await _writeSnapshot(
        backup,
        onProgress: (share) => onProgress(
          GraphRestoreProgress(GraphRestorePhase.snapshotWrite, share),
        ),
        cancelled: cancelled,
      );
      snapshot = written;
      return await exclusive.replace(() {
        onProgress(
          const GraphRestoreProgress(GraphRestorePhase.replacement, 0),
        );
        return _replacement.replaceGraph(
          written,
          onProgress: (share) => onProgress(
            GraphRestoreProgress(GraphRestorePhase.replacement, share),
          ),
          isCancelled: () => isCancelled,
        );
      });
    } on GraphReplacementSnapshotCancelled {
      // Запись снимка замены при отмене удаляет свой файл.
      return const GraphBackupRestoreCancelled();
    } on GraphReplacementCancelled {
      await snapshot?.delete();
      return const GraphBackupRestoreCancelled();
    } on Object catch (error) {
      await snapshot?.delete();
      return switch (classifySqliteFailure(error)) {
        SqliteStorageFullFailure() => const GraphBackupRestoreStorageFull(),
        _ => const GraphBackupRestoreFailed(),
      };
    }
  }

  /// Пишет состояние на позиции копии [backup] в снимок замены, если копия
  /// хранится: найденная под отметкой чтения истории, она сохраняет базовый
  /// снимок своего состояния и пакеты после него до конца записи.
  Future<UnregisteredGraphSnapshot> _writeSnapshot(
    GraphBackupEntry backup, {
    required void Function(double share) onProgress,
    required Future<void> cancelled,
  }) => _compaction.readHistory((history) async {
    if (!await _isStored(backup)) throw const _GraphBackupNotStored();
    return _compaction.writeReplacementSnapshot(
      await history.selectStateAt(backup.position),
      onProgress: onProgress,
      cancelled: cancelled,
    );
  });

  /// Хранится ли копия [backup] в реестре. Отказ чтения реестра передаётся
  /// исключением.
  Future<bool> _isStored(GraphBackupEntry backup) async =>
      (await _backups.readBackups()).any((stored) => stored.id == backup.id);
}

/// Копию уже удалило окно хранения.
final class _GraphBackupNotStored implements Exception {
  const _GraphBackupNotStored();
}
