@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

final class _Select {
  const _Select(this.sql, this.arguments, this.rows, this.microseconds);

  final String sql;
  final List<Object?> arguments;
  final int rows;
  final int microseconds;
}

final class _Trace extends LocalDatabaseConnectionObserver {
  final selects = <_Select>[];
  final _timer = Stopwatch();

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      _timer.reset();
      _timer.start();
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    _timer.stop();
    selects.add(
      _Select(
        statement.statements.single,
        statement.arguments,
        rows.length,
        _timer.elapsedMicroseconds,
      ),
    );
    return rows;
  }

  void clear() {
    selects.clear();
  }
}

final class _Page {
  const _Page(this.value, this.microseconds, this.selects);

  final TaggedEntitiesPage value;
  final int microseconds;
  final List<_Select> selects;

  _Select get main => selects.last;
  _Select? get referenceCheck => selects.length == 4 ? selects[2] : null;
}

List<String> _plan(sqlite.Database database, String sql, List<Object?> args) =>
    [
      for (final row in database.select('EXPLAIN QUERY PLAN $sql', args))
        row['detail'].toString(),
    ];

int _assignmentVisits(
  sqlite.Database database,
  _Select select, {
  bool checkPlan = true,
}) {
  var visits = 0;
  database.createFunction(
    functionName: 'measure_navigation_visit',
    function: (_) {
      visits++;
      return 1;
    },
  );
  // Нейтральный предикат считает и назначения, отсеянные охватом или
  // проверкой ссылок. Инструментирование не участвует в замерах времени.
  final measuredSql = select.sql.replaceFirst(
    'WHERE a.tag_id = ?',
    'WHERE a.tag_id = ? AND measure_navigation_visit(a.creation_sequence) = 1',
  );
  expect(measuredSql, isNot(select.sql));
  if (checkPlan) {
    expect(
      _plan(database, measuredSql, select.arguments),
      _plan(database, select.sql, select.arguments),
    );
  }
  expect(
    database.select(measuredSql, select.arguments),
    hasLength(select.rows),
  );
  return visits;
}

void _emit(Map<String, Object?> record) =>
    debugPrintSynchronously(jsonEncode(record));

void main() {
  for (final pairs in [5003, 15003]) {
    test(
      'стоимость смешанных порций и редкого архива при ${pairs * 2} назначениях',
      () => _measure(pairs),
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

Future<void> _measure(int pairs) async {
  final directory = await Directory.systemTemp.createTemp('doable_navigation_');
  final file = File('${directory.path}/navigation.sqlite');
  final trace = _Trace();
  late sqlite.Database raw;
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        file,
        setup: (connection) => raw = connection,
      ),
      trace,
    ),
  );
  try {
    await database.open();
    seedLargeTaggedEntitiesFixture(raw, recipientPairs: pairs);
    final graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    );
    final tagId = switch (TagId.decode(tagFixtureId(9000))) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректная фикстура'),
    };
    int scalar(String sql) => raw.select(sql).single.values.single as int;
    expect(scalar('SELECT COUNT(*) FROM intentions'), pairs + 1);
    expect(scalar('SELECT COUNT(*) FROM long_term_relations'), pairs);
    expect(scalar('SELECT COUNT(*) FROM tag_assignments'), pairs * 4);
    _emit({
      'kind': 'tagged_entities_fixture',
      'recipientPairs': pairs,
      'intentions': pairs + 1,
      'relations': pairs,
      'selectedTagAssignments': pairs * 2,
      'unrelatedTagAssignments': pairs * 2,
      'sqliteBytes': scalar('PRAGMA page_count') * scalar('PRAGMA page_size'),
      'dbFileBytes': file.lengthSync(),
      'journalMode': raw.select('PRAGMA journal_mode').single.values.single,
      'sqliteVersion': raw
          .select('SELECT sqlite_version()')
          .single
          .values
          .single,
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'buildMode': const bool.fromEnvironment('dart.vm.product')
          ? 'release'
          : const bool.fromEnvironment('dart.vm.profile')
          ? 'profile'
          : 'debug',
      'sampleRepetitions': 5,
    });
    Future<_Page> read(
      TaggedEntitiesScope scope,
      int size,
      TaggedEntitiesCursor? cursor,
    ) async {
      trace.clear();
      final timer = Stopwatch()..start();
      final result = await graph.getTaggedEntitiesPage(
        TaggedEntitiesQuery(
          tagId: tagId,
          scope: scope,
          pageSize: size,
          cursor: cursor,
        ),
      );
      timer.stop();
      expect(result, isA<TaggedEntitiesPageSuccess>());
      final page = (result as TaggedEntitiesPageSuccess).value;
      final selects = List<_Select>.of(trace.selects);
      expect(selects, hasLength(cursor == null ? 4 : 3));
      expect(selects[0].sql, contains('FROM pragma_data_version'));
      expect(selects[0].rows, 1);
      expect(selects[1].sql, contains('FROM tags WHERE id = ?'));
      expect(selects[1].rows, 1);
      if (cursor == null) {
        expect(selects[2].sql, contains('SELECT 1 FROM tag_assignments a'));
        expect(selects[2].rows, 0);
      }
      for (final select in selects) {
        final sql = select.sql.toUpperCase();
        expect(sql, isNot(contains('OFFSET')));
        expect(sql, isNot(contains('COUNT(')));
        expect(sql, isNot(contains('SELECT *')));
        expect(sql, isNot(contains('DAILY_CHOICES')));
        expect(sql, isNot(contains('DAILY_CHOICE_PATH_STEPS')));
      }
      final main = selects.last;
      expect(main.sql, contains('ORDER BY a.creation_sequence ASC LIMIT ?'));
      expect(main.arguments.last, size + 1);
      expect(main.rows, lessThanOrEqualTo(size + 1));
      expect(main.rows, page.items.length + (page.nextCursor == null ? 0 : 1));
      expect(page.items.length, lessThanOrEqualTo(size));
      expect(page.tag.id, tagId);
      expect(page.scope, scope);
      return _Page(page, timer.elapsedMicroseconds, selects);
    }

    for (final scope in TaggedEntitiesScope.values) {
      for (final size in [1, 50, 100]) {
        await _traverse(raw, pairs, scope, size, read);
      }
    }
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}

String _identity(TaggedEntity entity) => switch (entity) {
  TaggedIntention(:final id) => 'intention:${id.toCanonicalString()}',
  TaggedLongTermRelation(:final id) => 'relation:${id.toCanonicalString()}',
};

Future<void> _traverse(
  sqlite.Database raw,
  int pairs,
  TaggedEntitiesScope scope,
  int size,
  Future<_Page> Function(TaggedEntitiesScope, int, TaggedEntitiesCursor?) read,
) async {
  final expected = <(String, int)>[
    for (var index = 0; index < pairs; index++) ...[
      if ((index % 40 == 0) == (scope == TaggedEntitiesScope.archived))
        ('intention:${tagFixtureId(100000 + index)}', index * 2),
      if ((index % 20 == 0) == (scope == TaggedEntitiesScope.archived))
        ('relation:${tagFixtureId(200000 + index)}', index * 2 + 1),
    ],
  ];
  final pageCount = (expected.length / size).ceil();
  final samples = <String, (TaggedEntitiesCursor?, _Page, int)>{};
  final ids = <String>[];
  TaggedEntitiesCursor? cursor;
  var boundaryOrdinal = -1;
  var pages = 0;
  var queries = 0;
  var materializedRows = 0;
  var pageMicroseconds = 0;
  var mainMicroseconds = 0;
  var mainVisits = 0;
  var referenceRuns = 0;
  var referenceVisits = 0;
  var referenceMicroseconds = 0;
  do {
    final queryCursor = cursor;
    final page = await read(scope, size, queryCursor);
    final end = ids.length + page.value.items.length;
    final lastVisitedOrdinal = end < expected.length
        ? expected[end].$2
        : pairs * 2 - 1;
    final sampled =
        pages == 0 ||
        pages + 1 == (pageCount / 2).ceil() ||
        page.value.nextCursor == null;
    final visits = _assignmentVisits(raw, page.main, checkPlan: sampled);
    expect(visits, lastVisitedOrdinal - boundaryOrdinal);
    pages++;
    queries += page.selects.length;
    materializedRows += page.selects.fold<int>(
      0,
      (sum, select) => sum + select.rows,
    );
    pageMicroseconds += page.microseconds;
    mainMicroseconds += page.main.microseconds;
    mainVisits += visits;
    if (page.referenceCheck case final check?) {
      referenceRuns++;
      referenceVisits += _assignmentVisits(raw, check);
      referenceMicroseconds += check.microseconds;
    }
    ids.addAll(page.value.items.map(_identity));
    if (pages == 1) samples['first'] = (queryCursor, page, visits);
    if (pages == (pageCount / 2).ceil()) {
      samples['middle'] = (queryCursor, page, visits);
    }
    cursor = page.value.nextCursor;
    if (cursor == null) samples['last'] = (queryCursor, page, visits);
    boundaryOrdinal = expected[end - 1].$2;
  } while (cursor != null);
  expect(pages, pageCount);
  expect(ids, expected.map((entry) => entry.$1));
  expect(ids.toSet(), hasLength(expected.length));
  expect(queries, pages * 3 + 1);
  expect(materializedRows, expected.length + pages - 1 + pages * 2);
  expect(referenceRuns, 1);
  expect(referenceVisits, pairs * 2);
  // Повторный просмотр дополнительной строки и промежутка до неё
  // допустим; повтор полного отбора на каждой порции — нет.
  expect(mainVisits, inInclusiveRange(pairs * 2, pairs * 4));
  _emit({
    'kind': 'tagged_entities_traversal',
    'recipientPairs': pairs,
    'scope': scope.name,
    'pageSize': size,
    'pages': pages,
    'selectQueries': queries,
    'resultRows': ids.length,
    'materializedRows': materializedRows,
    'mainQueryAssignmentVisits': mainVisits,
    'referenceCheckRuns': referenceRuns,
    'referenceCheckAssignmentVisits': referenceVisits,
    'pageElapsedMicroseconds': pageMicroseconds,
    'mainQueryElapsedMicroseconds': mainMicroseconds,
    'referenceCheckElapsedMicroseconds': referenceMicroseconds,
  });
  for (final position in ['first', 'middle', 'last']) {
    final (sampleCursor, first, visits) = samples[position]!;
    final durations = <int>[first.microseconds];
    final queryDurations = <List<int>>[
      [for (final select in first.selects) select.microseconds],
    ];
    for (var repetition = 1; repetition < 5; repetition++) {
      final again = await read(scope, size, sampleCursor);
      expect(
        again.value.items.map(_identity),
        first.value.items.map(_identity),
      );
      expect(
        again.selects.map((select) => select.rows),
        first.selects.map((select) => select.rows),
      );
      durations.add(again.microseconds);
      queryDurations.add([
        for (final select in again.selects) select.microseconds,
      ]);
    }
    final plans = [
      for (final select in first.selects)
        _plan(raw, select.sql, select.arguments),
    ];
    for (final plan in [
      plans.last,
      if (first.referenceCheck != null) plans[2],
    ]) {
      expect(
        plan.first,
        contains('SEARCH a USING INDEX tag_assignments_tag_order'),
      );
      expect(plan.join(' '), isNot(contains('USE TEMP B-TREE')));
      expect(plan.join(' '), isNot(contains('SCAN a')));
    }
    _emit({
      'kind': 'tagged_entities_page',
      'recipientPairs': pairs,
      'scope': scope.name,
      'pageSize': size,
      'position': position,
      'selectQueriesPerPage': first.selects.length,
      'materializedRowsPerSelect': [
        for (final select in first.selects) select.rows,
      ],
      'mainQueryAssignmentVisits': visits,
      'referenceCheckAssignmentVisits': first.referenceCheck == null
          ? 0
          : pairs * 2,
      'pageElapsedMicroseconds': durations,
      'selectElapsedMicroseconds': queryDurations,
      'sql': [for (final select in first.selects) select.sql],
      'plans': plans,
    });
  }
}
