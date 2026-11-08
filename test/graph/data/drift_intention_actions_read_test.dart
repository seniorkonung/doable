import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';
import '../../support/intention_cascade_execution.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;

/// Отказывает чтению порции действий намерения, пока включён.
final class _IntentionActionsReadFailure
    extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM action_path_items')) {
      throw error;
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _IntentionActionsReadFailure readFailure;

  setUp(() async {
    readFailure = _IntentionActionsReadFailure();
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
      for (var number = 1; number <= 4; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
      seedRelation(raw, seedUuid(103), seedUuid(4), seedUuid(2));
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

  Future<IntentionActionsPage> read(
    int intention,
    IntentionActionRole role, {
    int pageSize = IntentionActionsQuery.defaultPageSize,
    IntentionActionsCursor? cursor,
  }) async => ((await repository.getIntentionActionsPage(
    IntentionActionsQuery(
      intentionId: _intention(intention),
      role: role,
      pageSize: pageSize,
      cursor: cursor,
    ),
  )) as IntentionActionsPageSuccess).value;

  List<ActionId> ids(IntentionActionsPage page) => [
    for (final item in page.items) item.id,
  ];

  (int, int, int, int) counts(IntentionActionsPage page) {
    final counts = (page as IntentionActionsFirstPage).counts;
    return (counts.root, counts.intermediate, counts.terminal, counts.total);
  }

  test('путь из одного намерения засчитывается корневым и конечным, а '
      'действие с намерением в пути считается один раз', () async {
    addAction(11, path: [1]);
    addAction(12, path: [1, 2, 3]);

    final root = await read(1, IntentionActionRole.root);
    final intermediate = await read(1, IntentionActionRole.intermediate);
    final terminal = await read(1, IntentionActionRole.terminal);

    expect(counts(root), (2, 0, 1, 2));
    expect(ids(root), [_action(12), _action(11)]);
    expect(ids(intermediate), isEmpty);
    expect(ids(terminal), [_action(11)]);
    for (final page in [intermediate, terminal]) {
      expect(counts(page), (2, 0, 1, 2));
      expect(page.revision.compareTo(root.revision), GraphRevisionOrder.same);
    }
  });

  test('роль определяется позицией намерения в пути каждого действия, '
      'а действия без намерения в пути не входят', () async {
    addAction(11, path: [1, 2, 3]);
    addAction(12, path: [4, 2]);
    addAction(13, path: [2, 3]);
    addAction(14, path: [1]);

    final root = await read(2, IntentionActionRole.root);
    final intermediate = await read(2, IntentionActionRole.intermediate);
    final terminal = await read(2, IntentionActionRole.terminal);

    expect(counts(root), (1, 1, 1, 3));
    expect(ids(root), [_action(13)]);
    expect(ids(intermediate), [_action(11)]);
    expect(ids(terminal), [_action(12)]);
  });

  test('строка несёт поля действия, корневое намерение и число намерений '
      'пути', () async {
    addAction(
      11,
      path: [4, 2, 3],
      hour: 18,
      priority: 2,
      isCompleted: true,
      description: 'Утром',
    );

    final page = await read(2, IntentionActionRole.intermediate);

    final item = page.items.single;
    expect(item.id, _action(11));
    expect(item.title, ActionTitle('Действие 11'));
    expect(item.description, ActionDescription.fromInput('Утром'));
    expect(item.date, CalendarDate.fromParts(2026, 10, 8));
    expect(item.schedule, ActionAtHour(18));
    expect(item.priority, ActionPriority.p2);
    expect(item.isCompleted, isTrue);
    expect(item.rootTitle, 'Намерение 4');
    expect(item.pathIntentionCount, 3);
  });

  test(
    'порции идут от поздней даты к ранней, затем от позднего часа к '
    '«Весь день», затем от новых к старым без повторов и пропусков',
    () async {
      addAction(11, date: '2026-09-20', hour: 7);
      addAction(12, date: '2026-10-12'); // весь день
      addAction(13, date: '2026-10-12', hour: 9);
      addAction(14, date: '2026-10-12', hour: 9); // новее 13
      addAction(15, date: '2026-10-12', hour: 0);
      addAction(16, date: '2025-08-03', hour: 23, priority: 1);
      addAction(17, date: '2026-10-08', isCompleted: true);
      addAction(18, date: '2026-10-08', path: [2, 3]); // другая роль

      final pages = <IntentionActionsPage>[];
      IntentionActionsCursor? cursor;
      do {
        final page = await read(
          1,
          IntentionActionRole.root,
          pageSize: 3,
          cursor: cursor,
        );
        pages.add(page);
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(pages.map((page) => page.items.length), [3, 3, 1]);
      expect(pages.first, isA<IntentionActionsFirstPage>());
      expect(
        pages.skip(1),
        everyElement(isA<IntentionActionsContinuationPage>()),
      );
      expect(pages.expand(ids), [
        for (final number in [14, 13, 15, 12, 17, 11, 16]) _action(number),
      ]);
      expect(counts(pages.first), (7, 0, 0, 7));
    },
  );

  test('порции корневых сливают путь из одного намерения с многозвенным '
      'путём без повторов и пропусков', () async {
    // Последовательность создания растёт в порядке добавления.
    addAction(32, path: [1, 2], date: '2026-10-12', hour: 9);
    addAction(31, path: [1], date: '2026-10-12', hour: 9);
    addAction(33, path: [1], date: '2026-10-12'); // весь день
    addAction(34, path: [1, 2, 3], date: '2026-10-10', hour: 20);
    addAction(36, path: [1, 2], date: '2026-10-10', hour: 7);
    addAction(35, path: [1], date: '2026-10-10', hour: 7); // новее 36
    addAction(37, path: [1], date: '2026-09-01', hour: 23);

    final first = await read(1, IntentionActionRole.root, pageSize: 3);
    final second = await read(
      1,
      IntentionActionRole.root,
      pageSize: 3,
      cursor: first.nextCursor,
    );
    final last = await read(
      1,
      IntentionActionRole.root,
      pageSize: 3,
      cursor: second.nextCursor,
    );

    // Границы порций — действие 33 из одного намерения и многозвенное 36.
    expect([first, second, last].map(ids), [
      [_action(31), _action(32), _action(33)],
      [_action(34), _action(35), _action(36)],
      [_action(37)],
    ]);
    expect(last.nextCursor, isNull);
  });

  test('архивное намерение читается так же, как активное', () async {
    addAction(11, path: [1, 2]);
    addAction(12, path: [4, 2, 3]);
    final active = await read(2, IntentionActionRole.terminal);
    expect(
      await repository.execute(
        await previewedArchiveIntention(repository, _intention(2)),
      ),
      isA<GraphCommandSucceeded>(),
    );

    final archived = await read(2, IntentionActionRole.terminal);

    expect(counts(archived), counts(active));
    expect(counts(archived), (0, 1, 1, 2));
    expect(ids(archived), [_action(11)]);
    expect(archived.items.single.rootTitle, 'Намерение 1');
  });

  test('продолжение после подтверждённого изменения отклоняется как '
      'устаревшее', () async {
    addAction(11);
    addAction(12);
    final first = await read(1, IntentionActionRole.root, pageSize: 1);
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

    final result = await repository.getIntentionActionsPage(
      IntentionActionsQuery(
        intentionId: _intention(1),
        role: IntentionActionRole.root,
        pageSize: 1,
        cursor: cursor,
      ),
    );

    expect(
      (result as IntentionActionsPageError).failure,
      isA<IntentionActionsSnapshotExpired>(),
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

    final result = await repository.getIntentionActionsPage(
      IntentionActionsQuery(
        intentionId: _intention(1),
        role: IntentionActionRole.root,
      ),
    );

    expect(
      (result as IntentionActionsPageError).failure,
      isA<IntentionActionsCorruptionFailure>(),
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
      IntentionActionsUnavailableFailure,
      'unavailable',
    ),
    (
      StateError('CANARY-причина'),
      IntentionActionsUnexpectedFailure,
      'unexpected',
    ),
  ]) {
    test('сбой чтения ($code) различим по категории, а диагностика не '
        'раскрывает данные', () async {
      addAction(11);
      readFailure.failure = error;

      final result = await repository.getIntentionActionsPage(
        IntentionActionsQuery(
          intentionId: _intention(1),
          role: IntentionActionRole.root,
        ),
      );
      readFailure.failure = null;

      expect(
        (result as IntentionActionsPageError).failure.runtimeType,
        failure,
      );
      expect(diagnostics.events, [
        {
          'operation': 'intentionActionsPageRead',
          'stage': 'read',
          'pageSize': IntentionActionsQuery.defaultPageSize,
          'isContinuation': false,
          'outcome': 'started',
        },
        {
          'operation': 'intentionActionsPageRead',
          'stage': 'read',
          'pageSize': IntentionActionsQuery.defaultPageSize,
          'isContinuation': false,
          'outcome': 'failed',
          'failureCode': code,
        },
      ]);
      expect(jsonEncode(diagnostics.events), isNot(contains('CANARY')));
      expect(jsonEncode(diagnostics.events), isNot(contains(seedUuid(1))));
    });
  }
}
