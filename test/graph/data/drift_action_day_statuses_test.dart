import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

/// Отказывает чтению состояний дней, пока включён.
final class _ReadFailureProbe extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM actions')) {
      throw error;
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _ReadFailureProbe probe;

  setUp(() async {
    probe = _ReadFailureProbe();
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      diagnostics,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
    });
  });

  tearDown(() => database.close());

  void addAction(int number, String date, {bool completed = false}) =>
      seedRawGraph(
        raw,
        () => seedAction(
          raw,
          id: seedUuid(number),
          path: [seedUuid(1), seedUuid(2)],
          date: date,
          isCompleted: completed,
        ),
      );

  Future<GraphSnapshot<ActionDayStatuses>> read(
    ActionDayStatusQuery query,
  ) async => ((await repository.getActionDayStatuses(
    query,
  )) as ActionDayStatusesReadSuccess).value;

  test(
    'различает состояния всех действий даты и включает обе границы окна',
    () async {
      addAction(201, '2026-10-05', completed: true);
      addAction(202, '2026-10-05', completed: true);
      addAction(203, '2026-10-06', completed: true);
      addAction(204, '2026-10-06');
      addAction(205, '2026-10-08');
      addAction(206, '2026-10-04');
      addAction(207, '2026-10-09');
      final query = ActionDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 10, 5),
        lastDate: CalendarDate.fromParts(2026, 10, 8),
      );

      final statuses = (await read(query)).value;

      expect(statuses.query.firstDate, query.firstDate);
      expect(statuses.query.lastDate, query.lastDate);
      // Даты 2026-10-07 нет в карте: в этот день нет действий.
      expect(statuses.statuses, {
        CalendarDate.fromParts(2026, 10, 5): ActionDayStatus.allCompleted,
        CalendarDate.fromParts(2026, 10, 6): ActionDayStatus.hasIncomplete,
        CalendarDate.fromParts(2026, 10, 8): ActionDayStatus.hasIncomplete,
      });
    },
  );

  test('учитывает действия с архивными и удалёнными звеньями пути', () async {
    addAction(201, '2026-10-05', completed: true);
    addAction(202, '2026-10-06');
    addAction(203, '2026-10-07', completed: true);
    seedRawGraph(raw, () {
      raw.execute('UPDATE long_term_relations SET is_archived = 1');
      raw.execute('UPDATE intentions SET is_archived = 1');
    });
    seedRawGraph(raw, () {
      raw.execute('DELETE FROM long_term_relations');
      raw.execute('DELETE FROM intentions');
    });

    final statuses = (await read(
      ActionDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 10, 5),
        lastDate: CalendarDate.fromParts(2026, 10, 7),
      ),
    )).value;

    expect(statuses.statuses, {
      CalendarDate.fromParts(2026, 10, 5): ActionDayStatus.allCompleted,
      CalendarDate.fromParts(2026, 10, 6): ActionDayStatus.hasIncomplete,
      CalendarDate.fromParts(2026, 10, 7): ActionDayStatus.allCompleted,
    });
  });

  test('день окна без действий даёт успешный пустой снимок', () async {
    addAction(201, '2026-10-05');
    final date = CalendarDate.fromParts(2026, 10, 6);

    final statuses = (await read(
      ActionDayStatusQuery(firstDate: date, lastDate: date),
    )).value;

    expect(statuses.statuses, isEmpty);
  });

  test('состояние после команды возвращается с её подтверждённой '
      'ревизией', () async {
    addAction(201, '2026-10-05');
    final date = CalendarDate.fromParts(2026, 10, 5);
    final query = ActionDayStatusQuery(firstDate: date, lastDate: date);
    final before = await read(query);

    final command = await repository.execute(
      UpdateActionFields(
        actionId: _action(201),
        patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
      ),
    );
    expect(command, isA<GraphCommandSucceeded>());
    final after = await read(query);

    expect(before.value.statuses[date], ActionDayStatus.hasIncomplete);
    expect(after.value.statuses[date], ActionDayStatus.allCompleted);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
    expect(
      after.revision.compareTo(
        (command as GraphCommandSucceeded).value.revision,
      ),
      GraphRevisionOrder.same,
    );
  });

  test('сохранённая несуществующая дата в окне отклоняет весь снимок как '
      'повреждение', () async {
    addAction(201, '2026-02-01', completed: true);
    addAction(202, '2026-02-30');

    final result = await repository.getActionDayStatuses(
      ActionDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 2, 1),
        lastDate: CalendarDate.fromParts(2026, 3, 1),
      ),
    );

    expect(
      (result as ActionDayStatusesReadError).failure,
      isA<ActionDayStatusesCorruptionFailure>(),
    );
    expect(diagnostics.events.last, containsPair('failureCode', 'corruption'));
  });

  for (final (error, failure, code) in <(Object, Type, String)>[
    (
      sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'CANARY-ошибка',
        causingStatement: 'CANARY-запрос',
        parametersToStatement: ['CANARY-дата'],
      ),
      ActionDayStatusesUnavailableFailure,
      'unavailable',
    ),
    (
      sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
        message: 'CANARY-ошибка',
      ),
      ActionDayStatusesCorruptionFailure,
      'corruption',
    ),
    (
      StateError('CANARY-причина'),
      ActionDayStatusesUnexpectedFailure,
      'unexpected',
    ),
  ]) {
    test('сбой чтения ($code) различим по категории, а диагностика не '
        'раскрывает данные', () async {
      addAction(201, '2026-10-05', completed: true);
      probe.failure = error;
      final date = CalendarDate.fromParts(2026, 10, 5);

      final result = await repository.getActionDayStatuses(
        ActionDayStatusQuery(firstDate: date, lastDate: date),
      );
      probe.failure = null;

      expect(
        (result as ActionDayStatusesReadError).failure.runtimeType,
        failure,
      );
      expect(diagnostics.events, [
        {
          'operation': 'actionDayStatusesRead',
          'stage': 'read',
          'outcome': 'started',
        },
        {
          'operation': 'actionDayStatusesRead',
          'stage': 'read',
          'outcome': 'failed',
          'failureCode': code,
        },
      ]);
      expect(jsonEncode(diagnostics.events), isNot(contains('CANARY')));
    });
  }

  test(
    'успешное чтение записывает событие без пользовательских данных',
    () async {
      addAction(201, '2026-10-05');
      final date = CalendarDate.fromParts(2026, 10, 5);

      await read(ActionDayStatusQuery(firstDate: date, lastDate: date));

      expect(diagnostics.events, [
        {
          'operation': 'actionDayStatusesRead',
          'stage': 'read',
          'outcome': 'started',
        },
        {
          'operation': 'actionDayStatusesRead',
          'stage': 'read',
          'outcome': 'succeeded',
        },
      ]);
    },
  );
}
