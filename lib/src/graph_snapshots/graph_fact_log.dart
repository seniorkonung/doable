import 'dart:typed_data';

/// Наибольшее число пакетов в одной порции [GraphFactLog.readPackages].
const int graphFactLogPortionLimit = 100;

/// Пакет фактов в том виде, в каком его хранит лог.
final class StoredGraphFactPackage {
  const StoredGraphFactPackage({
    required this.position,
    required this.formatVersion,
    required this.facts,
  });

  final int position;

  /// Номер версии формата, которой записаны факты пакета. Он может быть
  /// старше текущей версии, поэтому проверяется и повышается при чтении
  /// фактов.
  final int formatVersion;

  /// Факты в кодировке пакета формата данных графа.
  final Uint8List facts;
}

/// Снимок в реестре снимков: файл состояния графа на позиции лога.
final class GraphSnapshotEntry {
  const GraphSnapshotEntry({
    required this.position,
    required this.formatVersion,
    required this.fileName,
    required this.byteSize,
    required this.checksum,
  });

  final int position;

  /// Номер версии формата записей снимка.
  final int formatVersion;

  /// Имя файла в каталоге снимков, уникальное в реестре.
  final String fileName;

  final int byteSize;

  /// SHA-256 файла, 32 байта.
  final Uint8List checksum;
}

/// Доступ хранилища снимков к логу фактов и реестру снимков.
///
/// Позиция 0 — пустой граф новой установки, каждый подтверждённый пакет
/// получает следующую позицию, и позиции не переиспользуются. Каждая
/// операция — отдельное короткое обращение к базе: команды графа выполняются
/// между операциями, а сами операции граф не меняют. Отказ базы передаётся
/// исключением.
abstract interface class GraphFactLog {
  /// Позиция последнего подтверждённого пакета. Удаление истории её не
  /// уменьшает.
  Future<int> readCurrentPosition();

  /// Порция пакетов с позициями после [after] не дальше [upTo] по
  /// возрастанию позиций, не больше [graphFactLogPortionLimit] пакетов.
  ///
  /// Следующая порция читается после позиции последнего пакета предыдущей,
  /// пустая порция означает, что пакетов в диапазоне больше нет. Пакеты,
  /// подтверждённые между порциями, получают позиции после прежних, поэтому
  /// диапазон до уже достигнутой позиции [upTo] они не меняют. Вызывающий не
  /// удаляет историю, которую читает.
  Future<List<StoredGraphFactPackage>> readPackages({
    required int after,
    required int upTo,
  });

  /// Ближайший зарегистрированный снимок не новее [position]; из снимков
  /// одной позиции — зарегистрированный последним. `null` — такого снимка
  /// нет, и базой служит пустой граф позиции 0.
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position);

  /// Имена файлов всех зарегистрированных снимков.
  Future<Set<String>> readSnapshotFileNames();

  /// Регистрирует снимок, файл которого уже надёжно записан.
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot);

  /// Удаляет историю за границей хранения [boundary] одной транзакцией.
  ///
  /// Сохраняются последний снимок, ближайший снимок не новее границы и все
  /// пакеты после него, а без такого снимка — все пакеты. Остальные снимки и
  /// более ранние пакеты удаляются из реестра. Возвращает имена файлов
  /// удалённых снимков: их удаляет вызывающий.
  Future<List<String>> removeHistoryBefore(int boundary);
}
