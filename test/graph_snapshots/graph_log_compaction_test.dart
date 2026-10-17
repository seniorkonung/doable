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
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/encoded_diagnostics_log.dart';
import '../support/failing_snapshot_temporary_files.dart';
import '../support/forwarding_graph_fact_log.dart';
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
  late List<Future<GraphSnapshotEntry>> attempts;
  late EncodedDiagnosticsLog diagnostics;
  var now = DateTime.utc(2026, 10, 17, 9);
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
    attempts = [];
    diagnostics = EncodedDiagnosticsLog();
  });

  tearDown(() => harness.dispose());

  /// Сжатие с порогом проверок, которое запоминает каждую попытку записи
  /// снимка. [runners] задают запись попыток по порядку, а после них
  /// запись идёт в настоящем изоляте.
  GraphLogCompaction compactionOver(
    ObservableGraphFactLog log, {
    List<GraphSnapshotWriteRunner> runners = const [],
  }) => GraphLogCompaction(
    log: log,
    directory: snapshots,
    clock: () => now,
    diagnosticsSink: diagnostics,
    threshold: _threshold,
    runner: (write) {
      final runner = attempts.length < runners.length
          ? runners[attempts.length]
          : runGraphSnapshotWriteInIsolate;
      final attempt = runner(write);
      attempts.add(attempt);
      return attempt;
    },
  );

  Future<void> confirmCommands(int count) async {
    for (var index = 0; index < count; index++) {
      tagNumber++;
      expect(
        await repository.execute(
          CreateTag(TagName.fromInput('Тег $tagNumber')),
        ),
        isA<GraphCommandSucceeded>(),
      );
    }
    // Сигнал о пакете доходит до сжатия после подтверждения команды.
    await pumpEventQueue();
  }

  Future<void> expectStateMatchesDatabase() async {
    final position = await repository.readCurrentPosition();
    final state = await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).readStateAt(position);
    expect(
      _lines(await state.records.toList()),
      _lines(await referenceGraphRecords(database)),
    );
  }

  test('сжатие начинается, когда пакетов после последнего снимка больше '
      'порога, и оставляет только новый снимок и пакеты после него', () async {
    await confirmCommands(2);
    final previous = await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).writeSnapshot(2);
    final compaction = compactionOver(repository)..start();

    await confirmCommands(_threshold);
    expect(attempts, isEmpty);
    await confirmCommands(1);
    await compaction.shutdown();

    const position = 2 + _threshold + 1;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(attempts, hasLength(1));
    expect(latest?.position, position);
    expect(latest?.fileName, isNot(previous.fileName));
    expect(await repository.readSnapshotFileNames(), {latest?.fileName});
    expect(await _fileNamesIn(snapshots), {latest?.fileName});
    expect(await repository.readPackages(after: 0, upTo: position), isEmpty);
    await expectStateMatchesDatabase();
  });

  test('команда во время сжатия подтверждается до его окончания, а второе '
      'сжатие не начинается', () async {
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
    await confirmCommands(_threshold + 1);
    await registrationReached.future;
    var compacted = false;
    unawaited(attempts.single.whenComplete(() => compacted = true));

    await confirmCommands(_threshold + 1);

    expect(compacted, isFalse);
    expect(attempts, hasLength(1));
    releaseRegistration.complete();
    await compaction.shutdown();
    const position = _threshold + 1;
    expect(
      (await repository.readSnapshotAtOrBefore(position))?.position,
      position,
    );
    expect(
      await repository.readPackages(after: position, upTo: 2 * position),
      hasLength(position),
    );
    await expectStateMatchesDatabase();
  });

  test('после отказа записи снимка сжатие не повторяется, пока не записан ещё '
      'порог пакетов, и повторяется по его достижении', () async {
    final compaction = compactionOver(
      repository,
      runners: [writeGraphSnapshotFailingOnTemporaryFiles],
    )..start();
    await confirmCommands(_threshold + 1);
    await expectLater(attempts.single, throwsA(isA<FileSystemException>()));
    await pumpEventQueue();

    expect(await repository.readSnapshotFileNames(), isEmpty);
    expect(await _fileNamesIn(snapshots), isEmpty);
    expect(
      await repository.readPackages(after: 0, upTo: _threshold + 1),
      hasLength(_threshold + 1),
    );
    await confirmCommands(_threshold - 1);
    expect(attempts, hasLength(1));
    await confirmCommands(1);
    await compaction.shutdown();

    const position = 2 * _threshold + 1;
    expect(attempts, hasLength(2));
    expect(
      (await repository.readSnapshotAtOrBefore(position))?.position,
      position,
    );
    await expectStateMatchesDatabase();
  });

  test('отказ регистрации снимка оставляет реестр, каталог и лог прежними, '
      'а следующий запуск сжимает лог снова', () async {
    await confirmCommands(1);
    final previous = await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).writeSnapshot(1);
    final failing = compactionOver(
      _InterceptingLog(
        repository,
        beforeRegistration: () async => throw _diskFull,
      ),
    )..start();
    await confirmCommands(_threshold + 1);
    await expectLater(attempts.single, throwsA(isA<sqlite.SqliteException>()));
    await failing.shutdown();

    expect(await repository.readSnapshotFileNames(), {previous.fileName});
    expect(await _fileNamesIn(snapshots), {previous.fileName});
    expect(
      await repository.readPackages(after: 1, upTo: _threshold + 2),
      hasLength(_threshold + 1),
    );
    await expectStateMatchesDatabase();

    final next = compactionOver(repository)..start();
    await next.shutdown();

    const position = _threshold + 2;
    expect(attempts, hasLength(2));
    expect(
      (await repository.readSnapshotAtOrBefore(position))?.position,
      position,
    );
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    await expectStateMatchesDatabase();
  });

  test('отказ удаления истории оставляет новый снимок зарегистрированным, а '
      'прежние снимок и пакеты — в реестре и каталоге, пока их не удалит '
      'следующее успешное сжатие', () async {
    await confirmCommands(1);
    final previous = await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).writeSnapshot(1);
    // Отказ внутри транзакции удаления истории, когда пакеты до нового
    // снимка уже удалены.
    await database.customStatement('''
      CREATE TEMP TRIGGER fail_history_removal
      BEFORE DELETE ON graph_snapshots
      BEGIN
        SELECT RAISE(ABORT, 'injected history removal failure');
      END
    ''');
    final failing = compactionOver(repository)..start();
    await confirmCommands(_threshold + 1);
    await failing.shutdown();
    await confirmCommands(1);

    const snapshotPosition = _threshold + 2;
    final snapshot = await attempts.single;
    expect(snapshot.position, snapshotPosition);
    expect(await repository.readSnapshotFileNames(), {
      previous.fileName,
      snapshot.fileName,
    });
    expect(
      await _fileNamesIn(snapshots),
      await repository.readSnapshotFileNames(),
    );
    expect(
      await repository.readPackages(after: 0, upTo: snapshotPosition),
      hasLength(snapshotPosition),
    );
    expect(
      (await repository.readSnapshotAtOrBefore(snapshotPosition + 1))?.fileName,
      snapshot.fileName,
    );
    await expectStateMatchesDatabase();

    await database.customStatement('DROP TRIGGER fail_history_removal');
    final next = compactionOver(repository)..start();
    await confirmCommands(_threshold);
    await next.shutdown();

    const position = snapshotPosition + 1 + _threshold;
    final latest = await repository.readSnapshotAtOrBefore(position);
    expect(latest?.position, position);
    expect(await repository.readSnapshotFileNames(), {latest?.fileName});
    expect(await _fileNamesIn(snapshots), {latest?.fileName});
    expect(await repository.readPackages(after: 0, upTo: position), isEmpty);
    await expectStateMatchesDatabase();
  });

  test('сжатие диагностируется успехом записи снимка и сжатия, а сверка, '
      'после которой сжатие не понадобилось, событий не даёт', () async {
    final compaction = compactionOver(repository)..start();

    await confirmCommands(_threshold + 1);
    await compaction.shutdown();

    expect(diagnostics.events, [
      {'operation': 'graphSnapshotWrite', 'outcome': 'succeeded'},
      {'operation': 'graphLogCompaction', 'outcome': 'succeeded'},
    ]);
  });

  test('отказ сверки с порогом диагностируется этапом сверки и категорией '
      'повреждения базы', () async {
    final compaction = compactionOver(
      _InterceptingLog(
        repository,
        beforeCurrentPosition: () async => throw sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'database disk image is malformed',
        ),
      ),
    )..start();

    await compaction.shutdown();

    expect(diagnostics.events, [
      {
        'operation': 'graphLogCompaction',
        'stage': 'check',
        'outcome': 'failed',
        'failureCode': 'corruption',
      },
    ]);
  });

  for (final (failure, intercepted, runners, events)
      in <
        (
          String,
          ObservableGraphFactLog Function(ObservableGraphFactLog log),
          List<GraphSnapshotWriteRunner>,
          List<Map<String, Object?>>,
        )
      >[
        (
          'записи временного файла снимка',
          (log) => log,
          [writeGraphSnapshotFailingOnTemporaryFiles],
          [
            {
              'operation': 'graphSnapshotWrite',
              'stage': 'fileWrite',
              'outcome': 'failed',
              'failureCode': 'unavailable',
            },
            {
              'operation': 'graphLogCompaction',
              'stage': 'snapshotWrite',
              'outcome': 'failed',
              'failureCode': 'unavailable',
            },
          ],
        ),
        (
          'регистрации снимка',
          (log) => _InterceptingLog(
            log,
            beforeRegistration: () async => throw _diskFull,
          ),
          const [],
          [
            {
              'operation': 'graphSnapshotWrite',
              'stage': 'registration',
              'outcome': 'failed',
              'failureCode': 'unexpected',
            },
            {
              'operation': 'graphLogCompaction',
              'stage': 'snapshotWrite',
              'outcome': 'failed',
              'failureCode': 'unexpected',
            },
          ],
        ),
        (
          'удаления истории',
          (log) => _InterceptingLog(
            log,
            beforeHistoryRemoval: () async => throw _diskFull,
          ),
          const [],
          [
            {'operation': 'graphSnapshotWrite', 'outcome': 'succeeded'},
            {
              'operation': 'graphLogCompaction',
              'stage': 'historyRemoval',
              'outcome': 'failed',
              'failureCode': 'unexpected',
            },
          ],
        ),
      ]) {
    test('отказ $failure диагностируется этапом и категорией отказа без '
        'позиций, имён файлов и исходного исключения', () async {
      final compaction = compactionOver(
        intercepted(repository),
        runners: runners,
      )..start();

      await confirmCommands(_threshold + 1);
      await compaction.shutdown();

      expect(diagnostics.events, events);
    });
  }
}

/// Отказ базы из-за нехватки места.
final _diskFull = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_FULL,
  message: 'database or disk is full',
);

/// Лог фактов, который перед операцией вызывает действие теста: задержку или
/// отказ вместо операции.
final class _InterceptingLog extends ForwardingGraphFactLog {
  _InterceptingLog(
    super.source, {
    this.beforeCurrentPosition = _proceed,
    this.beforeRegistration = _proceed,
    this.beforeHistoryRemoval = _proceed,
  });

  final Future<void> Function() beforeCurrentPosition;
  final Future<void> Function() beforeRegistration;
  final Future<void> Function() beforeHistoryRemoval;

  static Future<void> _proceed() async {}

  @override
  Future<int> readCurrentPosition() async {
    await beforeCurrentPosition();
    return super.readCurrentPosition();
  }

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) async {
    await beforeRegistration();
    await super.registerSnapshot(snapshot);
  }

  @override
  Future<List<String>> removeHistoryBefore(int boundary) async {
    await beforeHistoryRemoval();
    return super.removeHistoryBefore(boundary);
  }
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
