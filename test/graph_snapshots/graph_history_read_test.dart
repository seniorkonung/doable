import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/forwarding_graph_fact_log.dart';
import '../support/graph_history_rows.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

/// Порог проверок: несколько пакетов вместо производственного значения.
const _threshold = 3;

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late _CompactionOutcomes outcomes;
  var now = DateTime.utc(2026, 10, 18, 9);
  var tagNumber = 0;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    outcomes = _CompactionOutcomes();
  });

  tearDown(() => harness.dispose());

  GraphLogCompaction compactionOver(ObservableGraphFactLog log) =>
      GraphLogCompaction(
        log: log,
        directory: snapshots,
        clock: () => now,
        diagnosticsSink: outcomes,
        threshold: _threshold,
      );

  GraphSnapshotStore store() => GraphSnapshotStore(
    log: repository,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );

  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      tagNumber++;
      expect(
        await repository.execute(
          CreateTag(
            name: TagName.fromInput('Тег $tagNumber'),
            color: null,
            placement: TagPlacement.first,
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
    }
    // Сигнал о пакете доходит до сжатия после подтверждения команды.
    await pumpEventQueue();
  }

  /// Записи состояния, собранного на позиции источника [state] из его
  /// базового снимка и пакетов после него, в кодировке формата.
  Future<List<String>> readState(GraphStateSource state) async =>
      _lines(await (await store().readState(state)).records.toList());

  Future<List<String>> referenceState() async =>
      _lines(await referenceGraphRecords(database));

  test('сжатие, завершившееся после выбора базового снимка чтения истории, '
      'оставляет этот снимок и пакеты после него, а после чтения следующее '
      'сжатие удаляет их', () async {
    await confirmCommands(1);
    final previous = await store().writeSnapshot(1);
    final expected = await referenceState();
    final compaction = compactionOver(repository)..start();
    final baseSelected = Completer<void>();
    final releaseRead = Completer<void>();
    final read = compaction.readHistory((history) async {
      final state = await _selectCurrentState(history);
      baseSelected.complete();
      await releaseRead.future;
      return readState(state);
    });
    await baseSelected.future;

    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    const position = _threshold + 2;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(latest?.position, position);
    expect(await repository.readSnapshotFileNames(), {
      previous.fileName,
      latest?.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    expect(
      await repository.readPackages(after: previous.position, upTo: position),
      hasLength(_threshold + 1),
    );
    releaseRead.complete();
    expect(await read, expected);

    final next = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await next).status, isA<DiagnosticsSucceeded>());
    await compaction.shutdown();

    const nextPosition = position + _threshold + 1;
    final nextLatest = await repository.readSnapshotAtOrBefore(nextPosition);
    expect(nextLatest?.position, nextPosition);
    expect(await repository.readSnapshotFileNames(), {nextLatest?.fileName});
    expect(await _fileNamesIn(snapshots), {nextLatest?.fileName});
    expect(
      await repository.readPackages(after: 0, upTo: nextPosition),
      isEmpty,
    );
  });

  test('сжатие, завершившееся во время двух чтений истории, базовые снимки '
      'которых новее снимка хранимой копии, сохраняет оба базовых снимка, а '
      'после чтений следующее сжатие удаляет их', () async {
    await confirmCommands(1);
    final kept = await store().writeSnapshot(1);
    await insertDailyBackupRow(database, position: 1);
    final compaction = compactionOver(repository);
    Future<List<String>> delayedRead(
      Completer<void> baseSelected,
      Future<void> release,
    ) => compaction.readHistory((history) async {
      final state = await _selectCurrentState(history);
      baseSelected.complete();
      await release;
      return readState(state);
    });

    await confirmCommands(1);
    final firstBase = await store().writeSnapshot(2);
    final firstExpected = await referenceState();
    final firstSelected = Completer<void>();
    final releaseFirst = Completer<void>();
    final firstRead = delayedRead(firstSelected, releaseFirst.future);
    await firstSelected.future;
    await confirmCommands(1);
    final secondBase = await store().writeSnapshot(3);
    final secondExpected = await referenceState();
    final secondSelected = Completer<void>();
    final releaseSecond = Completer<void>();
    final secondRead = delayedRead(secondSelected, releaseSecond.future);
    await secondSelected.future;

    compaction.start();
    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    const position = 3 + _threshold + 1;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(latest?.position, position);
    expect(await repository.readSnapshotFileNames(), {
      kept.fileName,
      firstBase.fileName,
      secondBase.fileName,
      latest?.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    releaseFirst.complete();
    releaseSecond.complete();
    expect(await firstRead, firstExpected);
    expect(await secondRead, secondExpected);

    final next = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await next).status, isA<DiagnosticsSucceeded>());
    await compaction.shutdown();

    const nextPosition = position + _threshold + 1;
    final nextLatest = await repository.readSnapshotAtOrBefore(nextPosition);
    expect(nextLatest?.position, nextPosition);
    expect(await repository.readSnapshotFileNames(), {
      kept.fileName,
      nextLatest?.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
  });

  test(
    'сжатие, завершившееся во время чтения состояния на прежней позиции, '
    'базовый снимок которого новее снимка более старой хранимой копии, '
    'сохраняет этот снимок, а после чтения следующее сжатие удаляет его',
    () async {
      await confirmCommands(1);
      final kept = await store().writeSnapshot(1);
      await insertDailyBackupRow(database, position: 1);
      await confirmCommands(1);
      // Снимок, который не нужен ни копии, ни чтению: сжатие во время чтения
      // удаляет его.
      await store().writeSnapshot(2);
      await confirmCommands(1);
      final base = await store().writeSnapshot(3);
      await confirmCommands(1);
      final expected = await referenceState();
      await confirmCommands(1);
      final compaction = compactionOver(repository)..start();
      final baseSelected = Completer<void>();
      final releaseRead = Completer<void>();
      final read = compaction.readHistory((history) async {
        final state = await history.selectStateAt(4);
        baseSelected.complete();
        await releaseRead.future;
        return readState(state);
      });
      await baseSelected.future;

      final compacted = outcomes.next;
      await confirmCommands(2);
      expect((await compacted).status, isA<DiagnosticsSucceeded>());

      const position = 7;
      final latest = await repository.readSnapshotAtOrBefore(position);
      expect(latest?.position, position);
      expect(await repository.readSnapshotFileNames(), {
        kept.fileName,
        base.fileName,
        latest?.fileName,
      });
      expect(
        await _fileNamesIn(snapshots),
        await repository.readSnapshotFileNames(),
      );
      releaseRead.complete();
      expect(await read, expected);

      final next = outcomes.next;
      await confirmCommands(_threshold + 1);
      expect((await next).status, isA<DiagnosticsSucceeded>());
      await compaction.shutdown();

      const nextPosition = position + _threshold + 1;
      final nextLatest = await repository.readSnapshotAtOrBefore(nextPosition);
      expect(nextLatest?.position, nextPosition);
      expect(await repository.readSnapshotFileNames(), {
        kept.fileName,
        nextLatest?.fileName,
      });
      expect(
        await _fileNamesIn(snapshots),
        await repository.readSnapshotFileNames(),
      );
    },
  );

  test('чтение пакетов с позиции копии, строка которой удалена во время '
      'чтения, получает все пакеты диапазона по порядку, хотя между их '
      'порциями завершилось сжатие, а после чтения следующее сжатие удаляет '
      'их', () async {
    await confirmCommands(1);
    await insertDailyBackupRow(database, position: 1);
    // Пакеты диапазона не умещаются в одну порцию, поэтому сжатие
    // завершается между порциями чтения.
    await confirmCommands(graphFactLogPortionLimit);
    // Снимок, который не нужен ни копиям, ни чтению: сжатие во время чтения
    // удаляет его.
    await store().writeSnapshot(graphFactLogPortionLimit + 1);
    final replaced = await insertSameGraphReplacement(
      database,
      snapshots: snapshots,
      position: graphFactLogPortionLimit + 1,
    );
    await confirmCommands(1);
    final upTo = await repository.readCurrentPosition();
    final compaction = compactionOver(repository)..start();
    final firstReceived = Completer<void>();
    final releaseRead = Completer<void>();
    final read = compaction.readHistory((history) async {
      final received = <GraphHistoryPackage>[];
      await for (final package in history.readPackages(after: 1, upTo: upTo)) {
        received.add(package);
        if (received.length == 1) {
          firstReceived.complete();
          await releaseRead.future;
        }
      }
      return received;
    });
    await firstReceived.future;
    await database.delete(database.graphBackups).go();

    final compacted = outcomes.next;
    await confirmCommands(_threshold + replaced.position - upTo + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    final position = replaced.position + _threshold + 1;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(latest?.position, position);
    expect(await repository.readSnapshotFileNames(), {
      replaced.fileName,
      latest?.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    releaseRead.complete();
    final received = await read;
    expect(received.map((package) => package.position), [
      for (var next = 2; next <= upTo; next++) next,
    ]);
    expect(
      received.whereType<GraphHistoryReset>().map(
        (package) => package.position,
      ),
      [replaced.position],
    );

    final next = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await next).status, isA<DiagnosticsSucceeded>());
    await compaction.shutdown();

    final nextPosition = position + _threshold + 1;
    final nextLatest = await repository.readSnapshotAtOrBefore(nextPosition);
    expect(nextLatest?.position, nextPosition);
    expect(await repository.readSnapshotFileNames(), {nextLatest?.fileName});
    expect(await _fileNamesIn(snapshots), {nextLatest?.fileName});
    expect(
      await repository.readPackages(after: 0, upTo: nextPosition),
      isEmpty,
    );
  });

  test('чтение истории, начатое, когда сжатие уже прочитало текущую позицию, '
      'но ещё не зарегистрировало новый снимок, выбирает базой прежний '
      'снимок, а сжатие оставляет его и пакеты после него', () async {
    await confirmCommands(1);
    final previous = await store().writeSnapshot(1);
    final registrationReached = Completer<void>();
    final releaseRegistration = Completer<void>();
    final compaction = compactionOver(
      _InterceptingLog(
        repository,
        beforeRegistration: () async {
          registrationReached.complete();
          await releaseRegistration.future;
        },
      ),
    )..start();
    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    await registrationReached.future;
    final expected = await referenceState();

    final baseSelected = Completer<GraphStateSource>();
    final releaseRead = Completer<void>();
    final read = compaction.readHistory((history) async {
      final state = await _selectCurrentState(history);
      baseSelected.complete(state);
      await releaseRead.future;
      return readState(state);
    });
    expect((await baseSelected.future).base?.fileName, previous.fileName);
    releaseRegistration.complete();
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    const position = _threshold + 2;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(latest?.position, position);
    expect(await repository.readSnapshotFileNames(), {
      previous.fileName,
      latest?.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    expect(
      await repository.readPackages(after: previous.position, upTo: position),
      hasLength(_threshold + 1),
    );
    releaseRead.complete();
    expect(await read, expected);
    await compaction.shutdown();
  });

  test('сжатие, завершившееся, пока чтение истории ещё не выбрало базовый '
      'снимок своей позиции, оставляет историю, из которой чтение собирает '
      'состояние на этой позиции', () async {
    await confirmCommands(1);
    final previous = await store().writeSnapshot(1);
    final expected = await referenceState();
    final selectionReached = Completer<void>();
    final releaseSelection = Completer<void>();
    final compaction = compactionOver(
      _InterceptingLog(
        repository,
        beforeSnapshotSelection: () async {
          if (selectionReached.isCompleted) return;
          selectionReached.complete();
          await releaseSelection.future;
        },
      ),
    );
    final read = compaction.readHistory(
      (history) async => readState(await _selectCurrentState(history)),
    );
    await selectionReached.future;

    compaction.start();
    final compacted = outcomes.next;
    await confirmCommands(_threshold + 1);
    expect((await compacted).status, isA<DiagnosticsSucceeded>());

    const position = _threshold + 2;
    expect(
      await repository.readSnapshotFileNames(),
      contains(previous.fileName),
    );
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    expect(
      await repository.readPackages(after: previous.position, upTo: position),
      hasLength(_threshold + 1),
    );
    releaseSelection.complete();
    expect(await read, expected);
    await compaction.shutdown();
  });
}

/// Получатель диагностики, по которому проверка дожидается окончания
/// сжатия: исход сжатия сообщается после удаления истории.
final class _CompactionOutcomes implements DiagnosticsSink {
  final _outcomes =
      StreamController<GraphLogCompactionDiagnosticsEvent>.broadcast();

  /// Исход следующего сжатия.
  Future<GraphLogCompactionDiagnosticsEvent> get next => _outcomes.stream.first;

  @override
  void record(DiagnosticsEvent event) {
    if (event is GraphLogCompactionDiagnosticsEvent) _outcomes.add(event);
  }
}

/// Лог фактов, который перед операцией вызывает задержку теста.
final class _InterceptingLog extends ForwardingGraphFactLog {
  _InterceptingLog(
    super.source, {
    this.beforeSnapshotSelection = _proceed,
    this.beforeRegistration = _proceed,
  });

  final Future<void> Function() beforeSnapshotSelection;
  final Future<void> Function() beforeRegistration;

  static Future<void> _proceed() async {}

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) async {
    await beforeSnapshotSelection();
    return super.readSnapshotAtOrBefore(position);
  }

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) async {
    await beforeRegistration();
    await super.registerSnapshot(snapshot);
  }
}

/// Источник состояния на текущей позиции, выбранный чтением истории
/// [history].
Future<GraphStateSource> _selectCurrentState(GraphHistoryRead history) async =>
    history.selectStateAt(await history.readCurrentPosition());

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
