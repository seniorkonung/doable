import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';

/// Пишет снимок замены графа в отдельном изоляте, как
/// [runGraphReplacementSnapshotWriteInIsolate], но чтение файла по пути
/// [path] останавливается после первой половины его байтов: порт [stalled]
/// получает порт, сообщение в который продолжает чтение.
/// https://api.dart.dev/dart-io/IOOverrides-class.html
GraphReplacementSnapshotWriteRunner writeGraphReplacementSnapshotStallingReadOf(
  String path,
  SendPort stalled,
) =>
    (write) => Isolate.run(
      () => IOOverrides.runWithIOOverrides(
        write.run,
        _StallingFiles(path, stalled),
      ),
    );

final class _StallingFiles extends IOOverrides {
  _StallingFiles(this._path, this._stalled);

  final String _path;
  final SendPort _stalled;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == _path ? _StallingFile(file, _stalled) : file;
  }
}

final class _StallingFile implements File {
  _StallingFile(this._file, this._stalled);

  final File _file;
  final SendPort _stalled;

  @override
  String get path => _file.path;

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    final bytes = await _file.readAsBytes();
    final half = bytes.length ~/ 2;
    yield bytes.sublist(0, half);
    final resume = ReceivePort();
    _stalled.send(resume.sendPort);
    await resume.first;
    yield bytes.sublist(half);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
