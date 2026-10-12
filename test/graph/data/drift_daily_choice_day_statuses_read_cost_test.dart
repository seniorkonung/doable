import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  test('максимальное окно читает только агрегаты дней через индекс даты', () async {
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
    await seedDurabilityGraph(database);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 12),
      InMemoryDiagnosticsSink(),
    );
    final first = DateTime.utc(2026, 1, 1);
    final dates = [
      for (var offset = 0; offset < DailyChoiceDayStatusQuery.maxDays; offset++)
        _date(first.add(Duration(days: offset))),
    ];
    final expected = {
      for (var index = 0; index < dates.length; index++)
        dates[index]: index.isEven
            ? DailyChoiceDayStatus.allCompleted
            : DailyChoiceDayStatus.hasIncomplete,
    };
    final insertChoice = raw.prepare('''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          is_completed) VALUES (?, ?, ?, ?, ?)''');
    final insertStep = raw.prepare('''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, ?)''');
    var choiceNumber = 10000;
    void addChoice(CalendarDate date, bool completed) {
      final number = choiceNumber++;
      insertChoice.execute([
        durabilityUuid(number),
        durabilityUuid(1),
        durabilityUuid(3),
        date.toCanonicalString(),
        completed ? 1 : 0,
      ]);
      for (var index = 0; index < 2; index++) {
        insertStep.execute([
          durabilityUuid(number * 10 + index),
          durabilityUuid(number),
          durabilityUuid(101 + index),
          index == 0 ? null : durabilityUuid(number * 10),
        ]);
      }
    }

    raw.execute('BEGIN');
    try {
      for (var day = 0; day < dates.length; day++) {
        for (var choice = 0; choice < 20; choice++) {
          addChoice(dates[day], day.isEven || choice != 0);
        }
      }
      for (var choice = 0; choice < 3000; choice++) {
        addChoice(_date(first.subtract(const Duration(days: 1))), false);
        addChoice(
          _date(
            first.add(const Duration(days: DailyChoiceDayStatusQuery.maxDays)),
          ),
          false,
        );
      }
      raw.execute('COMMIT');
    } on Object {
      raw.execute('ROLLBACK');
      rethrow;
    } finally {
      insertChoice.close();
      insertStep.close();
    }
    trace.reads.clear();

    final result = await repository.getDailyChoiceDayStatuses(
      DailyChoiceDayStatusQuery(firstDate: dates.first, lastDate: dates.last),
    );

    expect(result, isA<DailyChoiceDayStatusesReadSuccess>());
    expect(
      (result as DailyChoiceDayStatusesReadSuccess).value.value.statuses,
      expected,
    );
    expect(trace.reads, isNotEmpty);
    expect(trace.reads.length, lessThanOrEqualTo(1));
    expect(
      trace.reads.fold<int>(0, (total, read) => total + read.rowCount),
      lessThanOrEqualTo(DailyChoiceDayStatusQuery.maxDays),
    );
    for (final read in trace.reads) {
      final sql = read.statement.statements.single;
      expect(
        sql,
        isNot(
          matches(
            r'\b(daily_choice_path_steps|intentions|long_term_relations)\b',
          ),
        ),
      );
      final plan = raw.select(
        'EXPLAIN QUERY PLAN $sql',
        read.statement.arguments,
      );
      final details = plan.map((row) => row['detail'] as String).join('\n');
      expect(
        details,
        contains(
          'SEARCH daily_choices USING INDEX daily_choices_date_creation_order',
        ),
      );
      expect(details, contains('choice_date>?'));
      expect(details, contains('choice_date<?'));
      expect(details, isNot(contains('SCAN')));
    }
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
