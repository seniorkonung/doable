import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../shared/diagnostics/diagnostics_sink.dart';
import 'graph_fact_log.dart';
import 'graph_snapshot_store.dart';

/// Наибольшее число пакетов после последнего снимка, при котором лог ещё не
/// сжимается.
///
/// Больший порог реже переписывает весь граф в снимок, но сборка состояния
/// держит в памяти итог фактов всех пакетов после снимка. Значение выбрано
/// бенчмарком лога фактов: итог тысячи правок занимает около 4,5 МиБ, а
/// правок описаний на пределе графем — около 12 МиБ, что сопоставимо с
/// остальной памятью сборки. Сжатие графа из миллиона сущностей длится
/// около 34 с и при этом пороге случается раз на тысячу команд.
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

/// Выполняет запись состояния графа [write] в отдельном изоляте. Подмена
/// позволяет проверкам внедрять отказы файловой системы в изоляте записи.
typedef GraphStateWriteRunner = Future<void> Function(GraphStateWrite write);

/// Отдельная функция не захватывает лог и базу замыканием изолята, как
/// [runGraphSnapshotWriteInIsolate].
Future<void> runGraphStateWriteInIsolate(GraphStateWrite write) =>
    Isolate.run(write.run);

/// Фоновое сжатие лога фактов в снимки.
///
/// Когда пакетов после последнего снимка становится больше порога, снимок
/// текущей позиции собирается, пишется и регистрируется в отдельном изоляте,
/// а затем удаляется история до него, кроме нужной идущим чтениям истории
/// [readHistory]: её удаляет следующее сжатие. Если последний снимок не
/// проходит проверку, снимок текущего состояния пересобирается из базы, а
/// повреждённый снимок удаляет та же граница хранения. База получает только
/// короткие операции лога и порции графа, поэтому команды графа
/// подтверждаются и во время сжатия. Одновременно идёт не больше одного
/// сжатия.
///
/// Неудачное сжатие не повторяется на каждом новом пакете: следующая
/// попытка — когда после неё записано ещё не меньше порога пакетов. Отказ
/// записи или регистрации снимка оставляет базу, лог и прежний снимок без
/// изменений, поэтому [start] в следующем запуске приложения пробует снова.
/// Отказ удаления истории наступает, когда новый снимок уже зарегистрирован:
/// прежние снимки и пакеты остаются в реестре и каталоге снимков, по новому
/// снимку сжатие не нужно, а прежнюю историю удаляет граница хранения
/// следующего успешного сжатия.
///
/// Исход сжатия и записи или пересборки снимка в изоляте записи сообщается в
/// [DiagnosticsSink]; отказ диагностики исход сжатия не меняет.
///
/// Состояние графа на текущей позиции для экспорта пишет [writeCurrentState]
/// тем же способом: в отдельном изоляте, который обращается к логу через
/// это сжатие, под отметкой чтения истории.
final class GraphLogCompaction {
  GraphLogCompaction({
    required this._log,
    required this._directory,
    required this._clock,
    required this._diagnosticsSink,
    this._threshold = graphLogCompactionThreshold,
    this._runner = runGraphSnapshotWriteInIsolate,
    this._stateWriteRunner = runGraphStateWriteInIsolate,
  });

  final ObservableGraphFactLog _log;
  final Directory _directory;
  final DateTime Function() _clock;
  final DiagnosticsSink _diagnosticsSink;
  final int _threshold;
  final GraphSnapshotWriteRunner _runner;
  final GraphStateWriteRunner _stateWriteRunner;
  late final _store = GraphSnapshotStore(
    log: _log,
    directory: _directory,
    clock: _clock,
    diagnosticsSink: _diagnosticsSink,
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

  /// Удаляет из каталога снимков незарегистрированные и временные файлы по
  /// правилу [GraphSnapshotStore.removeUnregisteredFiles]. Выполняется не
  /// одновременно со сжатием.
  Future<void> removeUnregisteredFiles() => _store.removeUnregisteredFiles();

  /// Чтение истории по правилу [GraphSnapshotStore.readHistory]: сжатие не
  /// удаляет его базовый снимок и пакеты после него, пока [read] не
  /// завершилось.
  Future<T> readHistory<T>(Future<T> Function(GraphHistoryRead history) read) =>
      _store.readHistory(read);

  /// Пишет состояние графа на текущей позиции в новый файл формата [file]
  /// существующего каталога с моментом [writtenAt] в заголовке по правилу
  /// [GraphSnapshotStore.writeStateFile] в отдельном изоляте; [onProgress]
  /// получает ход записи.
  ///
  /// Чтение истории [readHistory] фиксирует текущую позицию и сохраняет её
  /// базовый снимок и пакеты после него до конца записи. Поэтому файл
  /// отражает состояние на этой позиции, даже если во время записи
  /// подтверждаются команды и завершается сжатие, а команды записи не ждут:
  /// база получает от изолята записи только короткие операции лога.
  Future<void> writeCurrentState(
    File file, {
    required DateTime writtenAt,
    required void Function(double share) onProgress,
  }) => readHistory(
    (history) => _inWriter(
      (compaction) => _stateWriteRunner(
        GraphStateWrite._(
          history,
          file.path,
          _directory,
          writtenAt,
          compaction,
        ),
      ),
      onProgress: onProgress,
    ),
  );

  /// Сверяет лог с порогом и следит за новыми пакетами. Вызывается один раз,
  /// не одновременно с [removeUnregisteredFiles].
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
    final stopwatch = Stopwatch()..start();
    var stage = GraphLogCompactionDiagnosticsStage.check;
    try {
      final position = await _log.readCurrentPosition();
      _latestPosition = max(_latestPosition, position);
      final latest = await _log.readSnapshotAtOrBefore(position);
      final snapshotPosition = _snapshotPosition = latest?.position ?? 0;
      if (position - snapshotPosition <= _threshold) return;
      stage = GraphLogCompactionDiagnosticsStage.snapshotWrite;
      final snapshot = await _writeSnapshot(position);
      _snapshotPosition = snapshot.position;
      _failedAt = null;
      stage = GraphLogCompactionDiagnosticsStage.historyRemoval;
      await _store.removeHistoryBefore(snapshot.position);
      _recordDiagnostics(
        GraphLogCompactionDiagnosticsEvent.succeeded(
          duration: stopwatch.elapsed,
        ),
      );
    } on Object catch (error) {
      // Запись снимка при отказе удаляет свой файл и не регистрирует его.
      // Удаление истории откатывается своей транзакцией, а новый снимок
      // остаётся зарегистрированным: прежнюю историю удалит граница хранения
      // следующего успешного сжатия.
      _failedAt = _latestPosition;
      _recordDiagnostics(
        GraphLogCompactionDiagnosticsEvent.failed(
          stage: stage,
          duration: stopwatch.elapsed,
          code: graphSnapshotFailureCode(error),
        ),
      );
    }
  }

  Future<GraphSnapshotEntry> _writeSnapshot(int position) => _inWriter(
    (compaction) => _runner(
      GraphSnapshotWrite._(position, _directory, _clock(), compaction),
    ),
  );

  /// Выполняет [write] изолята записи, который обращается к логу и
  /// диагностике через порт: операции выполняет [_log] этого изолята,
  /// поэтому база и её исполнитель остаются здесь, события записывает
  /// [_diagnosticsSink], а ход записи получает [onProgress].
  ///
  /// Сообщения изолята записи обрабатываются в порядке отправки, а его
  /// результат приходит последним, поэтому к завершению записи все её
  /// события и ход уже переданы.
  Future<T> _inWriter<T>(
    Future<T> Function(SendPort compaction) write, {
    void Function(double share)? onProgress,
  }) async {
    final messages = ReceivePort();
    messages.listen((message) {
      switch (message as _WriterMessage) {
        case final _GraphFactLogCall<Object?> call:
          call.answer(_log);
        case _WriterDiagnostics(:final event):
          _recordDiagnostics(event);
        case _WriterProgress(:final share):
          onProgress?.call(share);
      }
    });
    try {
      return await write(messages.sendPort);
    } finally {
      messages.close();
    }
  }

  void _recordDiagnostics(DiagnosticsEvent event) =>
      recordDiagnosticsSafely(_diagnosticsSink, event);
}

/// Запись снимка для отдельного изолята: позиция, каталог снимков, момент
/// записи и порт, через который изолят обращается к логу фактов и
/// передаёт события диагностики.
final class GraphSnapshotWrite {
  const GraphSnapshotWrite._(
    this._position,
    this._directory,
    this._writtenAt,
    this._compaction,
  );

  final int _position;
  final Directory _directory;
  final DateTime _writtenAt;
  final SendPort _compaction;

  /// Пишет и регистрирует снимок, а если последний снимок не проходит
  /// проверку, пересобирает снимок из базы; выполняется в изоляте записи.
  Future<GraphSnapshotEntry> run() async {
    final store = GraphSnapshotStore(
      log: _PortGraphFactLog(_compaction),
      directory: _directory,
      clock: () => _writtenAt,
      diagnosticsSink: _PortDiagnosticsSink(_compaction),
    );
    try {
      return await store.writeSnapshot(_position);
    } on GraphSnapshotCorruption {
      return store.rebuildSnapshot();
    }
  }
}

/// Запись состояния графа для отдельного изолята: чтение истории, путь файла,
/// каталог снимков, момент записи и порт, через который изолят обращается к
/// логу фактов и передаёт ход записи.
final class GraphStateWrite {
  const GraphStateWrite._(
    this._history,
    this._path,
    this._directory,
    this._writtenAt,
    this._compaction,
  );

  final GraphHistoryRead _history;
  final String _path;
  final Directory _directory;
  final DateTime _writtenAt;
  final SendPort _compaction;

  /// Пишет состояние на позиции чтения истории в файл; выполняется в
  /// изоляте записи.
  Future<void> run() =>
      GraphSnapshotStore(
        log: _PortGraphFactLog(_compaction),
        directory: _directory,
        clock: () => _writtenAt,
        diagnosticsSink: _PortDiagnosticsSink(_compaction),
      ).writeStateFile(
        _history,
        File(_path),
        onProgress: (share) => _compaction.send(_WriterProgress(share)),
      );
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

/// Получатель диагностики изолята записи: события записывает получатель
/// изолята сжатия.
final class _PortDiagnosticsSink implements DiagnosticsSink {
  const _PortDiagnosticsSink(this._compaction);

  final SendPort _compaction;

  @override
  void record(DiagnosticsEvent event) =>
      _compaction.send(_WriterDiagnostics(event));
}

/// Сообщение изолята записи изоляту сжатия.
sealed class _WriterMessage {
  const _WriterMessage();
}

final class _WriterDiagnostics extends _WriterMessage {
  const _WriterDiagnostics(this.event);

  final DiagnosticsEvent event;
}

/// Доля записанных записей состояния графа.
final class _WriterProgress extends _WriterMessage {
  const _WriterProgress(this.share);

  final double share;
}

final class _GraphFactLogCall<T> extends _WriterMessage {
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
