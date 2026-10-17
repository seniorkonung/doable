import 'dart:typed_data';

import '../graph_format/graph_format_records.dart';
import '../intention/domain/intention.dart';
import '../intention/domain/intention_id.dart';

/// Наибольшее число пакетов в одной порции [GraphFactLog.readPackages] и
/// записей в одной порции [GraphFactLog.readGraphRecords].
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

/// Место строки графа в каноническом порядке файла формата: секция и ключ
/// порядка строки в ней. Ключ строки не меняется, пока строка есть в базе.
///
/// Ключи выдаёт [GraphFactLog.readGraphRecords], а вызывающий передаёт их
/// обратно без изменений.
sealed class GraphRecordOrderKey {
  const GraphRecordOrderKey();
}

final class TagOrderKey extends GraphRecordOrderKey {
  const TagOrderKey(this.creationSequence);

  final int creationSequence;
}

final class IntentionOrderKey extends GraphRecordOrderKey {
  const IntentionOrderKey({required this.createdAt, required this.id});

  final IntentionTimestamp createdAt;
  final IntentionId id;
}

final class TagAssignmentOrderKey extends GraphRecordOrderKey {
  const TagAssignmentOrderKey(this.creationSequence);

  final int creationSequence;
}

final class LongTermRelationOrderKey extends GraphRecordOrderKey {
  const LongTermRelationOrderKey(this.creationSequence);

  final int creationSequence;
}

final class DailyChoiceOrderKey extends GraphRecordOrderKey {
  const DailyChoiceOrderKey(this.creationSequence);

  final int creationSequence;
}

/// Порция записей графа, прочитанная одним коротким обращением к базе.
final class GraphRecordPortion {
  const GraphRecordPortion({
    required this.position,
    required this.records,
    required this.next,
  });

  /// Позиция лога, состояние графа на которой отражают записи порции.
  final int position;

  /// Записи в каноническом порядке файла формата.
  final List<GraphEntityRecord> records;

  /// Ключ последней записи, после которого читается следующая порция;
  /// `null` — порция дошла до конца записей графа.
  final GraphRecordOrderKey? next;
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

  /// Порция записей текущего состояния графа после ключа [after], а без
  /// него — с начала, не больше [graphFactLogPortionLimit] записей.
  ///
  /// Каждая порция отражает состояние графа на своей позиции, а граф может
  /// меняться между порциями. Строки читаются по возрастанию неизменных
  /// ключей порядка, поэтому порции не повторяют строк и не пропускают
  /// строку, которая была в базе на протяжении всего чтения.
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after});

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

/// Лог фактов, который сообщает о подтверждённых пакетах: по сигналу сжатие
/// узнаёт о росте лога, не читая базу после каждой команды.
abstract interface class ObservableGraphFactLog implements GraphFactLog {
  /// Позиции пакетов, подтверждённых после подписки, по возрастанию.
  Stream<int> get confirmedPositions;
}
