@Tags(['slow'])
library;

import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

const _fixtureSize = 50000;
const _pageSize = 100;

void main() {
  test(
    'сохраняет ограниченную стоимость каталога на большой file-backed fixture',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _SelectTrace();
      final database = await harness.openReadyDatabase(observer: trace);
      final repository = DriftIntentionRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 3),
        InMemoryDiagnosticsSink(),
      );

      await _populateFixture(database);
      trace.clear();

      await _expectQueryPlans(database);
      trace.clear();

      await _expectBoundedPages(repository);
      await _expectFirstPageSql(repository, trace);
      await _expectWarmedShortFilterLatency(repository, trace);
      await _expectCompleteKeysetTraversal(repository, trace);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _populateFixture(AppDatabase database) => database.batch((batch) {
  final timestampBase = DateTime.utc(2026, 9, 1).microsecondsSinceEpoch;
  for (var index = 0; index < _fixtureSize; index++) {
    final timestamp =
        timestampBase + (index % 7) * Duration.microsecondsPerMinute;
    final title = 'ааа запись $index';
    batch.insert(
      database.intentions,
      IntentionsCompanion.insert(
        id: _fixtureId(index),
        title: title,
        titleSearchKey: title,
        isArchived: Value(index.isOdd),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }
});

Future<void> _expectQueryPlans(AppDatabase database) async {
  final ftsPlan = await _queryPlan(database, '''
      EXPLAIN QUERY PLAN
      SELECT id FROM intentions
      WHERE is_archived = 0
        AND rowid IN (
          SELECT rowid FROM intention_titles_fts
          WHERE intention_titles_fts MATCH '"ааа"'
        )
      ORDER BY created_at DESC, id ASC
      LIMIT ${_pageSize + 1}
    ''');
  expect(ftsPlan.join('\n'), contains('intention_titles_fts'));

  for (final filter in const ['а', 'я', 'аа', 'яя']) {
    final shortFilterPlan = await _queryPlan(database, '''
        EXPLAIN QUERY PLAN
        SELECT id FROM intentions
        WHERE is_archived = 0
          AND instr(title, '$filter') > 0
        ORDER BY created_at DESC, id ASC
        LIMIT ${_pageSize + 1}
      ''');
    final details = shortFilterPlan.join('\n');
    expect(details, contains('SCAN'));
    expect(details, isNot(contains('intention_titles_fts')));
  }

  for (final scope in _IndexScope.values) {
    for (final timestamp in _IndexTimestamp.values) {
      for (final direction in _IndexDirection.values) {
        final indexName =
            'intentions_${scope.name}_${timestamp.column}_${direction.name}_id_asc';
        final column = timestamp.column;
        final comparison = switch (direction) {
          _IndexDirection.asc => '>',
          _IndexDirection.desc => '<',
        };
        final order = direction.sql;

        final firstPagePlan = await _queryPlan(database, '''
            EXPLAIN QUERY PLAN
            SELECT id FROM intentions
            WHERE ${scope.predicate}
            ORDER BY $column $order, id ASC
            LIMIT ${_pageSize + 1}
          ''');
        expect(firstPagePlan.join('\n'), contains(indexName));

        final continuationPlan = await _queryPlan(database, '''
            EXPLAIN QUERY PLAN
            SELECT id FROM intentions
            WHERE ${scope.predicate}
              AND ($column $comparison 0 OR ($column = 0 AND id > ''))
            ORDER BY $column $order, id ASC
            LIMIT ${_pageSize + 1}
          ''');
        expect(continuationPlan.join('\n'), contains(indexName));
      }
    }
  }
}

Future<List<String>> _queryPlan(AppDatabase database, String statement) async {
  final rows = await database.customSelect(statement).get();
  return [for (final row in rows) row.read<String>('detail')];
}

Future<void> _expectBoundedPages(DriftIntentionRepository repository) async {
  for (final scope in IntentionScope.values) {
    for (final order in _catalogOrders) {
      for (final filter in _allFilters) {
        final page = _page(
          await repository.getCatalogPage(
            _query(scope: scope, order: order, titleFilter: filter),
          ),
        );
        expect(page.items.length, lessThanOrEqualTo(_pageSize));
      }
    }
  }
}

Future<void> _expectFirstPageSql(
  DriftIntentionRepository repository,
  _SelectTrace trace,
) async {
  for (final filter in _allFilters) {
    trace.clear();
    final page = _page(
      await repository.getCatalogPage(
        _query(
          scope: IntentionScope.active,
          order: IntentionCatalogOrder.createdAtDescending,
          titleFilter: filter,
        ),
      ),
    );
    final expectedCount = switch (filter) {
      'я' || 'яя' => 0,
      _ => _fixtureSize ~/ 2,
    };
    expect(page, isA<IntentionCatalogFirstPage>());
    expect((page as IntentionCatalogFirstPage).totalCount, expectedCount);
    _expectSingleCountAndBoundedRead(trace);
  }
}

Future<void> _expectWarmedShortFilterLatency(
  DriftIntentionRepository repository,
  _SelectTrace trace,
) async {
  for (final filter in _shortFilters) {
    final query = _query(
      scope: IntentionScope.active,
      order: IntentionCatalogOrder.createdAtDescending,
      titleFilter: filter,
    );
    trace.isRecording = false;
    trace.clear();
    final samples = <Duration>[];
    try {
      for (var index = 0; index < 5; index++) {
        _page(await repository.getCatalogPage(query));
      }

      for (var index = 0; index < 30; index++) {
        final stopwatch = Stopwatch()..start();
        final page = _page(await repository.getCatalogPage(query));
        samples.add(stopwatch.elapsed);
        expect(page.items.length, lessThanOrEqualTo(_pageSize));
      }
    } finally {
      trace.isRecording = true;
    }
    expect(trace.selects, isEmpty);

    if (Platform.isLinux) {
      expect(
        _percentile95(samples),
        lessThanOrEqualTo(const Duration(milliseconds: 100)),
        reason: 'p95 полного repository path для фильтра «$filter»',
      );
    }
  }
}

Future<void> _expectCompleteKeysetTraversal(
  DriftIntentionRepository repository,
  _SelectTrace trace,
) async {
  trace.clear();
  var query = _query(
    scope: IntentionScope.all,
    order: IntentionCatalogOrder.createdAtDescending,
    titleFilter: null,
  );
  final ids = <String>{};
  IntentionCatalogFirstPage? firstPage;

  while (true) {
    final page = _page(await repository.getCatalogPage(query));
    expect(page.items.length, lessThanOrEqualTo(_pageSize));
    final pageIds = page.items
        .map((summary) => summary.id.toCanonicalString())
        .toSet();
    expect(pageIds, hasLength(page.items.length));
    expect(ids.intersection(pageIds), isEmpty);
    ids.addAll(pageIds);
    final cursor = page.nextCursor;
    if (firstPage == null) {
      expect(page, isA<IntentionCatalogFirstPage>());
      firstPage = page as IntentionCatalogFirstPage;
    }
    if (cursor == null) break;
    query = _query(
      scope: query.scope,
      order: query.order,
      titleFilter: null,
      cursor: cursor,
    );
  }

  expect(firstPage.totalCount, _fixtureSize);
  expect(ids, hasLength(_fixtureSize));
  _expectNoOffset(trace);
  expect(
    trace.selects.where((select) => select.statement.contains('COUNT(')),
    hasLength(1),
  );
  expect(
    trace.selects.where((select) => select.statement.contains('LIMIT')),
    hasLength(_fixtureSize ~/ _pageSize),
  );
}

void _expectSingleCountAndBoundedRead(_SelectTrace trace) {
  _expectNoOffset(trace);
  final counts = [
    for (final select in trace.selects)
      if (select.statement.contains('COUNT(')) select,
  ];
  final reads = [
    for (final select in trace.selects)
      if (select.statement.contains('LIMIT')) select,
  ];

  expect(counts, hasLength(1));
  expect(reads, hasLength(1));
  expect(reads.single.statement, contains('LIMIT ${_pageSize + 1}'));
  expect(reads.single.statement, contains('"description" IS NOT NULL'));
  expect(reads.single.statement, isNot(contains('"description" AS')));
}

void _expectNoOffset(_SelectTrace trace) => expect(
  trace.selects,
  isNot(anyElement((select) => select.statement.contains('OFFSET'))),
);

Duration _percentile95(List<Duration> samples) {
  final sorted = [...samples]..sort();
  final index = ((sorted.length * 95 + 99) ~/ 100) - 1;
  return sorted[index];
}

IntentionCatalogPage _page(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value;
}

IntentionCatalogQuery _query({
  required IntentionScope scope,
  required IntentionCatalogOrder order,
  required String? titleFilter,
  IntentionCatalogCursor? cursor,
}) => IntentionCatalogQuery(
  scope: scope,
  titleFilter: titleFilter,
  order: order,
  pageSize: _pageSize,
  cursor: cursor,
);

String _fixtureId(int index) =>
    '018f0b5d-6b2e-7c80-8000-${index.toRadixString(16).padLeft(12, '0')}';

const _allFilters = <String?>[null, 'а', 'я', 'аа', 'яя', 'ааа'];
const _shortFilters = <String>['а', 'я', 'аа', 'яя'];
const _catalogOrders = <IntentionCatalogOrder>[
  IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.ascending,
  ),
  IntentionCatalogOrder.createdAtDescending,
  IntentionCatalogOrder(
    field: IntentionCatalogSortField.updatedAt,
    direction: IntentionCatalogSortDirection.ascending,
  ),
  IntentionCatalogOrder(
    field: IntentionCatalogSortField.updatedAt,
    direction: IntentionCatalogSortDirection.descending,
  ),
];

enum _IndexScope {
  active('is_archived = 0'),
  archived('is_archived = 1'),
  all('1');

  const _IndexScope(this.predicate);

  final String predicate;
}

enum _IndexTimestamp {
  createdAt('created_at'),
  updatedAt('updated_at');

  const _IndexTimestamp(this.column);

  final String column;
}

enum _IndexDirection {
  asc('ASC'),
  desc('DESC');

  const _IndexDirection(this.sql);

  final String sql;
}

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  final selects = <_TracedSelect>[];
  var isRecording = true;

  void clear() => selects.clear();

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (isRecording &&
        statement.operation == LocalDatabaseSqlOperation.select) {
      selects.add(
        _TracedSelect(statement.statements.single, statement.arguments),
      );
    }
  }
}

final class _TracedSelect {
  const _TracedSelect(this.statement, this.arguments);

  final String statement;
  final List<Object?> arguments;
}
