import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('эталонный файл версии 1 превращается в незарегистрированный снимок '
      'замены с записями файла в том же порядке и с переданными размером, '
      'суммой и количествами', () async {
    final compaction = GraphLogCompaction(
      log: repository,
      directory: snapshots,
      clock: () => DateTime.utc(2026, 10, 19, 10),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    final snapshot = await compaction.writeReplacementSnapshotOfFile(
      input,
      onProgress: (_) {},
      cancelled: Completer<void>().future,
    );

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
}

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
