import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/data/local/app_database.dart'
    show LocalDatabaseConnectionObserver, LocalDatabaseSqlStatement;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/graph_seed.dart';
import '../../test/support/in_memory_diagnostics_sink.dart';
import '../../test/support/local_database_harness.dart';
import '../support/benchmark.dart';
import '../support/graph_log_fixture.dart';
import '../support/graph_log_memory_worker.dart';

/// Длина диапазона пакетов после снимка, на которой начинается сжатие.
const _rangePackages = graphLogCompactionThreshold + 1;

/// Насколько пик живых данных на профиле может превышать пик на графе в
/// десять раз меньше: замеры одной операции колеблются на несколько
/// мебибайт, а данные, растущие с графом, заняли бы на профиле десятки.
const _memoryNoiseBytes = 8 << 20;

/// Замеров сжатия профиля в серии. Сжатие длится десятки секунд, а его
/// замеры расходятся на проценты, поэтому сорок замеров заняли бы полчаса
/// без пользы. Прогрев не нужен: код сборки и записи снимка уже
/// скомпилирован подготовкой снимка профиля, а изоляты одной группы делят
/// код.
const _compactionSeriesSamples = 3;

/// Бюджет наибольшей длительности сжатия лога профиля в серии.
const _compactionBudgetMs = 45000;

/// Связей у намерения, которое архивирует каскадная команда профиля.
const _cascadeRelations = 1000;

void main() {
  // Графы общие для наборов и строятся при первом обращении: граф профиля
  // строится больше минуты. Набор команд выключает захват фактов, после
  // чего лог профиля расходится с базой, поэтому он идёт последним.
  final trace = _CommandTrace();
  final smaller = _GraphOnce(graphLogProfileEntities ~/ 10);
  final profile = _GraphOnce(
    graphLogProfileEntities,
    hubRelations: _cascadeRelations,
    observer: trace,
  );
  tearDownAll(() async {
    await smaller.dispose();
    await profile.dispose();
  });

  test(
    'бенчмарк лога фактов: память чтения файла из записей на пределе',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'doable_graph_log_records_',
      );
      addTearDown(() => directory.delete(recursive: true));
      // Файлы одного объёма читаются примерно одинаково долго, и буферы
      // отладочной VM растут в них одинаково.
      const fileBytes = 32 * graphFormatRecordByteLimit;
      for (final recordBytes in [
        graphFormatRecordByteLimit ~/ 16,
        graphFormatRecordByteLimit,
      ]) {
        final file = File('${directory.path}/records_$recordBytes.jsonl.gz');
        final records = fileBytes ~/ recordBytes;
        await _writeRecordsOfLength(file, records, recordBytes);
        final memory = await measureGraphLogMemory(
          GraphLogMemoryOperation.fileRead,
          file,
        );
        expect(memory.records, records);
        _report({
          'benchmark': 'graphLogRecordLimitRead',
          'recordLimitBytes': graphFormatRecordByteLimit,
          'recordBytes': recordBytes,
          'records': records,
          'residentSetPeakMiB': _mebibytes(memory.growthBytes),
        });
        await file.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('бенчмарк лога фактов: память сборки состояния и сжатия не растёт '
      'с размером графа', () async {
    final peaks = <({int assembly, int compaction})>[];
    for (final shared in [smaller, profile]) {
      final graph = await shared.graph;
      await graph.confirmEdits(_rangePackages);
      final assembly = await graph.measureMemory(
        GraphLogMemoryOperation.assembly,
      );
      expect(assembly.records, graph.fixture.entities);
      final compaction = await graph.measureMemory(
        GraphLogMemoryOperation.compaction,
      );
      peaks.add((
        assembly: assembly.growthBytes,
        compaction: compaction.growthBytes,
      ));
      _report({
        'benchmark': 'graphLogMemory',
        'entities': graph.fixture.entities,
        'rangePackages': _rangePackages,
        'assemblyLiveHeapPeakMiB': _mebibytes(assembly.growthBytes),
        'compactionLiveHeapPeakMiB': _mebibytes(compaction.growthBytes),
      });
    }
    final [smallerPeaks, profilePeaks] = peaks;
    for (final (operation, growth) in [
      ('assembly', profilePeaks.assembly - smallerPeaks.assembly),
      ('compaction', profilePeaks.compaction - smallerPeaks.compaction),
    ]) {
      _report({
        'case': 'profile/$operation',
        'metric': 'рост пика живых данных с размером графа',
        'growthMiB': _mebibytes(growth),
        'noiseMiB': _mebibytes(_memoryNoiseBytes),
        'status': growth < _memoryNoiseBytes ? 'withinNoise' : 'exceeded',
      });
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test(
    'бенчмарк лога фактов: итог фактов диапазона для порога сжатия',
    () async {
      final graph = await smaller.graph;
      for (final longDescriptions in [false, true]) {
        await graph.confirmEdits(
          _rangePackages,
          longDescriptions: longDescriptions,
        );
        final summary = await graph.measureMemory(
          GraphLogMemoryOperation.rangeSummary,
        );
        expect(summary.records, graph.fixture.entities);
        await graph.compact();
        _report({
          'benchmark': 'graphLogRangeSummary',
          'packages': _rangePackages,
          'edits': longDescriptions ? 'longDescriptions' : 'typical',
          'summaryMiB': _mebibytes(summary.growthBytes),
          'bytesPerPackage': summary.growthBytes ~/ _rangePackages,
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('бенчмарк лога фактов: части длительности сжатия', () async {
    // Доли частей не зависят от размера графа, а на графе в десять раз
    // меньше профиля замер в десять раз короче.
    final graph = await smaller.graph;
    await graph.confirmEdits(_rangePackages);
    final parts = await graph.measureCompactionParts();
    final compaction = await graph.compact();
    _report({
      'benchmark': 'graphLogCompactionParts',
      'entities': graph.fixture.entities,
      'rangePackages': _rangePackages,
      'snapshotReadMs': _milliseconds(parts.snapshotRead),
      'stateAssemblyMs': _milliseconds(parts.stateAssembly),
      'stateAssemblyAndEncodingMs': _milliseconds(
        parts.stateAssemblyAndEncoding,
      ),
      'compactionMs': _milliseconds(compaction),
      'snapshotBytes': parts.snapshotBytes,
    });
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('бенчмарк лога фактов: длительность сжатия на профиле', () async {
    const benchmarkCase = 'profile/compaction';
    if (!benchmarkIncludes(benchmarkCase)) return;
    final graph = await profile.graph;
    final samples = <Duration>[];
    while (samples.length < min(benchmarkSamples, _compactionSeriesSamples)) {
      await graph.confirmEdits(_rangePackages);
      samples.add(await graph.compact());
    }
    final slowest = samples.reduce(
      (first, second) => first > second ? first : second,
    );
    _report({
      'case': benchmarkCase,
      'metric': 'длительность сжатия',
      'maxMs': _milliseconds(slowest),
      'budgetMs': _compactionBudgetMs,
      'samples': samples.length,
      'budgetStatus': samples.length < _compactionSeriesSamples
          ? 'smoke'
          : slowest.inMilliseconds <= _compactionBudgetMs
          ? 'withinBudget'
          : 'exceeded',
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('бенчмарк лога фактов: накладные расходы лога на команды', () async {
    final graph = await profile.graph;
    for (final kind in _CommandKind.values) {
      final benchmarkCase = 'profile/${kind.name}';
      if (!benchmarkIncludes(benchmarkCase)) continue;
      final captured = <_CommandSample>[];
      final uncaptured = <_CommandSample>[];
      for (
        var sample = -benchmarkWarmups;
        sample < benchmarkSamples;
        sample++
      ) {
        // Порядок пары чередуется, чтобы дрейф не копился в разности.
        final order = sample.isEven ? [true, false] : [false, true];
        final pair = <bool, _CommandSample>{};
        for (final capture in order) {
          pair[capture] = await graph.runCommand(kind, trace, capture);
        }
        if (sample >= 0) {
          captured.add(pair[true]!);
          uncaptured.add(pair[false]!);
        }
      }
      final overheads = [
        for (var index = 0; index < captured.length; index++)
          captured[index].total - uncaptured[index].total,
      ];
      _report({
        'benchmark': 'graphLogCommandOverhead',
        'command': kind.name,
        'entities': graph.fixture.entities,
        if (kind == _CommandKind.cascadeArchive)
          'cascadeRelations': _cascadeRelations,
        'capturedP95Ms': benchmarkP95([
          for (final sample in captured) sample.total,
        ]),
        'uncapturedP95Ms': benchmarkP95([
          for (final sample in uncaptured) sample.total,
        ]),
        // Медианы частей складываются в медиану команды приближённо.
        'captured': _CommandSample.medians(captured),
        'uncaptured': _CommandSample.medians(uncaptured),
      });
      reportBenchmarkBudget(
        benchmarkCase,
        'накладные расходы лога',
        overheads,
        kind.overheadBudgetMs,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Граф, который строится при первом обращении и освобождается в конце.
final class _GraphOnce {
  _GraphOnce(this._entities, {this._hubRelations = 0, this._observer});

  final int _entities;
  final int _hubRelations;
  final LocalDatabaseConnectionObserver? _observer;
  Future<_Graph>? _graph;

  Future<_Graph> get graph => _graph ??= _Graph.prepare(
    _entities,
    hubRelations: _hubRelations,
    observer: _observer,
  );

  Future<void> dispose() async {
    if (_graph case final graph?) await (await graph).dispose();
  }
}

/// Граф в пропорциях профиля решения 15 дизайна в файловой базе с базовым
/// снимком позиции 0.
final class _Graph {
  _Graph._(this.harness, this.raw, this.repository, this.fixture)
    : snapshots = GraphSnapshotStore.directoryIn(harness.temporaryDirectory);

  static Future<_Graph> prepare(
    int entities, {
    int hubRelations = 0,
    LocalDatabaseConnectionObserver? observer,
  }) async {
    final harness = await LocalDatabaseHarness.fileBacked();
    late sqlite.Database raw;
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
      observer: observer,
    );
    final fixture = GraphLogFixture(entities, hubRelations: hubRelations);
    final graph = _Graph._(
      harness,
      raw,
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => _now,
        InMemoryDiagnosticsSink(),
      ),
      fixture,
    );
    final preparation = Stopwatch()..start();
    fixture.populate(raw);
    // Снимок базы — состояние на позиции 0, с которого начинается лог.
    final snapshot = await Zone.root.run(graph._store.rebuildSnapshot);
    preparation.stop();
    _report({
      'benchmark': 'graphLogFixture',
      'entities': entities,
      'tags': fixture.tags,
      'intentions': fixture.intentions,
      'tagAssignments': fixture.tagAssignments,
      'longTermRelations': fixture.longTermRelations,
      'dailyChoices': fixture.dailyChoices,
      'hubRelations': hubRelations,
      'preparationMs': preparation.elapsedMilliseconds,
      'databaseBytes': harness.databaseFile.lengthSync(),
      'snapshotBytes': snapshot.byteSize,
      'environment': Platform.operatingSystem,
      'dart': Platform.version,
      'sqlite': sqlite.sqlite3.version.libVersion,
      'warmups': benchmarkWarmups,
      'repetitions': benchmarkSamples,
    });
    return graph;
  }

  static final _now = DateTime.utc(2026, 10, 17, 12);

  final LocalDatabaseHarness harness;
  final sqlite.Database raw;
  final DriftPersonalGraphRepository repository;
  final GraphLogFixture fixture;
  final Directory snapshots;
  late final _store = GraphSnapshotStore(
    log: repository,
    directory: snapshots,
    clock: () => _now,
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );

  /// Номер следующей правки: каждая правка затрагивает новую сущность.
  var _edits = 0;

  /// Номер следующей пары команд каждого вида.
  final _pairs = <_CommandKind, int>{};

  /// Подтверждает [count] команд, каждая из которых пишет один пакет:
  /// правки названий намерений и описаний дневных выборов поочерёдно, а с
  /// [longDescriptions] — описания намерений на пределе графем.
  Future<void> confirmEdits(int count, {bool longDescriptions = false}) async {
    final before = await repository.readCurrentPosition();
    final results = await Zone.root.run(() async {
      final results = <Object>[];
      for (var index = 0; index < count; index++) {
        final edit = _edits++;
        results.add(
          await repository.execute(
            _edit(edit, longDescription: longDescriptions),
          ),
        );
      }
      return results;
    });
    expect(results, everyElement(isA<GraphCommandSucceeded>()));
    expect(await repository.readCurrentPosition(), before + count);
  }

  _GraphCommand _edit(int edit, {required bool longDescription}) {
    if (longDescription) {
      final intention = edit % fixture.intentions;
      return UpdateIntention(
        id: fixture.intentionId(intention),
        title: fixture.intentionTitle(intention),
        description: _longDescription(edit),
      );
    }
    final entity = edit ~/ 2;
    if (edit.isEven) {
      final intention = entity % fixture.intentions;
      return UpdateIntention(
        id: fixture.intentionId(intention),
        title: '${fixture.intentionTitle(intention)} · правка $edit',
        description: fixture.intentionDescription(intention),
      );
    }
    return UpdateDailyChoiceFields(
      choiceId: fixture.dailyChoiceId(entity % fixture.dailyChoices),
      patch: DailyChoiceFieldsPatch(
        description: DailyChoiceDescriptionSet(
          DailyChoiceDescription.fromInput('Правка $edit')!,
        ),
      ),
    );
  }

  /// Сжимает лог в снимок текущей позиции, как фоновое сжатие приложения.
  Future<Duration> compact() async {
    final diagnostics = InMemoryDiagnosticsSink();
    final compaction = GraphLogCompaction(
      log: repository,
      directory: snapshots,
      clock: () => _now,
      diagnosticsSink: diagnostics,
    );
    final stopwatch = Stopwatch()..start();
    await Zone.root.run(() {
      compaction.start();
      return compaction.shutdown();
    });
    stopwatch.stop();
    expect(
      diagnostics.events.whereType<GraphLogCompactionDiagnosticsEvent>().map(
        (event) => event.status,
      ),
      [isA<DiagnosticsSucceeded>()],
    );
    return stopwatch.elapsed;
  }

  /// Части сжатия без записи файла: одно чтение последнего снимка, сборка
  /// состояния, которая читает его дважды, и сборка вместе с кодированием
  /// и gzip.
  Future<
    ({
      Duration snapshotRead,
      Duration stateAssembly,
      Duration stateAssemblyAndEncoding,
      int snapshotBytes,
    })
  >
  measureCompactionParts() async {
    final position = await repository.readCurrentPosition();
    final snapshot = (await repository.readSnapshotAtOrBefore(position))!;
    final file = File.fromUri(snapshots.uri.resolve(snapshot.fileName));
    Future<Duration> measure(Future<void> Function() operation) async {
      final stopwatch = Stopwatch()..start();
      await Zone.root.run(operation);
      return stopwatch.elapsed;
    }

    return (
      snapshotRead: await measure(() async {
        await (await GraphFormatFile.read(file.openRead())).records.length;
      }),
      stateAssembly: await measure(() async {
        await (await _store.readStateAt(position)).records.length;
      }),
      stateAssemblyAndEncoding: await measure(() async {
        final state = await _store.readStateAt(position);
        await GraphFormatFile.write(
          GraphFormatHeader(writtenAt: _now, counts: state.counts),
          state.records,
        ).length;
      }),
      snapshotBytes: snapshot.byteSize,
    );
  }

  /// Память операции [operation] в отдельном процессе над этой базой.
  Future<GraphLogMemory> measureMemory(GraphLogMemoryOperation operation) =>
      measureGraphLogMemory(
        operation,
        harness.databaseFile,
        snapshots: snapshots,
      );

  /// Выполняет очередную команду вида [kind] с включённым или выключенным
  /// захватом фактов и измеряет её части по [trace].
  Future<_CommandSample> runCommand(
    _CommandKind kind,
    _CommandTrace trace,
    bool capture,
  ) async {
    final pair = _pairs[kind] = (_pairs[kind] ?? -1) + 1;
    final entity = 2 * pair + (capture ? 0 : 1);
    if (kind == _CommandKind.cascadeArchive) _restoreHub();
    raw.execute('UPDATE graph_log_control SET capture = ?', [
      if (capture) 1 else 0,
    ]);
    final _GraphCommand command = switch (kind) {
      _CommandKind.intentionEdit => UpdateIntention(
        id: fixture.intentionId(entity),
        title: '${fixture.intentionTitle(entity)} · замер $pair',
        description: fixture.intentionDescription(entity),
      ),
      _CommandKind.intentionCreation => CreateIntention.withInitialState(
        title: 'Новое намерение $pair · $capture',
        description: 'Зачем: проверить запись нового намерения с тегами.',
        readiness: IntentionReadiness.notReady,
        tagIds: [for (var tag = 0; tag < 3; tag++) fixture.tagId(tag)],
      ),
      // Выбор с номером 5k + 4 хранит путь из пяти шагов.
      _CommandKind.dailyChoiceCompletion => UpdateDailyChoiceFields(
        choiceId: fixture.dailyChoiceId(5 * entity + 4),
        patch: DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet((5 * entity + 4).isEven),
        ),
      ),
      _CommandKind.cascadeArchive => ArchiveIntention(fixture.hubIntentionId),
    };
    final stopwatch = Stopwatch();
    final result = await Zone.root.run(() async {
      trace.start();
      stopwatch.start();
      final result = await repository.execute(command);
      stopwatch.stop();
      trace.stop();
      return result;
    });
    raw.execute('UPDATE graph_log_control SET capture = 1');
    expect(result, isA<GraphCommandSucceeded>());
    return _CommandSample(
      total: stopwatch.elapsed,
      logStatements: trace.logStatements,
      graphStatements: trace.graphStatements,
    );
  }

  /// Возвращает узел каскада и его связи в активное состояние без фактов:
  /// подготовка замера, а не изменение графа.
  void _restoreHub() {
    final hub = fixture.hubIntentionId.toCanonicalString();
    seedRawGraph(raw, () {
      raw
        ..execute('UPDATE intentions SET is_archived = 0 WHERE id = ?', [hub])
        ..execute(
          'UPDATE long_term_relations SET is_archived = 0 '
          'WHERE source_intention_id = ?',
          [hub],
        );
    });
  }

  Future<void> dispose() => harness.dispose();
}

typedef _GraphCommand = GraphCommand<GraphCommandOutcome, GraphCommandFailure>;

enum _CommandKind {
  /// Правка названия намерения: один факт.
  intentionEdit(4),

  /// Создание намерения с тремя тегами: факты двух секций.
  intentionCreation(4),

  /// Отметка выполнения дневного выбора: факт с путём из пяти шагов.
  dailyChoiceCompletion(4),

  /// Архивирование намерения с [_cascadeRelations] активными связями.
  cascadeArchive(25);

  const _CommandKind(this.overheadBudgetMs);

  /// Бюджет p95 накладных расходов лога на команду.
  final int overheadBudgetMs;
}

/// Длительность команды и её SQL: операторы лога фактов и операторы
/// таблиц графа вместе с триггерами отметок.
final class _CommandSample {
  const _CommandSample({
    required this.total,
    required this.logStatements,
    required this.graphStatements,
  });

  final Duration total;
  final Duration logStatements;
  final Duration graphStatements;

  /// Код команды и фактов на Dart, границы транзакции и наблюдатель.
  Duration get rest => total - logStatements - graphStatements;

  static Map<String, double> medians(List<_CommandSample> samples) => {
    'totalMs': _milliseconds(_median([for (final s in samples) s.total])),
    'logStatementsMs': _milliseconds(
      _median([for (final s in samples) s.logStatements]),
    ),
    'graphStatementsMs': _milliseconds(
      _median([for (final s in samples) s.graphStatements]),
    ),
    'restMs': _milliseconds(_median([for (final s in samples) s.rest])),
  };
}

/// Время операторов SQL команды по видам.
final class _CommandTrace extends LocalDatabaseConnectionObserver {
  final _statement = Stopwatch();
  var _recording = false;
  var logStatements = Duration.zero;
  var graphStatements = Duration.zero;

  void start() {
    logStatements = Duration.zero;
    graphStatements = Duration.zero;
    _recording = true;
  }

  void stop() => _recording = false;

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
    if (statement.statements.any((sql) => sql.contains('graph_log_'))) {
      logStatements += _statement.elapsed;
    } else {
      graphStatements += _statement.elapsed;
    }
  }
}

/// Пишет в [file] файл формата из [records] намерений, запись каждого из
/// которых занимает [recordBytes] байтов: описание — один графемный кластер
/// из буквы с комбинирующими знаками по два байта UTF-8.
Future<void> _writeRecordsOfLength(
  File file,
  int records,
  int recordBytes,
) async {
  IntentionRecord intention(int index, String description) => IntentionRecord(
    Intention(
      id: (IntentionId.decode(
        '018f0b5d-6b2e-7c80-8000-${index.toRadixString(16).padLeft(12, '0')}',
      ) as IntentionIdDecodingSuccess).id,
      title: 'Заметки $index',
      description: description,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026, 10, 17)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 17)),
    ),
  );
  Stream<GraphEntityRecord> generate() async* {
    for (var index = 0; index < records; index++) {
      final missing =
          recordBytes - GraphFormatCodec.encode(intention(index, 'a')).length;
      final record = intention(
        index,
        'a${'́' * (missing ~/ 2)}${'b' * (missing % 2)}',
      );
      expect(GraphFormatCodec.encode(record), hasLength(recordBytes));
      yield record;
    }
  }

  await GraphFormatFile.write(
    GraphFormatHeader(
      writtenAt: DateTime.utc(2026, 10, 17),
      counts: GraphRecordCounts(
        tags: 0,
        intentions: records,
        tagAssignments: 0,
        longTermRelations: 0,
        dailyChoices: 0,
      ),
    ),
    generate(),
  ).pipe(file.openWrite());
}

/// Описание намерения на пределе графем из русского текста.
String _longDescription(int edit) {
  final text = StringBuffer();
  while (text.length < IntentionText.maxDescriptionLength) {
    text.write('Шаг $edit: подробно описать, зачем он нужен и как понять, ');
  }
  return '${text.toString().substring(0, IntentionText.maxDescriptionLength - 1)}.';
}

Duration _median(List<Duration> samples) {
  final sorted = [...samples]..sort();
  return sorted[sorted.length ~/ 2];
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;

double _mebibytes(int bytes) => (bytes / (1 << 20) * 10).round() / 10;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
