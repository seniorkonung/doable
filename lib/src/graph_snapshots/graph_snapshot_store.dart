import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../data/local/sqlite_failure_classifier.dart';
import '../graph_format/graph_format_codec.dart';
import '../graph_format/graph_format_file.dart';
import '../graph_format/graph_format_records.dart';
import '../shared/diagnostics/diagnostics_sink.dart';
import 'graph_fact_log.dart';
import 'graph_state_assembly.dart';

/// Снимок не прошёл проверку при чтении: размер или SHA-256 файла не
/// совпали с реестром, файла нет или его записи не читаются.
///
/// Отказ не несёт прочитанных данных: в них пользовательский текст.
final class GraphSnapshotCorruption implements Exception {
  const GraphSnapshotCorruption();
}

/// Граф заменён после базового состояния сборки: в диапазоне её пакетов есть
/// пакет «сброс», поэтому состояние на позиции из этого базового состояния
/// не собирается.
final class GraphReplacedInRange implements Exception {
  const GraphReplacedInRange();
}

/// Запись снимка замены графа [GraphSnapshotStore.writeReplacementSnapshot]
/// отменена, а её файл удалён.
final class GraphReplacementSnapshotCancelled implements Exception {
  const GraphReplacementSnapshotCancelled();
}

/// Файл снимка, надёжно записанный в каталог снимков, но не
/// зарегистрированный: позицию ему даёт регистрация.
final class UnregisteredGraphSnapshot {
  const UnregisteredGraphSnapshot({
    required this.fileName,
    required this.byteSize,
    required this.checksum,
    required this.counts,
  });

  /// Имя файла в каталоге снимков.
  final String fileName;

  final int byteSize;

  /// SHA-256 файла, 32 байта.
  final Uint8List checksum;

  /// Количества записей из заголовка файла.
  final GraphRecordCounts counts;

  /// Запись реестра снимков для этого файла на позиции [position].
  GraphSnapshotEntry entryAt(int position) => GraphSnapshotEntry(
    position: position,
    fileName: fileName,
    byteSize: byteSize,
    checksum: checksum,
  );
}

/// Безопасная категория отказа операции со снимками для диагностики.
///
/// Снимок, не прошедший проверку, отличается от повреждения данных лога и
/// базы, в том числе строк графа вне формы хранения. Нехватка места на
/// устройстве — в базе или в файлах — отдельная категория; остальные отказы
/// файлов снимков относятся к недоступности хранилища, как у файла настройки
/// установки. Замена графа во время чтения истории — конфликт с
/// одновременным изменением.
DiagnosticsFailureCode graphSnapshotFailureCode(Object error) =>
    switch (error) {
      GraphSnapshotCorruption() => DiagnosticsFailureCode.snapshotCorruption,
      GraphReplacedInRange() => DiagnosticsFailureCode.conflict,
      GraphFormatCorruption() ||
      GraphRecordCorruption() => DiagnosticsFailureCode.corruption,
      _ => switch (classifySqliteFailure(error)) {
        SqliteStorageFullFailure() => DiagnosticsFailureCode.storageFull,
        _ when error is FileSystemException =>
          DiagnosticsFailureCode.unavailable,
        SqliteCorruptionFailure() => DiagnosticsFailureCode.corruption,
        SqliteUnavailableFailure() => DiagnosticsFailureCode.unavailable,
        SqliteConstraintFailure() ||
        SqliteUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
      },
    };

/// Идущее чтение истории [GraphSnapshotStore.readHistory].
///
/// Чтение выбирает историю один раз: состояние на позиции [selectStateAt]
/// или пакеты диапазона [readPackages]. Пока история не выбрана, удаление
/// истории хранилищем не выполняется, поэтому позицию можно найти внутри
/// чтения до выбора: копия, найденная в реестре внутри чтения, сохраняет
/// свою историю до его конца, а копию, удалённую раньше, поиск не находит.
/// Чтение действует, пока не завершилось обращение, которое его получило.
final class GraphHistoryRead {
  GraphHistoryRead._(this._log, this._mark);

  final GraphFactLog _log;
  final _HistoryReadMark _mark;

  /// Позиция последнего подтверждённого пакета.
  Future<int> readCurrentPosition() => _log.readCurrentPosition();

  /// Выбирает источник состояния графа на позиции [position], не новее
  /// текущей: ближайший зарегистрированный снимок не новее неё. До конца
  /// чтения удаление истории сохраняет этот снимок и пакеты после него.
  Future<GraphStateSource> selectStateAt(int position) async {
    _mark.beginSelection();
    final base = await _log.readSnapshotAtOrBefore(position);
    _mark.history = (from: base?.position ?? 0, base: base);
    return GraphStateSource._(position, base);
  }

  /// Пакеты с позициями после [after] не дальше [upTo], не новее текущей,
  /// по возрастанию позиций; факты пакетов «изменение» прочитаны в текущей
  /// версии формата.
  ///
  /// Пакеты читаются короткими порциями, а до конца чтения удаление истории
  /// сохраняет все пакеты после [after]. Поток однократный.
  Stream<GraphHistoryPackage> readPackages({
    required int after,
    required int upTo,
  }) {
    _mark.beginSelection();
    _mark.history = (from: after, base: null);
    return _readHistoryPackages(_log, after: after, upTo: upTo);
  }
}

/// Источник состояния графа на позиции, выбранный чтением истории
/// [GraphHistoryRead.selectStateAt]: позиция и её базовый снимок.
final class GraphStateSource {
  const GraphStateSource._(this.position, this.base);

  final int position;

  /// Ближайший зарегистрированный снимок не новее [position]; `null` — такого
  /// снимка нет, и базой служит пустой граф позиции 0.
  final GraphSnapshotEntry? base;
}

/// Пакет лога, прочитанный чтением истории [GraphHistoryRead.readPackages].
sealed class GraphHistoryPackage {
  const GraphHistoryPackage({required this.position});

  /// Пакет истории из хранимого пакета [package]: факты пакета «изменение»
  /// прочитаны в текущей версии формата.
  factory GraphHistoryPackage.decode(StoredGraphLogPackage package) =>
      switch (package) {
        StoredGraphChangePackage(
          :final position,
          :final formatVersion,
          :final facts,
        ) =>
          GraphHistoryChange(
            position: position,
            facts: GraphFormatCodec.decodePackage(
              facts,
              GraphFormatVersion.ofCarrier(formatVersion),
            ),
          ),
        StoredGraphResetPackage(:final position) => GraphHistoryReset(
          position: position,
        ),
      };

  final int position;
}

/// Пакет «изменение»: факты одной подтверждённой транзакции графа.
final class GraphHistoryChange extends GraphHistoryPackage {
  const GraphHistoryChange({required super.position, required this.facts});

  final List<GraphFact> facts;
}

/// Пакет «сброс»: граф заменён, и состояние после замены записано только в
/// снимке, а не фактами.
final class GraphHistoryReset extends GraphHistoryPackage {
  const GraphHistoryReset({required super.position});
}

/// Файлы снимков в собственном каталоге и сборка состояния графа на позиции
/// из снимка и лога фактов.
///
/// Снимок — неизменяемый файл формата данных графа. Он регистрируется в
/// реестре только после надёжной записи, а при каждом чтении сверяется с
/// реестром, потому что вне базы файл журналом не защищён.
///
/// Запись снимка, пересборка и очистка сообщают исход в [DiagnosticsSink];
/// отказ диагностики их исход не меняет.
final class GraphSnapshotStore {
  GraphSnapshotStore({
    required this._log,
    required this._directory,
    required this._clock,
    required this._diagnosticsSink,
  });

  /// Каталог снимков в каталоге данных приложения
  /// [applicationDocumentsDirectory]. На Android это app_flutter, который
  /// правила резервного копирования исключают из облачной копии и переноса.
  static Directory directoryIn(Directory applicationDocumentsDirectory) =>
      Directory.fromUri(
        applicationDocumentsDirectory.uri.resolve('graph_snapshots/'),
      );

  final GraphFactLog _log;

  /// Каталог принадлежит хранилищу: всё, что в нём не зарегистрировано,
  /// удаляет очистка.
  final Directory _directory;
  final DateTime Function() _clock;
  final DiagnosticsSink _diagnosticsSink;

  /// Идущие чтения истории [readHistory]. Отметки не сохраняются: после
  /// завершения процесса идущих чтений нет.
  final _historyReads = <_HistoryReadMark>{};

  /// Состояние графа на позиции [position], не новее текущей, из ближайшего
  /// зарегистрированного снимка не новее неё и пакетов после него.
  ///
  /// Снимок, не прошедший проверку, даёт [GraphSnapshotCorruption] здесь или
  /// в [AssembledGraphState.records] до завершения записей.
  Future<AssembledGraphState> readStateAt(int position) async =>
      _assemble(position, await _log.readSnapshotAtOrBefore(position));

  /// Отмечает чтение истории на время [read]: пока оно идёт,
  /// [removeHistoryBefore] этого хранилища сохраняет выбранную им историю —
  /// базовый снимок состояния и пакеты после него или пакеты после начала
  /// диапазона, — даже когда границу задаёт более старая копия или другое
  /// чтение, а отложенное ради чтения удаление выполняет вызов после его
  /// окончания. Чтение из-за удаления истории не прерывается и не
  /// повторяется.
  ///
  /// Отметка ставится до выбора истории, поэтому удаление истории не
  /// затрагивает ни снимок, который чтение выберет базой, ни пакеты, которые
  /// оно прочитает. Состояние на позиции выбранного источника собирает
  /// [readState] этого или другого хранилища того же каталога, пока [read] не
  /// завершилось.
  Future<T> readHistory<T>(
    Future<T> Function(GraphHistoryRead history) read,
  ) async {
    final mark = _HistoryReadMark();
    _historyReads.add(mark);
    try {
      return await read(GraphHistoryRead._(_log, mark));
    } finally {
      _historyReads.remove(mark);
    }
  }

  /// Состояние графа на позиции источника [state] из его базового снимка и
  /// пакетов после него по правилу [readStateAt].
  Future<AssembledGraphState> readState(GraphStateSource state) =>
      _assemble(state.position, state.base);

  /// Пишет состояние графа на позиции источника [state] по правилу
  /// [readState] в новый файл формата [file] существующего каталога.
  /// Заголовок несёт момент записи по часам хранилища и количества записей.
  ///
  /// [onProgress] получает долю записанных записей от количеств заголовка,
  /// когда она достигает следующей сотой доли, и последней — полную. Файл
  /// не регистрируется и не сбрасывается на диск: он не снимок. Снимок, не
  /// прошедший проверку, даёт [GraphSnapshotCorruption], а при любом отказе
  /// файл удаляется.
  Future<void> writeStateFile(
    GraphStateSource state,
    File file, {
    required void Function(double share) onProgress,
  }) async {
    try {
      final assembled = await readState(state);
      final counts = assembled.counts;
      await _writeTemporary(
        file,
        GraphFormatFile.write(
          GraphFormatHeader(writtenAt: _clock(), counts: counts),
          _reportingProgress(assembled.records, _total(counts), onProgress),
        ),
      );
    } catch (_) {
      await _deleteLeftover(file);
      rethrow;
    }
  }

  /// Пишет состояние графа на позиции источника [state] по правилу
  /// [readState] в новый файл каталога снимков так же надёжно, как
  /// [writeSnapshot], но не регистрирует его: снимок замены графа
  /// регистрирует транзакция замены. Заголовок несёт момент записи по часам
  /// хранилища и количества записей.
  ///
  /// [onProgress] получает ход записи по правилу [writeStateFile]. Когда
  /// [isCancelled] истинно, запись прекращается перед следующей прочитанной
  /// или записанной записью отказом [GraphReplacementSnapshotCancelled].
  /// Снимок, не прошедший проверку, даёт [GraphSnapshotCorruption]. При
  /// отказе и отмене файл удаляется, а файл, оставшийся после завершения
  /// процесса, удаляет [removeUnregisteredFiles]. Запись не выполняется
  /// одновременно с [removeUnregisteredFiles].
  Future<UnregisteredGraphSnapshot> writeReplacementSnapshot(
    GraphStateSource state, {
    required void Function(double share) onProgress,
    required bool Function() isCancelled,
  }) async {
    final assembled = await _assemble(
      state.position,
      state.base,
      isCancelled: isCancelled,
    );
    final counts = assembled.counts;
    return _writeSnapshotFile(
      counts,
      _reportingProgress(
        _untilCancelled(assembled.records, isCancelled),
        _total(counts),
        onProgress,
      ),
    );
  }

  /// Сборка состояния на позиции [position] из снимка [snapshot] и пакетов
  /// после него. Перед каждой записью, прочитанной из снимка, проверяется
  /// отмена [isCancelled]: сборка читает снимок дважды, и первое чтение ради
  /// количеств ещё ничего не пишет.
  Future<AssembledGraphState> _assemble(
    int position,
    GraphSnapshotEntry? snapshot, {
    bool Function() isCancelled = _notCancelled,
  }) {
    final base = snapshot == null
        ? const GraphStateBase.empty()
        : GraphStateBase(
            position: snapshot.position,
            readRecords: () =>
                _untilCancelled(_readSnapshot(snapshot), isCancelled),
          );
    return GraphStateAssembly.assemble(
      base,
      _readPackages(after: base.position, upTo: position),
    );
  }

  /// Пишет снимок состояния на позиции [position], не новее текущей, и
  /// регистрирует его.
  ///
  /// Состояние пишется во временный файл каталога, который после fsync
  /// атомарно переименовывается в файл снимка, а после fsync каталога
  /// снимок регистрируется. При отказе файл удаляется, а реестр не меняется.
  /// Запись не выполняется одновременно с [removeUnregisteredFiles].
  Future<GraphSnapshotEntry> writeSnapshot(int position) async {
    final stopwatch = Stopwatch()..start();
    var stage = GraphSnapshotWriteDiagnosticsStage.stateAssembly;
    try {
      final state = await readStateAt(position);
      stage = GraphSnapshotWriteDiagnosticsStage.fileWrite;
      final snapshot = await _writeState(
        position,
        state,
        beforeRegistration: () =>
            stage = GraphSnapshotWriteDiagnosticsStage.registration,
      );
      _recordDiagnostics(
        GraphSnapshotWriteDiagnosticsEvent.succeeded(
          duration: stopwatch.elapsed,
        ),
      );
      return snapshot;
    } on Object catch (error) {
      _recordDiagnostics(
        GraphSnapshotWriteDiagnosticsEvent.failed(
          stage: stage,
          duration: stopwatch.elapsed,
          code: graphSnapshotFailureCode(error),
        ),
      );
      rethrow;
    }
  }

  /// Пересобирает из базы снимок текущего состояния и регистрирует его, когда
  /// последний снимок не проходит проверку.
  ///
  /// Записи графа читаются короткими порциями во временный файл каталога, а
  /// команды графа выполняются между порциями, поэтому порции отражают разные
  /// позиции лога. Состояние на позиции последней порции собирается из этого
  /// файла и пакетов после позиции первой порции и пишется, как в
  /// [writeSnapshot]. Временный файл удаляется, а при отказе реестр не
  /// меняется. Если между порциями граф заменён, пересборка отказывает
  /// [GraphReplacedInRange]. Пересборка не выполняется одновременно с
  /// [removeUnregisteredFiles].
  Future<GraphSnapshotEntry> rebuildSnapshot() async {
    final stopwatch = Stopwatch()..start();
    var stage = GraphSnapshotRebuildDiagnosticsStage.databaseRead;
    try {
      final snapshot = await _rebuildSnapshot((next) => stage = next);
      _recordDiagnostics(
        GraphSnapshotRebuildDiagnosticsEvent.succeeded(
          duration: stopwatch.elapsed,
        ),
      );
      return snapshot;
    } on Object catch (error) {
      _recordDiagnostics(
        GraphSnapshotRebuildDiagnosticsEvent.failed(
          stage: stage,
          duration: stopwatch.elapsed,
          code: graphSnapshotFailureCode(error),
        ),
      );
      rethrow;
    }
  }

  /// Пересборка по правилу [rebuildSnapshot], которая сообщает [enter] о
  /// начале каждого этапа после чтения базы.
  Future<GraphSnapshotEntry> _rebuildSnapshot(
    void Function(GraphSnapshotRebuildDiagnosticsStage stage) enter,
  ) async {
    await _createDirectory();
    final portions = _file(_temporaryFileName());
    try {
      final (:start, :end, :portionStarts) = await _writePortions(portions);
      enter(GraphSnapshotRebuildDiagnosticsStage.stateAssembly);
      final state = await GraphStateAssembly.assemble(
        GraphStateBase.portions(
          position: start,
          readRecords: () => _readPortions(portions, portionStarts),
        ),
        _readPackages(after: start, upTo: end),
      );
      enter(GraphSnapshotRebuildDiagnosticsStage.fileWrite);
      return await _writeState(
        end,
        state,
        beforeRegistration: () =>
            enter(GraphSnapshotRebuildDiagnosticsStage.registration),
      );
    } finally {
      await _deleteLeftover(portions);
    }
  }

  /// Пишет снимок состояния [state] на позиции [position] и регистрирует
  /// его по правилу [writeSnapshot]; [beforeRegistration] вызывается, когда
  /// файл снимка уже надёжно записан.
  Future<GraphSnapshotEntry> _writeState(
    int position,
    AssembledGraphState state, {
    required void Function() beforeRegistration,
  }) async {
    final written = await _writeSnapshotFile(state.counts, state.records);
    final snapshot = written.entryAt(position);
    try {
      beforeRegistration();
      await _log.registerSnapshot(snapshot);
      return snapshot;
    } catch (_) {
      await _deleteLeftover(_file(written.fileName));
      rethrow;
    }
  }

  /// Пишет файл снимка с количествами [counts] и моментом записи по часам
  /// хранилища в заголовке и записями [records] во временный файл каталога,
  /// который после fsync атомарно переименовывается в файл снимка, а затем
  /// выполняет fsync каталога. При отказе файл удаляется.
  Future<UnregisteredGraphSnapshot> _writeSnapshotFile(
    GraphRecordCounts counts,
    Stream<GraphEntityRecord> records,
  ) async {
    await _createDirectory();
    final fileName = '${const Uuid().v4()}$_snapshotExtension';
    var file = _file('$fileName$_temporaryExtension');
    try {
      final (:byteSize, :checksum) = await _writeDurably(
        file,
        GraphFormatFile.write(
          GraphFormatHeader(writtenAt: _clock(), counts: counts),
          records,
        ),
      );
      file = await file.rename(_file(fileName).path);
      _syncDirectory(_directory);
      return UnregisteredGraphSnapshot(
        fileName: fileName,
        byteSize: byteSize,
        checksum: checksum,
        counts: counts,
      );
    } catch (_) {
      await _deleteLeftover(file);
      rethrow;
    }
  }

  /// Удаляет историю за границей хранения [boundary] по правилу
  /// [GraphFactLog.removeHistoryBefore]: сначала из реестра, затем файлы
  /// удалённых из него снимков. Файл, который не удалось удалить, удаляет
  /// очистка.
  ///
  /// Граница не позже базовых снимков и начал диапазонов идущих чтений
  /// истории [readHistory], а базовые снимки сохраняются, даже когда
  /// ближайший снимок не новее границы старше них. Пока какое-либо из чтений
  /// не выбрало историю, она не удаляется: позиция такого чтения может
  /// предшествовать [boundary], и тогда ему нужна история до неё.
  Future<void> removeHistoryBefore(int boundary) async {
    var retainedBoundary = boundary;
    final readBases = <GraphSnapshotEntry>[];
    for (final read in _historyReads) {
      final history = read.history;
      if (history == null) return;
      retainedBoundary = min(retainedBoundary, history.from);
      if (history.base case final base?) readBases.add(base);
    }
    final removed = await _log.removeHistoryBefore(
      retainedBoundary,
      retained: readBases,
    );
    for (final fileName in removed) {
      await _deleteLeftover(_file(fileName));
    }
  }

  /// Удаляет из каталога снимков незарегистрированные и временные файлы,
  /// которые оставили прерванные и неудачные записи и удаление истории.
  Future<void> removeUnregisteredFiles() async {
    final stopwatch = Stopwatch()..start();
    var stage = GraphSnapshotCleanupDiagnosticsStage.fileRemoval;
    try {
      if (await _directory.exists()) {
        stage = GraphSnapshotCleanupDiagnosticsStage.registryRead;
        final registered = await _log.readSnapshotFileNames();
        stage = GraphSnapshotCleanupDiagnosticsStage.fileRemoval;
        await for (final entity in _directory.list()) {
          if (!registered.contains(entity.uri.pathSegments.last)) {
            await entity.delete();
          }
        }
      }
      _recordDiagnostics(
        GraphSnapshotCleanupDiagnosticsEvent.succeeded(
          duration: stopwatch.elapsed,
        ),
      );
    } on Object catch (error) {
      _recordDiagnostics(
        GraphSnapshotCleanupDiagnosticsEvent.failed(
          stage: stage,
          duration: stopwatch.elapsed,
          code: graphSnapshotFailureCode(error),
        ),
      );
      rethrow;
    }
  }

  /// Пакеты «изменение» после базового состояния сборки. Пакет «сброс» даёт
  /// [GraphReplacedInRange]: граф после него записан только в снимке, и
  /// состояние поверх прежнего графа не собирается.
  Stream<GraphFactPackage> _readPackages({
    required int after,
    required int upTo,
  }) async* {
    await for (final package in _readHistoryPackages(
      _log,
      after: after,
      upTo: upTo,
    )) {
      yield switch (package) {
        GraphHistoryChange(:final position, :final facts) => GraphFactPackage(
          position: position,
          facts: facts,
        ),
        GraphHistoryReset() => throw const GraphReplacedInRange(),
      };
    }
  }

  /// Пишет в [file] записи графа, прочитанные порциями до конца. Возвращает
  /// позиции первой и последней порции и начала порций с новой позицией.
  Future<({int start, int end, List<_PortionStart> portionStarts})>
  _writePortions(File file) async {
    final first = await _log.readGraphRecords();
    var end = first.position;
    final portionStarts = <_PortionStart>[];
    var written = 0;
    Stream<GraphEntityRecord> records() async* {
      for (var portion = first; ;) {
        end = portion.position;
        if (portionStarts.lastOrNull?.position != portion.position) {
          portionStarts.add((firstRecord: written, position: portion.position));
        }
        written += portion.records.length;
        for (final record in portion.records) {
          yield record;
        }
        final next = portion.next;
        if (next == null) return;
        portion = await _log.readGraphRecords(after: next);
      }
    }

    await _writeTemporary(file, GraphFormatFile.writeRecords(records()));
    return (start: first.position, end: end, portionStarts: portionStarts);
  }

  /// Записи файла порций [file] с позициями их порций.
  Stream<GraphStateBaseRecord> _readPortions(
    File file,
    List<_PortionStart> portionStarts,
  ) async* {
    var index = 0;
    var nextStart = 0;
    late int position;
    await for (final record in GraphFormatFile.readRecords(file.openRead())) {
      while (nextStart < portionStarts.length &&
          portionStarts[nextStart].firstRecord <= index) {
        position = portionStarts[nextStart++].position;
      }
      yield (record: record, position: position);
      index++;
    }
  }

  /// Записи снимка, сверенного с реестром: размер — до чтения, SHA-256 —
  /// по прочтении всего файла, до завершения записей.
  Stream<GraphEntityRecord> _readSnapshot(GraphSnapshotEntry snapshot) async* {
    final file = _file(snapshot.fileName);
    try {
      if (await file.length() != snapshot.byteSize) {
        throw const GraphSnapshotCorruption();
      }
      final reading = await GraphFormatFile.read(
        _checked(file.openRead(), snapshot.checksum),
      );
      await for (final record in reading.records) {
        yield record;
      }
    } on PathNotFoundException {
      throw const GraphSnapshotCorruption();
    } on GraphFormatCorruption {
      throw const GraphSnapshotCorruption();
    }
  }

  Future<void> _createDirectory() async {
    if (await _directory.exists()) return;
    await _directory.create(recursive: true);
    _syncDirectory(_directory.parent);
  }

  File _file(String name) => File.fromUri(_directory.uri.resolve(name));

  void _recordDiagnostics(DiagnosticsEvent event) =>
      recordDiagnosticsSafely(_diagnosticsSink, event);
}

const _snapshotExtension = '.jsonl.gz';

const _temporaryExtension = '.tmp';

String _temporaryFileName() =>
    '${const Uuid().v4()}$_snapshotExtension$_temporaryExtension';

/// Отметка идущего чтения истории.
final class _HistoryReadMark {
  var _selecting = false;

  /// История, которую читает чтение: позиция, с которой нужны пакеты, и
  /// базовый снимок состояния; `null` — история ещё не выбрана.
  ({int from, GraphSnapshotEntry? base})? history;

  /// Чтение выбирает историю один раз: история, выбранная повторно, могла
  /// быть удалена после первого выбора.
  void beginSelection() {
    if (_selecting) throw StateError('Чтение истории уже выбрало историю.');
    _selecting = true;
  }
}

/// Пакеты лога [log] после позиции [after] не дальше [upTo], прочитанные
/// порциями, с фактами в текущей версии формата.
Stream<GraphHistoryPackage> _readHistoryPackages(
  GraphFactLog log, {
  required int after,
  required int upTo,
}) async* {
  var next = after;
  while (true) {
    final portion = await log.readPackages(after: next, upTo: upTo);
    if (portion.isEmpty) return;
    for (final package in portion) {
      yield GraphHistoryPackage.decode(package);
    }
    next = portion.last.position;
  }
}

/// Порция файла пересборки, позиция которой отличается от предыдущей: её
/// записи, начиная с записи номер [firstRecord], отражают состояние на
/// [position]. Позиция меняется не чаще пакетов после первой порции.
typedef _PortionStart = ({int firstRecord, int position});

/// Пишет [bytes] в [file] и выполняет fsync: writeFrom передаёт байты
/// системе без буфера процесса, а flush сбрасывает файл на диск.
/// https://api.dart.dev/dart-io/RandomAccessFile/flush.html
Future<({int byteSize, Uint8List checksum})> _writeDurably(
  File file,
  Stream<List<int>> bytes,
) async {
  final digest = _DigestSink();
  final hashing = sha256.startChunkedConversion(digest);
  var byteSize = 0;
  final output = await file.open(mode: FileMode.writeOnly);
  try {
    await for (final chunk in bytes) {
      await output.writeFrom(chunk);
      hashing.add(chunk);
      byteSize += chunk.length;
    }
    await output.flush();
  } finally {
    await output.close();
  }
  hashing.close();
  return (byteSize: byteSize, checksum: Uint8List.fromList(digest.value.bytes));
}

/// Записи [records], по мере выдачи которых [onProgress] получает долю
/// выданных записей от [total], когда она достигает следующей сотой доли.
///
/// Ход записи пересекает границу изолятов сообщениями, поэтому их число не
/// растёт с размером графа.
Stream<GraphEntityRecord> _reportingProgress(
  Stream<GraphEntityRecord> records,
  int total,
  void Function(double share) onProgress,
) {
  var written = 0;
  var reportedSteps = 0;
  return records.map((record) {
    written++;
    final steps = written * _progressSteps ~/ total;
    if (steps > reportedSteps) {
      reportedSteps = steps;
      onProgress(written / total);
    }
    return record;
  });
}

/// Число долей, которыми сообщается ход записи состояния.
const _progressSteps = 100;

/// Записи [records], перед выдачей каждой из которых проверяется отмена
/// [isCancelled]: отменённая запись завершается отказом
/// [GraphReplacementSnapshotCancelled].
Stream<GraphEntityRecord> _untilCancelled(
  Stream<GraphEntityRecord> records,
  bool Function() isCancelled,
) => records.map((record) {
  if (isCancelled()) throw const GraphReplacementSnapshotCancelled();
  return record;
});

bool _notCancelled() => false;

int _total(GraphRecordCounts counts) =>
    counts.tags +
    counts.intentions +
    counts.tagAssignments +
    counts.longTermRelations +
    counts.dailyChoices;

/// Пишет [bytes] в [file] без сброса на диск: файлы порций пересборки и
/// состояния — не снимки, и после сбоя процесса они не нужны.
Future<void> _writeTemporary(File file, Stream<List<int>> bytes) async {
  final output = await file.open(mode: FileMode.writeOnly);
  try {
    await for (final chunk in bytes) {
      await output.writeFrom(chunk);
    }
  } finally {
    await output.close();
  }
}

/// Передаёт байты [file] как есть и по их окончании сверяет SHA-256 с
/// [checksum].
Stream<List<int>> _checked(Stream<List<int>> file, Uint8List checksum) async* {
  final digest = _DigestSink();
  final hashing = sha256.startChunkedConversion(digest);
  await for (final chunk in file) {
    hashing.add(chunk);
    yield chunk;
  }
  hashing.close();
  if (digest.value != Digest(checksum)) throw const GraphSnapshotCorruption();
}

/// Оставшийся файл удаляет следующая очистка, поэтому отказ удаления не
/// прерывает удаление истории и не заменяет исходный отказ записи.
Future<void> _deleteLeftover(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Файла нет, или его удалит очистка.
  }
}

final class _DigestSink implements Sink<Digest> {
  late final Digest value;

  @override
  void add(Digest digest) => value = digest;

  @override
  void close() {}
}

/// Сбрасывает на диск записи каталога [directory] о созданных и
/// переименованных в нём файлах. dart:io не открывает каталоги, поэтому
/// fsync каталога выполняется через libc синхронно и занимает изолят до
/// своего окончания.
void _syncDirectory(Directory directory) {
  final path = Uint8List.fromList([...utf8.encode(directory.path), 0]);
  final handle = _openDirectory(path.address);
  if (handle == nullptr) {
    throw const FileSystemException('Каталог не открыт для fsync.');
  }
  try {
    if (_fsync(_directoryDescriptor(handle)) != 0) {
      throw const FileSystemException('fsync каталога не выполнен.');
    }
  } finally {
    _closeDirectory(handle);
  }
}

@Native<Pointer<Void> Function(Pointer<Uint8>)>(symbol: 'opendir', isLeaf: true)
external Pointer<Void> _openDirectory(Pointer<Uint8> path);

@Native<Int Function(Pointer<Void>)>(symbol: 'dirfd')
external int _directoryDescriptor(Pointer<Void> directory);

@Native<Int Function(Int)>(symbol: 'fsync')
external int _fsync(int descriptor);

@Native<Int Function(Pointer<Void>)>(symbol: 'closedir')
external int _closeDirectory(Pointer<Void> directory);
