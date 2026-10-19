import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_export.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/file_document_access.dart';
import '../../test/support/in_memory_diagnostics_sink.dart';
import 'graph_backup_restore.dart';
import 'graph_file_import.dart';

const _operationVariable = 'DOABLE_GRAPH_LOG_OPERATION';
const _pathVariable = 'DOABLE_GRAPH_LOG_PATH';
const _snapshotsVariable = 'DOABLE_GRAPH_LOG_SNAPSHOTS';
const _documentVariable = 'DOABLE_GRAPH_LOG_DOCUMENT';
const _resultMarker = 'DOABLE_GRAPH_LOG_MEMORY:';

/// Насколько пик живых данных операции на профиле может превышать её пик на
/// графе в десять раз меньше: замеры одной операции колеблются на несколько
/// мебибайт, а данные, растущие с графом, заняли бы на профиле десятки.
const graphLogMemoryNoiseBytes = 8 << 20;

/// Операция, память которой измеряет отдельный процесс.
///
/// Сравнение графов разного размера ведётся по живым данным кучи Dart после
/// принудительной сборки мусора: они не зависят от того, когда сборщик
/// успел освободить мусор. Пик resident set size отладочной VM Flutter для
/// этого не годится: он растёт с длительностью работы, пока буферы
/// профилировщика и таймлайна и арены malloc не выйдут на плато.
enum GraphLogMemoryOperation {
  /// Сборка состояния на текущей позиции из последнего снимка и пакетов
  /// после него до последней записи: наибольший объём живых данных за время
  /// сборки.
  assembly,

  /// Сжатие лога в новый снимок в отдельном изоляте, как в приложении:
  /// наибольший объём живых данных за время сжатия.
  compaction,

  /// Экспорт состояния на текущей позиции от выбранного документа до
  /// записанного; документ — локальный файл, в который копируется временный
  /// файл экспорта: наибольший объём живых данных за время экспорта.
  export,

  /// Восстановление ручной копии, которую сделала подготовка графа, от
  /// подтверждения до замены графа: наибольший объём живых данных кучи
  /// вместе с памятью malloc процесса. В ней SQLite держит кэш страниц и
  /// журналы операторов транзакции замены: в этой сборке они живут в памяти
  /// (`SQLITE_TEMP_STORE=2`).
  restore,

  /// Импорт файла экспорта от выбранного документа до замены графа его
  /// записями: копирование документа во временный файл, чтение заголовка,
  /// запись снимка замены и замена. Замер — наибольший объём живых данных
  /// кучи вместе с памятью malloc процесса, как у [restore].
  import,

  /// Итог фактов пакетов после последнего снимка: живые данные, которые
  /// собранное состояние удерживает до выдачи записей.
  rangeSummary,

  /// Чтение файла формата до последней записи: пик resident set size,
  /// то есть память вместе с мусором до его сборки.
  fileRead,
}

/// Прирост памяти операции над её значением перед операцией и число
/// выданных операцией записей; у сжатия записей нет, у экспорта это записи
/// записанного документа, а у восстановления и импорта — записи графа после
/// замены.
typedef GraphLogMemory = ({int growthBytes, int records});

/// Выполняет [operation] в новом процессе Flutter: операции лога — над
/// базой [path] с каталогом снимков [snapshots], импорт — ещё и документа
/// [document], чтение — над файлом формата [path].
///
/// Отдельный процесс не наследует память, которую заняли подготовка данных
/// и предыдущие замеры: освобождённая память остаётся у процесса, и рост
/// операции на её месте не виден.
Future<GraphLogMemory> measureGraphLogMemory(
  GraphLogMemoryOperation operation,
  File path, {
  Directory? snapshots,
  File? document,
}) async {
  final result = await Process.run(
    _findFlutterExecutable(),
    [
      'test',
      '--no-pub',
      if (operation != GraphLogMemoryOperation.fileRead) '--enable-vmservice',
      '--reporter',
      'compact',
      'benchmark/support/graph_log_memory_worker.dart',
    ],
    workingDirectory: Directory.current.path,
    environment: {
      _operationVariable: operation.name,
      _pathVariable: path.path,
      _snapshotsVariable: ?snapshots?.path,
      _documentVariable: ?document?.path,
    },
  );
  final output = result.stdout as String;
  final line = const LineSplitter()
      .convert(output)
      .where((line) => line.contains(_resultMarker))
      .firstOrNull;
  if (result.exitCode != 0 || line == null) {
    throw StateError(
      'Процесс замера памяти завершился с кодом ${result.exitCode}.\n'
      'stdout:\n$output\nstderr:\n${result.stderr}',
    );
  }
  final json = jsonDecode(
    line.substring(line.indexOf(_resultMarker) + _resultMarker.length),
  ) as Map<String, Object?>;
  return (
    growthBytes: json['growthBytes']! as int,
    records: json['records']! as int,
  );
}

void main() {
  test('процесс измеряет память операции лога фактов', () async {
    final environment = Platform.environment;
    final path = File(environment[_pathVariable]!);
    final operation = GraphLogMemoryOperation.values.byName(
      environment[_operationVariable]!,
    );
    final run = switch (operation) {
      GraphLogMemoryOperation.fileRead => () => _readFile(path),
      GraphLogMemoryOperation.restore => _restoreInIsolate(
        path,
        Directory(environment[_snapshotsVariable]!),
      ),
      GraphLogMemoryOperation.import => _importInIsolate(
        path,
        Directory(environment[_snapshotsVariable]!),
        File(environment[_documentVariable]!),
        await _temporaryDirectory('doable_graph_import_'),
      ),
      _ => await _openGraphOperation(
        operation,
        path,
        Directory(environment[_snapshotsVariable]!),
      ),
    };
    final measurement = switch (operation) {
      GraphLogMemoryOperation.assembly ||
      GraphLogMemoryOperation.compaction ||
      GraphLogMemoryOperation.export => await _LiveHeapPeak.start(),
      GraphLogMemoryOperation.restore ||
      GraphLogMemoryOperation.import => await _LiveHeapPeak.startWithMalloc(),
      GraphLogMemoryOperation.rangeSummary => await _RetainedLiveHeap.start(),
      GraphLogMemoryOperation.fileRead => _ResidentSetPeak.start(),
    };
    // Приложение работает в корневой зоне, а зона теста в несколько раз
    // замедляет потоки.
    final outcome = await Zone.root.run(run);
    final growth = await measurement.finish();
    final records = await Zone.root.run(outcome);
    stdout.writeln(
      '$_resultMarker${jsonEncode({'growthBytes': growth, 'records': records})}',
    );
  }, timeout: Timeout.none);
}

/// Замеряемая операция. Её итог читается после замера, поэтому данные,
/// которые он удерживает, живы до конца замера.
typedef _Operation = Future<_Outcome> Function();

/// Число записей операции.
typedef _Outcome = Future<int> Function();

Future<_Operation> _openGraphOperation(
  GraphLogMemoryOperation operation,
  File databaseFile,
  Directory snapshots,
) async {
  final database = AppDatabase(openFileBackedLocalDatabase(databaseFile));
  addTearDown(database.close);
  final repository = await _openRepository(database);
  final position = await repository.readCurrentPosition();
  final diagnostics = InMemoryDiagnosticsSink();
  final store = GraphSnapshotStore(
    log: repository,
    directory: snapshots,
    clock: () => _now,
    diagnosticsSink: diagnostics,
  );
  return switch (operation) {
    GraphLogMemoryOperation.assembly => () async {
      final records = await (await store.readStateAt(position)).records.length;
      return () async => records;
    },
    GraphLogMemoryOperation.rangeSummary => () async {
      final state = await store.readStateAt(position);
      return () => state.records.length;
    },
    GraphLogMemoryOperation.compaction => () async {
      final compaction = GraphLogCompaction(
        log: repository,
        directory: snapshots,
        clock: () => _now,
        diagnosticsSink: diagnostics,
      )..start();
      await compaction.shutdown();
      final outcomes = diagnostics.events
          .whereType<GraphLogCompactionDiagnosticsEvent>()
          .map((event) => event.status);
      final snapshot = await repository.readSnapshotAtOrBefore(position);
      if (outcomes.single is! DiagnosticsSucceeded ||
          snapshot?.position != position) {
        throw StateError('Сжатие не записало снимок текущей позиции.');
      }
      return () async => 0;
    },
    GraphLogMemoryOperation.export => await _openExport(
      repository,
      snapshots,
      diagnostics,
    ),
    GraphLogMemoryOperation.restore ||
    GraphLogMemoryOperation.import ||
    GraphLogMemoryOperation.fileRead => throw ArgumentError.value(operation),
  };
}

/// Экспорт в документ, уже выбранный до замера, как после системного
/// диалога сохранения.
Future<_Operation> _openExport(
  DriftPersonalGraphRepository repository,
  Directory snapshots,
  InMemoryDiagnosticsSink diagnostics,
) async {
  final directory = await _temporaryDirectory('doable_graph_export_');
  final documents = FileDocumentAccess(
    await Directory.fromUri(directory.uri.resolve('documents/')).create(),
  );
  final export = GraphExport(
    documents: documents,
    compaction: GraphLogCompaction(
      log: repository,
      directory: snapshots,
      clock: () => _now,
      diagnosticsSink: diagnostics,
    ),
    temporaryDirectory: Future.value(
      Directory.fromUri(directory.uri.resolve('tmp/')),
    ),
    clock: () => _now,
    diagnosticsSink: diagnostics,
  );
  final DocumentCreated(:document) = documents.newDocument();
  return () async {
    final outcome = await export.write(document, onProgress: (_) {});
    if (outcome != GraphExportOutcome.succeeded) {
      throw StateError('Экспорт не записал документ.');
    }
    return () async =>
        (await GraphFormatFile.read(documents.created.single.openRead()))
            .records
            .length;
  };
}

/// Восстановление ручной копии, которую сделала подготовка графа, как после
/// подтверждения восстановления, в отдельном изоляте той же группы.
///
/// Замена графа занимает свой изолят без пауз: драйвер SQLite синхронный, а
/// каждый шаг замены продолжает предыдущий в той же очереди микрозадач. В
/// изоляте замены ответ на сборку мусора доходил бы до замера лишь между
/// шагами, и память читалась бы вместе с мусором, накопленным за эти шаги.
/// Куча у изолятов одной группы общая, поэтому замер охватывает и изолят
/// замены.
_Operation _restoreInIsolate(File databaseFile, Directory snapshots) =>
    () async {
      final records = await Isolate.run(() async {
        final database = AppDatabase(openFileBackedLocalDatabase(databaseFile));
        try {
          final restore = BenchmarkGraphRestore(
            await _openRepository(database),
            snapshots: snapshots,
            clock: () => _now,
          );
          try {
            await restore.restore(await restore.readManualBackup());
          } finally {
            await restore.dispose();
          }
          return await _graphRecords(database);
        } finally {
          await database.close();
        }
      });
      return () async => records;
    };

/// Импорт документа [document], выбранного в диалоге выбора, через временный
/// каталог [temporary], как после подтверждения импорта, в отдельном изоляте
/// той же группы по той же причине, что и [_restoreInIsolate].
_Operation _importInIsolate(
  File databaseFile,
  Directory snapshots,
  File document,
  Directory temporary,
) => () async {
  final records = await Isolate.run(() async {
    final database = AppDatabase(openFileBackedLocalDatabase(databaseFile));
    try {
      final import = BenchmarkGraphImport(
        await _openRepository(database),
        document: document,
        snapshots: snapshots,
        temporary: temporary,
        clock: () => _now,
      );
      try {
        await import.importFile(await import.readChosenFile());
      } finally {
        await import.dispose();
      }
      return await _graphRecords(database);
    } finally {
      await database.close();
    }
  });
  return () async => records;
};

/// Число записей графа в базе [database].
Future<int> _graphRecords(AppDatabase database) async {
  final row = await database.customSelect('''SELECT
    (SELECT count(*) FROM tags) + (SELECT count(*) FROM intentions) +
    (SELECT count(*) FROM tag_assignments) +
    (SELECT count(*) FROM long_term_relations) +
    (SELECT count(*) FROM daily_choices) AS records''').getSingle();
  return row.read<int>('records');
}

/// Новый временный каталог с префиксом [prefix], который удаляется в конце
/// замера.
Future<Directory> _temporaryDirectory(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

final _now = DateTime.utc(2026, 10, 17, 12);

Future<DriftPersonalGraphRepository> _openRepository(
  AppDatabase database,
) async {
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => _now,
    InMemoryDiagnosticsSink(),
  );
  // Первое обращение открывает базу до замера.
  await repository.readCurrentPosition();
  return repository;
}

Future<_Outcome> _readFile(File file) async {
  final records = await (await GraphFormatFile.read(file.openRead()))
      .records
      .length;
  return () async => records;
}

/// Замер памяти от начала операции до [finish].
sealed class _Measurement {
  /// Прирост памяти над её значением в начале операции.
  Future<int> finish();
}

/// Наибольший объём живых данных кучи после принудительной сборки мусора,
/// которую процесс повторяет, пока идёт операция.
///
/// У изолятов одной группы общая куча, поэтому замер охватывает и изолят
/// записи снимка.
final class _LiveHeapPeak implements _Measurement {
  _LiveHeapPeak._(this._service, this._read, this._baseline)
    : _peak = _baseline {
    _sampling = _sample();
  }

  static Future<_LiveHeapPeak> start() =>
      _start((service) => service.readLiveBytes());

  /// Замер, который прибавляет к живым данным кучи память malloc процесса,
  /// занятую в момент замера. Кучу Dart VM размещает не в malloc, а в
  /// отображённых страницах, поэтому она не учитывается дважды.
  static Future<_LiveHeapPeak> startWithMalloc() => _start(
    (service) async => await service.readLiveBytes() + _mallocInUseBytes(),
  );

  static Future<_LiveHeapPeak> _start(
    Future<int> Function(_VmService service) read,
  ) async {
    final service = await _VmService.connect();
    return _LiveHeapPeak._(service, read, await read(service));
  }

  /// Пауза между сборками: непрерывная сборка мусора замедлила бы сжатие
  /// вдвое.
  static const _interval = Duration(milliseconds: 50);

  /// Без нескольких замеров во время операции её пик неизвестен.
  static const _minimumSamples = 3;

  final _VmService _service;
  final Future<int> Function(_VmService service) _read;
  final int _baseline;
  int _peak;
  var _samples = 0;
  var _finished = false;
  late final Future<void> _sampling;

  Future<void> _sample() async {
    while (!_finished) {
      final live = await _read(_service);
      if (_finished) break;
      if (live > _peak) _peak = live;
      _samples++;
      await Future<void>.delayed(_interval);
    }
  }

  @override
  Future<int> finish() async {
    _finished = true;
    await _sampling;
    await _service.close();
    if (_samples < _minimumSamples) {
      throw StateError('Операция завершилась за $_samples замеров памяти.');
    }
    return _peak - _baseline;
  }
}

/// Живые данные кучи после принудительной сборки мусора в конце операции,
/// пока её итог удерживает свои данные.
final class _RetainedLiveHeap implements _Measurement {
  _RetainedLiveHeap._(this._service, this._baseline);

  static Future<_RetainedLiveHeap> start() async {
    final service = await _VmService.connect();
    return _RetainedLiveHeap._(service, await service.readLiveBytes());
  }

  final _VmService _service;
  final int _baseline;

  @override
  Future<int> finish() async {
    final retained = await _service.readLiveBytes() - _baseline;
    await _service.close();
    return retained;
  }
}

/// Пик resident set size процесса с начала операции.
final class _ResidentSetPeak implements _Measurement {
  _ResidentSetPeak._(this._baseline);

  /// Сбрасывает пик процесса до его текущего размера:
  /// https://docs.kernel.org/filesystems/proc.html#proc-pid-clear-refs
  factory _ResidentSetPeak.start() {
    if (!Platform.isLinux) {
      throw UnsupportedError('Пик resident set size читается из /proc Linux.');
    }
    final baseline = _status('VmRSS');
    File('/proc/self/clear_refs').openSync(mode: FileMode.writeOnly)
      ..writeStringSync('5')
      ..closeSync();
    return _ResidentSetPeak._(baseline);
  }

  final int _baseline;

  @override
  Future<int> finish() async => _status('VmHWM') - _baseline;

  /// Значение поля [field] из /proc/self/status в байтах.
  static int _status(String field) {
    final line = File('/proc/self/status')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('$field:'));
    return int.parse(line.split(RegExp(r'\s+'))[1]) * 1024;
  }
}

/// Память, занятая в malloc процесса во всех его аренах, по mallinfo2
/// glibc: https://man7.org/linux/man-pages/man3/mallinfo.3.html
int _mallocInUseBytes() {
  if (!Platform.isLinux) {
    throw UnsupportedError('Память malloc читается из glibc Linux.');
  }
  final info = _mallinfo2();
  return info.uordblks + info.hblkhd;
}

final _mallinfo2 = DynamicLibrary.process()
    .lookupFunction<_MallInfo2 Function(), _MallInfo2 Function()>('mallinfo2');

/// `struct mallinfo2` glibc.
final class _MallInfo2 extends Struct {
  @Size()
  external int arena;
  @Size()
  external int ordblks;
  @Size()
  external int smblks;
  @Size()
  external int hblks;

  /// Байты блоков, выделенных отдельными отображениями.
  @Size()
  external int hblkhd;
  @Size()
  external int usmblks;
  @Size()
  external int fsmblks;

  /// Байты занятых блоков арен.
  @Size()
  external int uordblks;
  @Size()
  external int fordblks;
  @Size()
  external int keepcost;
}

/// Клиент JSON-RPC протокола VM service текущего процесса.
final class _VmService {
  _VmService._(this._socket, this._replies);

  static Future<_VmService> connect() async {
    final uri = (await Service.getInfo()).serverUri;
    if (uri == null) throw StateError('VM service процесса не запущен.');
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
    );
    return _VmService._(socket, StreamIterator(socket));
  }

  final WebSocket _socket;
  final StreamIterator<Object?> _replies;
  final _isolateId = Service.getIsolateId(Isolate.current)!;
  var _nextId = 0;

  /// Объём кучи и внешних данных после полной сборки мусора.
  ///
  /// Сборку выполняет закрытый метод VM service, которым её запускает и
  /// flutter_driver этой версии Flutter
  /// (packages/flutter_driver/lib/src/driver/vmservice_driver.dart).
  /// Открытый getAllocationProfile с gc тоже собирает мусор, но его ответ о
  /// всех классах разбирается в десятки мегабайт объектов и сам попадает в
  /// замер.
  Future<int> readLiveBytes() async {
    final isolate = {'isolateId': _isolateId};
    await _call('_collectAllGarbage', isolate);
    final usage = await _call('getMemoryUsage', isolate);
    return (usage['heapUsage']! as int) + (usage['externalUsage']! as int);
  }

  Future<void> close() => _socket.close();

  /// Вызовы идут по одному, поэтому ответ — следующее сообщение с тем же
  /// номером; события потоков без подписки не приходят.
  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> parameters,
  ) async {
    final id = '${_nextId++}';
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': parameters,
      }),
    );
    while (await _replies.moveNext()) {
      final reply = jsonDecode(_replies.current! as String) as Map;
      if (reply['id'] != id) continue;
      if (reply['result'] case final Map<String, Object?> result) {
        return result;
      }
      throw StateError('VM service отклонил $method: ${reply['error']}.');
    }
    throw StateError('VM service закрыл соединение.');
  }
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File('${directory.path}/bin/flutter');
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Не найден Flutter SDK для дочернего процесса.');
    }
    directory = parent;
  }
}
