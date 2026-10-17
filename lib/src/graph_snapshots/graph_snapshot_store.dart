import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../graph_format/graph_format_codec.dart';
import '../graph_format/graph_format_file.dart';
import '../graph_format/graph_format_records.dart';
import 'graph_fact_log.dart';
import 'graph_state_assembly.dart';

/// Снимок не прошёл проверку при чтении: размер или SHA-256 файла не
/// совпали с реестром, файла нет или его записи не читаются.
///
/// Отказ не несёт прочитанных данных: в них пользовательский текст.
final class GraphSnapshotCorruption implements Exception {
  const GraphSnapshotCorruption();
}

/// Файлы снимков в собственном каталоге и сборка состояния графа на позиции
/// из снимка и лога фактов.
///
/// Снимок — неизменяемый файл формата данных графа. Он регистрируется в
/// реестре только после надёжной записи, а при каждом чтении сверяется с
/// реестром, потому что вне базы файл журналом не защищён.
final class GraphSnapshotStore {
  GraphSnapshotStore({
    required this._log,
    required this._directory,
    required this._clock,
  });

  final GraphFactLog _log;

  /// Каталог принадлежит хранилищу: всё, что в нём не зарегистрировано,
  /// удаляет очистка.
  final Directory _directory;
  final DateTime Function() _clock;

  /// Состояние графа на позиции [position], не новее текущей, из ближайшего
  /// зарегистрированного снимка не новее неё и пакетов после него.
  ///
  /// Снимок, не прошедший проверку, даёт [GraphSnapshotCorruption] здесь или
  /// в [AssembledGraphState.records] до завершения записей.
  Future<AssembledGraphState> readStateAt(int position) async {
    final snapshot = await _log.readSnapshotAtOrBefore(position);
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
    final state = await readStateAt(position);
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
        formatVersion: GraphFormatVersion.current.number,
        fileName: fileName,
        byteSize: byteSize,
        checksum: checksum,
      );
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
  Future<void> removeHistoryBefore(int boundary) async {
    for (final fileName in await _log.removeHistoryBefore(boundary)) {
      await _deleteLeftover(_file(fileName));
    }
  }

  /// Удаляет из каталога снимков незарегистрированные и временные файлы,
  /// которые оставили прерванные и неудачные записи и удаление истории.
  Future<void> removeUnregisteredFiles() async {
    if (!await _directory.exists()) return;
    final registered = await _log.readSnapshotFileNames();
    await for (final entity in _directory.list()) {
      if (!registered.contains(entity.uri.pathSegments.last)) {
        await entity.delete();
      }
    }
  }

  Stream<GraphFactPackage> _readPackages({
    required int after,
    required int upTo,
  }) async* {
    var next = after;
    while (true) {
      final portion = await _log.readPackages(after: next, upTo: upTo);
      if (portion.isEmpty) return;
      for (final package in portion) {
        yield GraphFactPackage(
          position: package.position,
          facts: GraphFormatCodec.decodePackage(
            package.facts,
            GraphFormatVersion.ofCarrier(package.formatVersion),
          ),
        );
      }
      next = portion.last.position;
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
}

const _snapshotExtension = '.jsonl.gz';

const _temporaryExtension = '.tmp';

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
