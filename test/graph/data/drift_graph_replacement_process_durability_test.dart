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
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_log_completeness_reference.dart';
import '../../support/graph_replacement_process_worker.dart'
    show
        GraphReplacementStopPoint,
        graphReplacementWorkerDatabasePath,
        graphReplacementWorkerDirectoryPath,
        graphReplacementWorkerReady,
        graphReplacementWorkerStarted,
        graphReplacementWorkerStopPoint;
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  for (final stopPoint in GraphReplacementStopPoint.values) {
    final committed = stopPoint == GraphReplacementStopPoint.afterCommit;
    final outcome = committed
        ? 'целиком новый граф с копией перед заменой и пакетом «сброс»'
        : 'целиком прежний граф с прежними копиями без копии перед заменой';
    test('прерывание процесса ${_description(stopPoint)} оставляет после '
        'повторного открытия $outcome, очистка оставляет только '
        'зарегистрированные снимки, а выгрузка базы и состояния копий '
        'совпадают с собранными из снимков и лога', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final snapshots = Directory.fromUri(
        harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
      );

      var database = await harness.openReadyDatabase();
      var repository = _repository(database);
      final tags = await _seedBackupGraph(repository);
      await repository.insertManualBackup(since: null);
      final backupPosition = await repository.readCurrentPosition();
      final backupGraph = await _graphLines(database);
      await _changeAfterBackup(repository, tags.first);
      final previousPosition = await repository.readCurrentPosition();
      final previousGraph = await _graphLines(database);
      final before = await _storedState(database);
      await harness.closePersistenceObjectGraph();

      final share = await _runWorkerUntilStopPoint(
        harness,
        snapshots,
        stopPoint,
      );

      database = await harness.openReadyDatabase();
      repository = _repository(database);
      // Ход замены показывает, что процесс остановился в своей точке.
      final deletedShare =
          previousGraph.length / (previousGraph.length + backupGraph.length);
      switch (stopPoint) {
        case GraphReplacementStopPoint.afterDeletion:
          expect(share, deletedShare);
        case GraphReplacementStopPoint.midInsertion:
          expect(share, allOf(greaterThan(deletedShare), lessThan(1)));
        case GraphReplacementStopPoint.beforeCommit ||
            GraphReplacementStopPoint.afterCommit:
          expect(share, 1);
      }
      final leftovers = (await _fileNamesIn(snapshots)).difference({
        for (final row in await _registry(database)) row.fileName,
      });
      if (committed) {
        expect(leftovers, isEmpty);
        expect(await _graphLines(database), backupGraph);
        expect(
          await _rows(
            database,
            'SELECT package.position AS package_position, package.kind, '
            'snapshot.position AS snapshot_position '
            'FROM graph_log_packages AS package '
            'LEFT JOIN graph_snapshots AS snapshot '
            'ON snapshot.id = package.snapshot_id '
            'WHERE package.position > $previousPosition',
          ),
          [
            [previousPosition + 1, 'reset', previousPosition + 1],
          ],
        );
        // Захват включён, а признак записи единым путём снят.
        expect(await _logControl(database), [
          [1, 0],
        ]);
      } else {
        // Незарегистрированный снимок замены, который записал процесс.
        expect(leftovers, [endsWith('.jsonl.gz')]);
        expect(await _storedState(database), before);
      }

      await GraphLogCompaction(
        log: repository,
        directory: snapshots,
        clock: () => DateTime.utc(2026, 10, 18, 13),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ).removeUnregisteredFiles();

      await _expectDirectoryMatchesRegistry(snapshots, database);
      final store = GraphSnapshotStore(
        log: repository,
        directory: snapshots,
        clock: () => DateTime.utc(2026, 10, 18, 13),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      expect(
        await _stateLinesAt(store, await repository.readCurrentPosition()),
        await _graphLines(database),
      );
      final expectedBackups = [
        if (committed)
          (GraphBackupKind.beforeReplacement, previousPosition, previousGraph),
        (GraphBackupKind.manual, backupPosition, backupGraph),
      ];
      final backups = switch (await repository.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups,
        GraphBackupsReadFailed() => throw TestFailure('Копии не прочитаны.'),
      };
      expect(
        [for (final backup in backups) (backup.kind, backup.position)],
        [for (final (kind, position, _) in expectedBackups) (kind, position)],
      );
      for (final (kind, position, graph) in expectedBackups) {
        expect(await _stateLinesAt(store, position), graph, reason: '$kind');
      }
    }, timeout: Timeout.none);
  }
}

String _description(GraphReplacementStopPoint stopPoint) => switch (stopPoint) {
  GraphReplacementStopPoint.afterDeletion => 'после удаления прежнего графа',
  GraphReplacementStopPoint.midInsertion => 'посреди вставок записей снимка',
  GraphReplacementStopPoint.beforeCommit => 'до COMMIT замены',
  GraphReplacementStopPoint.afterCommit => 'после COMMIT замены',
};

DriftPersonalGraphRepository _repository(AppDatabase database) {
  var now = DateTime.utc(2026, 10, 18, 9);
  return DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => now = now.add(const Duration(seconds: 1)),
    InMemoryDiagnosticsSink(),
  );
}

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

Future<Intention> _createIntention(
  DriftPersonalGraphRepository repository,
  String title,
  List<Tag> tags,
) async => (await _confirm<IntentionSaved>(
  repository,
  CreateIntention.withInitialState(
    title: title,
    description: null,
    readiness: IntentionReadiness.notReady,
    tagIds: {for (final tag in tags) tag.id},
  ),
)).intention;

/// Граф копии: пять тегов и двадцать намерений, у каждого из которых все
/// теги. Его 125 строк не умещаются в один пакет вставки замены, который
/// ограничен сотней строк, поэтому замена прерывается и посреди вставок.
Future<List<Tag>> _seedBackupGraph(
  DriftPersonalGraphRepository repository,
) async {
  final tags = [
    for (var number = 1; number <= 5; number++)
      (await _confirm<TagCreated>(
        repository,
        CreateTag(name: TagName.fromInput('Тег $number'), color: null),
      )).tag,
  ];
  for (var number = 1; number <= 20; number++) {
    await _createIntention(repository, 'Намерение $number', tags);
  }
  return tags;
}

/// Изменения после копии: граф, который заменяется, отличается от графа
/// копии и удалённым тегом с его назначениями, и новым намерением.
Future<void> _changeAfterBackup(
  DriftPersonalGraphRepository repository,
  Tag deleted,
) async {
  await _confirm<TagDeleted>(repository, DeleteTag(deleted.id));
  await _createIntention(repository, 'После копии', const []);
}

/// Граф, копии, лог, реестр снимков и признаки захвата фактов.
Future<List<Object>> _storedState(AppDatabase database) async => [
  await _graphLines(database),
  await _rows(database, 'SELECT * FROM graph_backups ORDER BY id'),
  await _rows(
    database,
    'SELECT position, kind, snapshot_id FROM graph_log_packages '
    'ORDER BY position',
  ),
  await _rows(database, 'SELECT * FROM graph_snapshots ORDER BY id'),
  await _logControl(database),
];

/// Признаки захвата фактов и записи единым путём.
Future<List<List<Object?>>> _logControl(AppDatabase database) =>
    _rows(database, 'SELECT capture, writing FROM graph_log_control');

Future<List<List<Object?>>> _rows(AppDatabase database, String query) async => [
  for (final row in await database.customSelect(query).get())
    row.data.values.toList(),
];

Future<List<String>> _graphLines(AppDatabase database) async =>
    _lines(await referenceGraphRecords(database));

/// Состояние на позиции [position], собранное из снимка и пакетов после
/// него.
Future<List<String>> _stateLinesAt(
  GraphSnapshotStore store,
  int position,
) async => _lines(await (await store.readStateAt(position)).records.toList());

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

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

/// Запускает восстановление последней копии в отдельном процессе,
/// принудительно завершает процесс в точке замены [stopPoint] и возвращает
/// последнюю долю хода замены, которую процесс сообщил перед остановкой.
Future<double> _runWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  Directory snapshots,
  GraphReplacementStopPoint stopPoint,
) async {
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_replacement_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    _findFlutterExecutable(),
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      graphReplacementWorkerDatabasePath: harness.databaseFile.path,
      graphReplacementWorkerDirectoryPath: snapshots.path,
      graphReplacementWorkerStopPoint: stopPoint.environmentValue,
    },
  );
  final output = StringBuffer();
  final errors = StringBuffer();
  final ready = Completer<(int, double)>();
  final startedPattern = RegExp('$graphReplacementWorkerStarted:(\\d+)\\s');
  final readyPattern = RegExp(
    '$graphReplacementWorkerReady:(\\d+):([0-9.]+)\\s',
  );
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
      ready.complete((
        int.parse(stopped.group(1)!),
        double.parse(stopped.group(2)!),
      ));
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
            'Процесс замены завершился с кодом $code до точки '
            '${stopPoint.environmentValue}.\nstdout:\n$output\n'
            'stderr:\n$errors',
          ),
        );
      }
    }),
  );

  var killed = false;
  final double share;
  try {
    final (workerPid, reported) = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс замены не достиг точки ${stopPoint.environmentValue}.'
        '\nstdout:\n$output\nstderr:\n$errors',
      ),
    );
    share = reported;
    killed = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(killed, isTrue, reason: 'Процесс замены не завершён.');
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
  return share;
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
