@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

const _fixtureSize = 50000;
const _pageSize = 100;
const _jointMatchCount = 235;
const _conditionCount = 1201;
const _smallConditionCount = 10;
const _extraTagCount = 137;
const _backgroundTagCount = 64;
const _backgroundTagOffsets = [0, 21, 42];
const _requiredTagBase = 100000;
const _excludedTagBase = 110000;
const _extraTagBase = 120000;
const _backgroundTagBase = 130000;

/// Число обязательных и исключённых условий запроса; условия берутся
/// первыми тегами соответствующего диапазона фикстуры.
typedef _Conditions = ({int required, int excluded});

const _allConditions = (required: _conditionCount, excluded: _conditionCount);

void main() {
  test(
    'сохраняет ограниченную стоимость каталога на большой file-backed fixture',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _SelectTrace();
      final database = await harness.openReadyDatabase(observer: trace);
      final PersonalGraphRepository repository = DriftPersonalGraphRepository(
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

  test(
    'материализует только порцию редких совместных совпадений и все её теги',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _SelectTrace();
      late sqlite.Database raw;
      final database = await harness.openReadyDatabase(
        observer: trace,
        setup: (connection) => raw = connection,
      );
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 3),
        InMemoryDiagnosticsSink(),
      );
      await _populateFixture(database);
      _populateJointTagFixture(raw);
      trace.clear();
      trace.parameterLimit = 400;

      // Без фильтра названия совпадение отсекают только теги среди
      // 25 000 готовых активных кандидатов; «Другое название» проходит.
      final tagOnlyMatchCount = _jointMatchCount + 1;
      for (final (pageSize, titleFilter, matchCount) in [
        (1, 'редкое %_', _jointMatchCount),
        (_pageSize, 'редкое %_', _jointMatchCount),
        (_pageSize, 'ре', _jointMatchCount),
        (_pageSize, null, tagOnlyMatchCount),
      ]) {
        trace.clear();
        final first = _page(
          await repository.getCatalogPage(
            _jointQuery(pageSize: pageSize, titleFilter: titleFilter),
          ),
        ) as IntentionCatalogFirstPage;
        expect(first.totalCount, matchCount);
        expect(first.items, hasLength(pageSize));
        _expectJointMaterialization(
          first,
          trace,
          isFirst: true,
          pageSize: pageSize,
        );
        _expectJointPlans(raw, trace, titleFilter: titleFilter);
      }

      for (final (titleFilter, matches) in [
        (
          'редкое %_',
          [
            for (var index = 0; index < _jointMatchCount; index++)
              _jointIntentionIndex(index),
          ],
        ),
        (
          null,
          [
            for (var index = 0; index < _jointMatchCount; index++)
              _jointIntentionIndex(index),
            _jointIntentionIndex(241),
          ],
        ),
      ]) {
        await _expectJointTraversal(
          repository,
          raw,
          trace,
          titleFilter: titleFilter,
          matches: matches,
        );
      }

      // Каждый из 25 000 активных кандидатов имеет несколько собственных
      // назначений. Отсечение кандидата не должно перебирать набор условий:
      // оба набора читаются из параметра один раз на запрос, поэтому малое и
      // большое число условий дают одинаковую форму плана. Без фильтра
      // названия из 24 997 готовых активных кандидатов, кроме исключённого
      // намерения, первые десять исключённых тегов отсекают двух кандидатов,
      // а все 1201 — трёх. Первые десять обязательных тегов есть у 242
      // совместных кандидатов, все 1201 — у 239.
      for (final (label, conditions, matchCount) in [
        (
          'только исключённые',
          (required: 0, excluded: _smallConditionCount),
          24995,
        ),
        ('только исключённые', (required: 0, excluded: _conditionCount), 24994),
        (
          'только обязательные',
          (required: _smallConditionCount, excluded: 0),
          242,
        ),
        ('только обязательные', (required: _conditionCount, excluded: 0), 239),
        (
          'совместные',
          (required: _smallConditionCount, excluded: _smallConditionCount),
          tagOnlyMatchCount + 4,
        ),
        ('совместные', _allConditions, tagOnlyMatchCount),
      ]) {
        trace.clear();
        final first = _page(
          await repository.getCatalogPage(
            _jointQuery(titleFilter: null, conditions: conditions),
          ),
        ) as IntentionCatalogFirstPage;
        expect(first.totalCount, matchCount);
        expect(first.items, hasLength(_pageSize));
        _expectJointPlans(
          raw,
          trace,
          titleFilter: null,
          conditions: conditions,
        );
        _expectJointMaterialization(
          first,
          trace,
          isFirst: true,
          conditions: conditions,
        );
        _printJointCost(
          raw,
          trace,
          titleFilter: null,
          page: 0,
          label: label,
          conditions: conditions,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Полный обход совместного поиска: каждая порция, включая продолжения,
/// материализует только себя и сохраняет адресные планы проверок тегов.
Future<void> _expectJointTraversal(
  DriftPersonalGraphRepository repository,
  sqlite.Database raw,
  _SelectTrace trace, {
  required String? titleFilter,
  required List<int> matches,
}) async {
  final expected = [...matches]
    ..sort((left, right) {
      final timestampOrder = (right % 7).compareTo(left % 7);
      return timestampOrder == 0 ? left.compareTo(right) : timestampOrder;
    });
  final actual = <String>[];
  IntentionCatalogCursor? cursor;
  var pageNumber = 0;
  do {
    trace.clear();
    final page = _page(
      await repository.getCatalogPage(
        _jointQuery(titleFilter: titleFilter, cursor: cursor),
      ),
    );
    _expectJointMaterialization(page, trace, isFirst: pageNumber == 0);
    _expectJointPlans(raw, trace, titleFilter: titleFilter);
    if (pageNumber == 0) {
      expect((page as IntentionCatalogFirstPage).totalCount, matches.length);
    }
    _printJointCost(raw, trace, titleFilter: titleFilter, page: pageNumber);
    actual.addAll(page.items.map((item) => item.id.toCanonicalString()));
    cursor = page.nextCursor;
    pageNumber++;
  } while (cursor != null);

  expect(pageNumber, 3);
  expect(actual, expected.map(_fixtureId));
  expect(actual.toSet(), hasLength(matches.length));
}

/// Среди 50 000 намерений 245 кандидатов далеко за первой обычной порцией.
/// Десять отсекаются разными частями запроса; остальные имеют все 1201 тега.
/// Каждое намерение дополнительно имеет три фоновых тега вне условий.
void _populateJointTagFixture(sqlite.Database database) {
  final insertTag = database.prepare(
    'INSERT INTO tags (id, name) VALUES (?, ?)',
  );
  final insertAssignment = database.prepare(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
  );
  database.execute('BEGIN');
  try {
    // Все намерения готовы: редкость совпадений задают теги, а не готовность.
    database.execute('UPDATE intentions SET is_action_ready = 1');
    for (final (base, count) in [
      (_requiredTagBase, _conditionCount),
      (_excludedTagBase, _conditionCount),
      (_extraTagBase, _extraTagCount),
      (_backgroundTagBase, _backgroundTagCount),
    ]) {
      for (var index = 0; index < count; index++) {
        insertTag.execute([_fixtureId(base + index), 'Тег ${base + index}']);
      }
    }
    for (var index = 0; index < _jointCandidateCount; index++) {
      final id = _fixtureId(_jointIntentionIndex(index));
      database.execute(
        'UPDATE intentions SET title = ?, is_action_ready = ?, '
        'is_archived = ? WHERE id = ?',
        [
          index == 241 ? 'Другое название' : 'Редкое %_ совпадение',
          index == 243 ? 0 : 1,
          index == 242 ? 1 : 0,
          id,
        ],
      );
      for (var tag = 0; tag < _jointRequiredTagCount(index); tag++) {
        insertAssignment.execute([_fixtureId(_requiredTagBase + tag), id]);
      }
      if (_jointExcludedTag(index) case final tag?) {
        insertAssignment.execute([_fixtureId(_excludedTagBase + tag), id]);
      }
    }
    // Дополнительные собственные теги не входят в условия. Плотная строка
    // вне результата проверяет, что чтение назначений не захватывает соседей.
    for (final id in [_fixtureId(_jointIntentionIndex(0)), _fixtureId(0)]) {
      for (var tag = 0; tag < _extraTagCount; tag++) {
        insertAssignment.execute([_fixtureId(_extraTagBase + tag), id]);
      }
    }
    // У каждого намерения несколько собственных тегов вне условий: проверка
    // кандидата не может отсечь его по одному отсутствию назначений.
    for (var index = 0; index < _fixtureSize; index++) {
      for (final tag in _backgroundTags(index)) {
        insertAssignment.execute([
          _fixtureId(_backgroundTagBase + tag),
          _fixtureId(index),
        ]);
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  } finally {
    insertTag.close();
    insertAssignment.close();
  }
}

const _jointCandidateCount = _jointMatchCount + 10;

int _jointIntentionIndex(int index) => 1000 + index * 200;

/// Трём совместным кандидатам не хватает последнего обязательного тега.
int _jointRequiredTagCount(int index) =>
    index >= 235 && index <= 237 ? _conditionCount - 1 : _conditionCount;

/// Номер исключённого тега совместного кандидата, если он назначен.
int? _jointExcludedTag(int index) => switch (index) {
  238 || 239 => 0,
  240 => _conditionCount - 1,
  _ => null,
};

/// Фоновые теги намерения фикстуры в порядке их создания.
List<int> _backgroundTags(int fixtureIndex) => [
  for (final offset in _backgroundTagOffsets)
    (fixtureIndex + offset) % _backgroundTagCount,
]..sort();

/// Полный состав собственных тегов намерения фикстуры в порядке создания
/// тегов: обязательные, исключённый, дополнительные, фоновые.
List<TagId> _fixtureTagIds(int fixtureIndex) {
  final offset = fixtureIndex - _jointIntentionIndex(0);
  final joint = offset >= 0 && offset % 200 == 0 ? offset ~/ 200 : null;
  final jointIndex = joint != null && joint < _jointCandidateCount
      ? joint
      : null;
  return [
    if (jointIndex != null) ...[
      for (var tag = 0; tag < _jointRequiredTagCount(jointIndex); tag++)
        _tagId(_requiredTagBase + tag),
      if (_jointExcludedTag(jointIndex) case final tag?)
        _tagId(_excludedTagBase + tag),
    ],
    if (fixtureIndex == 0 || jointIndex == 0)
      for (var tag = 0; tag < _extraTagCount; tag++)
        _tagId(_extraTagBase + tag),
    for (final tag in _backgroundTags(fixtureIndex))
      _tagId(_backgroundTagBase + tag),
  ];
}

int _fixtureIndexOf(IntentionId id) =>
    int.parse(id.toCanonicalString().substring(24), radix: 16);

TagId _tagId(int number) => switch (TagId.decode(_fixtureId(number))) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw ArgumentError.value(number),
};

IntentionCatalogQuery _jointQuery({
  int pageSize = _pageSize,
  String? titleFilter = 'редкое %_',
  _Conditions conditions = _allConditions,
  IntentionCatalogCursor? cursor,
}) => IntentionCatalogQuery(
  scope: IntentionScope.active,
  readinessFilter: IntentionReadinessFilter.readyOnly,
  titleFilter: titleFilter,
  tagFilter: IntentionTagFilter(
    requiredTagIds: [
      for (var index = 0; index < conditions.required; index++)
        _tagId(_requiredTagBase + index),
    ],
    excludedTagIds: [
      for (var index = 0; index < conditions.excluded; index++)
        _tagId(_excludedTagBase + index),
    ],
  ),
  excludedIntentionId: switch (IntentionId.decode(
    _fixtureId(_jointIntentionIndex(244)),
  )) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError('Неверный UUID фикстуры.'),
  },
  order: IntentionCatalogOrder.createdAtDescending,
  pageSize: pageSize,
  cursor: cursor,
);

void _expectJointMaterialization(
  IntentionCatalogPage page,
  _SelectTrace trace, {
  required bool isFirst,
  int pageSize = _pageSize,
  _Conditions conditions = _allConditions,
}) {
  final counts = trace.selects.where(
    (select) => _isCatalogCountStatement(select.statement),
  );
  expect(counts, hasLength(isFirst ? 1 : 0));
  if (isFirst) expect(counts.single.rowCount, 1);
  final read = trace.selects
      .where((select) => select.statement.contains('LIMIT'))
      .single;
  expect(read.rowCount, page.items.length + (page.nextCursor == null ? 0 : 1));
  expect(read.statement, contains('LIMIT ${pageSize + 1}'));
  final tags = trace.selects
      .where((select) => select.statement.contains('FROM tag_assignments a'))
      .single;
  final aggregates = trace.selects
      .where(
        (select) =>
            select.statement.contains('doable_relation_count_aggregates'),
      )
      .single;
  final ids = page.items.map((item) => item.id.toCanonicalString()).toSet();
  expect(tags.arguments, unorderedEquals(ids));
  expect(tags.intentionIds, ids);
  expect(aggregates.arguments, unorderedEquals(ids));
  expect(aggregates.rowCount, page.items.length);
  var tagCount = 0;
  for (final item in page.items) {
    final expectedTags = _fixtureTagIds(_fixtureIndexOf(item.id));
    expect(item.tags.map((tag) => tag.id), expectedTags);
    tagCount += expectedTags.length;
  }
  expect(tags.rowCount, tagCount);
  // Объём назначений может превышать размер порции. Число чтений не растёт
  // с числом намерений: количество, порция, агрегаты и назначения пакетны.
  // Наборы условий передаются параметрами, служебных записей и чтений нет.
  expect(
    trace.selects.where(
      (select) => select.statement.contains('total_changes()'),
    ),
    isEmpty,
  );
  expect(trace.writes, isEmpty);
  expect(trace.selects, hasLength(isFirst ? 4 : 3));
  for (final select in [...counts, read]) {
    final conditionSets = select.arguments
        .whereType<String>()
        .where((argument) => argument.startsWith('['))
        .map((argument) => (jsonDecode(argument) as List).toSet())
        .toList();
    expect(conditionSets, [
      if (conditions.required > 0)
        {
          for (var index = 0; index < conditions.required; index++)
            _fixtureId(_requiredTagBase + index),
        },
      if (conditions.excluded > 0)
        {
          for (var index = 0; index < conditions.excluded; index++)
            _fixtureId(_excludedTagBase + index),
        },
    ]);
  }
  _expectNoOffset(trace);
}

/// Строка `EXPLAIN QUERY PLAN`: подзапросы вложены через `parent`.
typedef _PlanNode = ({int id, int parent, String detail});

List<_PlanNode> _observedPlanTree(
  sqlite.Database database,
  _TracedSelect select,
) => [
  for (final row in database.select(
    'EXPLAIN QUERY PLAN ${select.statement}',
    select.arguments,
  ))
    (
      id: row['id'] as int,
      parent: row['parent'] as int,
      detail: row['detail'] as String,
    ),
];

List<String> _observedPlan(sqlite.Database database, _TracedSelect select) => [
  for (final node in _observedPlanTree(database, select)) node.detail,
];

/// Утверждения описывают свойство плана, а не порядок обхода: каждый набор
/// условий из json_each(?) читается подзапросом, не коррелированным с
/// текущим намерением, то есть один раз на выполнение запроса. Назначения
/// выбранных тегов отбираются по индексу `(tag_id, intention_id)`, а
/// кандидат проверяется поиском по ключу в отобранном множестве
/// (`LIST SUBQUERY` оператора `IN`). Поэтому стоимость отсечения кандидата
/// не растёт с числом условий.
void _expectConditionSetsReadOnce(
  List<_PlanNode> plan,
  _Conditions conditions,
) {
  final nodes = {for (final node in plan) node.id: node};
  List<String> ancestors(_PlanNode node) => [
    for (
      var parent = nodes[node.parent];
      parent != null;
      parent = nodes[parent.parent]
    )
      parent.detail,
  ];
  final correlated = startsWith('CORRELATED');
  final details = plan.map((node) => node.detail).join('\n');
  for (final alias in [
    if (conditions.required > 0) 'required_tag',
    if (conditions.excluded > 0) 'excluded_tag',
  ]) {
    final setReads = plan
        .where((node) => node.detail.startsWith('SCAN $alias VIRTUAL TABLE'))
        .toList();
    expect(setReads, hasLength(1), reason: 'Набор $alias в плане:\n$details');
    final chain = ancestors(setReads.single);
    expect(
      chain,
      everyElement(isNot(correlated)),
      reason:
          'Набор $alias читается коррелированным подзапросом, то есть '
          'заново для каждого кандидата:\n$details',
    );
    expect(
      chain.last,
      matches(RegExp(r'^LIST SUBQUERY \d+$')),
      reason: 'Кандидат проверяется поиском в множестве:\n$details',
    );
  }
  final assignmentReads = plan
      .where(
        (node) => RegExp(r'^(SCAN|SEARCH) assignment\b').hasMatch(node.detail),
      )
      .toList();
  expect(
    assignmentReads,
    hasLength(
      (conditions.required > 0 ? 1 : 0) + (conditions.excluded > 0 ? 1 : 0),
    ),
    reason: details,
  );
  for (final read in assignmentReads) {
    expect(read.detail, startsWith('SEARCH assignment'), reason: details);
    expect(read.detail, contains('(tag_id=?'), reason: details);
    expect(ancestors(read), everyElement(isNot(correlated)), reason: details);
  }
}

void _expectJointPlans(
  sqlite.Database database,
  _SelectTrace trace, {
  required String? titleFilter,
  _Conditions conditions = _allConditions,
}) {
  final usesFts = titleFilter != null && titleFilter.length >= 3;
  for (final select in trace.selects.where(
    (select) =>
        _isCatalogCountStatement(select.statement) ||
        select.statement.contains('LIMIT'),
  )) {
    final plan = _observedPlanTree(database, select);
    _expectConditionSetsReadOnce(plan, conditions);
    expect(
      plan.any((node) => node.detail.contains('intention_titles_fts')),
      usesFts,
    );
  }
  final tagPlan = _observedPlan(
    database,
    trace.selects.singleWhere(
      (select) => select.statement.contains('FROM tag_assignments a'),
    ),
  ).join('\n');
  expect(tagPlan, contains('tag_assignments_intention_order'));
  expect(tagPlan, isNot(contains('SCAN a')));
}

void _printJointCost(
  sqlite.Database database,
  _SelectTrace trace, {
  required String? titleFilter,
  required int page,
  String label = 'совместные',
  _Conditions conditions = _allConditions,
}) {
  final count = trace.selects
      .where((select) => _isCatalogCountStatement(select.statement))
      .singleOrNull;
  final read = trace.selects.singleWhere(
    (select) => select.statement.contains('LIMIT'),
  );
  final tags = trace.selects.singleWhere(
    (select) => select.statement.contains('FROM tag_assignments a'),
  );
  String cost(String label, _TracedSelect select) =>
      '$label=${select.elapsed.inMicroseconds} мкс/${select.rowCount} строк, '
      'план: ${_observedPlan(database, select).join(' | ')}';
  // Измерения характеризуют эту фикстуру и материализацию, а не постоянное
  // время поиска: COUNT и поиск редких совпадений зависят от объёма данных
  // и числа назначений выбранных тегов. Утверждения на них не опираются.
  // ignore: avoid_print
  print(
    'Поиск по тегам ($label), название ${titleFilter ?? 'без фильтра'}, '
    'порция $page: $_fixtureSize намерений, '
    '${conditions.required} обязательных и '
    '${conditions.excluded} исключённых условий; '
    '${trace.selects.length} чтения; '
    '${[if (count != null) cost('COUNT', count), cost('порция', read), cost('назначения', tags)].join('; ')}',
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
          WHERE title_search_key MATCH '"ааа"'
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
          AND instr(title_search_key, '$filter') > 0
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

Future<void> _expectBoundedPages(PersonalGraphRepository repository) async {
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
  PersonalGraphRepository repository,
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
  PersonalGraphRepository repository,
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
  PersonalGraphRepository repository,
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
    trace.selects.where((select) => _isCatalogCountStatement(select.statement)),
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
      if (_isCatalogCountStatement(select.statement)) select,
  ];
  final reads = [
    for (final select in trace.selects)
      if (select.statement.contains('LIMIT')) select,
  ];

  expect(counts, hasLength(1));
  expect(reads, hasLength(1));
  expect(counts.single.statement, isNot(contains('"description"')));
  expect(reads.single.statement, contains('LIMIT ${_pageSize + 1}'));
  expect(reads.single.statement, contains('"description"'));
  expect(reads.single.statement, isNot(contains('IS NOT NULL')));
}

void _expectNoOffset(_SelectTrace trace) => expect(
  trace.selects,
  isNot(anyElement((select) => select.statement.contains('OFFSET'))),
);

bool _isCatalogCountStatement(String statement) =>
    statement.startsWith('SELECT COUNT(') &&
    !statement.contains('doable_relation_count_aggregates');

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
  final writes = <String>[];
  final _started = <LocalDatabaseSqlStatement, Stopwatch>{};
  int? parameterLimit;
  var isRecording = true;

  void clear() {
    selects.clear();
    writes.clear();
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final limit = parameterLimit;
    if (limit != null && statement.arguments.length > limit) {
      throw StateError('Превышено число параметров SQL-выражения.');
    }
    if (isRecording &&
        statement.operation != LocalDatabaseSqlOperation.select) {
      writes.addAll(statement.statements);
    }
    if (isRecording &&
        statement.operation == LocalDatabaseSqlOperation.select) {
      _started[statement] = Stopwatch()..start();
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final stopwatch = _started.remove(statement);
    if (stopwatch != null) {
      stopwatch.stop();
      selects.add(
        _TracedSelect(
          statement.statements.single,
          statement.arguments,
          rows.length,
          stopwatch.elapsed,
          {
            for (final row in rows)
              if (row['intention_id'] case final String id) id,
          },
        ),
      );
    }
    return rows;
  }
}

final class _TracedSelect {
  const _TracedSelect(
    this.statement,
    this.arguments,
    this.rowCount,
    this.elapsed,
    this.intentionIds,
  );

  final String statement;
  final List<Object?> arguments;
  final int rowCount;
  final Duration elapsed;
  final Set<String> intentionIds;
}
