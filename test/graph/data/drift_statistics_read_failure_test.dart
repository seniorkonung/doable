import 'dart:isolate';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _FailureProbe probe;

  StatisticsQuery query({
    StatisticsPeriod? period,
    StatisticsView view = StatisticsView.rootIntentions,
  }) => StatisticsQuery(
    period: period ?? StatisticsMonth(2026, 2),
    view: view,
    pageSize: 100,
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _FailureProbe();
    database = await harness.openReadyDatabase(
      setup: (db) => raw = db,
      observer: probe,
    );
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 2, 12),
      diagnostics,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedAction(
        raw,
        id: seedUuid(201),
        path: [
          for (final number in [1, 2, 3]) seedUuid(number),
        ],
        date: '2026-02-12',
        isCompleted: true,
      );
    });
  });
  tearDown(() => harness.dispose());

  void expectFailure(
    StatisticsPageResult result,
    GraphFailureCategory category,
    StatisticsReadDiagnosticsStage stage,
  ) {
    expect(result, isA<StatisticsPageError>());
    expect((result as StatisticsPageError).failure.category, category);
    final events = diagnostics.events
        .whereType<StatisticsReadDiagnosticsEvent>()
        .toList();
    expect(events.last.readType, StatisticsReadDiagnosticsType.homePage);
    expect(events.last.stage, stage);
    expect(
      events.last.status,
      isA<DiagnosticsFailed>()
          .having((status) => status.code.name, 'категория', category.name)
          .having(
            (status) => status.duration,
            'длительность',
            greaterThanOrEqualTo(Duration.zero),
          ),
    );
  }

  for (final (error, category) in [
    (
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      GraphFailureCategory.unavailable,
    ),
    (
      sqlite.SqliteException(message: 'Повреждение', extendedResultCode: 11),
      GraphFailureCategory.corruption,
    ),
    (StateError('Неизвестный отказ'), GraphFailureCategory.unexpected),
  ]) {
    test('отказ агрегата сохраняет категорию: ${category.name}', () async {
      probe.failure = error;
      probe.failureStage = StatisticsReadDiagnosticsStage.sourceData;
      expectFailure(
        await repository.getStatisticsPage(query()),
        category,
        StatisticsReadDiagnosticsStage.sourceData,
      );
    });
  }

  test(
    'отказ названий отклоняет всю выдачу после успешных агрегатов',
    () async {
      probe.failure = sqlite.SqliteException(
        message: 'Повреждение',
        extendedResultCode: 11,
      );
      probe.failureStage = StatisticsReadDiagnosticsStage.titles;
      expectFailure(
        await repository.getStatisticsPage(query()),
        GraphFailureCategory.corruption,
        StatisticsReadDiagnosticsStage.titles,
      );
      expect(
        diagnostics.events.whereType<StatisticsReadDiagnosticsEvent>().map(
          (event) => (event.stage, event.status.runtimeType),
        ),
        [
          (StatisticsReadDiagnosticsStage.sourceData, DiagnosticsStarted),
          (StatisticsReadDiagnosticsStage.sourceData, DiagnosticsSucceeded),
          (StatisticsReadDiagnosticsStage.titles, DiagnosticsStarted),
          (StatisticsReadDiagnosticsStage.titles, DiagnosticsFailed),
        ],
      );
    },
  );

  for (final (stage, error, category) in [
    (
      StatisticsReadDiagnosticsStage.sourceData,
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      GraphFailureCategory.unavailable,
    ),
    (
      StatisticsReadDiagnosticsStage.relationSnapshot,
      sqlite.SqliteException(message: 'Повреждение', extendedResultCode: 11),
      GraphFailureCategory.corruption,
    ),
    (
      StatisticsReadDiagnosticsStage.computation,
      StateError('CANARY-содержимое-графа'),
      GraphFailureCategory.unexpected,
    ),
    (
      StatisticsReadDiagnosticsStage.relationSnapshot,
      const StatisticsSnapshotExpired(),
      GraphFailureCategory.conflict,
    ),
    (
      StatisticsReadDiagnosticsStage.titles,
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      GraphFailureCategory.unavailable,
    ),
  ]) {
    test(
      'отказ этапа через связи отклоняет всё чтение: ${stage.name}/${category.name}',
      () async {
        if (stage == StatisticsReadDiagnosticsStage.computation) {
          repository = DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 2, 12),
            diagnostics,
            statisticsReachabilityRunner: _failedComputation,
          );
        } else {
          probe.failure = error;
          probe.failureStage = stage;
        }
        expectFailure(
          await repository.getStatisticsPage(
            query(view: StatisticsView.throughRelations),
          ),
          category,
          stage,
        );
        expect(
          diagnostics.events.whereType<StatisticsReadDiagnosticsEvent>().where(
            (event) => event.status is DiagnosticsFailed,
          ),
          hasLength(1),
        );
      },
    );
  }

  test('некорректная календарная дата отклоняет весь период', () async {
    // Формат этой даты допускается схемой, но календарный день не существует.
    seedRawGraph(raw, () {
      for (final (number, date) in [
        (202, '2026-01-01'),
        (203, '2026-02-30'),
        (204, '2026-12-01'),
      ]) {
        seedAction(raw, id: seedUuid(number), path: [seedUuid(1)], date: date);
      }
    });
    expectFailure(
      await repository.getStatisticsPage(query(period: StatisticsYear(2026))),
      GraphFailureCategory.corruption,
      StatisticsReadDiagnosticsStage.sourceData,
    );
  });

  for (final (field, value) in <(String, Object)>[
    ('is_completed', 2),
    ('planned', -1),
    ('contribution', 2),
    ('total_items', -1),
    ('date', 'не дата'),
  ]) {
    test('декодирование отклоняет повреждённое значение: $field', () async {
      probe.replaceField = field;
      probe.replacement = value;
      expectFailure(
        await repository.getStatisticsPage(query()),
        GraphFailureCategory.corruption,
        StatisticsReadDiagnosticsStage.sourceData,
      );
      expect(probe.didReplace, isTrue);
    });
  }
}

final class _FailureProbe extends LocalDatabaseConnectionObserver {
  Object? failure;
  StatisticsReadDiagnosticsStage? failureStage;
  String? replaceField;
  Object? replacement;
  bool didReplace = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    final sql = statement.statements.single;
    // Существование намерений проверяют и запросы исходных данных, поэтому
    // этап названий узнаётся по своим столбцам.
    final stage = sql.contains('SELECT id, title, is_archived FROM intentions')
        ? StatisticsReadDiagnosticsStage.titles
        : sql.contains('creation_sequence >')
        ? StatisticsReadDiagnosticsStage.relationSnapshot
        : StatisticsReadDiagnosticsStage.sourceData;
    if (stage == failureStage) {
      if (failure case final error?) throw error;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final field = replaceField;
    if (field == null ||
        didReplace ||
        rows.isEmpty ||
        !rows.first.containsKey(field)) {
      return rows;
    }
    didReplace = true;
    return [
      {...rows.first, field: replacement},
      ...rows.skip(1),
    ];
  }
}

Future<List<ContributionReachabilityEntry>> _failedComputation(
  ContributionRelationGraph graph,
  List<ContributionSeedGroup> groups,
) => Isolate.run(() => throw StateError('CANARY-содержимое-графа'));
