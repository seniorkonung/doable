import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _pageSize = 5;
const _roleActions = 12;
const _longPath = 60;

IntentionId _intention(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;

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
      // Намерение 2 — корневое, промежуточное и конечное в равном числе
      // путей; первым по порядку идёт самый длинный путь. Пути без него не
      // меньше выбранных.
      var number = 1000;
      for (var index = 0; index < _roleActions; index++) {
        final date = '2026-10-${(index + 10).toString().padLeft(2, '0')}';
        final longest = index == _roleActions - 1;
        for (final path in [
          [2, for (var i = 3; i <= (longest ? _longPath : 3); i++) i],
          [1, 2, 3],
          [1, 2],
          [1, 3],
        ]) {
          seedAction(
            raw,
            id: seedUuid(number++),
            path: [for (final intention in path) seedUuid(intention)],
            date: date,
          );
        }
      }
    });
    trace.clear();
  });

  tearDown(() => database.close());

  test('порция каждой роли читает не больше своих строк без путей, а '
      'запросы идут по индексу роли без сортировки', () async {
    final statements = <LocalDatabaseSqlStatement>[];
    final continuations = <LocalDatabaseSqlStatement>[];
    for (final role in IntentionActionRole.values) {
      trace.clear();
      final first = ((await repository.getIntentionActionsPage(
        IntentionActionsQuery(
          intentionId: _intention(2),
          role: role,
          pageSize: _pageSize,
        ),
      )) as IntentionActionsPageSuccess).value;
      expect(first.items, hasLength(_pageSize));
      if (role == IntentionActionRole.root) {
        expect(first.items.first.pathIntentionCount, _longPath - 1);
      }
      final next = ((await repository.getIntentionActionsPage(
        IntentionActionsQuery(
          intentionId: _intention(2),
          role: role,
          pageSize: _pageSize,
          cursor: first.nextCursor,
        ),
      )) as IntentionActionsPageSuccess).value;
      expect(next.items, hasLength(_pageSize));

      // Строка запроса порции — лишняя за признак продолжения, а числа
      // ролей — одна строка: ни один путь не читается целиком.
      expect(
        trace.reads.map((read) => read.rows.length),
        everyElement(lessThanOrEqualTo(_pageSize + 1)),
      );
      expect(trace.reads, hasLength(3));
      statements.addAll(trace.reads.map((read) => read.statement));
      continuations.add(trace.reads.last.statement);
    }

    String planOf(LocalDatabaseSqlStatement statement) => raw
        .select(
          'EXPLAIN QUERY PLAN ${statement.statements.single}',
          statement.arguments,
        )
        .map((row) => row['detail'] as String)
        .join('\n');
    for (final statement in statements) {
      final plan = planOf(statement);
      expect(plan, contains('INDEX action_path_items_intention_role_order'));
      expect(plan, isNot(contains('USE TEMP B-TREE')));
      expect(plan, isNot(contains('SCAN action_path_items')));
      expect(plan, isNot(contains('SCAN actions')));
    }
    // Продолжение начинает диапазон роли с курсора, а не проходит строки
    // до него.
    for (final statement in continuations) {
      expect(
        planOf(statement),
        contains(
          'action_path_items_intention_role_order (intention_id=? AND '
          'role=? AND (order_date,order_hour,order_sequence)<(?,?,?))',
        ),
      );
    }
  });
}
