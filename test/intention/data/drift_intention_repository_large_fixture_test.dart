@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
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
const _popularTag = 140000;
const _massTag = 150000;

/// Условия запроса: популярный обязательный тег и число редких обязательных
/// и исключённых условий, которые берутся первыми тегами соответствующего
/// диапазона фикстуры.
typedef _Conditions = ({bool popular, int required, int excluded});

const _allConditions = (
  popular: false,
  required: _conditionCount,
  excluded: _conditionCount,
);

/// Число обязательных условий запроса вместе с популярным тегом.
int _requiredConditionCount(_Conditions conditions) =>
    conditions.required + (conditions.popular ? 1 : 0);

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
      final (:repository, :raw, :trace) = await _openJointFixture();

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
          (popular: false, required: 0, excluded: _smallConditionCount),
          24995,
        ),
        (
          'только исключённые',
          (popular: false, required: 0, excluded: _conditionCount),
          24994,
        ),
        (
          'только обязательные',
          (popular: false, required: _smallConditionCount, excluded: 0),
          242,
        ),
        (
          'только обязательные',
          (popular: false, required: _conditionCount, excluded: 0),
          239,
        ),
        (
          'совместные',
          (
            popular: false,
            required: _smallConditionCount,
            excluded: _smallConditionCount,
          ),
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

  test('ведёт порцию и продолжение по индексу порядка при популярном обязательном теге', () async {
    final (:repository, :raw, :trace) = await _openJointFixture();

    // Популярный тег назначен 19 999 из 24 999 активных намерений. Среди
    // них не готов кандидат 243 и исключён из выдачи кандидат 244, поэтому
    // один популярный тег оставляет 19 997 совпадений. Первые девять
    // исключённых тегов отсекают ещё двух кандидатов, все 1201 — трёх.
    // С редкими обязательными тегами совпадения сужаются до совместных
    // кандидатов, но популярный тег остаётся в наборе условий. Во всех
    // сценариях порция и продолжение идут по индексу порядка охвата.
    const popularBounds = [(6, 1728), (1756, 3478)];
    for (final (label, conditions, matchCount, bounds) in [
      (
        'только обязательные',
        (popular: true, required: 0, excluded: 0),
        19997,
        popularBounds,
      ),
      (
        'только обязательные',
        (popular: true, required: _smallConditionCount - 1, excluded: 0),
        242,
        null,
      ),
      (
        'только обязательные',
        (popular: true, required: _conditionCount, excluded: 0),
        239,
        null,
      ),
      (
        'совместные',
        (popular: true, required: 0, excluded: _smallConditionCount - 1),
        19995,
        popularBounds,
      ),
      (
        'совместные',
        (popular: true, required: 0, excluded: _conditionCount),
        19994,
        popularBounds,
      ),
      (
        'совместные',
        (popular: true, required: _conditionCount, excluded: _conditionCount),
        236,
        null,
      ),
    ]) {
      final expected = _expectedTagOnlyMatches(conditions);
      expect(expected, hasLength(matchCount), reason: label);
      IntentionCatalogCursor? cursor;
      for (var pageNumber = 0; pageNumber < 2; pageNumber++) {
        trace.clear();
        final page = _page(
          await repository.getCatalogPage(
            _jointQuery(
              titleFilter: null,
              conditions: conditions,
              cursor: cursor,
            ),
          ),
        );
        final isFirst = pageNumber == 0;
        if (isFirst) {
          expect(
            (page as IntentionCatalogFirstPage).totalCount,
            matchCount,
            reason: label,
          );
        }
        final indexes = [
          for (final item in page.items) _fixtureIndexOf(item.id),
        ];
        expect(
          indexes,
          expected.skip(pageNumber * _pageSize).take(_pageSize),
          reason: '$label, порция $pageNumber',
        );
        if (bounds != null) {
          expect(
            (indexes.first, indexes.last),
            bounds[pageNumber],
            reason: '$label, порция $pageNumber',
          );
        }
        expect(page.nextCursor, isA<IntentionCatalogCursor>(), reason: label);
        _expectJointPlans(
          raw,
          trace,
          titleFilter: null,
          conditions: conditions,
        );
        _expectJointMaterialization(
          page,
          trace,
          isFirst: isFirst,
          conditions: conditions,
        );
        _printJointCost(
          raw,
          trace,
          titleFilter: null,
          page: pageNumber,
          label: label,
          conditions: conditions,
        );
        cursor = page.nextCursor;
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'согласует массовое удаление исключённого тега ограниченными порциями',
    () async {
      final (:repository, :raw, :trace) = await _openJointFixture();
      _populateMassExcludedTag(raw);

      // До удаления массовый тег оставляет в выдаче 2500 намерений с номерами
      // вида 20k + 4. Выдача загружена до конца 25 обычными порциями, поэтому
      // сохранённая область во много раз больше порции согласования.
      final before = [
        for (final index in _expectedTagOnlyMatches(_massConditions))
          if (!_hasMassTag(index)) index,
      ];
      expect(before, hasLength(25 * _pageSize));
      final loaded = <IntentionSummary>[];
      final continuations = <IntentionCatalogCursor>[];
      IntentionCatalogCursor? cursor;
      do {
        final page = _page(
          await repository.getCatalogPage(_massQuery(cursor: cursor)),
        );
        loaded.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor != null) continuations.add(cursor);
      } while (cursor != null);
      expect(loaded.map((item) => _fixtureIndexOf(item.id)), before);
      expect(continuations, hasLength(24));

      trace.isRecording = false;
      final deletion = await repository.execute(DeleteTag(_tagId(_massTag)));
      trace.isRecording = true;
      expect(deletion, isA<TagCommandSucceeded>());
      final deletionRevision = (deletion as TagCommandSucceeded).value.revision;

      // Удаление открывает почти 20 000 совпадений внутри сохранённой
      // области. Условие по удалённому тегу остаётся в запросе.
      final after = _expectedTagOnlyMatches(_massConditions);
      expect(after, hasLength(19994));
      for (final (label, boundary, storedCount) in [
        (
          'ранее полностью загруженная выдача',
          const IntentionCatalogCompletedBoundary(),
          before.length,
        ),
        (
          'частично загруженный префикс',
          IntentionCatalogPartialPrefixBoundary(continuations[1]),
          2 * _pageSize,
        ),
      ]) {
        final storedRows = loaded.take(storedCount).toList();
        final stored = before.take(storedCount).toList();
        final areaEnd = switch (boundary) {
          IntentionCatalogCompletedBoundary() => null,
          IntentionCatalogPartialPrefixBoundary() => stored.last,
        };
        final area = [
          for (final index in after)
            if (areaEnd == null || _compareCatalogOrder(index, areaEnd) <= 0)
              index,
        ];
        final missing = [
          for (final index in area)
            if (!stored.contains(index)) index,
        ];
        expect(missing, hasLength(area.length - stored.length), reason: label);

        final reconciled = await _expectMassReconciliation(
          repository,
          raw,
          trace,
          label: label,
          boundary: boundary,
          stored: storedRows,
          missing: missing,
          totalCount: after.length,
          revision: deletionRevision,
        );
        expect(
          [...stored, ...reconciled]..sort(_compareCatalogOrder),
          area,
          reason: label,
        );
      }

      await _expectFailedReconciliationReadsKeepConnection(
        repository,
        raw,
        trace,
        stored: loaded,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Массовый тег назначен всем намерениям фикстуры, кроме номеров вида
/// 20k + 4: среди активных готовых намерений с популярным тегом он
/// оставляет только их.
void _populateMassExcludedTag(sqlite.Database database) {
  final insertAssignment = database.prepare(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
  );
  database.execute('BEGIN');
  try {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _fixtureId(_massTag),
      'Тег $_massTag',
    ]);
    for (var index = 0; index < _fixtureSize; index++) {
      if (_hasMassTag(index)) {
        insertAssignment.execute([_fixtureId(_massTag), _fixtureId(index)]);
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  } finally {
    insertAssignment.close();
  }
}

bool _hasMassTag(int fixtureIndex) => fixtureIndex % 20 != 4;

/// Популярный обязательный тег и все исключённые условия; массовый тег
/// добавляется к исключённым условиям запросом [_massQuery].
const _massConditions = (popular: true, required: 0, excluded: _conditionCount);

IntentionCatalogQuery _massQuery({IntentionCatalogCursor? cursor}) =>
    _jointQuery(
      titleFilter: null,
      conditions: _massConditions,
      excludesMassTag: true,
      cursor: cursor,
    );

/// Проходит согласование области до конца скользящим окном сохранённых
/// строк и возвращает номера недостающих совпадений в порядке получения.
/// Каждая порция читает только себя: строка после границы порции не
/// выбирается повторно, сохранённые строки и предшествующие порции не
/// перечитываются. Вход каждого чтения — не больше порции сохранённых
/// идентификаторов независимо от размера области, а число чтений растёт
/// линейно с числом сохранённых и недостающих строк.
Future<List<int>> _expectMassReconciliation(
  DriftPersonalGraphRepository repository,
  sqlite.Database raw,
  _SelectTrace trace, {
  required String label,
  required IntentionCatalogReconciliationBoundary boundary,
  required List<IntentionSummary> stored,
  required List<int> missing,
  required int totalCount,
  required GraphRevision revision,
}) async {
  final storedIndexes = [for (final row in stored) _fixtureIndexOf(row.id)];
  final changesBefore = _connectionChanges(raw);
  final reconciled = <int>[];
  final costs = <_TracedSelect>[];
  final storedInputSizes = <int>[];
  IntentionCatalogReconciliationCursor? cursor;
  var windowStart = 0;
  var portionNumber = 0;
  do {
    final windowEnd = min(windowStart + _pageSize, stored.length);
    final windowRows = stored.sublist(windowStart, windowEnd);
    final IntentionCatalogReconciliationWindow window =
        windowEnd < stored.length
        ? IntentionCatalogInnerReconciliationWindow(windowRows)
        : IntentionCatalogFinalReconciliationWindow(windowRows);
    trace.clear();
    final result = await repository.getCatalogReconciliationPortion(
      IntentionCatalogReconciliationQuery(
        catalogQuery: _massQuery(),
        boundary: boundary,
        window: window,
        cursor: cursor,
      ),
    );
    expect(
      result,
      isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>(),
      reason: '$label, порция $portionNumber',
    );
    final outcome =
        (result as ResultSuccess<IntentionCatalogReconciliationOutcome>).value;
    expect(
      outcome,
      isA<IntentionCatalogReconciliationPortion>(),
      reason: '$label, порция $portionNumber',
    );
    final portion = outcome as IntentionCatalogReconciliationPortion;
    final isFirst = portionNumber == 0;
    if (isFirst) {
      expect(
        (portion as IntentionCatalogReconciliationFirstPortion).totalCount,
        totalCount,
        reason: label,
      );
    } else {
      expect(portion, isA<IntentionCatalogReconciliationContinuationPortion>());
    }
    expect(portion.revision.compareTo(revision), GraphRevisionOrder.same);

    final indexes = [
      for (final item in portion.items) _fixtureIndexOf(item.id),
    ];
    expect(
      indexes,
      hasLength(lessThanOrEqualTo(_pageSize)),
      reason: '$label, порция $portionNumber',
    );
    // Порция — следующие недостающие совпадения не дальше верхнего края
    // окна: последней строки внутреннего окна либо границы области.
    final upperEdge = switch (window) {
      IntentionCatalogInnerReconciliationWindow(:final upperEdgeRow) =>
        _fixtureIndexOf(upperEdgeRow.id),
      IntentionCatalogFinalReconciliationWindow() => null,
    };
    final expected = missing
        .skip(reconciled.length)
        .takeWhile(
          (index) =>
              upperEdge == null || _compareCatalogOrder(index, upperEdge) < 0,
        )
        .take(_pageSize);
    expect(indexes, expected, reason: '$label, порция $portionNumber');
    expect(
      portion.nextCursor == null,
      window is IntentionCatalogFinalReconciliationWindow &&
          reconciled.length + indexes.length == missing.length,
      reason: '$label, порция $portionNumber',
    );
    _expectReconciliationMaterialization(
      portion,
      trace,
      isFirst: isFirst,
      window: window,
    );
    _expectReconciliationPlans(raw, trace, window: window);
    final read = trace.selects.singleWhere(
      (select) => select.statement.contains('LIMIT'),
    );
    costs.add(read);
    storedInputSizes.add(_storedRowParameterSize(read, window: window));
    if (isFirst || portion.nextCursor == null) {
      _printJointCost(
        raw,
        trace,
        titleFilter: null,
        page: portionNumber,
        label: 'согласование: $label',
        conditions: _massConditions,
      );
    }
    reconciled.addAll(indexes);
    cursor = portion.nextCursor;
    if (cursor != null) {
      final position = indexes.length == _pageSize
          ? indexes.last
          : _fixtureIndexOf(
              (window as IntentionCatalogInnerReconciliationWindow)
                  .upperEdgeRow
                  .id,
            );
      while (windowStart < stored.length &&
          _compareCatalogOrder(storedIndexes[windowStart], position) <= 0) {
        windowStart += 1;
      }
    }
    portionNumber++;
  } while (cursor != null);

  expect(reconciled, missing, reason: label);
  // Вход чтения ограничен окном: порция сохранённых идентификаторов для
  // области любого размера, меньше — только для области меньше порции.
  expect(
    storedInputSizes,
    everyElement(lessThanOrEqualTo(_pageSize)),
    reason: label,
  );
  expect(
    storedInputSizes.reduce(max),
    min(stored.length, _pageSize),
    reason: label,
  );
  // Заполненная порция забирает `pageSize` недостающих строк, а незаполненная
  // исчерпывает окно из `pageSize` сохранённых строк либо завершает область,
  // поэтому число чтений линейно по обоим размерам.
  expect(
    portionNumber,
    inInclusiveRange(
      (missing.length + _pageSize - 1) ~/ _pageSize,
      missing.length ~/ _pageSize +
          max(1, (stored.length + _pageSize - 1) ~/ _pageSize),
    ),
    reason: label,
  );
  // Каждое чтение выбирает не больше `pageSize + 1` строк после своей
  // позиции, поэтому все порции вместе читают недостающие совпадения
  // однократно, а сохранённые строки не читают вовсе.
  expect(
    costs.map((select) => select.rowCount),
    everyElement(lessThanOrEqualTo(_pageSize + 1)),
    reason: label,
  );
  expect(
    costs.fold<int>(0, (sum, select) => sum + select.rowCount),
    lessThanOrEqualTo(missing.length + portionNumber),
    reason: label,
  );
  expect(_connectionChanges(raw), changesBefore, reason: label);
  final elapsed = [for (final select in costs) select.elapsed]..sort();
  // Измерения характеризуют фикстуру и не становятся порогом.
  // ignore: avoid_print
  print(
    'Согласование ($label): ${stored.length} сохранённых строк, '
    '${missing.length} недостающих совпадений, $portionNumber порций; '
    'вход чтения: не больше ${storedInputSizes.reduce(max)} сохранённых '
    'идентификаторов; чтение порции: медиана ${elapsed[elapsed.length ~/ 2].inMicroseconds} '
    'мкс, максимум ${elapsed.last.inMicroseconds} мкс, всего '
    '${elapsed.fold(Duration.zero, (sum, value) => sum + value).inMilliseconds} '
    'мс',
  );
  return reconciled;
}

/// Число сохранённых идентификаторов в SQL-параметре чтения порции: набор
/// передаётся последним `json_each(?)` и отсутствует для пустого окна.
int _storedRowParameterSize(
  _TracedSelect read, {
  required IntentionCatalogReconciliationWindow window,
}) {
  if (window.storedRows.isEmpty) return 0;
  final sets = [
    for (final argument in read.arguments.whereType<String>())
      if (argument.startsWith('[')) jsonDecode(argument) as List,
  ];
  return sets.last.length;
}

/// Порция согласования материализует только себя и полные назначения своих
/// строк, а абсолютное количество считается отдельным агрегатом полного
/// предиката без границы области и сохранённых строк.
void _expectReconciliationMaterialization(
  IntentionCatalogReconciliationPortion portion,
  _SelectTrace trace, {
  required bool isFirst,
  required IntentionCatalogReconciliationWindow window,
}) {
  final conditionSets = [
    {_fixtureId(_popularTag)},
    {
      _fixtureId(_massTag),
      for (var index = 0; index < _conditionCount; index++)
        _fixtureId(_excludedTagBase + index),
    },
  ];
  List<Set<Object?>> jsonSets(_TracedSelect select) => [
    for (final argument in select.arguments.whereType<String>())
      if (argument.startsWith('[')) (jsonDecode(argument) as List).toSet(),
  ];

  final counts = trace.selects
      .where((select) => _isCatalogCountStatement(select.statement))
      .toList();
  expect(counts, hasLength(isFirst ? 1 : 0));
  if (isFirst) {
    final count = counts.single;
    expect(count.rowCount, 1);
    expect(count.statement, isNot(contains('stored_row')));
    expect(count.statement, isNot(contains('LIMIT')));
    expect(jsonSets(count), conditionSets);
  }
  final read = trace.selects
      .where((select) => select.statement.contains('LIMIT'))
      .single;
  expect(read.rowCount, inInclusiveRange(portion.items.length, _pageSize + 1));
  expect(read.statement, contains('LIMIT ${_pageSize + 1}'));
  expect(jsonSets(read), [
    ...conditionSets,
    if (window.storedRows.isNotEmpty)
      {for (final id in window.storedIntentionIds) id.toCanonicalString()},
  ]);

  final ids = portion.items.map((item) => item.id.toCanonicalString()).toSet();
  final tags = trace.selects
      .where((select) => select.statement.contains('FROM tag_assignments a'))
      .single;
  expect(tags.arguments, unorderedEquals(ids));
  expect(tags.intentionIds, ids);
  final aggregates = trace.selects
      .where(
        (select) =>
            select.statement.contains('doable_relation_count_aggregates'),
      )
      .single;
  expect(aggregates.arguments, unorderedEquals(ids));
  expect(aggregates.rowCount, portion.items.length);
  var tagCount = 0;
  for (final item in portion.items) {
    final expectedTags = _fixtureTagIds(_fixtureIndexOf(item.id));
    expect(item.tags.map((tag) => tag.id), expectedTags);
    tagCount += expectedTags.length;
  }
  expect(tags.rowCount, tagCount);
  _expectMarkMaterialization(portion.items, trace);
  // Число чтений не растёт с числом строк порции, сохранённых строк и
  // условий: количество, порция, агрегаты, назначения и отметки пакетны.
  expect(trace.writes, isEmpty);
  expect(trace.selects, hasLength(isFirst ? 5 : 4));
  _expectNoOffset(trace);
}

/// Порцию согласования ведёт индекс порядка охвата. Наборы условий и
/// сохранённых идентификаторов читаются из своих `json_each(?)` один раз на
/// выполнение запроса, а кандидат проверяется поиском в отобранном
/// множестве, поэтому стоимость его отсечения не растёт с размером наборов.
void _expectReconciliationPlans(
  sqlite.Database database,
  _SelectTrace trace, {
  required IntentionCatalogReconciliationWindow window,
}) {
  _expectJointPlans(
    database,
    trace,
    titleFilter: null,
    conditions: _massConditions,
  );
  final read = _observedPlanTree(
    database,
    trace.selects.singleWhere((select) => select.statement.contains('LIMIT')),
  );
  if (window.storedRows.isNotEmpty) {
    _expectParameterSetReadOnce(read, 'stored_row');
  }
}

/// Отказавшие чтения согласования, в том числе продолжения, откатываются
/// без записей на соединении, а повтор того же чтения успешен.
Future<void> _expectFailedReconciliationReadsKeepConnection(
  DriftPersonalGraphRepository repository,
  sqlite.Database raw,
  _SelectTrace trace, {
  required List<IntentionSummary> stored,
}) async {
  // Первое окно — начало сохранённой области; окно продолжения — сохранённые
  // строки после последней строки заполненной первой порции.
  final firstWindow = IntentionCatalogInnerReconciliationWindow(
    stored.take(_pageSize),
  );
  final first = await repository.getCatalogReconciliationPortion(
    IntentionCatalogReconciliationQuery(
      catalogQuery: _massQuery(),
      boundary: const IntentionCatalogCompletedBoundary(),
      window: firstWindow,
    ),
  );
  final firstPortion =
      (first as ResultSuccess<IntentionCatalogReconciliationOutcome>).value
          as IntentionCatalogReconciliationPortion;
  final continuation = firstPortion.nextCursor;
  expect(continuation, isA<IntentionCatalogReconciliationCursor>());
  expect(firstPortion.items, hasLength(_pageSize));
  final position = firstPortion.items.last;
  final continuationWindow = IntentionCatalogInnerReconciliationWindow(
    stored
        .where((row) => _massQuery().compare(row, position) > 0)
        .take(_pageSize),
  );
  IntentionCatalogReconciliationQuery query({
    IntentionCatalogReconciliationCursor? cursor,
  }) => IntentionCatalogReconciliationQuery(
    catalogQuery: _massQuery(),
    boundary: const IntentionCatalogCompletedBoundary(),
    window: cursor == null ? firstWindow : continuationWindow,
    cursor: cursor,
  );

  for (final (label, cursor, failsOn)
      in <
        (String, IntentionCatalogReconciliationCursor?, bool Function(String))
      >[
        ('количество', null, _isCatalogCountStatement),
        ('первая порция', null, (sql) => sql.contains('LIMIT')),
        (
          'теги первой порции',
          null,
          (sql) => sql.contains('FROM tag_assignments a'),
        ),
        (
          'отметки первой порции',
          null,
          (sql) => sql.contains('FROM favorite_intentions'),
        ),
        ('продолжение', continuation, (sql) => sql.contains('LIMIT')),
        (
          'теги продолжения',
          continuation,
          (sql) => sql.contains('FROM tag_assignments a'),
        ),
        (
          'отметки продолжения',
          continuation,
          (sql) => sql.contains('FROM favorite_intentions'),
        ),
      ]) {
    final changesBefore = _connectionChanges(raw);
    trace.failWhen = failsOn;
    final failed = await repository.getCatalogReconciliationPortion(
      query(cursor: cursor),
    );
    trace.failWhen = null;
    expect(trace.hasFailed, isTrue, reason: label);
    trace.hasFailed = false;
    expect(
      failed,
      isA<ResultFailure<IntentionCatalogReconciliationOutcome>>(),
      reason: label,
    );
    expect(_connectionChanges(raw), changesBefore, reason: label);

    final recovered = await repository.getCatalogReconciliationPortion(
      query(cursor: cursor),
    );
    expect(
      recovered,
      isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>().having(
        (result) => result.value,
        'исход',
        isA<IntentionCatalogReconciliationPortion>(),
      ),
      reason: label,
    );
    expect(_connectionChanges(raw), changesBefore, reason: label);
  }
}

int _connectionChanges(sqlite.Database raw) =>
    raw.select('SELECT total_changes() AS count').single['count'] as int;

/// Файловая база с большой фикстурой, совместными кандидатами и популярным
/// тегом; трассировка очищена и ограничивает число SQL-параметров.
Future<
  ({
    DriftPersonalGraphRepository repository,
    sqlite.Database raw,
    _SelectTrace trace,
  })
>
_openJointFixture() async {
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
  return (repository: repository, raw: raw, trace: trace);
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
  final expected = [...matches]..sort(_compareCatalogOrder);
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
  final insertFavorite = database.prepare(
    'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
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
      (_popularTag, 1),
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
    // Популярный обязательный тег назначен большинству намерений каждого
    // охвата и всем совместным кандидатам.
    for (var index = 0; index < _fixtureSize; index++) {
      for (final tag in _backgroundTags(index)) {
        insertAssignment.execute([
          _fixtureId(_backgroundTagBase + tag),
          _fixtureId(index),
        ]);
      }
      if (_hasPopularTag(index)) {
        insertAssignment.execute([_fixtureId(_popularTag), _fixtureId(index)]);
      }
    }
    // Избранных намерений во много раз больше порции: чтение отметок порции
    // не может получать их все.
    for (var index = 0; index < _fixtureSize; index++) {
      if (_isFavorite(index)) {
        insertFavorite.execute([_fixtureId(index), index + 1]);
      }
    }
    database.execute('COMMIT');
  } on Object {
    database.execute('ROLLBACK');
    rethrow;
  } finally {
    insertTag.close();
    insertAssignment.close();
    insertFavorite.close();
  }
}

const _jointCandidateCount = _jointMatchCount + 10;

/// Избранное — каждое третье намерение фикстуры: 16 667 отметок, среди них
/// часть совместных кандидатов и большинство намерений вне любой порции.
bool _isFavorite(int fixtureIndex) => fixtureIndex % 3 == 0;

/// Отметки порции получены одним чтением только по её идентификаторам:
/// число строк не больше размера порции, а чтение ведёт первичный ключ.
void _expectMarkMaterialization(
  List<IntentionSummary> items,
  _SelectTrace trace,
) {
  final marks = trace.selects
      .where((select) => select.statement.contains('FROM favorite_intentions'))
      .single;
  final ids = items.map((item) => item.id.toCanonicalString()).toSet();
  expect(marks.arguments, unorderedEquals(ids));
  expect(marks.rowCount, lessThanOrEqualTo(items.length));
  final favoriteIds = <String>{};
  for (final item in items) {
    final isFavorite = _isFavorite(_fixtureIndexOf(item.id));
    expect(
      item.favoriteMark,
      isFavorite ? FavoriteMark.favorite : FavoriteMark.notFavorite,
    );
    if (isFavorite) favoriteIds.add(item.id.toCanonicalString());
  }
  expect(marks.intentionIds, favoriteIds);
  expect(marks.rowCount, favoriteIds.length);
}

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

/// Популярный тег есть у четырёх из пяти активных и архивных намерений, в
/// том числе у всех совместных кандидатов: их номера кратны десяти.
bool _hasPopularTag(int fixtureIndex) => fixtureIndex % 10 != 2;

/// Номер совместного кандидата для намерения фикстуры, если оно им является.
int? _jointIndexOf(int fixtureIndex) {
  final offset = fixtureIndex - _jointIntentionIndex(0);
  final joint = offset >= 0 && offset % 200 == 0 ? offset ~/ 200 : null;
  return joint != null && joint < _jointCandidateCount ? joint : null;
}

/// Порядок каталога фикстуры: `created_at` по убыванию, затем `id`.
int _compareCatalogOrder(int left, int right) {
  final timestampOrder = (right % 7).compareTo(left % 7);
  return timestampOrder == 0 ? left.compareTo(right) : timestampOrder;
}

/// Модель выдачи `_jointQuery` без фильтра названия: номера подходящих
/// намерений фикстуры в порядке каталога.
List<int> _expectedTagOnlyMatches(_Conditions conditions) => [
  for (var index = 0; index < _fixtureSize; index++)
    if (_matchesTagOnlyQuery(index, conditions)) index,
]..sort(_compareCatalogOrder);

bool _matchesTagOnlyQuery(int fixtureIndex, _Conditions conditions) {
  final joint = _jointIndexOf(fixtureIndex);
  // Активны чётные намерения, кроме переведённого в архив кандидата 242;
  // кандидат 243 не готов, кандидат 244 исключён из выдачи запросом.
  if (fixtureIndex.isOdd || joint == 242 || joint == 243 || joint == 244) {
    return false;
  }
  if (conditions.popular && !_hasPopularTag(fixtureIndex)) return false;
  if (conditions.required > 0 &&
      (joint == null || _jointRequiredTagCount(joint) < conditions.required)) {
    return false;
  }
  final excludedTag = joint == null ? null : _jointExcludedTag(joint);
  return excludedTag == null || excludedTag >= conditions.excluded;
}

/// Фоновые теги намерения фикстуры в порядке их создания.
List<int> _backgroundTags(int fixtureIndex) => [
  for (final offset in _backgroundTagOffsets)
    (fixtureIndex + offset) % _backgroundTagCount,
]..sort();

/// Полный состав собственных тегов намерения фикстуры в порядке создания
/// тегов: обязательные, исключённый, дополнительные, фоновые, популярный.
List<TagId> _fixtureTagIds(int fixtureIndex) {
  final jointIndex = _jointIndexOf(fixtureIndex);
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
    if (_hasPopularTag(fixtureIndex)) _tagId(_popularTag),
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
  bool excludesMassTag = false,
  IntentionCatalogCursor? cursor,
}) => IntentionCatalogQuery(
  scope: IntentionScope.active,
  readinessFilter: IntentionReadinessFilter.readyOnly,
  titleFilter: titleFilter,
  tagFilter: IntentionTagFilter(
    requiredTagIds: [
      if (conditions.popular) _tagId(_popularTag),
      for (var index = 0; index < conditions.required; index++)
        _tagId(_requiredTagBase + index),
    ],
    excludedTagIds: [
      if (excludesMassTag) _tagId(_massTag),
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
  _expectMarkMaterialization(page.items, trace);
  // Объём назначений может превышать размер порции. Число чтений не растёт
  // с числом намерений: количество, порция, агрегаты, назначения и отметки
  // пакетны.
  // Наборы условий передаются параметрами, служебных записей и чтений нет.
  expect(
    trace.selects.where(
      (select) => select.statement.contains('total_changes()'),
    ),
    isEmpty,
  );
  expect(trace.writes, isEmpty);
  expect(trace.selects, hasLength(isFirst ? 5 : 4));
  for (final select in [...counts, read]) {
    final conditionSets = select.arguments
        .whereType<String>()
        .where((argument) => argument.startsWith('['))
        .map((argument) => (jsonDecode(argument) as List).toSet())
        .toList();
    expect(conditionSets, [
      if (_requiredConditionCount(conditions) > 0)
        {
          if (conditions.popular) _fixtureId(_popularTag),
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

/// Набор [alias] из `json_each(?)` читается один раз подзапросом, не
/// коррелированным с текущим намерением, а кандидат проверяется поиском по
/// ключу в отобранном множестве (`LIST SUBQUERY` оператора `IN`).
void _expectParameterSetReadOnce(List<_PlanNode> plan, String alias) {
  final nodes = {for (final node in plan) node.id: node};
  final details = plan.map((node) => node.detail).join('\n');
  final setReads = plan
      .where((node) => node.detail.startsWith('SCAN $alias VIRTUAL TABLE'))
      .toList();
  expect(setReads, hasLength(1), reason: 'Набор $alias в плане:\n$details');
  final chain = [
    for (
      var parent = nodes[setReads.single.parent];
      parent != null;
      parent = nodes[parent.parent]
    )
      parent.detail,
  ];
  expect(
    chain,
    everyElement(isNot(startsWith('CORRELATED'))),
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
  final hasRequired = _requiredConditionCount(conditions) > 0;
  for (final alias in [
    if (hasRequired) 'required_tag',
    if (conditions.excluded > 0) 'excluded_tag',
  ]) {
    _expectParameterSetReadOnce(plan, alias);
  }
  final assignmentReads = plan
      .where(
        (node) => RegExp(r'^(SCAN|SEARCH) assignment\b').hasMatch(node.detail),
      )
      .toList();
  expect(
    assignmentReads,
    hasLength((hasRequired ? 1 : 0) + (conditions.excluded > 0 ? 1 : 0)),
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
    // Без полнотекстового индекса порцию ведёт индекс порядка охвата, и
    // выборка завершается после `pageSize + 1` строк. Точное количество может
    // использовать любой план.
    if (!usesFts && select.statement.contains('LIMIT')) {
      _expectOrderIndexDrivesPage(plan);
    }
  }
  final tagPlan = _observedPlan(
    database,
    trace.selects.singleWhere(
      (select) => select.statement.contains('FROM tag_assignments a'),
    ),
  ).join('\n');
  expect(tagPlan, contains('tag_assignments_intention_order'));
  expect(tagPlan, isNot(contains('SCAN a')));
  final markPlan = _observedPlan(
    database,
    trace.selects.singleWhere(
      (select) => select.statement.contains('FROM favorite_intentions'),
    ),
  ).join('\n');
  expect(markPlan, contains('sqlite_autoindex_favorite_intentions_1'));
  expect(markPlan, isNot(contains('SCAN favorite_intentions')));
}

void _expectOrderIndexDrivesPage(List<_PlanNode> plan) {
  final details = plan.map((node) => node.detail).join('\n');
  expect(
    details,
    contains('intentions_active_created_at_desc_id_asc'),
    reason: 'Порцию ведёт индекс порядка охвата:\n$details',
  );
  expect(
    details,
    isNot(contains('USE TEMP B-TREE FOR ORDER BY')),
    reason: 'Порция не сортирует все совпадения:\n$details',
  );
  expect(
    details,
    isNot(
      contains('SEARCH intentions USING INDEX sqlite_autoindex_intentions_1'),
    ),
    reason: 'Выборку не ведёт отобранное по тегам множество:\n$details',
  );
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
    '${_requiredConditionCount(conditions)} обязательных'
    '${conditions.popular ? ' (с популярным)' : ''} и '
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

  /// Чтение, на котором соединение отказывает; отказ однократен.
  bool Function(String statement)? failWhen;
  var hasFailed = false;

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
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final fails = failWhen;
    if (fails != null && !hasFailed && fails(statement.statements.single)) {
      hasFailed = true;
      throw StateError('CANARY-отказ чтения');
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
