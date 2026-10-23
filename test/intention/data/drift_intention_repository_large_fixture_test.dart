import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/intention_catalog_large_fixture.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_positions.dart';

const _fixtureSize = 5000;
const _pageSize = 10;
const _jointMatchCount = 23;
const _conditionCount = 1201;
const _extraTagCount = 137;
const _backgroundTagCount = 64;
const _backgroundTagOffsets = [0, 21, 42];
const _requiredTagBase = 100000;
const _excludedTagBase = 110000;
const _extraTagBase = 120000;
const _backgroundTagBase = 130000;
const _popularTag = 140000;

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

      await populateIntentionCatalogFixture(database, _fixtureSize);
      trace.clear();

      await _expectBoundedPages(repository);
      await _expectFirstPageCounts(repository, trace);
      await _expectCompleteKeysetTraversal(repository);
    },
  );

  test(
    'материализует только порцию редких совместных совпадений и все её теги',
    () async {
      final (:repository, raw: _, :trace) = await _openJointFixture();

      // Без фильтра названия совпадение отсекают только теги среди
      // 2 500 готовых активных кандидатов; «Другое название» проходит.
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
            _jointIntentionIndex(_otherTitleCandidate),
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

      // Каждый из 2 500 активных кандидатов имеет несколько собственных
      // назначений. Оба набора условий читаются из параметра один раз на
      // запрос. Без фильтра названия из 2 497 готовых активных кандидатов,
      // кроме исключённого намерения, все 1201 исключённых тегов отсекают
      // трёх кандидатов, а все 1201 обязательных тегов есть у 27 совместных
      // кандидатов.
      for (final (label, conditions, matchCount) in [
        (
          'только исключённые',
          (popular: false, required: 0, excluded: _conditionCount),
          2494,
        ),
        (
          'только обязательные',
          (popular: false, required: _conditionCount, excluded: 0),
          27,
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
  );

  test('отдаёт порцию и продолжение в порядке охвата при популярном обязательном теге', () async {
    final (:repository, raw: _, :trace) = await _openJointFixture();

    // Популярный тег назначен 1 999 из 2 499 активных намерений. Среди них
    // один кандидат не готов и один исключён из выдачи, поэтому один
    // популярный тег оставляет 1 997 совпадений. Все 1201 исключённых тегов
    // отсекают ещё трёх кандидатов.
    // С редкими обязательными тегами совпадения сужаются до совместных
    // кандидатов, но популярный тег остаётся в наборе условий.
    const popularBounds = [(6, 160), (174, 328)];
    for (final (label, conditions, matchCount, bounds) in [
      (
        'только обязательные',
        (popular: true, required: 0, excluded: 0),
        1997,
        popularBounds,
      ),
      (
        'только обязательные',
        (popular: true, required: _conditionCount, excluded: 0),
        27,
        null,
      ),
      (
        'совместные',
        (popular: true, required: 0, excluded: _conditionCount),
        1994,
        popularBounds,
      ),
      (
        'совместные',
        (popular: true, required: _conditionCount, excluded: _conditionCount),
        24,
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
  });
}

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
  await populateIntentionCatalogFixture(database, _fixtureSize);
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

/// Среди 5 000 намерений 33 кандидата далеко за первой обычной порцией.
/// Десять отсекаются разными частями запроса; остальные имеют все 1201 тега.
/// Каждое намерение дополнительно имеет три фоновых тега вне условий.
void _populateJointTagFixture(sqlite.Database database) {
  final insertTag = database.prepare(
    'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
  );
  final insertAssignment = database.prepare(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
  );
  database.execute('BEGIN');
  try {
    seedRawGraph(database, () {
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
          insertTag.execute([
            _fixtureId(base + index),
            'Тег ${base + index}',
            tagPositionKey(base + index),
          ]);
        }
      }
      for (var index = 0; index < _jointCandidateCount; index++) {
        final id = _fixtureId(_jointIntentionIndex(index));
        database.execute(
          'UPDATE intentions SET title = ?, is_action_ready = ?, '
          'is_archived = ? WHERE id = ?',
          [
            index == _otherTitleCandidate
                ? 'Другое название'
                : 'Редкое %_ совпадение',
            index == _notReadyCandidate ? 0 : 1,
            index == _archivedCandidate ? 1 : 0,
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
          insertAssignment.execute([
            _fixtureId(_popularTag),
            _fixtureId(index),
          ]);
        }
      }
    });
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

/// Номера кандидатов за совпадениями: каждый отсекает одна часть запроса.
const _otherTitleCandidate = _jointMatchCount + 6;
const _archivedCandidate = _jointMatchCount + 7;
const _notReadyCandidate = _jointMatchCount + 8;
const _excludedCandidate = _jointMatchCount + 9;

const _jointFirstIndex = 100;
const _jointIndexStep = 120;

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

int _jointIntentionIndex(int index) =>
    _jointFirstIndex + index * _jointIndexStep;

/// Трём совместным кандидатам не хватает последнего обязательного тега.
int _jointRequiredTagCount(int index) =>
    index >= _jointMatchCount && index <= _jointMatchCount + 2
    ? _conditionCount - 1
    : _conditionCount;

/// Номер исключённого тега совместного кандидата, если он назначен.
int? _jointExcludedTag(int index) => switch (index - _jointMatchCount) {
  3 || 4 => 0,
  5 => _conditionCount - 1,
  _ => null,
};

/// Популярный тег есть у четырёх из пяти активных и архивных намерений, в
/// том числе у всех совместных кандидатов: их номера кратны десяти.
bool _hasPopularTag(int fixtureIndex) => fixtureIndex % 10 != 2;

/// Номер совместного кандидата для намерения фикстуры, если оно им является.
int? _jointIndexOf(int fixtureIndex) {
  final offset = fixtureIndex - _jointIntentionIndex(0);
  final joint = offset >= 0 && offset % _jointIndexStep == 0
      ? offset ~/ _jointIndexStep
      : null;
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
  // Активны чётные намерения, кроме переведённого в архив кандидата;
  // ещё один кандидат не готов, а другой исключён из выдачи запросом.
  if (fixtureIndex.isOdd ||
      joint == _archivedCandidate ||
      joint == _notReadyCandidate ||
      joint == _excludedCandidate) {
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

/// Фоновые теги намерения фикстуры в ручном порядке по месту. Фикстура даёт
/// места по возрастанию номера тега, поэтому ручной порядок в ней совпадает
/// с порядком создания.
List<int> _backgroundTags(int fixtureIndex) => [
  for (final offset in _backgroundTagOffsets)
    (fixtureIndex + offset) % _backgroundTagCount,
]..sort();

/// Полный состав собственных тегов намерения фикстуры в ручном порядке по
/// месту: обязательные, исключённый, дополнительные, фоновые, популярный.
/// Фикстура даёт места по возрастанию номера тега, поэтому ручной порядок
/// в ней совпадает с порядком создания.
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
      for (var index = 0; index < conditions.excluded; index++)
        _tagId(_excludedTagBase + index),
    ],
  ),
  excludedIntentionId: switch (IntentionId.decode(
    _fixtureId(_jointIntentionIndex(_excludedCandidate)),
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
