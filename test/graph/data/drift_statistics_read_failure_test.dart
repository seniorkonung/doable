import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _FailureProbe probe;

  StatisticsQuery query({StatisticsPeriod? period}) => StatisticsQuery(
    period: period ?? StatisticsMonth(2026, 2),
    view: StatisticsView.sourceIntentions,
    localDate: CalendarDate.fromParts(2026, 2, 12),
    pageSize: 100,
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _FailureProbe();
    database = await harness.openReadyDatabase(observer: probe);
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 2, 12),
      diagnostics,
    );
    await seedDurabilityGraph(database);
    expect(
      await repository.execute(
        durabilityCreate(date: CalendarDate.fromParts(2026, 2, 12)),
      ),
      isA<GraphCommandSucceeded>(),
    );
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

  test('некорректная календарная дата отклоняет весь период', () async {
    // Формат этой даты допускается схемой, но календарный день не существует.
    await database.customStatement('UPDATE daily_choices SET choice_date = ?', [
      '2026-02-30',
    ]);
    for (final month in [1, 12]) {
      expect(
        await repository.execute(
          durabilityCreate(date: CalendarDate.fromParts(2026, month, 1)),
        ),
        isA<GraphCommandSucceeded>(),
      );
    }
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
    ('missed', 'не число'),
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
    final stage = sql.contains('FROM intentions')
        ? StatisticsReadDiagnosticsStage.titles
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
