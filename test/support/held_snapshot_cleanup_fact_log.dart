import 'forwarding_graph_fact_log.dart';

/// Лог фактов, в котором первое чтение имён файлов реестра снимков — чтение
/// очистки каталога снимков при запуске — начинается после [_hold]: так
/// проверка задерживает очистку.
final class HeldSnapshotCleanupFactLog extends ForwardingGraphFactLog {
  HeldSnapshotCleanupFactLog(super.source, this._hold);

  Future<void> Function()? _hold;

  @override
  Future<Set<String>> readSnapshotFileNames() async {
    final hold = _hold;
    _hold = null;
    await hold?.call();
    return super.readSnapshotFileNames();
  }
}
