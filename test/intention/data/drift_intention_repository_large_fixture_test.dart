@Tags(['slow'])
library;

import 'dart:math';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/intention_catalog_large_fixture.dart';
import '../../support/local_database_harness.dart';

const _fixtureSize = intentionCatalogFixtureSize;
const _pageSize = 100;
const _jointMatchCount = 235;
const _conditionCount = 1201;
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

      await populateIntentionCatalogFixture(database);
      trace.clear();

      await _expectBoundedPages(repository);
      await _expectFirstPageCounts(repository, trace);
      await _expectCompleteKeysetTraversal(repository);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'материализует только порцию редких совместных совпадений и все её теги',
    () async {
      final (:repository, raw: _, :trace) = await _openJointFixture();

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
        _expectJointPage(first, trace, isFirst: true);
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
          trace,
          titleFilter: titleFilter,
          matches: matches,
        );
      }

      // Каждый из 25 000 активных кандидатов имеет несколько собственных
      // назначений. Отсечение кандидата не должно перебирать набор условий:
      // оба набора читаются из параметра один раз на запрос. Без фильтра
      // названия из 24 997 готовых активных кандидатов, кроме исключённого
      // намерения, все 1201 исключённых тегов отсекают трёх кандидатов, а
      // все 1201 обязательных тегов есть у 239 совместных кандидатов.
      for (final (label, conditions, matchCount) in [
        (
          'только исключённые',
          (popular: false, required: 0, excluded: _conditionCount),
          24994,
        ),
        (
          'только обязательные',
          (popular: false, required: _conditionCount, excluded: 0),
          239,
        ),
        ('совместные', _allConditions, tagOnlyMatchCount),
      ]) {
        trace.clear();
        final first = _page(
          await repository.getCatalogPage(
            _jointQuery(titleFilter: null, conditions: conditions),
          ),
        ) as IntentionCatalogFirstPage;
        expect(first.totalCount, matchCount, reason: label);
        expect(first.items, hasLength(_pageSize), reason: label);
        _expectJointPage(first, trace, isFirst: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('отдаёт порцию и продолжение в порядке охвата при популярном обязательном теге', () async {
    final (:repository, raw: _, :trace) = await _openJointFixture();

    // Популярный тег назначен 19 999 из 24 999 активных намерений. Среди
    // них не готов кандидат 243 и исключён из выдачи кандидат 244, поэтому
    // один популярный тег оставляет 19 997 совпадений. Все 1201
    // исключённых тегов отсекают ещё трёх кандидатов.
    // С редкими обязательными тегами совпадения сужаются до совместных
    // кандидатов, но популярный тег остаётся в наборе условий.
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
        (popular: true, required: _conditionCount, excluded: 0),
        239,
        null,
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
        _expectJointPage(page, trace, isFirst: isFirst);
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
/// Каждая порция даёт только следующие недостающие совпадения и не читает
/// больше строк, чем нужно порции, а число порций растёт линейно с числом
/// сохранённых и недостающих строк.
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
  var readRows = 0;
  var allowedRows = 0;
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
    _expectBoundedReadVolume(
      trace,
      portion.items,
      isFirst: isFirst,
      portionRows: _pageSize + 1,
    );
    _expectFixtureTags(portion.items);
    readRows += _selectedRows(trace);
    allowedRows += _readVolumeLimit(
      portion.items,
      isFirst: isFirst,
      portionRows: portion.items.length + 1,
    );
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
  // Заполненная порция забирает `pageSize` недостающих строк, а незаполненная
  // исчерпывает окно из `pageSize` сохранённых строк либо завершает область,
  // поэтому число порций линейно по обоим размерам.
  expect(
    portionNumber,
    inInclusiveRange(
      (missing.length + _pageSize - 1) ~/ _pageSize,
      missing.length ~/ _pageSize +
          max(1, (stored.length + _pageSize - 1) ~/ _pageSize),
    ),
    reason: label,
  );
  // Все порции вместе читают недостающие совпадения однократно, а
  // сохранённые строки не читают вовсе: каждая порция читает не больше одной
  // строки сверх своих.
  expect(readRows, lessThanOrEqualTo(allowedRows), reason: label);
  expect(_connectionChanges(raw), changesBefore, reason: label);
  return reconciled;
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
  await populateIntentionCatalogFixture(database);
  _populateJointTagFixture(raw);
  trace.clear();
  trace.parameterLimit = 400;
  return (repository: repository, raw: raw, trace: trace);
}

/// Полный обход совместного поиска: каждая порция, включая продолжения, даёт
/// только себя и все свои теги.
Future<void> _expectJointTraversal(
  DriftPersonalGraphRepository repository,
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
    _expectJointPage(page, trace, isFirst: pageNumber == 0);
    if (pageNumber == 0) {
      expect((page as IntentionCatalogFirstPage).totalCount, matches.length);
    }
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

/// Порция несёт полный состав собственных тегов намерений фикстуры.
void _expectFixtureTags(List<IntentionSummary> items) {
  for (final item in items) {
    expect(
      item.tags.map((tag) => tag.id),
      _fixtureTagIds(_fixtureIndexOf(item.id)),
    );
  }
}

/// Строки всех чтений за один запрос.
int _selectedRows(_SelectTrace trace) =>
    trace.rowCounts.fold(0, (sum, rows) => sum + rows);

/// Предел строк, которые запрос может прочитать для порции [items]:
/// количество (только первая порция), сама порция, сводки связей и теги
/// именно этих намерений.
int _readVolumeLimit(
  List<IntentionSummary> items, {
  required bool isFirst,
  required int portionRows,
}) {
  final tagRows = items.fold(0, (sum, item) => sum + item.tags.length);
  return (isFirst ? 1 : 0) + portionRows + items.length + tagRows;
}

/// Запрос порции не читает строк сверх порции и её данных, как бы ни были
/// велики каталог и число назначений вне порции, и не пишет.
void _expectBoundedReadVolume(
  _SelectTrace trace,
  List<IntentionSummary> items, {
  required bool isFirst,
  required int portionRows,
}) {
  expect(
    _selectedRows(trace),
    lessThanOrEqualTo(
      _readVolumeLimit(items, isFirst: isFirst, portionRows: portionRows),
    ),
  );
  expect(trace.writes, isEmpty);
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

void _expectJointPage(
  IntentionCatalogPage page,
  _SelectTrace trace, {
  required bool isFirst,
}) {
  _expectFixtureTags(page.items);
  _expectBoundedReadVolume(
    trace,
    page.items,
    isFirst: isFirst,
    portionRows: page.items.length + (page.nextCursor == null ? 0 : 1),
  );
}

Future<void> _expectBoundedPages(PersonalGraphRepository repository) async {
  // Граница порции не зависит от текста фильтра: достаточно запроса без
  // фильтра и запроса с совпадением всех записей.
  for (final scope in IntentionScope.values) {
    for (final order in _catalogOrders) {
      for (final filter in const <String?>[null, 'ааа']) {
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

Future<void> _expectFirstPageCounts(
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
    _expectBoundedReadVolume(
      trace,
      page.items,
      isFirst: true,
      portionRows: page.items.length + (page.nextCursor == null ? 0 : 1),
    );
  }
}

Future<void> _expectCompleteKeysetTraversal(
  PersonalGraphRepository repository,
) async {
  var pageCount = 0;
  var query = _query(
    scope: IntentionScope.all,
    order: IntentionCatalogOrder.createdAtDescending,
    titleFilter: null,
  );
  final ids = <String>{};
  IntentionCatalogFirstPage? firstPage;

  while (true) {
    final page = _page(await repository.getCatalogPage(query));
    pageCount++;
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
  expect(pageCount, _fixtureSize ~/ _pageSize);
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

String _fixtureId(int index) => intentionCatalogFixtureId(index);

const _allFilters = <String?>[null, 'а', 'я', 'аа', 'яя', 'ааа'];
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

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  /// Число строк каждого чтения в порядке выполнения.
  final rowCounts = <int>[];
  final writes = <String>[];
  int? parameterLimit;
  var isRecording = true;

  void clear() {
    rowCounts.clear();
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
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (isRecording &&
        statement.operation == LocalDatabaseSqlOperation.select) {
      rowCounts.add(rows.length);
    }
    return rows;
  }
}
