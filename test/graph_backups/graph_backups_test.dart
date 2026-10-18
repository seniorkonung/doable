import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/forwarding_graph_fact_log.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

/// Порог сжатия проверок: несколько пакетов вместо производственного
/// значения.
const _threshold = 3;

void main() {
  late LocalDatabaseHarness harness;
  late _BackupInsertFailures failures;
  late DriftPersonalGraphRepository repository;
  late _HeldPackageReads log;
  late _CompactionOutcomes compactionOutcomes;
  late GraphLogCompaction compaction;
  late GraphBackups backups;
  late DateTime now;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    failures = _BackupInsertFailures();
    final database = await harness.openReadyDatabase(observer: failures);
    now = DateTime(2026, 10, 5, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
    log = _HeldPackageReads(repository);
    compactionOutcomes = _CompactionOutcomes();
    compaction = GraphLogCompaction(
      log: log,
      directory: Directory.fromUri(
        harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
      ),
      clock: () => now,
      diagnosticsSink: compactionOutcomes,
      threshold: _threshold,
    );
    backups = GraphBackups(
      registry: repository,
      compaction: compaction,
      clock: () => now,
    );
  });

  tearDown(() async {
    await compaction.shutdown();
    await harness.dispose();
  });

  Future<void> createTag(String name) async {
    expect(
      await repository.execute(CreateTag(TagName.fromInput(name))),
      isA<GraphCommandSucceeded>(),
    );
  }

  Future<List<GraphBackupEntry>> list() async {
    final read = await repository.watchBackups().first;
    return (read as GraphBackupsReadSucceeded).backups;
  }

  group('ежедневная копия', () {
    test(
      'сценарий «Ежедневная копия при первом открытии за день»: копия '
      'получает текущие момент и позицию и показывает «1 добавлено»',
      () async {
        await createTag('Дом');
        expect(
          await backups.makeDailyBackupIfDue(),
          DailyGraphBackupOutcome.made,
        );
        now = DateTime(2026, 10, 5, 20);
        expect(
          await repository.execute(
            CreateIntention(title: 'Бегать', description: null),
          ),
          isA<GraphCommandSucceeded>(),
        );
        now = DateTime(2026, 10, 6, 8, 15);

        expect(
          await backups.makeDailyBackupIfDue(),
          DailyGraphBackupOutcome.made,
        );

        final latest = (await list()).first;
        expect(latest.kind, GraphBackupKind.daily);
        expect(latest.madeAt.toLocal(), DateTime(2026, 10, 6, 8, 15));
        expect(latest.position, await repository.readCurrentPosition());
        expect(_shown(latest.summary), (added: 1, changed: 0, deleted: 0));
      },
    );

    test('сценарий «Перерыв в использовании не удаляет копии»: без '
        'изменений графа ежедневных копий за следующие дни нет', () async {
      await createTag('Дом');
      now = DateTime(2026, 10, 1, 9, 30);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      now = DateTime(2026, 10, 15, 10);

      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.notDue,
      );

      expect(_moments(await list()), [DateTime(2026, 10, 1, 9, 30)]);
    });

    test('после изменений графа новая ежедневная копия делается не раньше '
        '03:00 следующего дня по местному времени', () async {
      await createTag('Дом');
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      await createTag('Дача');

      now = DateTime(2026, 10, 6, 2, 59);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.notDue,
      );
      now = DateTime(2026, 10, 6, 3);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );

      expect(_moments(await list()), [
        DateTime(2026, 10, 6, 3),
        DateTime(2026, 10, 5, 9),
      ]);
    });

    test('перевод часов вперёд и назад добавляет ежедневные копии после '
        'изменений графа и не удаляет прежние копии', () async {
      await createTag('Дом');
      now = DateTime(2026, 10, 6, 9);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      await createTag('Дача');
      now = DateTime(2026, 10, 20, 9);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      await createTag('Сад');

      now = DateTime(2026, 10, 6, 12);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );

      expect(_moments(await list()), [
        DateTime(2026, 10, 6, 12),
        DateTime(2026, 10, 20, 9),
        DateTime(2026, 10, 6, 9),
      ]);
    });
  });

  group('копии по одной', () {
    test('ручная копия, запрошенная во время ежедневной, делается после неё '
        'и показывает «Нет изменений»', () async {
      await createTag('Дом');
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      await createTag('Дача');
      now = DateTime(2026, 10, 6, 9);
      final held = log.holdNextPackageRead();
      final daily = backups.makeDailyBackupIfDue();
      await held.reached;

      final manual = backups.makeManualBackup();
      held.release();

      expect(await daily, DailyGraphBackupOutcome.made);
      expect(await manual, ManualGraphBackupOutcome.made);
      expect(
        [for (final backup in await list()) backup.kind],
        [GraphBackupKind.manual, GraphBackupKind.daily, GraphBackupKind.daily],
      );
      expect(
        [for (final backup in await list()) _shown(backup.summary)],
        [
          (added: 0, changed: 0, deleted: 0),
          (added: 1, changed: 0, deleted: 0),
          (added: 1, changed: 0, deleted: 0),
        ],
      );
    });

    test('команда, подтверждённая во время подсчёта сводки, подтверждается '
        'до его окончания и входит в сводку и позицию копии', () async {
      await createTag('Дом');
      expect(await backups.makeManualBackup(), ManualGraphBackupOutcome.made);
      await createTag('Дача');
      final held = log.holdNextPackageRead();
      final manual = backups.makeManualBackup();
      await held.reached;

      await createTag('Сад');
      held.release();

      expect(await manual, ManualGraphBackupOutcome.made);
      final latest = (await list()).first;
      expect(latest.position, await repository.readCurrentPosition());
      expect(_shown(latest.summary), (added: 2, changed: 0, deleted: 0));
    });

    test('сжатие лога, завершившееся во время подсчёта сводки, сводку не '
        'меняет', () async {
      compaction.start();
      await createTag('Дом');
      expect(await backups.makeManualBackup(), ManualGraphBackupOutcome.made);
      await createTag('Дача');
      final held = log.holdNextPackageRead();
      final manual = backups.makeManualBackup();
      await held.reached;

      final compacted = compactionOutcomes.next;
      for (var number = 1; number <= _threshold + 1; number++) {
        await createTag('Тег $number');
      }
      expect((await compacted).status, isA<DiagnosticsSucceeded>());
      held.release();

      expect(await manual, ManualGraphBackupOutcome.made);
      expect(_shown((await list()).first.summary), (
        added: _threshold + 2,
        changed: 0,
        deleted: 0,
      ));
    });

    test('отказ записи ежедневной и ручной копий даёт исход отказа и не '
        'меняет копии, а следующая попытка делает копию', () async {
      await createTag('Дом');
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
      await createTag('Дача');
      now = DateTime(2026, 10, 6, 9);
      failures.failsBackupInsert = true;

      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.failed,
      );
      expect(await backups.makeManualBackup(), ManualGraphBackupOutcome.failed);

      failures.failsBackupInsert = false;
      expect(_moments(await list()), [DateTime(2026, 10, 5, 9)]);
      expect(
        await backups.makeDailyBackupIfDue(),
        DailyGraphBackupOutcome.made,
      );
    });
  });
}

/// Сводка так, как её показывает список копий: числа или признак замены.
Object _shown(GraphChangeSummary summary) => switch (summary) {
  GraphChangeCounts(:final added, :final changed, :final deleted) => (
    added: added,
    changed: changed,
    deleted: deleted,
  ),
  GraphDataReplaced() => 'Данные заменены',
};

/// Моменты копий по местному времени, от новых копий к старым.
List<DateTime> _moments(List<GraphBackupEntry> backups) => [
  for (final backup in backups) backup.madeAt.toLocal(),
];

/// Отказывает каждую вставку строки копии, пока задан [failsBackupInsert].
final class _BackupInsertFailures extends LocalDatabaseConnectionObserver {
  var failsBackupInsert = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failsBackupInsert &&
        statement.operation == LocalDatabaseSqlOperation.insert &&
        statement.statements.single.contains('"graph_backups"')) {
      throw StateError('Внедрённый отказ вставки копии');
    }
  }
}

/// Лог фактов, который задерживает одно чтение пакетов по запросу теста.
final class _HeldPackageReads extends ForwardingGraphFactLog {
  _HeldPackageReads(super.source);

  ({Completer<void> reached, Completer<void> released})? _held;

  /// Задерживает следующее чтение пакетов: `reached` завершается, когда оно
  /// начато, а продолжается оно после `release`. Следующие чтения не
  /// задерживаются.
  ({Future<void> reached, void Function() release}) holdNextPackageRead() {
    final held = (reached: Completer<void>(), released: Completer<void>());
    _held = held;
    return (reached: held.reached.future, release: held.released.complete);
  }

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) async {
    if (_held case final held?) {
      _held = null;
      held.reached.complete();
      await held.released.future;
    }
    return super.readPackages(after: after, upTo: upTo);
  }
}

/// Исходы сжатия лога из диагностики.
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
