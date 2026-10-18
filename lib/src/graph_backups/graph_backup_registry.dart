import 'graph_change_summary.dart';

/// Окно хранения копий: столько последних ежедневных копий хранится вместе
/// со всеми копиями, сделанными после самой старой из них.
const int retainedDailyGraphBackups = 7;

enum GraphBackupKind {
  /// Состояние в момент записи, не больше одной копии за день.
  daily,

  /// Состояние по действию «Сделать копию сейчас».
  manual,

  /// Состояние перед заменой графа импортом или восстановлением копии.
  beforeReplacement,
}

/// Номер резервной копии в реестре. Номера не переиспользуются, поэтому
/// номер удалённой копии не совпадает с номером ни одной хранимой, даже если
/// у хранимой копии та же позиция.
final class GraphBackupId {
  const GraphBackupId(this._value);

  final int _value;

  @override
  bool operator ==(Object other) =>
      other is GraphBackupId && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}

/// Резервная копия: позиция лога, состояние графа на которой она хранит.
final class GraphBackupEntry {
  const GraphBackupEntry({
    required this.id,
    required this.kind,
    required this.position,
    required this.madeAt,
    required this.summary,
  });

  final GraphBackupId id;
  final GraphBackupKind kind;
  final int position;

  /// Показание часов устройства при записи копии. Это наблюдение
  /// (ADR-0006): после перевода часов моменты копий могут идти назад, а
  /// порядок копий задаёт их создание.
  final DateTime madeAt;

  /// Что изменилось с предыдущей копии, а у первой копии — с пустого графа.
  final GraphChangeSummary summary;
}

/// Сделана ли копия с моментом [madeAt] в текущий день, который начался в
/// [dayStart], если сейчас [now].
///
/// Копия с моментом позже [now] сделана до перевода часов назад, то есть не в
/// текущий день: иначе после такого перевода ежедневных копий не было бы до
/// наступления её дня.
bool isGraphBackupMadeInCurrentDay(
  DateTime madeAt, {
  required DateTime dayStart,
  required DateTime now,
}) => !madeAt.isBefore(dayStart) && !madeAt.isAfter(now);

/// Исход чтения списка копий.
sealed class GraphBackupsRead {
  const GraphBackupsRead();
}

final class GraphBackupsReadSucceeded extends GraphBackupsRead {
  const GraphBackupsReadSucceeded(this.backups);

  /// Копии от новых к старым по созданию.
  final List<GraphBackupEntry> backups;
}

/// Копии не прочитаны. Отказ не означает, что копий нет; его причину
/// различает только диагностика хранилища.
final class GraphBackupsReadFailed extends GraphBackupsRead {
  const GraphBackupsReadFailed();
}

/// Реестр резервных копий в хранилище графа.
///
/// Копия получает позицию лога и момент по часам устройства, текущие в
/// транзакции её записи, и сводку изменений с предыдущей копии, согласованную
/// с этой позицией. Каждая запись — одна короткая транзакция хранилища,
/// поэтому команды графа её не ждут. Отказ хранилища передаётся исключением
/// и не меняет ни одной копии.
abstract interface class GraphBackupRegistry {
  /// Наблюдает список копий: первое значение — список при подписке, затем
  /// новый список после каждого изменения.
  ///
  /// Отказ чтения — последнее значение: повторное чтение повреждённого
  /// хранилища список не восстанавливает.
  Stream<GraphBackupsRead> watchBackups();

  /// Читает список копий от новых к старым по созданию один раз. Отказ
  /// хранилища передаётся исключением, поэтому его причину различает
  /// диагностика операции, которой нужен список.
  Future<List<GraphBackupEntry>> readBackups();

  /// Записывает ежедневную копию, если условие её записи держится и в
  /// транзакции записи; возвращает, записана ли копия.
  ///
  /// Условие: ежедневных копий нет, а граф не пуст, либо последняя ежедневная
  /// копия сделана не в текущий день, начавшийся в [dayStart], по правилу
  /// [isGraphBackupMadeInCurrentDay] с моментом новой копии, и после её
  /// позиции в логе есть пакеты.
  ///
  /// Новая ежедневная копия сдвигает окно хранения
  /// [retainedDailyGraphBackups]: копии любого вида, созданные раньше самой
  /// старой из хранимых ежедневных копий, удаляются той же транзакцией.
  ///
  /// [since] — по правилу [insertManualBackup].
  Future<bool> insertDailyBackup({
    required DateTime dayStart,
    required GraphChangeTally? since,
  });

  /// Записывает ручную копию.
  ///
  /// [since] — сводка с позиции последней копии, которую нашёл вызывающий;
  /// транзакция продолжает её пакетами, подтверждёнными после её конца.
  /// `null` — вызывающий копий не нашёл. Если копий нет и в транзакции,
  /// копия сравнивается с пустым графом: каждая сущность её состояния
  /// считается добавленной, — а если копия появилась после поиска, сводка
  /// считается с её позиции.
  Future<void> insertManualBackup({required GraphChangeTally? since});
}
