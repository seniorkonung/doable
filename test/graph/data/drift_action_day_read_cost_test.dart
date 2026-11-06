import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _pageSize = 5;
const _dayActions = 12;
const _longPath = 60;

/// Запоминает запросы и материализованные строки для проверки стоимости чтения.
final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final reads =
      <
        ({LocalDatabaseSqlStatement statement, List<Map<String, Object?>> rows})
      >[];

  void clear() => reads.clear();

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    reads.add((statement: statement, rows: rows));
    return rows;
  }
}

void main() {
  late _ReadTrace trace;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  final day = CalendarDate.fromParts(2026, 10, 8);

  setUp(() async {
    trace = _ReadTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7),
      InMemoryDiagnosticsSink(),
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= _longPath; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      // Самое раннее действие дня идёт по самому длинному пути, соседние
      // дни не меньше выбранного.
      var number = 1000;
      for (final date in ['2026-10-07', '2026-10-08', '2026-10-09']) {
        for (var index = 0; index < _dayActions; index++) {
          final longest = date == '2026-10-08' && index == 0;
          seedAction(
            raw,
            id: seedUuid(number++),
            path: [
              for (
                var intention = 1;
                intention <= (longest ? _longPath : 2);
                intention++
              )
                seedUuid(intention),
            ],
            date: date,
          );
        }
      }
    });
    trace.clear();
  });

  tearDown(() => database.close());

  test('порция читает не больше своих строк без путей, а запросы идут по '
      'индексам действий и первичному ключу пути', () async {
    final first = ((await repository.getActionDayPage(
      ActionDayQuery(
        date: day,
        section: ActionDaySection.incomplete,
        pageSize: _pageSize,
      ),
    )) as ActionDayPageSuccess).value;
    expect(first.items.first.pathIntentionCount, _longPath);
    expect(first.items, hasLength(_pageSize));

    // Строка запроса порции — лишняя за признак продолжения, а числа дня —
    // не больше двух строк: ни один путь не читается целиком.
    expect(
      trace.reads.map((read) => read.rows.length),
      everyElement(lessThanOrEqualTo(_pageSize + 1)),
    );

    final reads = [...trace.reads];
    trace.clear();
    final next = ((await repository.getActionDayPage(
      ActionDayQuery(
        date: day,
        section: ActionDaySection.incomplete,
        pageSize: _pageSize,
        cursor: first.nextCursor,
      ),
    )) as ActionDayPageSuccess).value;
    expect(next.items, hasLength(_pageSize));
    reads.addAll(trace.reads);

    expect(reads, hasLength(3));
    for (final read in reads) {
      final plan = raw
          .select(
            'EXPLAIN QUERY PLAN ${read.statement.statements.single}',
            read.statement.arguments,
          )
          .map((row) => row['detail'] as String)
          .join('\n');
      expect(plan, contains('actions_date_completion_schedule_order'));
      expect(plan, contains('date=?'));
      expect(plan, isNot(contains('USE TEMP B-TREE')));
      expect(plan, isNot(contains('SCAN action_path_items')));
      if (read.statement.statements.single.contains('action_path_items')) {
        expect(plan, contains('is_completed=?'));
        expect(plan, contains('action_id=? AND position=?'));
      }
    }
  });
}
