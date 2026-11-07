import '../graph_snapshots/graph_log_compaction.dart';
import '../graph_snapshots/graph_snapshot_store.dart'
    show graphSnapshotFailureCode;
import '../shared/diagnostics/diagnostics_sink.dart';
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
///
/// Сделанная копия и отказ сообщаются в [DiagnosticsSink]; отказ диагностики
/// исход копии не меняет.
final class GraphBackups {
  GraphBackups({
    required this._registry,
    required this._compaction,
    required this._clock,
    required this._diagnosticsSink,
  });

  final GraphBackupRegistry _registry;

  /// Сжатие лога фактов, которое ведёт отметки чтения истории.
  final GraphLogCompaction _compaction;
  final DateTime Function() _clock;
  final DiagnosticsSink _diagnosticsSink;

  /// Завершение последней запрошенной копии.
  Future<void> _previous = Future.value();

  /// Наблюдает список копий от новых к старым по созданию по правилу
  /// [GraphBackupRegistry.watchBackups].
  Stream<GraphBackupsRead> watchBackups() => _registry.watchBackups();

  /// Делает ежедневную копию, если ежедневных копий нет, а граф не пуст, либо
  /// последняя ежедневная копия сделана не в текущий день, а после неё граф
  /// изменялся. День начинается в 03:00 по местному времени устройства.
  /// Момент копии — показание часов при записи, а позиция — текущая.
  ///
  /// Копия делается фоном, поэтому отказ сообщается исходом, а не
  /// исключением.
  Future<DailyGraphBackupOutcome> makeDailyBackupIfDue() =>
      _oneAtATime(() async {
        final creation = _BackupCreationDiagnostics(
          GraphBackupCreationDiagnosticsKind.daily,
          _diagnosticsSink,
        );
        try {
          if (!await _makeDailyBackupIfDue(creation)) {
            return DailyGraphBackupOutcome.notDue;
          }
          creation.recordMade();
          return DailyGraphBackupOutcome.made;
        } on Object catch (error) {
          creation.recordFailure(error);
          return DailyGraphBackupOutcome.failed;
        }
      });

  /// Делает копию текущего состояния графа по запросу человека.
  Future<ManualGraphBackupOutcome> makeManualBackup() => _oneAtATime(() async {
    final creation = _BackupCreationDiagnostics(
      GraphBackupCreationDiagnosticsKind.manual,
      _diagnosticsSink,
    );
    try {
      final backups = await _registry.readBackups();
      final since = await _tallySince(backups.firstOrNull);
      creation.stage = GraphBackupCreationDiagnosticsStage.registration;
      await _registry.insertManualBackup(since: since);
      creation.recordMade();
      return ManualGraphBackupOutcome.made;
    } on Object catch (error) {
      creation.recordFailure(error);
      return ManualGraphBackupOutcome.failed;
    }
  });

  Future<bool> _makeDailyBackupIfDue(
    _BackupCreationDiagnostics creation,
  ) async {
    final now = _clock();
    final dayStart = _dayStartOf(now);
    final backups = await _registry.readBackups();
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
    final since = await _tallySince(backups.firstOrNull);
    creation.stage = GraphBackupCreationDiagnosticsStage.registration;
    return _registry.insertDailyBackup(dayStart: dayStart, since: since);
  }

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

/// Диагностика одного создания копии: длительность отсчитывается от начала
/// создания, а отказ относится к этапу [stage].
final class _BackupCreationDiagnostics {
  _BackupCreationDiagnostics(this._kind, this._sink);

  final GraphBackupCreationDiagnosticsKind _kind;
  final DiagnosticsSink _sink;
  final _stopwatch = Stopwatch()..start();

  /// Этап, который выполняется сейчас.
  var stage = GraphBackupCreationDiagnosticsStage.changeSummary;

  void recordMade() => recordDiagnosticsSafely(
    _sink,
    GraphBackupCreationDiagnosticsEvent.succeeded(
      kind: _kind,
      duration: _stopwatch.elapsed,
    ),
  );

  /// Копия читает реестр и пакеты лога через модуль снимков и пишет реестр
  /// в хранилище графа, поэтому её отказ классифицируется так же, как
  /// отказы снимков.
  void recordFailure(Object error) => recordDiagnosticsSafely(
    _sink,
    GraphBackupCreationDiagnosticsEvent.failed(
      kind: _kind,
      stage: stage,
      duration: _stopwatch.elapsed,
      code: graphSnapshotFailureCode(error),
    ),
  );
}
