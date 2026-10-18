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

/// Безопасная категория отказа операции со снимками для диагностики.
///
/// Снимок, не прошедший проверку, отличается от повреждения данных лога и
/// базы, в том числе строк графа вне формы хранения; отказы файлов снимков
/// относятся к недоступности хранилища, как у файла настройки установки.
/// Замена графа во время чтения истории — конфликт с одновременным
/// изменением.
DiagnosticsFailureCode graphSnapshotFailureCode(Object error) =>
    switch (error) {
      GraphSnapshotCorruption() => DiagnosticsFailureCode.snapshotCorruption,
      GraphReplacedInRange() => DiagnosticsFailureCode.conflict,
      GraphFormatCorruption() ||
      GraphRecordCorruption() => DiagnosticsFailureCode.corruption,
      FileSystemException() => DiagnosticsFailureCode.unavailable,
      _ => switch (classifySqliteFailure(error)) {
        SqliteCorruptionFailure() => DiagnosticsFailureCode.corruption,
        SqliteUnavailableFailure() => DiagnosticsFailureCode.unavailable,
        SqliteConstraintFailure() ||
        SqliteUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
      },
    };

/// Чтение истории, отмеченное [GraphSnapshotStore.readHistory]: позиция, на
/// которой собирается состояние, и её базовый снимок.
final class GraphHistoryRead {
  const GraphHistoryRead._(this.position, this.base);

  /// Позиция, текущая в начале чтения.
  final int position;

  /// Ближайший зарегистрированный снимок не новее [position]; `null` — такого
  /// снимка нет, и базой служит пустой граф позиции 0.
  final GraphSnapshotEntry? base;
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
  /// [removeHistoryBefore] этого хранилища сохраняет его базовый снимок и
  /// пакеты после него, даже когда границу задаёт более старая копия или
  /// другое чтение, а отложенное ради чтения удаление выполняет вызов после
  /// его окончания.
  ///
  /// Отметка ставится до чтения текущей позиции и выбора базового снимка,
  /// поэтому удаление истории не затрагивает ни снимок, который чтение
  /// выберет базой, ни пакеты после него. Состояние на позиции чтения
  /// собирает [readState] этого или другого хранилища того же каталога, пока
  /// [read] не завершилось.
  Future<T> readHistory<T>(
    Future<T> Function(GraphHistoryRead history) read,
  ) async {
    final mark = _HistoryReadMark();
    _historyReads.add(mark);
    try {
      final position = await _log.readCurrentPosition();
      final history = GraphHistoryRead._(
        position,
        await _log.readSnapshotAtOrBefore(position),
      );
      mark.history = history;
      return await read(history);
    } finally {
      _historyReads.remove(mark);
    }
  }

  /// Состояние графа на позиции чтения истории [history] из его базового
  /// снимка и пакетов после него по правилу [readStateAt].
  Future<AssembledGraphState> readState(GraphHistoryRead history) =>
      _assemble(history.position, history.base);

  /// Пишет состояние графа на позиции чтения истории [history] по правилу
  /// [readState] в новый файл формата [file] существующего каталога.
  /// Заголовок несёт момент записи по часам хранилища и количества записей.
  ///
  /// [onProgress] получает долю записанных записей от количеств заголовка,
  /// когда она достигает следующей сотой доли, и последней — полную. Файл
  /// не регистрируется и не сбрасывается на диск: он не снимок. Снимок, не
  /// прошедший проверку, даёт [GraphSnapshotCorruption], а при любом отказе
  /// файл удаляется.
  Future<void> writeStateFile(
    GraphHistoryRead history,
    File file, {
    required void Function(double share) onProgress,
  }) async {
    try {
      final state = await readState(history);
      final counts = state.counts;
      await _writeTemporary(
        file,
        GraphFormatFile.write(
          GraphFormatHeader(writtenAt: _clock(), counts: counts),
          _reportingProgress(state.records, _total(counts), onProgress),
        ),
      );
    } catch (_) {
      await _deleteLeftover(file);
      rethrow;
    }
  }

  Future<AssembledGraphState> _assemble(
    int position,
    GraphSnapshotEntry? snapshot,
  ) {
    final base = snapshot == null
        ? const GraphStateBase.empty()
        : GraphStateBase(
            position: snapshot.position,
            readRecords: () => _readSnapshot(snapshot),
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
    await _createDirectory();
    final fileName = '${const Uuid().v4()}$_snapshotExtension';
    var file = _file('$fileName$_temporaryExtension');
    try {
      final (:byteSize, :checksum) = await _writeDurably(
        file,
        GraphFormatFile.write(
          GraphFormatHeader(writtenAt: _clock(), counts: state.counts),
          state.records,
        ),
      );
      file = await file.rename(_file(fileName).path);
      _syncDirectory(_directory);
      final snapshot = GraphSnapshotEntry(
        position: position,
        fileName: fileName,
        byteSize: byteSize,
        checksum: checksum,
      );
      beforeRegistration();
      await _log.registerSnapshot(snapshot);
      return snapshot;
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
  /// Граница не позже базовых снимков идущих чтений истории [readHistory],
  /// и сами эти снимки сохраняются, даже когда ближайший снимок не новее
  /// границы старше них. Пока базовый снимок какого-либо из чтений не выбран,
  /// история не удаляется: позиция такого чтения может предшествовать
  /// [boundary], и тогда ему нужна история до неё.
  Future<void> removeHistoryBefore(int boundary) async {
    var retainedBoundary = boundary;
    final readBases = <GraphSnapshotEntry>[];
    for (final read in _historyReads) {
      final history = read.history;
      if (history == null) return;
      final base = history.base;
      retainedBoundary = min(retainedBoundary, base?.position ?? 0);
      if (base != null) readBases.add(base);
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
    var next = after;
    while (true) {
      final portion = await _log.readPackages(after: next, upTo: upTo);
      if (portion.isEmpty) return;
      for (final package in portion) {
        yield switch (package) {
          StoredGraphChangePackage(
            :final position,
            :final formatVersion,
            :final facts,
          ) =>
            GraphFactPackage(
              position: position,
              facts: GraphFormatCodec.decodePackage(
                facts,
                GraphFormatVersion.ofCarrier(formatVersion),
              ),
            ),
          StoredGraphResetPackage() => throw const GraphReplacedInRange(),
        };
      }
      next = portion.last.position;
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
  /// Позиция и базовый снимок чтения; `null` — снимок ещё не выбран.
  GraphHistoryRead? history;
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
