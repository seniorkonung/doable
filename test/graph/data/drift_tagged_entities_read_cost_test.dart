@Tags(['slow'])
library;

import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

final class _Select {
  const _Select(this.sql, this.arguments, this.rows);

  final String sql;
  final List<Object?> arguments;
  final int rows;
}

final class _Trace extends LocalDatabaseConnectionObserver {
  final selects = <_Select>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selects.add(
      _Select(statement.statements.single, statement.arguments, rows.length),
    );
    return rows;
  }

  void clear() {
    selects.clear();
  }
}

final class _Page {
  const _Page(this.value, this.selects);

  final TaggedIntentionsPage value;
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
  // проверкой ссылок.
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

void main() {
  const pairs = 5003;
  test(
    'стоимость порций намерений и редкого архива среди назначений противоположного охвата и другого тега при ${pairs * 2} назначениях',
    () => _measure(pairs),
    timeout: const Timeout(Duration(minutes: 5)),
  );
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
    expect(scalar('SELECT COUNT(*) FROM intentions'), pairs * 2 + 1);
    expect(scalar('SELECT COUNT(*) FROM long_term_relations'), pairs);
    expect(scalar('SELECT COUNT(*) FROM tag_assignments'), pairs * 4);
    Future<_Page> read(
      TaggedIntentionsScope scope,
      int size,
      TaggedIntentionsCursor? cursor,
    ) async {
      trace.clear();
      final result = await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: tagId,
          scope: scope,
          pageSize: size,
          cursor: cursor,
        ),
      );
      expect(result, isA<TaggedIntentionsPageSuccess>());
      final page = (result as TaggedIntentionsPageSuccess).value;
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
        expect(sql, isNot(contains('LONG_TERM_RELATIONS')));
        expect(sql, isNot(contains('SOURCE_INTENTION_ID')));
        expect(sql, isNot(contains('RELATED_INTENTION_ID')));
        expect(sql, isNot(contains('DESCRIPTION')));
        expect(sql, isNot(contains('PRIORITY')));
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
      return _Page(page, selects);
    }

    for (final scope in TaggedIntentionsScope.values) {
      for (final size in [1, 50]) {
        await _traverse(raw, pairs, scope, size, read);
      }
    }
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}

String _identity(TaggedIntention intention) => intention.id.toCanonicalString();

Future<void> _traverse(
  sqlite.Database raw,
  int pairs,
  TaggedIntentionsScope scope,
  int size,
  Future<_Page> Function(TaggedIntentionsScope, int, TaggedIntentionsCursor?)
  read,
) async {
  final expected = largeTaggedIntentions(
    pairs,
    archived: scope == TaggedIntentionsScope.archived,
  );
  final pageCount = (expected.length / size).ceil();
  final samples = <String, (TaggedIntentionsCursor?, _Page, int)>{};
  final ids = <String>[];
  TaggedIntentionsCursor? cursor;
  var boundaryOrdinal = -1;
  var pages = 0;
  var queries = 0;
  var materializedRows = 0;
  var mainVisits = 0;
  var referenceRuns = 0;
  var referenceVisits = 0;
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
    mainVisits += visits;
    if (page.referenceCheck case final check?) {
      referenceRuns++;
      referenceVisits += _assignmentVisits(raw, check);
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
  for (final position in ['first', 'middle', 'last']) {
    final (_, first, _) = samples[position]!;
    final plans = [
      for (final select in first.selects)
        _plan(raw, select.sql, select.arguments),
    ];
    expect(
      plans.last.first,
      contains('SEARCH a USING INDEX tag_assignments_tag_order'),
    );
    // Аудиту порядок не нужен: пара тега и намерения покрывает его поиск
    // по тегу так же, как индекс порядка.
    if (first.referenceCheck != null) {
      expect(
        plans[2].first,
        matches(
          RegExp(
            r'^SEARCH a USING (COVERING INDEX sqlite_autoindex_tag_assignments_1'
            r'|INDEX tag_assignments_tag_order) \(tag_id=\?\)$',
          ),
        ),
      );
    }
    for (final plan in [
      plans.last,
      if (first.referenceCheck != null) plans[2],
    ]) {
      expect(plan.join(' '), isNot(contains('USE TEMP B-TREE')));
      expect(plan.join(' '), isNot(contains('SCAN a')));
    }
  }
}
