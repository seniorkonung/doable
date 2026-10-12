import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late PersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadFailureProbe probe;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    probe = _ReadFailureProbe();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        probe,
      ),
    );
    await database.open();
    await seedDurabilityGraph(database);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  void addChoice(int number, String date, {bool completed = false}) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          is_completed) VALUES (?, ?, ?, ?, ?)''',
      [
        durabilityUuid(number),
        durabilityUuid(1),
        durabilityUuid(3),
        date,
        completed ? 1 : 0,
      ],
    );
    for (var index = 0; index < 2; index++) {
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          durabilityUuid(number * 10 + index),
          durabilityUuid(number),
          durabilityUuid(101 + index),
          index == 0 ? null : durabilityUuid(number * 10),
        ],
      );
    }
  }

  test('различает состояния всех выборов и включает обе границы', () async {
    addChoice(201, '2026-10-05', completed: true);
    addChoice(202, '2026-10-05', completed: true);
    addChoice(203, '2026-10-06', completed: true);
    addChoice(204, '2026-10-06');
    addChoice(205, '2026-10-08');
    addChoice(206, '2026-10-04');
    addChoice(207, '2026-10-09');
    final query = DailyChoiceDayStatusQuery(
      firstDate: CalendarDate.fromParts(2026, 10, 5),
      lastDate: CalendarDate.fromParts(2026, 10, 8),
    );

    final result = await repository.getDailyChoiceDayStatuses(query);

    expect(result, isA<DailyChoiceDayStatusesReadSuccess>());
    final statuses = (result as DailyChoiceDayStatusesReadSuccess).value.value;
    expect(statuses.query.firstDate, query.firstDate);
    expect(statuses.query.lastDate, query.lastDate);
    expect(statuses.statuses, {
      CalendarDate.fromParts(2026, 10, 5): DailyChoiceDayStatus.allCompleted,
      CalendarDate.fromParts(2026, 10, 6): DailyChoiceDayStatus.hasIncomplete,
      CalendarDate.fromParts(2026, 10, 8): DailyChoiceDayStatus.hasIncomplete,
    });
    expect(
      diagnostics.events
          .whereType<DailyChoiceDayStatusesReadDiagnosticsEvent>()
          .map((event) => event.status),
      [
        isA<DiagnosticsStarted>(),
        isA<DiagnosticsSucceeded>().having(
          (status) => status.duration,
          'длительность',
          greaterThanOrEqualTo(Duration.zero),
        ),
      ],
    );
  });

  test('отклоняет весь снимок с несуществующей сохранённой датой', () async {
    addChoice(201, '2026-02-01', completed: true);
    addChoice(202, '2026-02-30');

    final result = await repository.getDailyChoiceDayStatuses(
      DailyChoiceDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 2, 1),
        lastDate: CalendarDate.fromParts(2026, 3, 1),
      ),
    );

    expect(result, isA<DailyChoiceDayStatusesReadError>());
    expect(
      diagnostics.events
          .whereType<DailyChoiceDayStatusesReadDiagnosticsEvent>()
          .last
          .status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.corruption,
      ),
    );
  });

  test('возвращает пустой успешный снимок дня без выборов', () async {
    addChoice(201, '2026-10-05');
    final date = CalendarDate.fromParts(2026, 10, 6);

    final result = await repository.getDailyChoiceDayStatuses(
      DailyChoiceDayStatusQuery(firstDate: date, lastDate: date),
    );

    expect(result, isA<DailyChoiceDayStatusesReadSuccess>());
    expect(
      (result as DailyChoiceDayStatusesReadSuccess).value.value.statuses,
      isEmpty,
    );
  });

  test(
    'учитывает выборы с архивированными участниками и шагами пути',
    () async {
      addChoice(201, '2026-10-05', completed: true);
      addChoice(202, '2026-10-06');
      raw.execute('UPDATE long_term_relations SET is_archived = 1');
      raw.execute('UPDATE intentions SET is_archived = 1');

      final result = await repository.getDailyChoiceDayStatuses(
        DailyChoiceDayStatusQuery(
          firstDate: CalendarDate.fromParts(2026, 10, 5),
          lastDate: CalendarDate.fromParts(2026, 10, 6),
        ),
      );

      expect(result, isA<DailyChoiceDayStatusesReadSuccess>());
      expect(
        (result as DailyChoiceDayStatusesReadSuccess).value.value.statuses,
        {
          CalendarDate.fromParts(2026, 10, 5):
              DailyChoiceDayStatus.allCompleted,
          CalendarDate.fromParts(2026, 10, 6):
              DailyChoiceDayStatus.hasIncomplete,
        },
      );
    },
  );

  test(
    'состояние после команды возвращается с её подтверждённой ревизией',
    () async {
      addChoice(201, '2026-10-05');
      final date = CalendarDate.fromParts(2026, 10, 5);
      final query = DailyChoiceDayStatusQuery(firstDate: date, lastDate: date);
      final before = (await repository.getDailyChoiceDayStatuses(
        query,
      ) as DailyChoiceDayStatusesReadSuccess).value;

      final command = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      expect(command, isA<GraphCommandSucceeded>());
      final after = (await repository.getDailyChoiceDayStatuses(
        query,
      ) as DailyChoiceDayStatusesReadSuccess).value;

      expect(before.value.statuses[date], DailyChoiceDayStatus.hasIncomplete);
      expect(after.value.statuses[date], DailyChoiceDayStatus.allCompleted);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        after.revision.compareTo(
          (command as GraphCommandSucceeded).value.revision,
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  for (final (error, code, category) in [
    (
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      DiagnosticsFailureCode.unavailable,
      'недоступность',
    ),
    (
      sqlite.SqliteException(message: 'Повреждение', extendedResultCode: 11),
      DiagnosticsFailureCode.corruption,
      'повреждение',
    ),
    (
      StateError('Неизвестный отказ'),
      DiagnosticsFailureCode.unexpected,
      'неизвестная причина',
    ),
  ]) {
    test('возвращает единый отказ и записывает категорию: $category', () async {
      addChoice(201, '2026-10-05', completed: true);
      probe.failure = error;
      final date = CalendarDate.fromParts(2026, 10, 5);

      final result = await repository.getDailyChoiceDayStatuses(
        DailyChoiceDayStatusQuery(firstDate: date, lastDate: date),
      );

      expect(result, isA<DailyChoiceDayStatusesReadError>());
      expect(
        diagnostics.events
            .whereType<DailyChoiceDayStatusesReadDiagnosticsEvent>()
            .map((event) => event.status),
        [
          isA<DiagnosticsStarted>(),
          isA<DiagnosticsFailed>()
              .having((status) => status.code, 'категория', code)
              .having(
                (status) => status.duration,
                'длительность',
                greaterThanOrEqualTo(Duration.zero),
              ),
        ],
      );
    });
  }
}

final class _ReadFailureProbe extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM daily_choices')) {
      if (failure case final error?) throw error;
    }
  }
}
