import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:drift/drift.dart' show Value;

import 'graph_log_completeness_reference.dart';

/// Записывает прямой вставкой строку ежедневной копии на позиции
/// [position], как её запишет реестр копий.
Future<void> insertDailyBackupRow(
  AppDatabase database, {
  required int position,
}) => database.into(database.graphBackups).insert(_backup(position, 'daily'));

/// Записывает прямыми вставками в одной транзакции строки, которые запишет
/// замена графа графом того же содержимого: копию перед заменой на позиции
/// [position], текущей позиции лога, снимок заменившего графа на позиции
/// следующего пакета и пакет «сброс», который ссылается на этот снимок.
///
/// Таблицы графа не меняются, поэтому файл снимка в существующем каталоге
/// [snapshots] содержит их текущие записи. Возвращает снимок.
Future<GraphSnapshotEntry> insertSameGraphReplacement(
  AppDatabase database, {
  required Directory snapshots,
  required int position,
}) async {
  final records = await referenceGraphRecords(database);
  final bytes = Uint8List.fromList(
    await GraphFormatFile.write(
      GraphFormatHeader(
        writtenAt: DateTime.utc(2026, 10, 18),
        counts: GraphRecordCounts(
          tags: records.whereType<TagRecord>().length,
          intentions: records.whereType<IntentionRecord>().length,
          tagAssignments: records.whereType<TagAssignmentRecord>().length,
          longTermRelations: records.whereType<LongTermRelationRecord>().length,
          dailyChoices: records.whereType<DailyChoiceRecord>().length,
        ),
      ),
      Stream.fromIterable(records),
    ).expand((chunk) => chunk).toList(),
  );
  final snapshot = GraphSnapshotEntry(
    position: position + 1,
    fileName: 'заменивший-граф-${position + 1}.jsonl.gz',
    byteSize: bytes.length,
    checksum: Uint8List.fromList(sha256.convert(bytes).bytes),
  );
  await File.fromUri(snapshots.uri.resolve(snapshot.fileName))
      .writeAsBytes(bytes, flush: true);
  await database.transaction(() async {
    await database
        .into(database.graphBackups)
        .insert(_backup(position, 'before_replacement'));
    final snapshotId = await database
        .into(database.graphSnapshots)
        .insert(
          GraphSnapshotsCompanion.insert(
            position: snapshot.position,
            fileName: snapshot.fileName,
            byteSize: snapshot.byteSize,
            checksum: snapshot.checksum,
          ),
        );
    await database
        .into(database.graphLogPackages)
        .insert(
          GraphLogPackagesCompanion.insert(
            recordedAt: 0,
            kind: 'reset',
            snapshotId: Value(snapshotId),
          ),
        );
  });
  return snapshot;
}

GraphBackupsCompanion _backup(int position, String kind) =>
    GraphBackupsCompanion.insert(
      position: position,
      kind: kind,
      madeAt: 0,
      graphReplaced: false,
      addedCount: const Value(0),
      changedCount: const Value(0),
      deletedCount: const Value(0),
    );
