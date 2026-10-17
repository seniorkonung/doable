import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';

/// Пишет снимок в отдельном изоляте, как [runGraphSnapshotWriteInIsolate],
/// но временные файлы снимка появляются, а запись в них отказывает, как при
/// нехватке места.
/// https://api.dart.dev/dart-io/IOOverrides-class.html
Future<GraphSnapshotEntry> writeGraphSnapshotFailingOnTemporaryFiles(
  GraphSnapshotWrite write,
) => Isolate.run(
  () => IOOverrides.runWithIOOverrides(write.run, _FailingTemporaryFiles()),
);

final class _FailingTemporaryFiles extends IOOverrides {
  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('.tmp') ? _FailingTemporaryFile(file) : file;
  }
}

final class _FailingTemporaryFile implements File {
  _FailingTemporaryFile(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    await _file.writeAsBytes(const [0x1f, 0x8b]);
    throw FileSystemException(
      'Запись не выполнена.',
      path,
      const OSError('No space left on device', 28),
    );
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
