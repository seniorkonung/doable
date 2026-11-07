import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';

import 'graph_import_files.dart';

/// Идентификатор действия эталонного файла, путь которого — «Здоровье» и
/// удалённое намерение «Заниматься йогой» через удалённую связь. Только его
/// путь держит оба надгробия эталона.
const referenceTombstonedActionId = '5e6f7a8b-9c0d-4eaf-b012-3a4b5c6d7e12';

/// Заменяет граф [repository] записями эталонного файла формата версии 1 —
/// с действиями, их путями и надгробиями. Снимок замены записывается в
/// каталог снимков [snapshots], как его записывает импорт: действия
/// появляются в графе только заменой, а команды их создания нет.
Future<void> replaceWithReferenceGraph(
  DriftPersonalGraphRepository repository,
  Directory snapshots,
) async {
  final lines = referenceGraphFileLines();
  final bytes = graphExportFileOf(lines);
  await snapshots.create(recursive: true);
  const fileName = 'эталон.jsonl.gz';
  await File.fromUri(snapshots.uri.resolve(fileName))
      .writeAsBytes(bytes, flush: true);
  await repository.replaceGraph(
    UnregisteredGraphSnapshot(
      directory: snapshots,
      fileName: fileName,
      byteSize: bytes.length,
      checksum: Uint8List.fromList(sha256.convert(bytes).bytes),
      counts: GraphFormatCodec.decodeHeader(utf8.encode(lines.first))
          .header
          .counts,
    ),
    onProgress: (_) {},
    cancellation: GraphReplacementCancellation(),
  );
}
