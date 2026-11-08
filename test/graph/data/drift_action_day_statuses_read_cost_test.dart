import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _actionsPerDay = 5;
const _actionsOutsideWindow = 300;

void main() {
  test('максимальное окно читает только агрегаты дней через индекс даты '
      'действий', () async {
    final trace = _ReadTrace();
    late sqlite.Database raw;
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    addTearDown(database.close);
    await database.open();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      InMemoryDiagnosticsSink(),
    );
    final first = DateTime.utc(2026, 1, 1);
    final dates = [
      for (var offset = 0; offset < ActionDayStatusQuery.maxDays; offset++)
        _date(first.add(Duration(days: offset))),
    ];
    final expected = {
      for (var index = 0; index < dates.length; index++)
        dates[index]: index.isEven
            ? ActionDayStatus.allCompleted
            : ActionDayStatus.hasIncomplete,
    };
    var number = 10000;
    void addAction(CalendarDate date, bool completed) => seedAction(
      raw,
      id: seedUuid(number++),
      path: [seedUuid(1)],
      date: date.toCanonicalString(),
      isCompleted: completed,
    );
    seedRawGraph(raw, () {
      seedIntention(raw, seedUuid(1), 'Намерение');
      for (var day = 0; day < dates.length; day++) {
        for (var action = 0; action < _actionsPerDay; action++) {
          addAction(dates[day], day.isEven || action != 0);
        }
      }
      // Дни сразу за границами окна не должны попасть в чтение.
      for (var action = 0; action < _actionsOutsideWindow; action++) {
        addAction(_date(first.subtract(const Duration(days: 1))), false);
        addAction(
          _date(first.add(const Duration(days: ActionDayStatusQuery.maxDays))),
          false,
        );
      }
    });
    trace.reads.clear();

    final result = await repository.getActionDayStatuses(
      ActionDayStatusQuery(firstDate: dates.first, lastDate: dates.last),
    );

    expect(
      (result as ActionDayStatusesReadSuccess).value.value.statuses,
      expected,
    );
    expect(trace.reads, hasLength(1));
    expect(
      trace.reads.single.rowCount,
      lessThanOrEqualTo(ActionDayStatusQuery.maxDays),
    );
    final read = trace.reads.single;
    final sql = read.statement.statements.single;
    expect(sql, isNot(matches(r'\b(action_path_items|intentions)\b')));
    final plan = raw
        .select('EXPLAIN QUERY PLAN $sql', read.statement.arguments)
        .map((row) => row['detail'] as String)
        .join('\n');
    expect(
      plan,
      contains(
        'SEARCH actions USING COVERING INDEX '
        'actions_date_completion_schedule_order',
      ),
    );
    expect(plan, contains('date>?'));
    expect(plan, contains('date<?'));
    expect(plan, isNot(contains('SCAN')));
  });
}

CalendarDate _date(DateTime value) =>
    CalendarDate.fromParts(value.year, value.month, value.day);

final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final reads = <({LocalDatabaseSqlStatement statement, int rowCount})>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    reads.add((statement: statement, rowCount: rows.length));
    return rows;
  }
}
