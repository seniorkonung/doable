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
  () => IOOverrides.runWithIOOverrides(
    write.run,
    _FailingFiles((path) => path.endsWith('.tmp')),
  ),
);

/// Запись состояния графа в отдельном изоляте, как
/// [runGraphStateWriteInIsolate], при которой файл [file] появляется, а
/// запись в него отказывает, как при нехватке места.
GraphStateWriteRunner writeGraphStateFailingOn(File file) {
  final failingPath = file.path;
  return (write) => Isolate.run(
    () => IOOverrides.runWithIOOverrides(
      write.run,
      _FailingFiles((path) => path == failingPath),
    ),
  );
}

/// Запись состояния графа в отдельном изоляте, как
/// [runGraphStateWriteInIsolate], при которой файлы каталога [directory]
/// появляются, а запись в них отказывает, как при нехватке места.
GraphStateWriteRunner writeGraphStateFailingIn(Directory directory) {
  // Путь из адреса каталога заканчивается разделителем, поэтому файлы
  // каталога с похожим именем не совпадают.
  final failingPrefix = directory.uri.toFilePath();
  return (write) => Isolate.run(
    () => IOOverrides.runWithIOOverrides(
      write.run,
      _FailingFiles((path) => path.startsWith(failingPrefix)),
    ),
  );
}

final class _FailingFiles extends IOOverrides {
  _FailingFiles(this._fails);

  final bool Function(String path) _fails;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return _fails(path) ? _FailingFile(file) : file;
  }
}

final class _FailingFile implements File {
  _FailingFile(this._file);

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
