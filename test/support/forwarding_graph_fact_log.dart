import 'package:doable/src/graph_snapshots/graph_fact_log.dart';

/// Лог фактов, который передаёт каждую операцию исходному логу [source].
///
/// Тестовые подмены переопределяют только перехватываемые операции, поэтому
/// новая операция контракта лога меняет в тестах только эту пересылку.
abstract base class ForwardingGraphFactLog implements ObservableGraphFactLog {
  const ForwardingGraphFactLog(this.source);

  final ObservableGraphFactLog source;

  @override
  Stream<int> get confirmedPositions => source.confirmedPositions;

  @override
  Future<int> readCurrentPosition() => source.readCurrentPosition();

  @override
  Future<List<StoredGraphFactPackage>> readPackages({
    required int after,
    required int upTo,
  }) => source.readPackages(after: after, upTo: upTo);

  @override
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after}) =>
      source.readGraphRecords(after: after);

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) =>
      source.readSnapshotAtOrBefore(position);

  @override
  Future<Set<String>> readSnapshotFileNames() => source.readSnapshotFileNames();

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) =>
      source.registerSnapshot(snapshot);

  @override
  Future<List<String>> removeHistoryBefore(int boundary) =>
      source.removeHistoryBefore(boundary);
}
