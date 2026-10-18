import '../graph_snapshots/graph_log_compaction.dart';
import 'graph_backup_registry.dart';
import 'graph_change_summary.dart';

/// Час местного времени устройства, с которого начинается день ежедневных
/// копий.
const _dayStartHour = 3;

/// Исход ежедневной копии [GraphBackups.makeDailyBackupIfDue].
enum DailyGraphBackupOutcome {
  made,

  /// Копия не нужна: ежедневная копия текущего дня уже есть, с последней
  /// ежедневной копии граф не изменялся или ежедневных копий нет, а граф пуст.
  notDue,

  /// Копия не записана из-за отказа, а копии не изменились.
  failed,
}

/// Исход ручной копии [GraphBackups.makeManualBackup].
enum ManualGraphBackupOutcome {
  made,

  /// Копия не записана из-за отказа, а копии не изменились.
  failed,
}

/// Ежедневные и ручные резервные копии графа.
///
/// Сводка копии считается по пакетам лога от позиции предыдущей копии до
/// текущей чтением истории сжатия лога, а затем реестр копий одной короткой
/// транзакцией продолжает её пакетами, подтверждёнными за время подсчёта, и
/// записывает копию с позицией, текущей в этой транзакции. Поэтому команды
/// графа создания копии не ждут, а позиция и сводка копии согласованы.
///
/// Копии делаются по одной: следующая начинается, когда предыдущая записана
/// или отказала. Поэтому во время подсчёта сводки предыдущую копию может
/// сменить только копия перед заменой графа, а за ней в логе следует пакет
/// «сброс», и продолжение сводки даёт признак замены. Отказ копии не меняет
/// копии и не мешает следующей.
final class GraphBackups {
  GraphBackups({
    required this._registry,
    required this._compaction,
    required this._clock,
  });

  final GraphBackupRegistry _registry;

  /// Сжатие лога фактов, которое ведёт отметки чтения истории.
  final GraphLogCompaction _compaction;
  final DateTime Function() _clock;

  /// Завершение последней запрошенной копии.
  Future<void> _previous = Future.value();

  /// Делает ежедневную копию, если ежедневных копий нет, а граф не пуст, либо
  /// последняя ежедневная копия сделана не в текущий день, а после неё граф
  /// изменялся. День начинается в 03:00 по местному времени устройства.
  /// Момент копии — показание часов при записи, а позиция — текущая.
  ///
  /// Копия делается фоном, поэтому отказ сообщается исходом, а не
  /// исключением.
  Future<DailyGraphBackupOutcome> makeDailyBackupIfDue() =>
      _oneAtATime(() async {
        try {
          return await _makeDailyBackupIfDue()
              ? DailyGraphBackupOutcome.made
              : DailyGraphBackupOutcome.notDue;
        } on Object {
          return DailyGraphBackupOutcome.failed;
        }
      });

  /// Делает копию текущего состояния графа по запросу человека.
  Future<ManualGraphBackupOutcome> makeManualBackup() => _oneAtATime(() async {
    try {
      final backups = await _readBackups();
      await _registry.insertManualBackup(
        since: await _tallySince(backups.firstOrNull),
      );
      return ManualGraphBackupOutcome.made;
    } on Object {
      return ManualGraphBackupOutcome.failed;
    }
  });

  Future<bool> _makeDailyBackupIfDue() async {
    final now = _clock();
    final dayStart = _dayStartOf(now);
    final backups = await _readBackups();
    // Транзакция записи проверит условие заново, а копия текущего дня, уже
    // найденная здесь, избавляет каждое возвращение в приложение от подсчёта
    // сводки.
    final lastDaily = backups
        .where((backup) => backup.kind == GraphBackupKind.daily)
        .firstOrNull;
    if (lastDaily != null &&
        isGraphBackupMadeInCurrentDay(
          lastDaily.madeAt,
          dayStart: dayStart,
          now: now,
        )) {
      return false;
    }
    return _registry.insertDailyBackup(
      dayStart: dayStart,
      since: await _tallySince(backups.firstOrNull),
    );
  }

  /// Копии от новых к старым по созданию.
  Future<List<GraphBackupEntry>> _readBackups() async =>
      switch (await _registry.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups,
        GraphBackupsReadFailed() => throw const _GraphBackupsUnread(),
      };

  /// Сводка пакетов от позиции копии [last] до текущей; `null` — копий нет,
  /// и реестр сравнит новую копию с пустым графом.
  Future<GraphChangeTally?> _tallySince(GraphBackupEntry? last) async {
    if (last == null) return null;
    return _compaction.readHistory(
      (history) async => GraphChangeTally.ofRange(
        history,
        after: last.position,
        upTo: await history.readCurrentPosition(),
      ),
    );
  }

  /// Выполняет [make] после завершения предыдущей копии. [make] отказ
  /// сообщает исходом, поэтому очередь не прерывается.
  Future<T> _oneAtATime<T>(Future<T> Function() make) {
    final made = _previous.then((_) => make());
    _previous = made;
    return made;
  }
}

/// Начало дня ежедневных копий, в котором наступил [moment].
DateTime _dayStartOf(DateTime moment) {
  final local = moment.toLocal();
  final start = DateTime(local.year, local.month, local.day, _dayStartHour);
  return local.isBefore(start)
      ? DateTime(local.year, local.month, local.day - 1, _dayStartHour)
      : start;
}

/// Список копий не прочитан.
final class _GraphBackupsUnread implements Exception {
  const _GraphBackupsUnread();
}
