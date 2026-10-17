@Tags(['flutter_process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, RegisteredGraphSnapshot;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import '../support/encoded_diagnostics_log.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/graph_snapshot_process_worker.dart'
    show
        GraphSnapshotStopPoint,
        graphSnapshotWorkerDatabasePath,
        graphSnapshotWorkerDirectoryPath,
        graphSnapshotWorkerReady,
        graphSnapshotWorkerStarted,
        graphSnapshotWorkerStopPoint,
        graphSnapshotWorkerThreshold;
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

/// Позиция снимка, записанного до запуска дочернего процесса.
const _previousPosition = 5;

/// Позиция снимка, который пишет сжатие дочернего процесса: после прежнего
/// снимка записано больше порога пакетов.
const _interruptedPosition =
    _previousPosition + graphSnapshotWorkerThreshold + 1;

/// Позиция снимка следующего сжатия после повторного открытия.
const _nextPosition = _interruptedPosition + graphSnapshotWorkerThreshold + 1;

void main() {
  for (final stopPoint in GraphSnapshotStopPoint.values) {
    test('прерывание процесса ${_description(stopPoint)} оставляет после '
        'очистки только зарегистрированные целые снимки, состояние из '
        'последнего снимка совпадает с базой, а следующее сжатие '
        'проходит', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final snapshots = Directory.fromUri(
        harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
      );
      var now = DateTime.utc(2026, 10, 17, 9);
      DateTime clock() => now = now.add(const Duration(seconds: 1));

      var database = await harness.openReadyDatabase();
      var repository = _repository(database, clock);
      await _seedGraph(repository);
      final previous = await GraphSnapshotStore(
        log: repository,
        directory: snapshots,
        clock: clock,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ).writeSnapshot(_previousPosition);
      await _exceedThreshold(repository, 'До прерывания');
      await harness.closePersistenceObjectGraph();

      await _runWorkerUntilStopPoint(harness, snapshots, stopPoint);

      database = await harness.openReadyDatabase();
      repository = _repository(database, clock);
      final registry = await _registry(database);
      final leftovers = (await _fileNamesIn(snapshots))
          .difference({for (final row in registry) row.fileName});
      // Каталог до очистки показывает, что процесс остановился в своей точке.
      switch (stopPoint) {
        case GraphSnapshotStopPoint.beforeRename:
          expect(registry.map((row) => row.fileName), [previous.fileName]);
          expect(leftovers, [endsWith('.jsonl.gz.tmp')]);
        case GraphSnapshotStopPoint.beforeRegistration:
          expect(registry.map((row) => row.fileName), [previous.fileName]);
          expect(leftovers, [endsWith('.jsonl.gz')]);
        case GraphSnapshotStopPoint.afterRegistration:
          expect(registry.map((row) => row.position), [
            _previousPosition,
            _interruptedPosition,
          ]);
          expect(leftovers, isEmpty);
      }
      final diagnostics = EncodedDiagnosticsLog();
      final compaction = GraphLogCompaction(
        log: repository,
        directory: snapshots,
        clock: clock,
        diagnosticsSink: diagnostics,
        threshold: graphSnapshotWorkerThreshold,
      );

      await compaction.removeUnregisteredFiles();

      await _expectDirectoryMatchesRegistry(snapshots, database);
      expect(
        (await repository.readSnapshotAtOrBefore(_interruptedPosition))
            ?.position,
        switch (stopPoint) {
          GraphSnapshotStopPoint.beforeRename ||
          GraphSnapshotStopPoint.beforeRegistration => _previousPosition,
          GraphSnapshotStopPoint.afterRegistration => _interruptedPosition,
        },
      );
      await _expectStateMatchesDatabase(repository, database, snapshots);

      await _exceedThreshold(repository, 'После прерывания');
      compaction.start();
      await compaction.shutdown();

      expect(diagnostics.events.last, {
        'operation': 'graphLogCompaction',
        'outcome': 'succeeded',
      });
      expect((await _registry(database)).map((row) => row.position), [
        _nextPosition,
      ]);
      await _expectDirectoryMatchesRegistry(snapshots, database);
      await _expectStateMatchesDatabase(repository, database, snapshots);
    }, timeout: Timeout.none);
  }
}

String _description(GraphSnapshotStopPoint stopPoint) => switch (stopPoint) {
  GraphSnapshotStopPoint.beforeRename => 'до переименования временного файла',
  GraphSnapshotStopPoint.beforeRegistration =>
    'после переименования до регистрации снимка',
  GraphSnapshotStopPoint.afterRegistration => 'после регистрации снимка',
};

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DateTime Function() clock,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  clock,
  InMemoryDiagnosticsSink(),
);

Future<T> _confirm<T extends GraphCommandOutcome>(
  DriftPersonalGraphRepository repository,
  GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
) async {
  final result = await repository.execute(command);
  final confirmed =
      (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
          as ConfirmedGraphResult;
  return confirmed.value as T;
}

/// Граф прежнего снимка из [_previousPosition] пакетов: теги, намерения,
/// назначения, долговременная связь и их изменения.
Future<void> _seedGraph(DriftPersonalGraphRepository repository) async {
  final home = (await _confirm<TagCreated>(
    repository,
    CreateTag(TagName.fromInput('Дом')),
  )).tag;
  final health = (await _confirm<IntentionSaved>(
    repository,
    CreateIntention.withInitialState(
      title: 'Здоровье',
      description: null,
      readiness: IntentionReadiness.notReady,
      tagIds: {home.id},
    ),
  )).intention;
  final running = (await _confirm<IntentionSaved>(
    repository,
    CreateIntention.withInitialState(
      title: 'Бегать',
      description: null,
      readiness: IntentionReadiness.ready,
      tagIds: {home.id},
    ),
  )).intention;
  await _confirm<LongTermRelationCreated>(
    repository,
    CreateLongTermRelation(
      sourceIntentionId: health.id,
      relatedIntentionId: running.id,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      description: null,
    ),
  );
  await _confirm<TagAssignmentChanged>(
    repository,
    RemoveTagAssignment(tagId: home.id, intentionId: health.id),
  );
}

/// Подтверждает на один пакет больше порога сжатия.
Future<void> _exceedThreshold(
  DriftPersonalGraphRepository repository,
  String label,
) async {
  for (var number = 1; number <= graphSnapshotWorkerThreshold + 1; number++) {
    await _confirm<TagCreated>(
      repository,
      CreateTag(TagName.fromInput('$label $number')),
    );
  }
}

/// Строки реестра снимков в порядке регистрации.
Future<List<RegisteredGraphSnapshot>> _registry(AppDatabase database) =>
    (database.select(
      database.graphSnapshots,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

/// В каталоге только зарегистрированные снимки, и размер и SHA-256 каждого
/// файла совпадают с реестром.
Future<void> _expectDirectoryMatchesRegistry(
  Directory snapshots,
  AppDatabase database,
) async {
  final registry = await _registry(database);
  expect(await _fileNamesIn(snapshots), {
    for (final row in registry) row.fileName,
  });
  for (final row in registry) {
    final bytes = await File.fromUri(snapshots.uri.resolve(row.fileName))
        .readAsBytes();
    expect(bytes, hasLength(row.byteSize), reason: row.fileName);
    expect(sha256.convert(bytes).bytes, row.checksum, reason: row.fileName);
  }
}

/// Состояние на текущей позиции, собранное из последнего снимка и пакетов
/// после него, совпадает с выгрузкой базы.
Future<void> _expectStateMatchesDatabase(
  DriftPersonalGraphRepository repository,
  AppDatabase database,
  Directory snapshots,
) async {
  final state = await GraphSnapshotStore(
    log: repository,
    directory: snapshots,
    clock: () => DateTime.utc(2026, 10, 17),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  ).readStateAt(await repository.readCurrentPosition());
  expect(
    _lines(await state.records.toList()),
    _lines(await referenceGraphRecords(database)),
  );
}

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

/// Запускает сжатие в отдельном процессе и принудительно завершает процесс
/// в точке записи снимка [stopPoint].
Future<void> _runWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  Directory snapshots,
  GraphSnapshotStopPoint stopPoint,
) async {
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_snapshot_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    _findFlutterExecutable(),
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      graphSnapshotWorkerDatabasePath: harness.databaseFile.path,
      graphSnapshotWorkerDirectoryPath: snapshots.path,
      graphSnapshotWorkerStopPoint: stopPoint.environmentValue,
    },
  );
  final output = StringBuffer();
  final errors = StringBuffer();
  final ready = Completer<int>();
  final startedPattern = RegExp('$graphSnapshotWorkerStarted:(\\d+)');
  final readyPattern = RegExp('$graphSnapshotWorkerReady:(\\d+)');
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedPid;

  process.stdout.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    final text = output.toString();
    if (startedPattern.firstMatch(text) case final started?) {
      startedPid = int.parse(started.group(1)!);
    }
    if (readyPattern.firstMatch(text) case final stopped?
        when !ready.isCompleted) {
      ready.complete(int.parse(stopped.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(errors.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс снимков завершился с кодом $code до точки '
            '${stopPoint.environmentValue}.\nstdout:\n$output\n'
            'stderr:\n$errors',
          ),
        );
      }
    }),
  );

  var killed = false;
  try {
    final workerPid = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс снимков не достиг точки ${stopPoint.environmentValue}.'
        '\nstdout:\n$output\nstderr:\n$errors',
      ),
    );
    killed = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(killed, isTrue, reason: 'Процесс снимков не завершён.');
  } finally {
    if (!killed) {
      if (startedPid case final pid?) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
    }
  }

  final code = await process.exitCode.timeout(const Duration(seconds: 15));
  await Future.wait([stdoutDone.future, stderrDone.future]);
  expect(code, isNot(0));
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Не найден Flutter SDK для дочернего процесса.');
    }
    directory = parent;
  }
}
