import 'dart:convert';

import 'package:doable/src/action/application/path_candidates.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

/// Отказывает чтению кандидатов пути, пока включён.
final class _PathCandidatesReadFailure extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM long_term_relations')) {
      throw error;
    }
  }
}

ActionPath _draft(List<int> intentions) =>
    ActionPath([for (final number in intentions) seedIntentionId(number)]);

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _PathCandidatesReadFailure readFailure;

  setUp(() async {
    readFailure = _PathCandidatesReadFailure();
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
  });

  tearDown(() => database.close());

  void intention(int number, {bool archived = false}) => raw.execute(
    'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) '
    'VALUES (?, ?, ?, 1, 1)',
    [seedUuid(number), 'Намерение $number', archived ? 1 : 0],
  );

  // Порядок создания связей растёт в порядке вызовов.
  var relationNumber = 100;
  void relation(
    int source,
    int related, {
    LongTermRelationType type = LongTermRelationType.need,
    int priority = 4,
    bool archived = false,
  }) => raw.execute(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id, type, priority,
        is_archived, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, 1)''',
    [
      seedUuid(relationNumber++),
      seedUuid(source),
      seedUuid(related),
      type.name,
      priority,
      archived ? 1 : 0,
    ],
  );

  Future<PathCandidatesRead> read(
    List<int> draft, {
    LongTermRelationType half = LongTermRelationType.need,
    int pageSize = PathCandidatesQuery.defaultPageSize,
    PathCandidatesCursor? cursor,
  }) async => ((await repository.getPathCandidates(
    PathCandidatesQuery(
      draft: _draft(draft),
      half: half,
      pageSize: pageSize,
      cursor: cursor,
    ),
  )) as PathCandidatesSuccess).value;

  List<IntentionId> candidates(PathCandidatesRead page) => [
    for (final item in (page as PathCandidatesPage).items)
      item.relation.relatedIntentionId,
  ];

  test('участок идёт от корневого намерения до первого разрыва с текущими '
      'названиями, типами и приоритетами связей', () async {
    seedRawGraph(raw, () {
      for (var number = 1; number <= 5; number++) {
        intention(number);
      }
      relation(1, 2, priority: 2);
      relation(2, 3, type: LongTermRelationType.can, priority: 3);
      relation(3, 4, archived: true);
      relation(4, 5);
    });

    final page = await read([1, 2, 3, 4, 5]) as PathCandidatesFirstPage;

    expect(page.segment.root.title, 'Намерение 1');
    expect(
      [
        for (final step in page.segment.steps)
          (step.relation.type, step.relation.priority, step.intention.title),
      ],
      [
        (LongTermRelationType.need, RelationPriority.p2, 'Намерение 2'),
        (LongTermRelationType.can, RelationPriority.p3, 'Намерение 3'),
      ],
    );
  });

  test('связи нет между соседями черновика — участок заканчивается перед '
      'ней', () async {
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        intention(number);
      }
      relation(1, 2);
    });

    final page = await read([1, 2, 3]) as PathCandidatesFirstPage;

    expect(page.segment.last.id, seedIntentionId(2));
  });

  test(
    'архивное или удалённое корневое намерение даёт пустой участок',
    () async {
      seedRawGraph(raw, () {
        intention(1, archived: true);
        intention(2);
      });

      expect(await read([1, 2]), isA<EmptyPathSegment>());
      expect(await read([3, 2]), isA<EmptyPathSegment>());
    },
  );

  test('кандидаты — цели активных связей половины от последнего намерения '
      'участка без намерений участка, а числа обеих половин точные', () async {
    seedRawGraph(raw, () {
      for (var number = 1; number <= 9; number++) {
        intention(number, archived: number == 8);
      }
      relation(1, 2);
      relation(2, 3, archived: true);
      relation(2, 1); // обратно к корню участка
      relation(2, 4);
      relation(2, 5, archived: true);
      relation(2, 6, type: LongTermRelationType.can);
      relation(2, 7, type: LongTermRelationType.can);
      relation(2, 8, archived: true); // к архивному намерению
      relation(9, 2); // входящая
    });

    final need = await read([1, 2, 3]) as PathCandidatesFirstPage;
    final can = await read([1, 2, 3], half: LongTermRelationType.can);

    expect((need.counts.need, need.counts.can), (1, 2));
    expect(candidates(need), [seedIntentionId(4)]);
    expect(candidates(can), [seedIntentionId(6), seedIntentionId(7)]);
    expect(need.items.single.title, 'Намерение 4');
    expect(need.items.single.relation.sourceIntentionId, seedIntentionId(2));
  });

  test('пустая половина — успех с числом 0 и без кандидатов', () async {
    seedRawGraph(raw, () {
      intention(1);
      intention(2);
      relation(1, 2, type: LongTermRelationType.can);
    });

    final page = await read([1]) as PathCandidatesFirstPage;

    expect((page.counts.need, page.counts.can), (0, 1));
    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
  });

  test('порции идут по приоритету от P1 к P4, затем по порядку создания '
      'связей без повторов и пропусков', () async {
    seedRawGraph(raw, () {
      for (var number = 1; number <= 8; number++) {
        intention(number);
      }
      relation(1, 2, priority: 3);
      relation(1, 3, priority: 1);
      relation(1, 4, priority: 4);
      relation(1, 5, priority: 3);
      relation(1, 6, priority: 1);
      relation(1, 7, priority: 2);
      relation(1, 8, priority: 4);
    });

    final pages = <PathCandidatesRead>[];
    PathCandidatesCursor? cursor;
    do {
      final page = await read([1], pageSize: 3, cursor: cursor);
      pages.add(page);
      cursor = (page as PathCandidatesPage).nextCursor;
    } while (cursor != null);

    expect(pages.first, isA<PathCandidatesFirstPage>());
    expect(pages.skip(1), everyElement(isA<PathCandidatesContinuationPage>()));
    expect(pages.map((page) => candidates(page).length), [3, 3, 1]);
    expect(pages.expand(candidates), [
      for (final number in [3, 6, 7, 2, 5, 4, 8]) seedIntentionId(number),
    ]);
    for (final page in pages) {
      expect(
        page.revision.compareTo(pages.first.revision),
        GraphRevisionOrder.same,
      );
    }
  });

  test('продолжение после подтверждённого изменения отклоняется как '
      'устаревшее', () async {
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        intention(number);
      }
      relation(1, 2);
      relation(1, 3);
    });
    final first = await read([1], pageSize: 1) as PathCandidatesFirstPage;
    expect(
      await repository.execute(
        UpdateIntention(
          id: seedIntentionId(2),
          title: 'Другое',
          description: null,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );

    final result = await repository.getPathCandidates(
      PathCandidatesQuery(
        draft: _draft([1]),
        half: LongTermRelationType.need,
        pageSize: 1,
        cursor: first.nextCursor,
      ),
    );

    expect(
      (result as PathCandidatesError).failure,
      isA<PathCandidatesSnapshotExpired>(),
    );
    expect(diagnostics.events.last, containsPair('failureCode', 'conflict'));
  });

  test('повреждённое название кандидата даёт отказ «повреждение»', () async {
    seedRawGraph(raw, () {
      intention(1);
      intention(2);
      relation(1, 2);
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        '  Ходить  ',
        seedUuid(2),
      ]);
    });

    final result = await repository.getPathCandidates(
      PathCandidatesQuery(draft: _draft([1]), half: LongTermRelationType.need),
    );

    expect(
      (result as PathCandidatesError).failure,
      isA<PathCandidatesCorruptionFailure>(),
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
      PathCandidatesUnavailableFailure,
      'unavailable',
    ),
    (
      StateError('CANARY-причина'),
      PathCandidatesUnexpectedFailure,
      'unexpected',
    ),
  ]) {
    test('сбой чтения ($code) различим по категории, а диагностика не '
        'раскрывает данные', () async {
      seedRawGraph(raw, () => intention(1));
      readFailure.failure = error;

      final result = await repository.getPathCandidates(
        PathCandidatesQuery(
          draft: _draft([1]),
          half: LongTermRelationType.need,
        ),
      );
      readFailure.failure = null;

      expect((result as PathCandidatesError).failure.runtimeType, failure);
      expect(diagnostics.events, [
        {
          'operation': 'pathCandidatesRead',
          'stage': 'read',
          'pageSize': PathCandidatesQuery.defaultPageSize,
          'isContinuation': false,
          'outcome': 'started',
        },
        {
          'operation': 'pathCandidatesRead',
          'stage': 'read',
          'pageSize': PathCandidatesQuery.defaultPageSize,
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
