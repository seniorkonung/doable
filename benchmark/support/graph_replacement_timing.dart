import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/data_transfer/application/graph_replacement.dart';

/// Длительность замены графа импортом или восстановлением копии и её
/// частей: записи снимка замены, удаления прежнего графа, вставки записей
/// снимка и остатка замены — сверки количеств, строк копии перед заменой,
/// снимка и пакета «сброс», COMMIT и публикации исхода. Время операторов SQL
/// удаления, вставки и проверки путей входит в длительность своих частей.
final class GraphReplacementSample {
  const GraphReplacementSample._({
    required this.total,
    required this.snapshotWrite,
    required this.deletion,
    required this.insertion,
    required this.sql,
  });

  final Duration total;
  final Duration snapshotWrite;
  final Duration deletion;
  final Duration insertion;
  final GraphReplacementSql sql;

  /// Фаза 2: замена графа в монопольном режиме координатора.
  Duration get replacement => total - snapshotWrite;

  /// Длительности частей в миллисекундах, без общей длительности.
  Map<String, Object> partsToJson() => {
    'snapshotWriteMs': _milliseconds(snapshotWrite),
    'replacementMs': _milliseconds(replacement),
    'deletionMs': _milliseconds(deletion),
    'deletionSqlMs': _milliseconds(sql.deletion),
    'insertionMs': _milliseconds(insertion),
    'insertionSqlMs': _milliseconds(sql.insertion),
    'pathVerificationSqlMs': _milliseconds(sql.pathVerification),
    'replacementRestMs': _milliseconds(replacement - deletion - insertion),
  };
}

/// Замер одной замены графа от начала записи снимка замены до исхода по ходу
/// замены, который получает [onProgress], и по времени операторов SQL
/// наблюдателя [GraphReplacementTrace].
final class GraphReplacementTiming {
  GraphReplacementTiming.start(this._trace) {
    _trace._start();
    _stopwatch.start();
  }

  final GraphReplacementTrace _trace;
  final _stopwatch = Stopwatch();
  Duration? _replacementStart;
  Duration? _deletionEnd;
  Duration? _insertionEnd;

  void onProgress(GraphReplacementProgress progress) {
    if (progress.phase != GraphReplacementPhase.replacement) return;
    final elapsed = _stopwatch.elapsed;
    _replacementStart ??= elapsed;
    // Прежний граф и снимок замены — одно состояние, а ход замены считает
    // удалённые и вставленные записи, поэтому удаление заканчивается на
    // половине хода.
    if (progress.share >= 0.5) _deletionEnd ??= elapsed;
    if (progress.share == 1) _insertionEnd ??= elapsed;
  }

  /// Завершает замер, когда замена дала исход.
  GraphReplacementSample finish() {
    _stopwatch.stop();
    final sql = _trace._stop();
    if ((_replacementStart, _deletionEnd, _insertionEnd) case (
      final replacementStart?,
      final deletionEnd?,
      final insertionEnd?,
    )) {
      return GraphReplacementSample._(
        total: _stopwatch.elapsed,
        snapshotWrite: replacementStart,
        deletion: deletionEnd - replacementStart,
        insertion: insertionEnd - deletionEnd,
        sql: sql,
      );
    }
    throw StateError('Ход замены не дошёл до конца удаления и вставки.');
  }
}

/// Время операторов SQL замены графа по видам.
typedef GraphReplacementSql = ({
  Duration deletion,
  Duration insertion,
  Duration pathVerification,
});

/// Время операторов SQL замены графа: удаления прежнего графа, пакетов
/// вставки записей снимка и чтений шагов вставленных путей. Считает только
/// во время замера [GraphReplacementTiming].
final class GraphReplacementTrace extends LocalDatabaseConnectionObserver {
  final _statement = Stopwatch();
  var _recording = false;
  var _deletion = Duration.zero;
  var _insertion = Duration.zero;
  var _pathVerification = Duration.zero;

  void _start() {
    _deletion = Duration.zero;
    _insertion = Duration.zero;
    _pathVerification = Duration.zero;
    _recording = true;
  }

  GraphReplacementSql _stop() {
    _recording = false;
    return (
      deletion: _deletion,
      insertion: _insertion,
      pathVerification: _pathVerification,
    );
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_recording) return;
    _statement
      ..reset()
      ..start();
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_recording) return;
    final elapsed = _statement.elapsed;
    final [sql, ...] = statement.statements;
    if (statement.operation == LocalDatabaseSqlOperation.batch) {
      _insertion += elapsed;
    } else if (sql.startsWith('DELETE FROM')) {
      _deletion += elapsed;
    } else if (sql.contains('daily_choice_path_steps')) {
      _pathVerification += elapsed;
    }
  }
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;
