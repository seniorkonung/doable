import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_diagnostics_sink.dart';

const graphReplacementWorkerDatabasePath = 'DOABLE_REPLACEMENT_DATABASE_PATH';
const graphReplacementWorkerDirectoryPath = 'DOABLE_REPLACEMENT_DIRECTORY_PATH';
const graphReplacementWorkerStopPoint = 'DOABLE_REPLACEMENT_STOP_POINT';
const graphReplacementWorkerStarted = 'DOABLE_REPLACEMENT_WORKER_STARTED';

/// Маркер остановки: за ним идут pid процесса и последняя доля хода замены,
/// по которой проверка видит, где процесс остановился.
const graphReplacementWorkerReady = 'DOABLE_REPLACEMENT_WORKER_READY';

/// Точка замены графа, в которой дочерний процесс останавливается до
/// принудительного завершения.
enum GraphReplacementStopPoint {
  /// Прежний граф удалён, записи снимка ещё не вставлены.
  afterDeletion('after_deletion'),

  /// Первый пакет записей снимка вставлен, следующий — нет.
  midInsertion('mid_insertion'),

  /// Выполнен последний оператор транзакции замены, COMMIT — нет.
  beforeCommit('before_commit'),

  /// Транзакция замены подтверждена.
  afterCommit('after_commit');

  const GraphReplacementStopPoint(this.environmentValue);

  final String environmentValue;

  static GraphReplacementStopPoint parse(String? value) => values.firstWhere(
    (stopPoint) => stopPoint.environmentValue == value,
    orElse: () => throw StateError('Неизвестная точка остановки: $value.'),
  );
}

void main() {
  test('дочерний процесс восстанавливает последнюю копию и останавливается в '
      'заданной точке замены графа', () async {
    stdout.writeln('$graphReplacementWorkerStarted:$pid');
    await stdout.flush();
    final databasePath =
        Platform.environment[graphReplacementWorkerDatabasePath];
    final directoryPath =
        Platform.environment[graphReplacementWorkerDirectoryPath];
    if (databasePath == null || directoryPath == null) {
      throw StateError('Не заданы параметры дочернего процесса замены.');
    }
    final probe = _StoppingProbe(
      GraphReplacementStopPoint.parse(
        Platform.environment[graphReplacementWorkerStopPoint],
      ),
    );
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(File(databasePath)),
        probe,
      ),
    );
    try {
      await database.open();
      DateTime clock() => DateTime.utc(2026, 10, 18, 12);
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        clock,
        InMemoryDiagnosticsSink(),
      );
      final compaction = GraphLogCompaction(
        log: repository,
        directory: Directory(directoryPath),
        clock: clock,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      final backup = switch (await repository.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups.first,
        GraphBackupsReadFailed() => throw StateError(
          'Список копий не прочитан.',
        ),
      };
      // Снимок замены пишется в отдельном изоляте, как при восстановлении
      // копии в приложении.
      final snapshot = await compaction.readHistory(
        (history) async => compaction.writeReplacementSnapshot(
          await history.selectStateAt(backup.position),
          onProgress: (_) {},
          cancelled: Completer<void>().future,
        ),
      );
      probe.replacing = true;
      await repository.replaceGraph(
        snapshot,
        onProgress: (share) => probe.share = share,
        cancellation: GraphReplacementCancellation(),
      );
      if (probe.stopPoint == GraphReplacementStopPoint.afterCommit) {
        await probe.reportReadyAndWait();
      }
      throw StateError('Замена графа завершилась до точки остановки.');
    } finally {
      await database.close();
    }
  }, timeout: Timeout.none);
}

/// Останавливает процесс на операторе транзакции замены графа, который
/// отвечает точке [stopPoint].
final class _StoppingProbe extends LocalDatabaseConnectionObserver {
  _StoppingProbe(this.stopPoint);

  final GraphReplacementStopPoint stopPoint;

  /// Замена началась: операторы до неё читают лог для снимка замены.
  var replacing = false;

  /// Последняя доля хода замены.
  var share = 0.0;

  var _batches = 0;
  var _captureSwitches = 0;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (!replacing || statement.operation != LocalDatabaseSqlOperation.batch) {
      return;
    }
    // Записи снимка вставляются пакетами операторов после удаления всего
    // прежнего графа.
    _batches++;
    if (switch (stopPoint) {
      GraphReplacementStopPoint.afterDeletion => _batches == 1,
      GraphReplacementStopPoint.midInsertion => _batches == 2,
      GraphReplacementStopPoint.beforeCommit ||
      GraphReplacementStopPoint.afterCommit => false,
    }) {
      await reportReadyAndWait();
    }
  }

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if (!replacing ||
        stopPoint != GraphReplacementStopPoint.beforeCommit ||
        statement.operation != LocalDatabaseSqlOperation.update ||
        !statement.statements.single.contains('graph_log_control')) {
      return;
    }
    // Замена выключает захват первым оператором транзакции и включает
    // последним.
    if (++_captureSwitches == 2) await reportReadyAndWait();
  }

  Future<Never> reportReadyAndWait() async {
    stdout.writeln('$graphReplacementWorkerReady:$pid:$share');
    await stdout.flush();
    await Completer<void>().future;
    throw StateError('Недостижимое завершение ожидания процесса замены.');
  }
}
