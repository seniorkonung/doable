@Tags(['slow'])
library;

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _catalogChoices = 401;
const _otherGroupChoices = 150;
const _pathLength = 150;
const _pageSize = 25;

String _uuid(int number) => durabilityUuid(number);

IntentionId _intention(int number) => durabilityIntention(number);

LongTermRelationId _relation(int number) => durabilityRelation(number);

final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final selects = <_MeasuredSelect>[];
  final _started = <LocalDatabaseSqlStatement, Stopwatch>{};
  Completer<void>? _reachabilityStarted;
  Completer<void>? _releaseReachability;

  void clear() => selects.clear();

  void blockNextReachability() {
    _reachabilityStarted = Completer<void>();
    _releaseReachability = Completer<void>();
  }

  Future<void> get waitForReachability => _reachabilityStarted!.future;

  void releaseReachability() => _releaseReachability!.complete();

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    _started[statement] = Stopwatch()..start();
    final started = _reachabilityStarted;
    if (statement.statements.single.contains('WITH RECURSIVE') &&
        started != null &&
        !started.isCompleted) {
      started.complete();
      await _releaseReachability!.future;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final watch = _started.remove(statement)!..stop();
    selects.add(
      _MeasuredSelect(
        sql: statement.statements.single,
        arguments: statement.arguments,
        rows: rows.length,
        elapsed: watch.elapsed,
      ),
    );
    return rows;
  }
}

final class _MeasuredSelect {
  const _MeasuredSelect({
    required this.sql,
    required this.arguments,
    required this.rows,
    required this.elapsed,
  });

  final String sql;
  final List<Object?> arguments;
  final int rows;
  final Duration elapsed;
}

final class _Fixture {
  final trace = _ReadTrace();
  late final sqlite.Database raw;
  late final AppDatabase database;
  late final DriftPersonalGraphRepository repository;

  Future<void> open() async {
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 24),
      InMemoryDiagnosticsSink(),
      dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(12000)),
      choicePathStepIdGenerator: SequentialStepIds(32000),
    );
    raw.execute('BEGIN');
    try {
      for (var number = 1; number <= _pathLength + 1; number++) {
        _addIntention(number, ready: number == 2 || number == 151);
      }
      _addIntention(200);
      _addIntention(201, ready: true);
      _addRelation(900, 1, 2);
      for (var node = 2; node <= _pathLength; node++) {
        _addRelation(1000 + node, node, node + 1);
      }
      for (var node = 4; node <= _pathLength; node++) {
        _addRelation(5000 + node, node, node - 2);
      }
      _addRelation(901, 200, 201);
      for (var number = 11000; number < 11000 + _otherGroupChoices; number++) {
        _addChoice(number, 200, 201, [901], stepBase: number + 10000);
      }
      for (var number = 10000; number < 10000 + _catalogChoices - 1; number++) {
        _addChoice(number, 1, 2, [900], stepBase: number + 10000);
      }
      _addChoice(10400, 1, 151, [
        900,
        for (var node = 2; node <= _pathLength; node++) 1000 + node,
      ], stepBase: 30000);
      raw.execute('COMMIT');
    } on Object {
      raw.execute('ROLLBACK');
      rethrow;
    }
    trace.clear();
  }

  Future<void> close() => database.close();

  void _addIntention(int id, {bool ready = false}) => raw.execute(
    '''INSERT INTO intentions
       (id, title, is_action_ready, is_archived, created_at, updated_at)
       VALUES (?, ?, ?, 0, 1, 1)''',
    [_uuid(id), 'Намерение $id', ready ? 1 : 0],
  );

  void _addRelation(int id, int source, int related) => raw.execute(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id, type, priority,
        is_archived) VALUES (?, ?, ?, 'need', 2, 0)''',
    [_uuid(id), _uuid(source), _uuid(related)],
  );

  void _addChoice(
    int id,
    int source,
    int selected,
    List<int> path, {
    required int stepBase,
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed) VALUES (?, ?, ?, '2026-09-24', NULL, 0)''',
      [_uuid(id), _uuid(source), _uuid(selected)],
    );
    for (var index = 0; index < path.length; index++) {
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          _uuid(stepBase + index),
          _uuid(id),
          _uuid(path[index]),
          index == 0 ? null : _uuid(stepBase + index - 1),
        ],
      );
    }
  }

  List<String> plan(_MeasuredSelect select) => [
    for (final row in raw.select(
      'EXPLAIN QUERY PLAN ${select.sql}',
      select.arguments,
    ))
      row['detail'].toString(),
  ];
}

List<_MeasuredSelect> _matching(
  Iterable<_MeasuredSelect> selects,
  String fragment,
) => [
  for (final select in selects)
    if (select.sql.contains(fragment)) select,
];

_MeasuredSelect _boundedPage(
  List<_MeasuredSelect> selects, {
  required int expectedSteps,
  required int expectedCountReads,
  required bool group,
  int pageSize = _pageSize,
}) {
  final rows = _matching(
    selects,
    group ? 'FROM daily_choices INDEXED BY' : 'FROM daily_choices',
  ).where((select) => select.sql.contains('ORDER BY choice_date')).toList();
  expect(rows, hasLength(1));
  expect(rows.single.rows, lessThanOrEqualTo(pageSize + 1));
  expect(rows.single.sql, isNot(contains('OFFSET')));
  final counts = _matching(selects, 'COUNT(*) AS total_count');
  expect(counts, hasLength(expectedCountReads));
  expect(counts.map((select) => select.rows), everyElement(1));
  final steps = _matching(selects, 'FROM daily_choice_path_steps');
  expect(steps, hasLength(1));
  expect(steps.single.sql, contains('WHERE daily_choice_id IN'));
  expect(steps.single.rows, expectedSteps);
  expect(steps.single.arguments, hasLength(pageSize));
  final relations = selects.where(
    (select) =>
        select.sql.contains('FROM long_term_relations') &&
        select.sql.contains('WHERE id IN'),
  );
  expect(relations, isNotEmpty);
  expect(
    relations.fold<int>(0, (total, select) => total + select.rows),
    lessThanOrEqualTo(expectedSteps),
  );
  expect(
    relations,
    everyElement(
      isA<_MeasuredSelect>()
          .having(
            (select) => select.arguments.length,
            'размер пакета связей',
            lessThanOrEqualTo(400),
          )
          .having(
            (select) => select.sql,
            'содержимое связей',
            isNot(contains('description')),
          ),
    ),
  );
  expect(
    selects.where(
      (select) =>
          select.sql.contains('FROM daily_choices') &&
          !select.sql.contains('COUNT(') &&
          !select.sql.contains('ORDER BY choice_date'),
    ),
    isEmpty,
  );
  return rows.single;
}

_MeasuredSelect _boundedSuggestions(
  List<_MeasuredSelect> selects, {
  required String participantColumn,
  required String participantId,
  required int expectedSteps,
}) {
  final candidates = selects
      .where(
        (select) =>
            select.sql.contains('FROM daily_choices') &&
            select.sql.contains('WHERE $participantColumn = ?'),
      )
      .toList();
  expect(candidates, hasLength(1));
  final candidate = candidates.single;
  expect(candidate.sql, contains('ORDER BY creation_sequence DESC'));
  expect(candidate.sql, contains('LIMIT ?'));
  expect(candidate.arguments, [participantId, 20]);
  expect(candidate.rows, 20);

  final choices = _matching(selects, 'FROM daily_choices WHERE id = ?');
  expect(choices, hasLength(20));
  expect(choices.map((select) => select.rows), everyElement(1));
  expect(
    choices.map((select) => select.arguments.single).toSet(),
    hasLength(20),
  );
  expect(
    selects.where((select) => select.sql.contains('FROM daily_choices')),
    hasLength(21),
  );
  final steps = _matching(
    selects,
    'FROM daily_choice_path_steps WHERE daily_choice_id = ?',
  );
  expect(steps, hasLength(20));
  expect(steps.fold<int>(0, (sum, select) => sum + select.rows), expectedSteps);
  expect(selects.indexOf(candidate), lessThan(selects.indexOf(choices.first)));
  expect(selects.indexOf(candidate), lessThan(selects.indexOf(steps.first)));
  final relations = selects.where(
    (select) =>
        select.sql.contains('FROM long_term_relations') &&
        select.sql.contains('WHERE id IN'),
  );
  expect(relations, hasLength(20));
  expect(
    relations.fold<int>(0, (sum, select) => sum + select.rows),
    expectedSteps,
  );
  expect(
    selects.where((select) => select.sql.contains('daily_choice_path_steps')),
    hasLength(20),
  );
  return candidate;
}

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = _Fixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  test('подсказки обоих направлений читают только двадцать кандидатов и целый длинный путь', () async {
    fixture.trace.clear();
    final topWatch = Stopwatch()..start();
    final top = (await fixture.repository.getChoicePathSuggestions(
      ChoicePathSuggestionsForSource(_intention(1)),
    ) as ChoicePathSuggestionsSuccess).value;
    topWatch.stop();
    expect(top.items, hasLength(2));
    expect(top.items.first.originChoiceId, durabilityChoice(10400));
    expect(top.items.first.path, hasLength(_pathLength));
    expect(top.items.last.originChoiceId, durabilityChoice(10399));
    expect(
      fixture.raw
          .select('SELECT COUNT(*) AS count FROM daily_choices')
          .single['count'],
      _catalogChoices + _otherGroupChoices,
    );
    final topCandidate = _boundedSuggestions(
      fixture.trace.selects,
      participantColumn: 'source_intention_id',
      participantId: _uuid(1),
      expectedSteps: _pathLength + 19,
    );
    final topPlan = fixture.plan(topCandidate).join(' | ');
    expect(topPlan, contains('daily_choices_source_recent'));

    fixture._addRelation(902, 1, 201);
    fixture._addChoice(12001, 1, 201, [902], stepBase: 33000);
    for (var number = 12002; number <= 12021; number++) {
      fixture._addChoice(number, 200, 201, [901], stepBase: number + 21000);
    }
    fixture.trace.clear();
    final bottomWatch = Stopwatch()..start();
    final bottom = (await fixture.repository.getChoicePathSuggestions(
      ChoicePathSuggestionsForAction(_intention(201)),
    ) as ChoicePathSuggestionsSuccess).value;
    bottomWatch.stop();
    expect(bottom.items, hasLength(1));
    expect(bottom.items.single.originChoiceId, durabilityChoice(12021));
    expect(
      fixture.raw.select(
        'SELECT long_term_relation_id FROM daily_choice_path_steps WHERE daily_choice_id = ?',
        [_uuid(12001)],
      ).single['long_term_relation_id'],
      _uuid(902),
    );
    final bottomCandidate = _boundedSuggestions(
      fixture.trace.selects,
      participantColumn: 'selected_intention_id',
      participantId: _uuid(201),
      expectedSteps: 20,
    );
    final bottomPlan = fixture.plan(bottomCandidate).join(' | ');
    expect(bottomPlan, contains('daily_choices_selected_recent'));
    expect(
      fixture.raw
          .select('SELECT COUNT(*) AS count FROM daily_choices')
          .single['count'],
      _catalogChoices + _otherGroupChoices + 21,
    );

    // ignore: avoid_print
    print(
      'Подсказки 4.3: история=${_catalogChoices + _otherGroupChoices + 21}, '
      'кандидатов=20, длина пути=$_pathLength; '
      'сверху=${topWatch.elapsedMicroseconds} мкс, '
      'снизу=${bottomWatch.elapsedMicroseconds} мкс; '
      'план сверху=$topPlan; план снизу=$bottomPlan',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('каталог и дневная группа читают только выбранные порции и пересобирают загруженную часть', () async {
    final catalogWatch = Stopwatch()..start();
    final first =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(pageSize: _pageSize),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    catalogWatch.stop();
    expect(first.totalCount, _catalogChoices + _otherGroupChoices);
    expect(first.items.first.id, durabilityChoice(10400));
    final firstSql = _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pathLength + _pageSize - 1,
      expectedCountReads: 1,
      group: false,
    );
    final catalogPlan = fixture.plan(firstSql).join(' | ');
    expect(catalogPlan, contains('daily_choices_date_creation_order'));
    final countPlan = fixture
        .plan(
          _matching(fixture.trace.selects, 'COUNT(*) AS total_count').single,
        )
        .join(' | ');
    expect(countPlan, contains('COVERING INDEX'));

    fixture.trace.clear();
    final catalogNextWatch = Stopwatch()..start();
    final second = (await fixture.repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(pageSize: _pageSize, cursor: first.nextCursor),
    ) as DailyChoiceCatalogPageSuccess).value;
    catalogNextWatch.stop();
    expect(second.items, hasLength(_pageSize));
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pageSize,
      expectedCountReads: 0,
      group: false,
    );

    fixture.trace.clear();
    final groupWatch = Stopwatch()..start();
    final source =
        (await fixture.repository.getRelationGroupPage(
              DailyChoiceGroupQuery(
                intentionId: _intention(1),
                role: DailyChoiceRelationRole.source,
                pageSize: _pageSize,
              ),
            ) as RelationGroupPageSuccess).value
            as DailyChoiceGroupFirstPage;
    groupWatch.stop();
    expect(source.counts.dailySource, _catalogChoices);
    expect(source.counts.dailySelected, 0);
    final groupSql = _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pathLength + _pageSize - 1,
      expectedCountReads: 0,
      group: true,
    );
    final groupPlan = fixture.plan(groupSql).join(' | ');
    expect(groupPlan, contains('daily_choices_source_date_creation_order'));
    final aggregates = _matching(
      fixture.trace.selects,
      'doable_relation_count_aggregates',
    );
    expect(aggregates, hasLength(1));
    expect(aggregates.single.rows, 1);
    final aggregatePlan = fixture.plan(aggregates.single).join(' | ');
    expect(aggregatePlan, contains('daily_choices_source_recent'));
    expect(aggregatePlan, contains('daily_choices_selected_recent'));

    fixture.trace.clear();
    final selected =
        (await fixture.repository.getRelationGroupPage(
              DailyChoiceGroupQuery(
                intentionId: _intention(201),
                role: DailyChoiceRelationRole.selected,
                pageSize: _pageSize,
              ),
            ) as RelationGroupPageSuccess).value
            as DailyChoiceGroupFirstPage;
    expect(selected.counts.dailySelected, _otherGroupChoices);
    final selectedSql = _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pageSize,
      expectedCountReads: 0,
      group: true,
    );
    final selectedPlan = fixture.plan(selectedSql).join(' | ');
    expect(
      selectedPlan,
      contains('daily_choices_selected_date_creation_order'),
    );

    fixture.trace.clear();
    final groupNextWatch = Stopwatch()..start();
    final sourceNext = (await fixture.repository.getRelationGroupPage(
      DailyChoiceGroupQuery(
        intentionId: _intention(1),
        role: DailyChoiceRelationRole.source,
        pageSize: _pageSize,
        cursor: source.nextCursor,
      ),
    ) as RelationGroupPageSuccess).value;
    groupNextWatch.stop();
    expect(sourceNext, isA<DailyChoiceGroupContinuationPage>());
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pageSize,
      expectedCountReads: 0,
      group: true,
    );

    expect(
      await fixture.repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(10399),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 1)),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    fixture.trace.clear();
    final rebuildWatch = Stopwatch()..start();
    final rebuilt =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(pageSize: _pageSize),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(rebuilt.items.first.id, durabilityChoice(10399));
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pathLength + _pageSize - 1,
      expectedCountReads: 1,
      group: false,
    );
    fixture.trace.clear();
    final rebuiltNext = (await fixture.repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(pageSize: _pageSize, cursor: rebuilt.nextCursor),
    ) as DailyChoiceCatalogPageSuccess).value;
    expect(rebuiltNext.items, hasLength(_pageSize));
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pageSize,
      expectedCountReads: 0,
      group: false,
    );
    fixture.trace.clear();
    final rebuiltGroup =
        (await fixture.repository.getRelationGroupPage(
              DailyChoiceGroupQuery(
                intentionId: _intention(1),
                role: DailyChoiceRelationRole.source,
                pageSize: _pageSize,
              ),
            ) as RelationGroupPageSuccess).value
            as DailyChoiceGroupFirstPage;
    expect(rebuiltGroup.items.first.id, durabilityChoice(10399));
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pathLength + _pageSize - 1,
      expectedCountReads: 0,
      group: true,
    );
    fixture.trace.clear();
    expect(
      ((await fixture.repository.getRelationGroupPage(
                DailyChoiceGroupQuery(
                  intentionId: _intention(1),
                  role: DailyChoiceRelationRole.source,
                  pageSize: _pageSize,
                  cursor: rebuiltGroup.nextCursor,
                ),
              ) as RelationGroupPageSuccess).value
              as DailyChoiceGroupContinuationPage)
          .items,
      hasLength(_pageSize),
    );
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pageSize,
      expectedCountReads: 0,
      group: true,
    );
    rebuildWatch.stop();

    // ignore: avoid_print
    print(
      'Чтения 2.27: каталог=${_catalogChoices + _otherGroupChoices}, '
      'дневная группа=$_catalogChoices, путь=$_pathLength, порция=$_pageSize; '
      'первая=${catalogWatch.elapsedMicroseconds} мкс, '
      'продолжение=${catalogNextWatch.elapsedMicroseconds} мкс, '
      'группа=${groupWatch.elapsedMicroseconds} мкс, '
      'продолжение группы=${groupNextWatch.elapsedMicroseconds} мкс, '
      'пересборка=${rebuildWatch.elapsedMicroseconds} мкс; '
      'план каталога=$catalogPlan; план счётчика=$countPlan; '
      'план группы=$groupPlan; план выбранной роли=$selectedPlan; '
      'план сводки=$aggregatePlan',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('длинный путь и достижимость измеряются отдельно от размера порции и ожидания команды', () async {
    fixture.trace.clear();
    final singlePageWatch = Stopwatch()..start();
    final single = (await fixture.repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(pageSize: 1),
    ) as DailyChoiceCatalogPageSuccess).value;
    singlePageWatch.stop();
    expect(single.items.single.id, durabilityChoice(10400));
    _boundedPage(
      fixture.trace.selects,
      expectedSteps: _pathLength,
      expectedCountReads: 1,
      group: false,
      pageSize: 1,
    );
    fixture.trace.clear();
    final detailWatch = Stopwatch()..start();
    expect(
      await fixture.repository.getDailyChoice(durabilityChoice(10400)),
      isA<DailyChoiceReadSuccess>(),
    );
    detailWatch.stop();
    final detailSteps = _matching(
      fixture.trace.selects,
      'FROM daily_choice_path_steps WHERE daily_choice_id = ?',
    );
    expect(detailSteps, hasLength(1));
    expect(detailSteps.single.rows, _pathLength);
    final stepPlan = fixture.plan(detailSteps.single).join(' | ');
    expect(stepPlan, contains('daily_choice_path_steps'));

    final draft = ChoicePathDraftStart(_intention(1));
    fixture.trace.clear();
    final reachabilityWatch = Stopwatch()..start();
    final continuations = (await fixture.repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(draft: draft, pageSize: 1),
    ) as ChoicePathContinuationSuccess).value;
    reachabilityWatch.stop();
    expect(continuations.items, hasLength(1));
    final reachability = _matching(fixture.trace.selects, 'WITH RECURSIVE');
    expect(reachability, hasLength(1));
    expect(reachability.single.rows, lessThanOrEqualTo(2));
    final reachabilityPlan = fixture.plan(reachability.single).join(' | ');
    expect(reachabilityPlan, contains('reachable'));

    expect(
      await fixture.repository.execute(
        CreateDailyChoice(
          sourceIntentionId: _intention(1),
          selectedIntentionId: _intention(2),
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: _relation(900),
              sourceIntentionId: _intention(1),
              type: LongTermRelationType.need,
              relatedIntentionId: _intention(2),
            ),
          ]),
          date: CalendarDate.fromParts(2026, 9, 25),
          description: null,
          isCompleted: false,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await fixture.repository.getDailyChoice(durabilityChoice(12000)),
      isA<DailyChoiceReadSuccess>(),
    );
    fixture.trace.blockNextReachability();
    final readWatch = Stopwatch()..start();
    final pendingRead = fixture.repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(draft: draft, pageSize: 1),
    );
    await fixture.trace.waitForReachability;
    var commandCompleted = false;
    final queueWatch = Stopwatch()..start();
    final command = fixture.repository
        .execute(EnableIntentionReadiness(_intention(150)))
        .whenComplete(() => commandCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(commandCompleted, isFalse);
    fixture.trace.releaseReachability();
    expect(await pendingRead, isA<ChoicePathContinuationSuccess>());
    readWatch.stop();
    expect(await command, isA<GraphCommandSucceeded>());
    queueWatch.stop();

    // ignore: avoid_print
    print(
      'Путь и достижимость 2.27: намерений=153, связей=298, '
      'выборов=${_catalogChoices + _otherGroupChoices + 1}, '
      'длина пути=$_pathLength, порция продолжений=1; '
      'одна строка каталога=${singlePageWatch.elapsedMicroseconds} мкс, '
      'подробности=${detailWatch.elapsedMicroseconds} мкс, '
      'достижимость=${reachabilityWatch.elapsedMicroseconds} мкс, '
      'чтение с барьером=${readWatch.elapsedMicroseconds} мкс, '
      'ожидание команды=${queueWatch.elapsedMicroseconds} мкс; '
      'план шагов=$stepPlan; план достижимости=$reachabilityPlan',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
