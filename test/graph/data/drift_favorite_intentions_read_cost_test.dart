@Tags(['slow'])
library;

import 'package:doable/src/data/local/app_database.dart' hide Intention, Tags;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

final class _SelectMeasurement {
  const _SelectMeasurement(this.sql, this.arguments, this.rows);

  final String sql;
  final List<Object?> arguments;
  final int rows;
}

/// Обращения одного соединения: чтения с числом строк и записи.
final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final selects = <_SelectMeasurement>[];
  final writes = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) {
      writes.addAll(statement.statements);
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selects.add(
      _SelectMeasurement(
        statement.statements.single,
        statement.arguments,
        rows.length,
      ),
    );
    return rows;
  }

  void clear() {
    selects.clear();
    writes.clear();
  }
}

final class _MeasuredRead {
  const _MeasuredRead({
    required this.snapshot,
    required this.favoriteSelect,
    required this.aggregateSelects,
  });

  final FavoriteIntentionsSnapshot snapshot;
  final _SelectMeasurement favoriteSelect;
  final List<_SelectMeasurement> aggregateSelects;
}

/// Предел числа пакетных агрегатов счётчиков на 1000 избранных намерений:
/// построчное чтение превысило бы его на два порядка.
const _aggregateSelectLimit = 4;

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late _ReadTrace trace;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    trace = _ReadTrace();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
      observer: trace,
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 2, 12),
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  Future<_MeasuredRead> read() async {
    trace.clear();
    final marksBefore = storedFavoriteMarks(raw);
    final changesBefore = _connectionChanges(raw);
    final result = await repository.getFavoriteIntentions();
    expect(result, isA<FavoriteIntentionsSuccess>());

    // Чтение не пишет на соединение.
    expect(trace.writes, isEmpty);
    expect(_connectionChanges(raw), changesBefore);
    expect(storedFavoriteMarks(raw), marksBefore);

    final favoriteSelects = [
      for (final select in trace.selects)
        if (select.sql.toUpperCase().contains('FROM FAVORITE_INTENTIONS'))
          select,
    ];
    final aggregateSelects = [
      for (final select in trace.selects)
        if (select.sql.contains('doable_relation_count_aggregates')) select,
    ];
    // Одно чтение строк избранного; остальные обращения — только пакетные
    // агрегаты счётчиков.
    expect(favoriteSelects, hasLength(1));
    expect(
      trace.selects,
      hasLength(favoriteSelects.length + aggregateSelects.length),
    );
    final favoriteSelect = favoriteSelects.single;
    final sql = favoriteSelect.sql.toUpperCase();
    expect(sql, contains('ORDER BY F.POSITION ASC'));
    expect(sql, isNot(contains('LIMIT')));
    expect(sql, isNot(contains('OFFSET')));
    expect(favoriteSelect.arguments, isEmpty);
    final plan = [
      for (final row in raw.select('EXPLAIN QUERY PLAN ${favoriteSelect.sql}'))
        row['detail'].toString(),
    ];
    expect(plan, isNotEmpty);
    expect(plan.join(' ').toUpperCase(), isNot(contains('USE TEMP B-TREE')));
    return _MeasuredRead(
      snapshot: (result as FavoriteIntentionsSuccess).value,
      favoriteSelect: favoriteSelect,
      aggregateSelects: aggregateSelects,
    );
  }

  test('150 активных избранных намерений возвращаются одним снимком в едином '
      'порядке без продолжения, усечения и предела', () async {
    const count = 150;
    seedLargeFavoriteFixture(raw, count: count);

    final measured = await read();

    final expected = largeFavoriteFixtureActiveRows(count: count);
    expect(expected, hasLength(count));
    expect(measured.snapshot.items.map(_row), expected);
    expect(
      measured.snapshot.items.map((row) => row.id).toSet(),
      hasLength(150),
    );
    expect(measured.snapshot.archivedCount, 0);
    expect(measured.favoriteSelect.rows, count);
    expect(measured.aggregateSelects, hasLength(1));
    expect(measured.aggregateSelects.single.rows, count);
  });

  test('1000 избранных намерений с архивированными читаются одним чтением '
      'строк и пакетными агрегатами счётчиков без записи', () async {
    const count = 1000;
    const archivedEvery = 4;
    seedLargeFavoriteFixture(raw, count: count, archivedEvery: archivedEvery);
    final expected = largeFavoriteFixtureActiveRows(
      count: count,
      archivedEvery: archivedEvery,
    );
    final archivedCount = largeFavoriteFixtureArchivedCount(
      count: count,
      archivedEvery: archivedEvery,
    );
    expect(expected, hasLength(750));
    expect(archivedCount, 250);

    final measured = await read();

    expect(measured.snapshot.items.map(_row), expected);
    expect(measured.snapshot.archivedCount, archivedCount);
    // Строки всех избранных, включая архивированные, приходят одним чтением.
    expect(measured.favoriteSelect.rows, count);
    // Счётчики получены пакетами только для активных намерений.
    expect(
      measured.aggregateSelects.length,
      inInclusiveRange(1, _aggregateSelectLimit),
    );
    expect(
      measured.aggregateSelects.fold(0, (sum, select) => sum + select.rows),
      expected.length,
    );
  });
}

LargeFavoriteFixtureRow _row(FavoriteIntentionRow row) => (
  id: row.id.toCanonicalString(),
  title: row.title,
  isActionReady: row.readiness == IntentionReadiness.ready,
  activeRelationCount: row.activeRelationCount,
);

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;
