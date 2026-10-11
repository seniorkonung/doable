@Tags(['slow'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
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

/// Самый длинный путь вместе с его участниками.
const _pathWithParticipants = _pathLength + 1;

String _uuid(int number) => durabilityUuid(number);

IntentionId _intention(int number) => durabilityIntention(number);

LongTermRelationId _relation(int number) => durabilityRelation(number);

/// Запоминает число строк, которое вернуло каждое чтение.
final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final rowCounts = <int>[];

  void clear() => rowCounts.clear();

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    rowCounts.add(rows.length);
    return rows;
  }
}

final class _Fixture {
  _Fixture({this.file});

  final File? file;
  final trace = _ReadTrace();
  late final List<int> bootstrapRowCounts;
  late final sqlite.Database raw;
  late final AppDatabase database;
  late final DriftPersonalGraphRepository repository;
  bool _closed = false;

  Future<void> open({bool seed = true}) async {
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        file == null
            ? openInMemoryLocalDatabase(setup: (connection) => raw = connection)
            : openFileBackedLocalDatabase(
                file!,
                setup: (connection) => raw = connection,
              ),
        trace,
      ),
    );
    await database.open();
    bootstrapRowCounts = List.of(trace.rowCounts);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 24),
      InMemoryDiagnosticsSink(),
      dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(12000)),
      choicePathStepIdGenerator: SequentialStepIds(32000),
    );
    if (!seed) {
      trace.clear();
      return;
    }
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await database.close();
  }

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
    String date = '2026-09-24',
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed) VALUES (?, ?, ?, ?, NULL, 0)''',
      [_uuid(id), _uuid(source), _uuid(selected), date],
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
}

/// Ни одно чтение не возвращает больше [rows] строк: выдача ограничена
/// показанными записями, а не всей историей.
void _expectEachReadAtMost(_ReadTrace trace, int rows) {
  expect(trace.rowCounts, isNotEmpty);
  expect(trace.rowCounts, everyElement(lessThanOrEqualTo(rows)));
}

/// Порция из [pageSize] записей читает не больше строк, чем занимают её
/// записи и шаги их путей ([pageSteps]), и один лишний признак продолжения.
void _expectBoundedPage(
  _ReadTrace trace, {
  required int pageSteps,
  required int pageSize,
}) => _expectEachReadAtMost(trace, max(pageSteps, pageSize + 1));

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = _Fixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  test('сохранение и замена длинным путём ограничивают объём чтения', () async {
    final longPath = ConfirmedChoicePath([
      ConfirmedChoicePathStep(
        relationId: _relation(900),
        sourceIntentionId: _intention(1),
        type: LongTermRelationType.need,
        relatedIntentionId: _intention(2),
      ),
      for (var node = 2; node <= _pathLength; node++)
        ConfirmedChoicePathStep(
          relationId: _relation(1000 + node),
          sourceIntentionId: _intention(node),
          type: LongTermRelationType.need,
          relatedIntentionId: _intention(node + 1),
        ),
    ]);
    fixture.trace.clear();
    expect(
      await fixture.repository.execute(
        CreateDailyChoice(
          sourceIntentionId: _intention(1),
          selectedIntentionId: _intention(151),
          path: longPath,
          date: CalendarDate.fromParts(2026, 9, 25),
          description: null,
          isCompleted: false,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    final created = await fixture.repository.getDailyChoice(
      durabilityChoice(12000),
    );
    expect(created, isA<DailyChoiceReadSuccess>());
    expect(
      (created as DailyChoiceReadSuccess).value.value!.path.map(
        (step) => step.relation.id,
      ),
      longPath.steps.map((step) => step.relationId),
    );
    // Создание и чтение читают не больше одного пути вместе с его
    // участниками.
    _expectEachReadAtMost(fixture.trace, _pathWithParticipants);

    fixture.trace.clear();
    expect(
      await fixture.repository.execute(
        ReplaceDailyChoicePath(
          choiceId: durabilityChoice(10399),
          sourceIntentionId: _intention(1),
          selectedIntentionId: _intention(151),
          path: longPath,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    final replaced = await fixture.repository.getDailyChoice(
      durabilityChoice(10399),
    );
    expect(replaced, isA<DailyChoiceReadSuccess>());
    expect(
      (replaced as DailyChoiceReadSuccess).value.value!.path.map(
        (step) => step.relation.id,
      ),
      longPath.steps.map((step) => step.relationId),
    );
    _expectEachReadAtMost(fixture.trace, _pathWithParticipants);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'повторный bootstrap большой истории не читает сохранённые пути',
    () async {
      await fixture.close();
      final directory = await Directory.systemTemp.createTemp(
        'doable-choice-cost-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/choices.sqlite');
      final seeded = _Fixture(file: file);
      await seeded.open();
      await seeded.close();

      final reopened = _Fixture(file: file);
      await reopened.open(seed: false);
      addTearDown(reopened.close);
      expect(
        reopened.raw
            .select('SELECT COUNT(*) AS count FROM daily_choices')
            .single['count'],
        _catalogChoices + _otherGroupChoices,
      );
      // Чтение истории при запуске вернуло бы сотни строк выборов и шагов.
      expect(
        reopened.bootstrapRowCounts.fold<int>(0, (sum, rows) => sum + rows),
        lessThan(_pageSize),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'долгий SQLite запрос на рабочем isolate не останавливает цикл UI',
    () async {
      await fixture.close();
      final worker = await spawnConfiguredInMemoryLocalDatabaseIsolate();
      final database = AppDatabase(await worker.connect());
      try {
        await database.open();
        var ticks = 0;
        final timer = Timer.periodic(
          const Duration(milliseconds: 1),
          (_) => ticks++,
        );
        final result = await database.customSelect('''
        WITH RECURSIVE counter(value) AS (
          SELECT 1 UNION ALL SELECT value + 1 FROM counter WHERE value < 500000
        ) SELECT COUNT(*) AS total FROM counter
      ''').getSingle();
        timer.cancel();
        expect(result.read<int>('total'), 500000);
        expect(ticks, greaterThan(0));
      } finally {
        await database.close();
        await worker.shutdownAll();
      }
    },
  );

  test('каталог и дневная группа читают только выбранные порции и пересобирают загруженную часть', () async {
    const firstPageSteps = _pathLength + _pageSize - 1;
    final first =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(pageSize: _pageSize),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(first.totalCount, _catalogChoices + _otherGroupChoices);
    expect(first.items.first.id, durabilityChoice(10400));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: firstPageSteps,
      pageSize: _pageSize,
    );

    fixture.trace.clear();
    final second = (await fixture.repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(pageSize: _pageSize, cursor: first.nextCursor),
    ) as DailyChoiceCatalogPageSuccess).value;
    expect(second.items, hasLength(_pageSize));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pageSize,
      pageSize: _pageSize,
    );

    fixture.trace.clear();
    final source =
        (await fixture.repository.getRelationGroupPage(
              DailyChoiceGroupQuery(
                intentionId: _intention(1),
                role: DailyChoiceRelationRole.source,
                pageSize: _pageSize,
              ),
            ) as RelationGroupPageSuccess).value
            as DailyChoiceGroupFirstPage;
    expect(source.counts.dailySource, _catalogChoices);
    expect(source.counts.dailySelected, 0);
    _expectBoundedPage(
      fixture.trace,
      pageSteps: firstPageSteps,
      pageSize: _pageSize,
    );

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
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pageSize,
      pageSize: _pageSize,
    );

    fixture.trace.clear();
    final sourceNext = (await fixture.repository.getRelationGroupPage(
      DailyChoiceGroupQuery(
        intentionId: _intention(1),
        role: DailyChoiceRelationRole.source,
        pageSize: _pageSize,
        cursor: source.nextCursor,
      ),
    ) as RelationGroupPageSuccess).value;
    expect(sourceNext, isA<DailyChoiceGroupContinuationPage>());
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pageSize,
      pageSize: _pageSize,
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
    final rebuilt =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(pageSize: _pageSize),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(rebuilt.items.first.id, durabilityChoice(10399));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: firstPageSteps,
      pageSize: _pageSize,
    );
    fixture.trace.clear();
    final rebuiltNext = (await fixture.repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(pageSize: _pageSize, cursor: rebuilt.nextCursor),
    ) as DailyChoiceCatalogPageSuccess).value;
    expect(rebuiltNext.items, hasLength(_pageSize));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pageSize,
      pageSize: _pageSize,
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
    _expectBoundedPage(
      fixture.trace,
      pageSteps: firstPageSteps,
      pageSize: _pageSize,
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
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pageSize,
      pageSize: _pageSize,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('каталог одного дня читает только этот день порциями по 50', () async {
    // Сотни записей соседних дней созданы после записей выбранного дня.
    fixture.raw.execute('BEGIN');
    for (var number = 40000; number < 40300; number++) {
      fixture._addChoice(
        number,
        1,
        2,
        [900],
        stepBase: number + 10000,
        date: '2026-09-23',
      );
      fixture._addChoice(
        number + 1000,
        1,
        2,
        [900],
        stepBase: number + 11000,
        date: '2026-09-25',
      );
    }
    fixture.raw.execute('COMMIT');
    final day = CalendarDate.fromParts(2026, 9, 24);
    const dayChoices = _catalogChoices + _otherGroupChoices;
    const pageSize = DailyChoiceCatalogQuery.defaultPageSize;

    fixture.trace.clear();
    final first =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(date: day),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(first.totalCount, dayChoices);
    expect(first.items, hasLength(pageSize));
    expect(first.items.first.id, durabilityChoice(10400));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pathLength + pageSize - 1,
      pageSize: pageSize,
    );

    // Продолжения проходят весь день без строк соседних дней.
    final ids = {for (final item in first.items) item.id};
    var cursor = first.nextCursor;
    var continuations = 0;
    while (cursor != null) {
      fixture.trace.clear();
      final next = (await fixture.repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(date: day, cursor: cursor),
      ) as DailyChoiceCatalogPageSuccess).value;
      expect(next, isA<DailyChoiceCatalogContinuationPage>());
      expect(next.items.map((item) => item.date), everyElement(day));
      _expectBoundedPage(
        fixture.trace,
        pageSteps: next.items.length,
        pageSize: next.items.length,
      );
      ids.addAll(next.items.map((item) => item.id));
      cursor = next.nextCursor;
      continuations++;
    }
    expect(continuations, (dayChoices - 1) ~/ pageSize);
    expect(ids, hasLength(dayChoices));

    // Охват выполнения остаётся внутри выбранного дня.
    fixture.raw.execute(
      'UPDATE daily_choices SET is_completed = 1 WHERE source_intention_id = ?',
      [_uuid(200)],
    );
    fixture.trace.clear();
    final completed =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(date: day, isCompleted: true),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(completed.totalCount, _otherGroupChoices);
    expect(completed.items.map((item) => item.isCompleted), everyElement(true));
    _expectBoundedPage(fixture.trace, pageSteps: pageSize, pageSize: pageSize);

    // Перенос записи меняет количество обоих дней, а пересборка снова
    // читает только первую порцию выбранного дня.
    expect(
      await fixture.repository.execute(
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(10399),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 9, 25)),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    fixture.trace.clear();
    final rebuilt =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(date: day),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(rebuilt.totalCount, dayChoices - 1);
    expect(rebuilt.items.first.id, durabilityChoice(10400));
    expect(rebuilt.items[1].id, durabilityChoice(10398));
    _expectBoundedPage(
      fixture.trace,
      pageSteps: _pathLength + pageSize - 1,
      pageSize: pageSize,
    );
    fixture.trace.clear();
    final nextDay =
        (await fixture.repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(
                date: CalendarDate.fromParts(2026, 9, 25),
              ),
            ) as DailyChoiceCatalogPageSuccess).value
            as DailyChoiceCatalogFirstPage;
    expect(nextDay.totalCount, 301);
    _expectBoundedPage(fixture.trace, pageSteps: pageSize, pageSize: pageSize);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'длинный путь и достижимость читаются отдельно от размера порции',
    () async {
      fixture.trace.clear();
      final single = (await fixture.repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(pageSize: 1),
      ) as DailyChoiceCatalogPageSuccess).value;
      expect(single.items.single.id, durabilityChoice(10400));
      _expectBoundedPage(fixture.trace, pageSteps: _pathLength, pageSize: 1);

      final detail = await fixture.repository.getDailyChoice(
        durabilityChoice(10400),
      );
      expect(
        (detail as DailyChoiceReadSuccess).value.value!.path,
        hasLength(_pathLength),
      );

      final draft = ChoicePathDraftStart(_intention(1));
      fixture.trace.clear();
      final continuations =
          (await fixture.repository.getChoicePathContinuations(
            ChoicePathContinuationQuery(draft: draft, pageSize: 1),
          ) as ChoicePathContinuationSuccess).value;
      expect(continuations.items, hasLength(1));
      _expectEachReadAtMost(fixture.trace, 2);

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
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
