import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

/// Отказывает чтению порции дня, пока включён.
final class _ActionDayReadFailure extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM actions')) {
      throw error;
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _ActionDayReadFailure readFailure;
  final day = CalendarDate.fromParts(2026, 10, 8);

  setUp(() async {
    readFailure = _ActionDayReadFailure();
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        readFailure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7),
      diagnostics,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
    });
  });

  tearDown(() => database.close());

  void addAction(
    int number, {
    List<int> path = const [1, 2],
    String date = '2026-10-08',
    int? hour,
    int priority = 4,
    bool isCompleted = false,
    String? description,
  }) => seedRawGraph(
    raw,
    () => seedAction(
      raw,
      id: seedUuid(number),
      path: [for (final intention in path) seedUuid(intention)],
      title: 'Действие $number',
      description: description,
      date: date,
      hour: hour,
      priority: priority,
      isCompleted: isCompleted,
    ),
  );

  Future<ActionDayPage> read(
    CalendarDate date,
    ActionDaySection section, {
    int pageSize = ActionDayQuery.defaultPageSize,
    ActionDayCursor? cursor,
  }) async => ((await repository.getActionDayPage(
    ActionDayQuery(
      date: date,
      section: section,
      pageSize: pageSize,
      cursor: cursor,
    ),
  )) as ActionDayPageSuccess).value;

  List<ActionId> ids(ActionDayPage page) => [
    for (final item in page.items) item.id,
  ];

  test('секция идёт «Весь день», часами по возрастанию, приоритетом и '
      'порядком создания, а первая порция несёт числа обеих секций', () async {
    addAction(11, priority: 4); // весь день
    addAction(12, hour: 9, priority: 1);
    addAction(13, hour: 18, priority: 2);
    addAction(14, hour: 18, priority: 2); // новее 13
    addAction(15, hour: 18, priority: 1); // новее, но приоритетнее
    addAction(16, hour: 7, priority: 3, isCompleted: true);
    addAction(17, date: '2026-10-09');

    final incomplete =
        await read(day, ActionDaySection.incomplete) as ActionDayFirstPage;
    final completed =
        await read(day, ActionDaySection.completed) as ActionDayFirstPage;

    expect(ids(incomplete), [
      _action(11),
      _action(12),
      _action(15),
      _action(13),
      _action(14),
    ]);
    expect(ids(completed), [_action(16)]);
    for (final page in [incomplete, completed]) {
      expect(page.incompleteCount, 5);
      expect(page.completedCount, 1);
      expect(page.hasTimedActions, isTrue);
      expect(page.nextCursor, isNull);
    }
    expect(
      incomplete.revision.compareTo(completed.revision),
      GraphRevisionOrder.same,
    );
  });

  test('строка несёт поля действия, корневое намерение и число намерений '
      'пути без чтения самого пути', () async {
    addAction(11, path: [1, 2, 3], hour: 18, priority: 2, description: 'Утром');

    final page = await read(day, ActionDaySection.incomplete);

    final item = page.items.single;
    expect(item.id, _action(11));
    expect(item.title, ActionTitle('Действие 11'));
    expect(item.description, ActionDescription.fromInput('Утром'));
    expect(item.date, day);
    expect(item.schedule, ActionAtHour(18));
    expect(item.priority, ActionPriority.p2);
    expect(item.isCompleted, isFalse);
    expect(item.rootTitle, 'Намерение 1');
    expect(item.pathIntentionCount, 3);
  });

  test('название корня берётся из надгробия удалённого намерения, а у '
      'существующего — текущее', () async {
    addAction(11, path: [1, 2]);
    addAction(12, path: [2, 3]);
    seedRawGraph(raw, () {
      raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
        seedUuid(101),
      ]);
      raw.execute('DELETE FROM intentions WHERE id = ?', [seedUuid(1)]);
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        'Новое название',
        seedUuid(2),
      ]);
    });

    final page = await read(day, ActionDaySection.incomplete);

    expect(page.items.map((item) => item.rootTitle), [
      'Намерение 1',
      'Новое название',
    ]);
  });

  test('признак времени относится ко всему дню в обеих секциях, а пустой '
      'день даёт нули', () async {
    final allDay = CalendarDate.fromParts(2026, 10, 10);
    final timedElsewhere = CalendarDate.fromParts(2026, 10, 11);
    final empty = CalendarDate.fromParts(2026, 10, 12);
    addAction(11, date: '2026-10-10');
    addAction(12, date: '2026-10-10', isCompleted: true);
    addAction(13, date: '2026-10-11');
    addAction(14, date: '2026-10-11', hour: 0, isCompleted: true);

    final allDayPage =
        await read(allDay, ActionDaySection.incomplete) as ActionDayFirstPage;
    final timedPage = await read(
      timedElsewhere,
      ActionDaySection.incomplete,
    ) as ActionDayFirstPage;
    final emptyPage =
        await read(empty, ActionDaySection.incomplete) as ActionDayFirstPage;

    expect(allDayPage.hasTimedActions, isFalse);
    expect(timedPage.hasTimedActions, isTrue);
    expect(ids(timedPage), [_action(13)]);
    expect(emptyPage.items, isEmpty);
    expect((emptyPage.incompleteCount, emptyPage.completedCount), (0, 0));
    expect(emptyPage.hasTimedActions, isFalse);
  });

  test('продолжение отдаёт остаток секции порциями без повторов и пропусков '
      'и не берёт соседние дни и другую секцию', () async {
    addAction(11, priority: 4);
    addAction(12, hour: 9, priority: 2);
    addAction(13, hour: 9, priority: 2);
    addAction(14, hour: 9, priority: 1);
    addAction(15, hour: 18, priority: 3);
    addAction(16, hour: 18, priority: 3);
    addAction(17, hour: 23, priority: 1);
    addAction(21, date: '2026-10-07');
    addAction(22, date: '2026-10-09', hour: 9);
    addAction(23, hour: 9, priority: 1, isCompleted: true);

    final pages = <ActionDayPage>[];
    ActionDayCursor? cursor;
    do {
      final page = await read(
        day,
        ActionDaySection.incomplete,
        pageSize: 3,
        cursor: cursor,
      );
      pages.add(page);
      cursor = page.nextCursor;
    } while (cursor != null);

    expect(pages.map((page) => page.items.length), [3, 3, 1]);
    expect(pages.first, isA<ActionDayFirstPage>());
    expect(pages.skip(1), everyElement(isA<ActionDayContinuationPage>()));
    expect(pages.expand(ids), [
      for (final number in [11, 14, 12, 13, 15, 16, 17]) _action(number),
    ]);
    expect((pages.first as ActionDayFirstPage).incompleteCount, 7);
  });

  test('продолжение после подтверждённого изменения отклоняется как '
      'устаревшее', () async {
    addAction(11);
    addAction(12);
    final first = await read(day, ActionDaySection.incomplete, pageSize: 1);
    final cursor = first.nextCursor;
    expect(cursor, isNotNull);
    expect(
      await repository.execute(
        UpdateActionFields(
          actionId: _action(11),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );

    final result = await repository.getActionDayPage(
      ActionDayQuery(
        date: day,
        section: ActionDaySection.incomplete,
        pageSize: 1,
        cursor: cursor,
      ),
    );

    expect(
      (result as ActionDayPageError).failure,
      isA<ActionDaySnapshotExpired>(),
    );
    expect(diagnostics.events.last, containsPair('failureCode', 'conflict'));
  });

  test('повреждённая строка даёт отказ «повреждение»', () async {
    addAction(11);
    seedRawGraph(
      raw,
      () => raw.execute('UPDATE actions SET title = ? WHERE id = ?', [
        '  Пробежка  ',
        seedUuid(11),
      ]),
    );

    final result = await repository.getActionDayPage(
      ActionDayQuery(date: day, section: ActionDaySection.incomplete),
    );

    expect(
      (result as ActionDayPageError).failure,
      isA<ActionDayCorruptionFailure>(),
    );
  });

  for (final (error, failure, code) in <(Object, Type, String)>[
    (
      sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'CANARY-ошибка',
        causingStatement: 'CANARY-запрос',
        parametersToStatement: ['CANARY-название'],
      ),
      ActionDayUnavailableFailure,
      'unavailable',
    ),
    (StateError('CANARY-причина'), ActionDayUnexpectedFailure, 'unexpected'),
  ]) {
    test('сбой чтения ($code) различим по категории, а диагностика не '
        'раскрывает данные', () async {
      addAction(11);
      readFailure.failure = error;

      final result = await repository.getActionDayPage(
        ActionDayQuery(date: day, section: ActionDaySection.incomplete),
      );
      readFailure.failure = null;

      expect((result as ActionDayPageError).failure.runtimeType, failure);
      expect(diagnostics.events, [
        {
          'operation': 'actionDayPageRead',
          'stage': 'read',
          'pageSize': ActionDayQuery.defaultPageSize,
          'isContinuation': false,
          'outcome': 'started',
        },
        {
          'operation': 'actionDayPageRead',
          'stage': 'read',
          'pageSize': ActionDayQuery.defaultPageSize,
          'isContinuation': false,
          'outcome': 'failed',
          'failureCode': code,
        },
      ]);
      expect(jsonEncode(diagnostics.events), isNot(contains('CANARY')));
    });
  }
}
