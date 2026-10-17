import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'graph_fact_log.dart';
import 'graph_snapshot_store.dart';

/// Наибольшее число пакетов после последнего снимка, при котором лог ещё не
/// сжимается. Больший порог реже переписывает весь граф в снимок, но
/// удлиняет сборку состояния из пакетов после снимка.
const int graphLogCompactionThreshold = 1000;

/// Выполняет запись снимка [write] в отдельном изоляте. Подмена позволяет
/// проверкам наблюдать попытки сжатия и внедрять отказы файловой системы в
/// изоляте записи.
typedef GraphSnapshotWriteRunner = Future<GraphSnapshotEntry> Function(
  GraphSnapshotWrite write,
);

/// Отдельная функция не захватывает лог и базу замыканием изолята:
/// https://api.dart.dev/dart-isolate/Isolate/run.html
Future<GraphSnapshotEntry> runGraphSnapshotWriteInIsolate(
  GraphSnapshotWrite write,
) => Isolate.run(write.run);

/// Фоновое сжатие лога фактов в снимки.
///
/// Когда пакетов после последнего снимка становится больше порога, снимок
/// текущей позиции собирается, пишется и регистрируется в отдельном изоляте,
/// а затем удаляется история до него. Если последний снимок не проходит
/// проверку, снимок текущего состояния пересобирается из базы, а повреждённый
/// снимок удаляет та же граница хранения. База получает только короткие
/// операции лога и порции графа, поэтому команды графа подтверждаются и во
/// время сжатия. Одновременно идёт не больше одного сжатия.
///
/// Неудачное сжатие оставляет базу, лог и прежний снимок без изменений и не
/// повторяется на каждом новом пакете: следующая попытка — когда после неё
/// записано ещё не меньше порога пакетов либо при [start] в следующем
/// запуске приложения.
final class GraphLogCompaction {
  GraphLogCompaction({
    required this._log,
    required this._directory,
    required this._clock,
    this._threshold = graphLogCompactionThreshold,
    this._runner = runGraphSnapshotWriteInIsolate,
  });

  final ObservableGraphFactLog _log;
  final Directory _directory;
  final DateTime Function() _clock;
  final int _threshold;
  final GraphSnapshotWriteRunner _runner;
  late final _store = GraphSnapshotStore(
    log: _log,
    directory: _directory,
    clock: _clock,
  );
  StreamSubscription<int>? _signals;
  Future<void>? _running;

  /// Позиция последнего снимка, известная по последней проверке; `null` —
  /// ещё не прочитана.
  int? _snapshotPosition;

  /// Наибольшая известная позиция лога.
  var _latestPosition = 0;

  /// Позиция лога при последней неудачной попытке, пока за ней не последовала
  /// успешная.
  int? _failedAt;

  /// Сверяет лог с порогом и следит за новыми пакетами. Вызывается один раз,
  /// не одновременно с очисткой каталога снимков.
  void start() {
    _signals = _log.confirmedPositions.listen(_onConfirmed);
    _launch();
  }

  /// Перестаёт следить за новыми пакетами и дожидается идущего сжатия.
  Future<void> shutdown() async {
    await _signals?.cancel();
    await _running;
  }

  void _onConfirmed(int position) {
    _latestPosition = max(_latestPosition, position);
    if (_running != null || !_mayBeDue(position)) return;
    _launch();
  }

  /// Решение без обращения к базе: окончательно порог сверяется с
  /// прочитанными позициями перед сжатием.
  bool _mayBeDue(int position) {
    if (_snapshotPosition case final snapshot?
        when position - snapshot <= _threshold) {
      return false;
    }
    if (_failedAt case final failed? when position - failed < _threshold) {
      return false;
    }
    return true;
  }

  void _launch() {
    _running = _compactIfDue().whenComplete(() => _running = null);
  }

  Future<void> _compactIfDue() async {
    try {
      final position = await _log.readCurrentPosition();
      _latestPosition = max(_latestPosition, position);
      final latest = await _log.readSnapshotAtOrBefore(position);
      final snapshotPosition = _snapshotPosition = latest?.position ?? 0;
      if (position - snapshotPosition <= _threshold) return;
      final snapshot = await _writeSnapshot(position);
      _snapshotPosition = snapshot.position;
      _failedAt = null;
      await _store.removeHistoryBefore(snapshot.position);
    } on Object {
      // Запись снимка при отказе удаляет свой файл и не регистрирует его, а
      // удаление истории откатывается своей транзакцией.
      _failedAt = _latestPosition;
    }
  }

  /// Изолят записи обращается к логу через порт: операции выполняет [_log]
  /// этого изолята, поэтому база и её исполнитель остаются здесь.
  Future<GraphSnapshotEntry> _writeSnapshot(int position) async {
    final calls = ReceivePort();
    calls.listen((call) => (call as _GraphFactLogCall).answer(_log));
    try {
      return await _runner(
        GraphSnapshotWrite._(position, _directory, _clock(), calls.sendPort),
      );
    } finally {
      calls.close();
    }
  }
}

/// Запись снимка для отдельного изолята: позиция, каталог снимков, момент
/// записи и порт, через который изолят обращается к логу фактов.
final class GraphSnapshotWrite {
  const GraphSnapshotWrite._(
    this._position,
    this._directory,
    this._writtenAt,
    this._log,
  );

  final int _position;
  final Directory _directory;
  final DateTime _writtenAt;
  final SendPort _log;

  /// Пишет и регистрирует снимок, а если последний снимок не проходит
  /// проверку, пересобирает снимок из базы; выполняется в изоляте записи.
  Future<GraphSnapshotEntry> run() async {
    final store = GraphSnapshotStore(
      log: _PortGraphFactLog(_log),
      directory: _directory,
      clock: () => _writtenAt,
    );
    try {
      return await store.writeSnapshot(_position);
    } on GraphSnapshotCorruption {
      return store.rebuildSnapshot();
    }
  }
}

/// Лог фактов изолята записи: каждую операцию выполняет лог изолята сжатия,
/// а её отказ передаётся обратно.
final class _PortGraphFactLog implements GraphFactLog {
  const _PortGraphFactLog(this._calls);

  final SendPort _calls;

  @override
  Future<int> readCurrentPosition() =>
      _call((log) => log.readCurrentPosition());

  @override
  Future<List<StoredGraphFactPackage>> readPackages({
    required int after,
    required int upTo,
  }) => _call((log) => log.readPackages(after: after, upTo: upTo));

  @override
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after}) =>
      _call((log) => log.readGraphRecords(after: after));

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) =>
      _call((log) => log.readSnapshotAtOrBefore(position));

  @override
  Future<Set<String>> readSnapshotFileNames() =>
      _call((log) => log.readSnapshotFileNames());

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) =>
      _call((log) => log.registerSnapshot(snapshot));

  @override
  Future<List<String>> removeHistoryBefore(int boundary) =>
      _call((log) => log.removeHistoryBefore(boundary));

  /// Изоляты одной группы передают замыкания:
  /// https://api.dart.dev/dart-isolate/SendPort/send.html
  Future<T> _call<T>(Future<T> Function(GraphFactLog log) operation) async {
    final reply = ReceivePort();
    _calls.send(_GraphFactLogCall<T>(operation, reply.sendPort));
    return switch (await reply.first as _GraphFactLogReply<T>) {
      _GraphFactLogSuccess<T>(:final value) => value,
      _GraphFactLogFailure<T>(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
    };
  }
}

final class _GraphFactLogCall<T> {
  const _GraphFactLogCall(this._operation, this._reply);

  final Future<T> Function(GraphFactLog log) _operation;
  final SendPort _reply;

  /// Отказы лога пересекают границу изолятов уже сейчас — база работает в
  /// своём изоляте, — поэтому передаются как есть.
  Future<void> answer(GraphFactLog log) async {
    try {
      _reply.send(_GraphFactLogSuccess<T>(await _operation(log)));
    } on Object catch (error, stackTrace) {
      _reply.send(_GraphFactLogFailure<T>(error, stackTrace));
    }
  }
}

sealed class _GraphFactLogReply<T> {
  const _GraphFactLogReply();
}

final class _GraphFactLogSuccess<T> extends _GraphFactLogReply<T> {
  const _GraphFactLogSuccess(this.value);

  final T value;
}

final class _GraphFactLogFailure<T> extends _GraphFactLogReply<T> {
  const _GraphFactLogFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
