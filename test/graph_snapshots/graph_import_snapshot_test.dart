import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/failing_snapshot_temporary_files.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

void main() {
  final golden = File('test/graph_format/golden/graph_format_v1.jsonl')
      .readAsBytesSync();
  final goldenLines = utf8.decode(golden).split('\n')..removeLast();

  late LocalDatabaseHarness harness;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late File input;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    repository = DriftPersonalGraphRepository(
      await harness.openReadyDatabase(),
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 19, 9),
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    input = File.fromUri(
      harness.temporaryDirectory.uri.resolve('import.jsonl.gz'),
    );
    await input.writeAsBytes(gzip.encode(golden));
  });

  tearDown(() => harness.dispose());

  GraphLogCompaction compaction({
    GraphReplacementSnapshotWriteRunner replacementSnapshotRunner =
        runGraphReplacementSnapshotWriteInIsolate,
  }) => GraphLogCompaction(
    log: repository,
    directory: snapshots,
    clock: () => DateTime.utc(2026, 10, 19, 10),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    replacementSnapshotRunner: replacementSnapshotRunner,
  );

  Future<UnregisteredGraphSnapshot> writeImported(
    GraphLogCompaction compaction, {
    void Function(double share)? onProgress,
    Future<void>? cancelled,
  }) => compaction.writeReplacementSnapshotOfFile(
    input,
    onProgress: onProgress ?? (_) {},
    cancelled: cancelled ?? Completer<void>().future,
  );

  test('эталонный файл версии 1 превращается в незарегистрированный снимок '
      'замены с записями файла в том же порядке и с переданными размером, '
      'суммой и количествами', () async {
    final snapshot = await writeImported(compaction());

    final file = File.fromUri(snapshots.uri.resolve(snapshot.fileName));
    expect(await file.length(), snapshot.byteSize);
    expect(sha256.convert(await file.readAsBytes()).bytes, snapshot.checksum);
    expect(_countsOf(snapshot.counts), [2, 4, 3, 3, 2]);
    expect(_lines(await snapshot.readRecords().toList()), goldenLines.skip(1));
    expect(
      await repository.readSnapshotFileNames(),
      isNot(contains(snapshot.fileName)),
    );
  });

  test('ход записи растёт до полного к её окончанию', () async {
    final progress = <double>[];

    await writeImported(compaction(), onProgress: progress.add);

    expect(progress, hasLength(greaterThan(1)));
    for (var index = 1; index < progress.length; index++) {
      expect(progress[index], greaterThan(progress[index - 1]));
    }
    expect(progress.last, 1);
  });

  test('отмена прекращает запись между записями и не оставляет файлов в '
      'каталоге снимков', () async {
    final stalls = ReceivePort();
    addTearDown(stalls.close);
    final cancellation = Completer<void>();
    final write = writeImported(
      compaction(
        replacementSnapshotRunner: _stallingReadOf(input, stalls.sendPort),
      ),
      cancelled: cancellation.future,
    );
    final resume = await stalls.first as SendPort;

    cancellation.complete();
    // Отмена уходит в изолят записи микрозадачей и приходит туда раньше
    // продолжения чтения: сообщения одного изолята доставляются по порядку.
    await Future<void>.delayed(Duration.zero);
    resume.send(null);

    await expectLater(write, throwsA(isA<GraphReplacementSnapshotCancelled>()));
    expect(await _fileNamesIn(snapshots), isEmpty);
  });

  test('отказы чтения файла передаются своими исходами и не оставляют '
      'файлов в каталоге снимков', () async {
    final newer = utf8.encode(
      '{"format":"doable-graph","version":2,'
      '"writtenAt":"2030-01-01T00:00:00.000000Z"}\n',
    );
    final cases = {
      'обрезанный посередине': (
        gzip.encode(golden.sublist(0, golden.length ~/ 2)),
        isA<GraphFormatCorruption>(),
      ),
      'более новой версии': (
        gzip.encode(newer),
        isA<GraphFormatVersionTooNew>(),
      ),
    };

    for (final MapEntry(key: reason, value: (bytes, failure))
        in cases.entries) {
      await input.writeAsBytes(bytes);

      await expectLater(
        writeImported(compaction()),
        throwsA(failure),
        reason: reason,
      );
      expect(await _fileNamesIn(snapshots), isEmpty, reason: reason);
    }
  });

  test('нехватка места при записи временного файла снимка относится к '
      'нехватке места и не оставляет файлов в каталоге снимков', () async {
    await expectLater(
      writeImported(
        compaction(
          replacementSnapshotRunner:
              writeGraphReplacementSnapshotFailingOnTemporaryFiles,
        ),
      ),
      throwsA(
        isA<FileSystemException>().having(
          classifySqliteFailure,
          'категория отказа',
          isA<SqliteStorageFullFailure>(),
        ),
      ),
    );

    expect(await _fileNamesIn(snapshots), isEmpty);
  });
}

/// Пишет снимок замены графа в отдельном изоляте, как
/// [runGraphReplacementSnapshotWriteInIsolate], но чтение файла [input]
/// останавливается после первой половины его байтов: порт [stalled]
/// получает порт, сообщение в который продолжает чтение.
/// https://api.dart.dev/dart-io/IOOverrides-class.html
GraphReplacementSnapshotWriteRunner _stallingReadOf(
  File input,
  SendPort stalled,
) {
  final stallingPath = input.path;
  return (write) => Isolate.run(
    () => IOOverrides.runWithIOOverrides(
      write.run,
      _StallingFiles(stallingPath, stalled),
    ),
  );
}

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

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<int> _countsOf(GraphRecordCounts counts) => [
  counts.tags,
  counts.intentions,
  counts.tagAssignments,
  counts.longTermRelations,
  counts.dailyChoices,
];

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
