import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'encoded_diagnostics_log.dart';
import 'in_memory_diagnostics_sink.dart';

const graphSnapshotWorkerDatabasePath = 'DOABLE_SNAPSHOT_DATABASE_PATH';
const graphSnapshotWorkerDirectoryPath = 'DOABLE_SNAPSHOT_DIRECTORY_PATH';
const graphSnapshotWorkerStopPoint = 'DOABLE_SNAPSHOT_STOP_POINT';
const graphSnapshotWorkerStarted = 'DOABLE_SNAPSHOT_WORKER_STARTED';
const graphSnapshotWorkerReady = 'DOABLE_SNAPSHOT_WORKER_READY';

/// Порог сжатия дочернего процесса и проверок после него: несколько пакетов
/// вместо производственного значения.
const graphSnapshotWorkerThreshold = 3;

/// Точка записи снимка, в которой дочерний процесс останавливается до
/// принудительного завершения.
enum GraphSnapshotStopPoint {
  beforeRename('before_rename'),
  beforeRegistration('before_registration'),
  afterRegistration('after_registration');

  const GraphSnapshotStopPoint(this.environmentValue);

  final String environmentValue;

  static GraphSnapshotStopPoint parse(String? value) => values.firstWhere(
    (stopPoint) => stopPoint.environmentValue == value,
    orElse: () => throw StateError('Неизвестная точка остановки: $value.'),
  );
}

void main() {
  test(
    'дочерний процесс останавливается в заданной точке записи снимка',
    () async {
      stdout.writeln('$graphSnapshotWorkerStarted:$pid');
      await stdout.flush();
      final databasePath =
          Platform.environment[graphSnapshotWorkerDatabasePath];
      final directoryPath =
          Platform.environment[graphSnapshotWorkerDirectoryPath];
      if (databasePath == null || directoryPath == null) {
        throw StateError('Не заданы параметры дочернего процесса снимков.');
      }
      final stopPoint = GraphSnapshotStopPoint.parse(
        Platform.environment[graphSnapshotWorkerStopPoint],
      );
      final database = AppDatabase(
        openFileBackedLocalDatabase(File(databasePath)),
      );
      try {
        await database.open();
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 10, 17, 12),
          InMemoryDiagnosticsSink(),
        );
        final diagnostics = EncodedDiagnosticsLog();
        // Сжатие пишет снимок в отдельном изоляте, как в приложении.
        final compaction = GraphLogCompaction(
          log: _StoppingLog(repository, stopPoint),
          directory: Directory(directoryPath),
          clock: () => DateTime.utc(2026, 10, 17, 12),
          diagnosticsSink: diagnostics,
          threshold: graphSnapshotWorkerThreshold,
          runner: switch (stopPoint) {
            GraphSnapshotStopPoint.beforeRename => _writeStoppingBeforeRename,
            GraphSnapshotStopPoint.beforeRegistration ||
            GraphSnapshotStopPoint.afterRegistration =>
              runGraphSnapshotWriteInIsolate,
          },
        )..start();
        await compaction.shutdown();
        throw StateError(
          'Сжатие завершилось до точки остановки: ${diagnostics.events}.',
        );
      } finally {
        await database.close();
      }
    },
    timeout: Timeout.none,
  );
}

/// Лог фактов, который останавливает процесс до или после регистрации
/// снимка.
final class _StoppingLog implements ObservableGraphFactLog {
  _StoppingLog(this._log, this._stopPoint);

  final ObservableGraphFactLog _log;
  final GraphSnapshotStopPoint _stopPoint;

  @override
  Stream<int> get confirmedPositions => _log.confirmedPositions;

  @override
  Future<int> readCurrentPosition() => _log.readCurrentPosition();

  @override
  Future<List<StoredGraphFactPackage>> readPackages({
    required int after,
    required int upTo,
  }) => _log.readPackages(after: after, upTo: upTo);

  @override
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after}) =>
      _log.readGraphRecords(after: after);

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) =>
      _log.readSnapshotAtOrBefore(position);

  @override
  Future<Set<String>> readSnapshotFileNames() => _log.readSnapshotFileNames();

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) async {
    if (_stopPoint == GraphSnapshotStopPoint.beforeRegistration) {
      await _reportReadyAndWait();
    }
    await _log.registerSnapshot(snapshot);
    if (_stopPoint == GraphSnapshotStopPoint.afterRegistration) {
      await _reportReadyAndWait();
    }
  }

  @override
  Future<List<String>> removeHistoryBefore(int boundary) =>
      _log.removeHistoryBefore(boundary);
}

/// Пишет снимок в отдельном изоляте, как [runGraphSnapshotWriteInIsolate],
/// но останавливает процесс перед переименованием временного файла.
///
/// Отдельная функция не захватывает лог и базу замыканием изолята.
Future<GraphSnapshotEntry> _writeStoppingBeforeRename(
  GraphSnapshotWrite write,
) => Isolate.run(
  () => IOOverrides.runWithIOOverrides(write.run, _StopBeforeRename()),
);

/// Подменяет временные файлы изолята записи так, что переименование
/// записанного и сброшенного на диск файла останавливает процесс.
final class _StopBeforeRename extends IOOverrides {
  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('.tmp') ? _TemporaryFileStoppingAtRename(file) : file;
  }
}

/// Временный файл снимка: запись и удаление идут в настоящий файл, а
/// переименование не выполняется.
final class _TemporaryFileStoppingAtRename implements File {
  _TemporaryFileStoppingAtRename(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Uri get uri => _file.uri;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _file.open(mode: mode);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);

  @override
  Future<File> rename(String newPath) => _reportReadyAndWait();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Временный файл снимка не поддерживает ${invocation.memberName}.',
  );
}

Future<Never> _reportReadyAndWait() async {
  stdout.writeln('$graphSnapshotWorkerReady:$pid');
  await stdout.flush();
  await Completer<void>().future;
  throw StateError('Недостижимое завершение ожидания процесса снимков.');
}
