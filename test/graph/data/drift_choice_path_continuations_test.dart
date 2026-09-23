import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

final class _Fixture {
  late final sqlite.Database raw;
  late final AppDatabase database;
  late final DriftPersonalGraphRepository repository;
  final diagnostics = InMemoryDiagnosticsSink();

  Future<void> open({LocalDatabaseConnectionObserver? observer}) async {
    final connection = openInMemoryLocalDatabase(setup: (db) => raw = db);
    database = AppDatabase(
      observer == null
          ? connection
          : observeConfiguredLocalDatabaseConnection(connection, observer),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
  }

  Future<void> close() => database.close();

  void intention(int id, {bool ready = false, bool archived = false}) {
    raw.execute(
      '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, 1, 1)''',
      [_uuid(id), 'Намерение $id', ready ? 1 : 0, archived ? 1 : 0],
    );
  }

  void relation(
    int id,
    int source,
    int related, {
    String type = 'need',
    int priority = 2,
    bool archived = false,
  }) {
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          is_archived) VALUES (?, ?, ?, ?, ?, ?)''',
      [
        _uuid(id),
        _uuid(source),
        _uuid(related),
        type,
        priority,
        archived ? 1 : 0,
      ],
    );
  }

  ChoicePathDraftProgress progress(int source, List<(int, int, int)> steps) =>
      ChoicePathDraftProgress(_intention(source), [
        for (final (id, from, to) in steps)
          ConfirmedChoicePathStep(
            relationId: _relation(id),
            sourceIntentionId: _intention(from),
            type: LongTermRelationType.need,
            relatedIntentionId: _intention(to),
          ),
      ]);

  Future<ChoicePathContinuationsPage> page(
    ChoicePathDraft draft, {
    int pageSize = 50,
    ChoicePathContinuationCursor? cursor,
  }) async {
    final result = await repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(
        draft: draft,
        pageSize: pageSize,
        cursor: cursor,
      ),
    );
    expect(result, isA<ChoicePathContinuationSuccess>());
    return (result as ChoicePathContinuationSuccess).value;
  }
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  @override
  void record(DiagnosticsEvent event) => throw StateError('Сбой диагностики');
}

final class _ContinuationSelectTrace extends LocalDatabaseConnectionObserver {
  final selects = <_MeasuredSelect>[];
  final _started = <LocalDatabaseSqlStatement, Stopwatch>{};

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      _started[statement] = Stopwatch()..start();
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final stopwatch = _started.remove(statement)!..stop();
    selects.add(
      _MeasuredSelect(
        sql: statement.statements.single,
        arguments: statement.arguments,
        rowCount: rows.length,
        elapsed: stopwatch.elapsed,
      ),
    );
    return rows;
  }
}

final class _MeasuredSelect {
  const _MeasuredSelect({
    required this.sql,
    required this.arguments,
    required this.rowCount,
    required this.elapsed,
  });

  final String sql;
  final List<Object?> arguments;
  final int rowCount;
  final Duration elapsed;
}

final class _IsolateResponsivenessTrace
    extends LocalDatabaseConnectionObserver {
  bool _eventLoopAdvanced = false;
  bool? advancedBeforeReachabilityFinished;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.statements.single.contains('WITH RECURSIVE')) {
      Timer.run(() => _eventLoopAdvanced = true);
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (statement.statements.single.contains('WITH RECURSIVE')) {
      advancedBeforeReachabilityFinished = _eventLoopAdvanced;
    }
    return rows;
  }
}

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = _Fixture();
    await fixture.open();
  });

  tearDown(() => fixture.close());

  test('цикл, тупик и возврат в префикс исключаются из продолжений', () async {
    for (var id = 1; id <= 7; id++) {
      fixture.intention(id, ready: id == 5);
    }
    fixture.relation(101, 1, 2);
    fixture.relation(102, 2, 3);
    fixture.relation(103, 3, 1);
    fixture.relation(104, 2, 4);
    fixture.relation(105, 4, 1);
    fixture.relation(106, 2, 5);
    fixture.relation(107, 2, 6);
    fixture.relation(108, 6, 7);
    fixture.relation(109, 7, 6);

    final page = await fixture.page(fixture.progress(1, [(101, 1, 2)]));
    expect(page.items.map((item) => item.relation.id), [_relation(106)]);
    expect(page.canConfirm, isFalse);
    expect(page.current.id, _intention(2));
  });

  test('достигнутое действие можно подтвердить и продолжить', () async {
    fixture.intention(1, ready: true);
    fixture.intention(2, ready: true);
    fixture.intention(3, ready: true);
    fixture.relation(101, 1, 2);
    fixture.relation(102, 2, 3);

    final start = await fixture.page(ChoicePathDraftStart(_intention(1)));
    expect(start.canConfirm, isFalse);
    expect(start.items.single.relation.id, _relation(101));
    final middle = await fixture.page(fixture.progress(1, [(101, 1, 2)]));
    expect(middle.canConfirm, isTrue);
    expect(middle.items.single.relation.id, _relation(102));
    final end = await fixture.page(
      fixture.progress(1, [(101, 1, 2), (102, 2, 3)]),
    );
    expect(end.canConfirm, isTrue);
    expect(end.items, isEmpty);
  });

  test(
    'архивные участники и связи исключены, устаревший путь конфликтует',
    () async {
      fixture.intention(1);
      fixture.intention(2);
      fixture.intention(3, ready: true);
      fixture.intention(4, ready: true, archived: true);
      fixture.relation(101, 1, 2);
      fixture.relation(102, 2, 3, archived: true);
      fixture.relation(103, 2, 4, archived: true);
      expect(
        (await fixture.page(fixture.progress(1, [(101, 1, 2)]))).items,
        isEmpty,
      );
      fixture.raw.execute(
        'UPDATE long_term_relations SET is_archived = 0 WHERE id = ?',
        [_uuid(102)],
      );
      fixture.raw.execute(
        'UPDATE long_term_relations SET type = ? WHERE id = ?',
        ['can', _uuid(101)],
      );
      final result = await fixture.repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(draft: fixture.progress(1, [(101, 1, 2)])),
      );
      expect(result, isA<ChoicePathContinuationError>());
      expect(
        (result as ChoicePathContinuationError).failure,
        isA<ChoicePathContinuationSnapshotExpired>(),
      );
    },
  );

  test('страницы режутся после достижимости и сохраняют порядок', () async {
    fixture.intention(1);
    for (var id = 2; id <= 7; id++) {
      fixture.intention(id, ready: id == 7);
    }
    fixture.relation(101, 1, 2, priority: 1);
    fixture.relation(102, 1, 3, priority: 1);
    fixture.relation(103, 1, 4, type: 'can', priority: 1);
    fixture.relation(104, 1, 5, priority: 2);
    fixture.relation(105, 2, 7);
    fixture.relation(106, 4, 7);
    fixture.relation(107, 5, 6);
    fixture.relation(108, 6, 7);
    final draft = ChoicePathDraftStart(_intention(1));
    final first = await fixture.page(draft, pageSize: 1);
    expect(first.items.single.relation.id, _relation(101));
    final second = await fixture.page(
      draft,
      pageSize: 1,
      cursor: first.nextCursor,
    );
    expect(second.items.single.relation.id, _relation(104));
    final third = await fixture.page(
      draft,
      pageSize: 1,
      cursor: second.nextCursor,
    );
    expect(third.items.single.relation.id, _relation(103));
    expect(third.nextCursor, isNull);
  });

  test(
    'граница 100 строк оставляет последний переход следующей порции',
    () async {
      fixture.raw.execute('BEGIN');
      fixture.intention(1);
      for (var id = 2; id <= 102; id++) {
        fixture.intention(id, ready: true);
        fixture.relation(1000 + id, 1, id);
      }
      fixture.raw.execute('COMMIT');
      final draft = ChoicePathDraftStart(_intention(1));
      final first = await fixture.page(draft, pageSize: 100);
      expect(first.items, hasLength(100));
      expect(first.nextCursor, isNotNull);
      final last = await fixture.page(
        draft,
        pageSize: 100,
        cursor: first.nextCursor,
      );
      expect(last.items.single.relation.id, _relation(1102));
      expect(last.nextCursor, isNull);
    },
  );

  test(
    'чужой курсор и другая порция отклоняются, ошибка не становится тупиком',
    () async {
      fixture.intention(1);
      fixture.intention(2, ready: true);
      fixture.intention(3, ready: true);
      fixture.relation(101, 1, 2);
      fixture.relation(102, 1, 3);
      final draft = ChoicePathDraftStart(_intention(1));
      final first = await fixture.page(draft, pageSize: 1);
      final wrong = await fixture.repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(
          draft: draft,
          pageSize: 2,
          cursor: first.nextCursor,
        ),
      );
      expect(
        (wrong as ChoicePathContinuationError).failure,
        isA<ChoicePathContinuationValidationFailure>(),
      );
      final other = DriftPersonalGraphRepository(
        fixture.database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 23),
        fixture.diagnostics,
      );
      final foreign = await other.getChoicePathContinuations(
        ChoicePathContinuationQuery(
          draft: draft,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      );
      expect(
        (foreign as ChoicePathContinuationError).failure,
        isA<ChoicePathContinuationValidationFailure>(),
      );
      await fixture.database.close();
      final failed = await fixture.repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(draft: draft),
      );
      expect(failed, isA<ChoicePathContinuationError>());
      expect(
        fixture.diagnostics.events
            .whereType<ChoicePathContinuationReadDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsFailed>(),
      );
    },
  );

  test('изменение графа аннулирует следующую порцию', () async {
    for (var id = 1; id <= 4; id++) {
      fixture.intention(id, ready: id == 2 || id == 3);
    }
    fixture.relation(101, 1, 2);
    fixture.relation(102, 1, 3);
    final draft = ChoicePathDraftStart(_intention(1));
    final first = await fixture.page(draft, pageSize: 1);
    final mutation = await fixture.repository.execute(
      CreateLongTermRelation(
        sourceIntentionId: _intention(1),
        relatedIntentionId: _intention(4),
        type: LongTermRelationType.can,
        priority: RelationPriority.p1,
        description: null,
      ),
    );
    expect(mutation, isA<GraphCommandSucceeded>());
    final result = await fixture.repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(
        draft: draft,
        pageSize: 1,
        cursor: first.nextCursor,
      ),
    );
    expect(
      (result as ChoicePathContinuationError).failure,
      isA<ChoicePathContinuationSnapshotExpired>(),
    );
  });

  test(
    'длинная цепочка и большой цикл не ограничивают глубину поиска',
    () async {
      const length = 1100;
      fixture.raw.execute('BEGIN');
      for (var id = 1; id <= length + 1; id++) {
        fixture.intention(id, ready: id == length + 1);
      }
      for (var id = 1; id <= length; id++) {
        fixture.relation(2000 + id, id, id + 1);
      }
      fixture.relation(5000, length + 1, 1);
      fixture.raw.execute('COMMIT');

      final stopwatch = Stopwatch()..start();
      final page = await fixture.page(ChoicePathDraftStart(_intention(1)));
      stopwatch.stop();
      expect(page.items.map((item) => item.relation.id), [_relation(2001)]);
      final deepDraft = fixture.progress(1, [
        for (var id = 1; id < length; id++) (2000 + id, id, id + 1),
      ]);
      final deepPage = await fixture.page(deepDraft);
      expect(deepPage.items.single.relation.id, _relation(2000 + length));
      expect(
        fixture.diagnostics.events
            .whereType<ChoicePathContinuationReadDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsSucceeded>(),
      );
      // Время выводится для наблюдения стоимости без нестабильного порога.
      // ignore: avoid_print
      print('Продолжения: цикл $length, ${stopwatch.elapsedMilliseconds} мс');
    },
  );

  test('большой разветвлённый граф сохраняет ветви при разных порциях и измеряет ожидание команды', () async {
    await fixture.close();
    final trace = _ContinuationSelectTrace();
    fixture = _Fixture();
    await fixture.open(observer: trace);

    fixture.raw.execute('BEGIN');
    for (var node = 1; node <= 1900; node++) {
      fixture.intention(node, ready: node == 1800);
    }
    for (var node = 2; node <= 121; node++) {
      fixture.relation(10000 + node, 1, node);
    }
    for (var node = 2; node < 1800; node++) {
      fixture.relation(20000 + node, node, node + 1);
      if (node + 7 <= 1800) {
        fixture.relation(30000 + node, node, node + 7);
      }
      if (node + 37 <= 1800) {
        fixture.relation(40000 + node, node, node + 37);
      }
    }
    fixture.relation(10999, 1, 1801);
    for (var node = 1801; node <= 1900; node++) {
      fixture.relation(50000 + node, node, node == 1900 ? 1801 : node + 1);
    }
    fixture.raw.execute('COMMIT');

    final draft = ChoicePathDraftStart(_intention(1));
    Future<(List<LongTermRelationId>, Duration)> collect(int pageSize) async {
      final stopwatch = Stopwatch()..start();
      final ids = <LongTermRelationId>[];
      ChoicePathContinuationCursor? cursor;
      do {
        final page = await fixture.page(
          draft,
          pageSize: pageSize,
          cursor: cursor,
        );
        ids.addAll(page.items.map((item) => item.relation.id));
        cursor = page.nextCursor;
      } while (cursor != null);
      stopwatch.stop();
      return (ids, stopwatch.elapsed);
    }

    trace.selects.clear();
    final (smallPageIds, smallPageTime) = await collect(7);
    final smallPageSelects = List<_MeasuredSelect>.of(trace.selects);
    trace.selects.clear();
    final (largePageIds, largePageTime) = await collect(100);
    final largePageSelects = List<_MeasuredSelect>.of(trace.selects);

    expect(smallPageIds, largePageIds);
    expect(largePageIds, [
      for (var node = 2; node <= 121; node++) _relation(10000 + node),
    ]);
    expect(
      [
        ...smallPageSelects,
        ...largePageSelects,
      ].map((select) => select.rowCount),
      everyElement(lessThanOrEqualTo(101)),
    );
    final reachabilitySelects = largePageSelects.where(
      (select) => select.sql.contains('WITH RECURSIVE'),
    );
    expect(reachabilitySelects, hasLength(2));
    expect(reachabilitySelects.map((select) => select.rowCount), [101, 20]);
    final plan = fixture.raw.select(
      'EXPLAIN QUERY PLAN ${reachabilitySelects.first.sql}',
      reachabilitySelects.first.arguments,
    );
    expect(
      plan.map((row) => row['detail'].toString()).join(' '),
      contains('reachable'),
    );

    final readWatch = Stopwatch()..start();
    final pendingRead = fixture.page(draft, pageSize: 1);
    final queuedCommandWatch = Stopwatch()..start();
    final pendingCommand = fixture.repository.execute(
      EnableIntentionReadiness(_intention(1850)),
    );
    await pendingRead;
    readWatch.stop();
    expect(await pendingCommand, isA<GraphCommandSucceeded>());
    queuedCommandWatch.stop();
    final singleCommandWatch = Stopwatch()..start();
    expect(
      await fixture.repository.execute(
        EnableIntentionReadiness(_intention(1851)),
      ),
      isA<GraphCommandSucceeded>(),
    );
    singleCommandWatch.stop();

    final sqliteVersion = fixture.raw
        .select('SELECT sqlite_version()')
        .single['sqlite_version()'];
    // Измерения информируют о стоимости; пороги времени зависят от машины.
    // ignore: avoid_print
    print(
      'Продолжения: 1900 намерений, 5573 связи, SQLite $sqliteVersion; '
      'порция 7: ${smallPageTime.inMicroseconds} мкс / 18 страниц, '
      'порция 100: ${largePageTime.inMicroseconds} мкс / 2 страницы; '
      'запросы достижимости: '
      '${reachabilitySelects.map((select) => select.elapsed.inMicroseconds).toList()} мкс; '
      'чтение перед командой: ${readWatch.elapsedMicroseconds} мкс, '
      'команда в очереди: ${queuedCommandWatch.elapsedMicroseconds} мкс, '
      'отдельная команда: ${singleCommandWatch.elapsedMicroseconds} мкс',
    );
    // ignore: avoid_print
    print('План достижимости: ${plan.map((row) => row['detail']).join(' | ')}');
  });

  test('изолятное соединение не удерживает цикл событий во время поиска', () async {
    await fixture.close();
    final isolate = await spawnConfiguredInMemoryLocalDatabaseIsolate();
    final trace = _IsolateResponsivenessTrace();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(await isolate.connect(), trace),
    );
    try {
      await database.open();
      await database.customStatement('''
        WITH RECURSIVE ids(n) AS (
          VALUES(1) UNION ALL SELECT n + 1 FROM ids WHERE n < 4000
        )
        INSERT INTO intentions
          (id, title, is_action_ready, is_archived, created_at, updated_at)
        SELECT printf('018f0b5d-6b2e-7c80-8000-%012x', n),
               'Намерение', n = 4000, 0, 1, 1 FROM ids
      ''');
      for (final (offset, idBase) in [(1, 10000), (7, 20000), (37, 30000)]) {
        await database.customStatement('''
          WITH RECURSIVE ids(n) AS (
            VALUES(1) UNION ALL SELECT n + 1 FROM ids WHERE n < ${4000 - offset}
          )
          INSERT INTO long_term_relations
            (id, source_intention_id, related_intention_id, type, priority,
             is_archived)
          SELECT printf('018f0b5d-6b2e-7c80-8000-%012x', $idBase + n),
                 printf('018f0b5d-6b2e-7c80-8000-%012x', n),
                 printf('018f0b5d-6b2e-7c80-8000-%012x', n + $offset),
                 'need', 2, 0 FROM ids
        ''');
      }
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 23),
        InMemoryDiagnosticsSink(),
      );
      final stopwatch = Stopwatch()..start();
      final result = await repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(draft: ChoicePathDraftStart(_intention(1))),
      );
      stopwatch.stop();
      expect(result, isA<ChoicePathContinuationSuccess>());
      expect(
        (result as ChoicePathContinuationSuccess).value.items,
        hasLength(3),
      );
      expect(trace.advancedBeforeReachabilityFinished, isTrue);
      // ignore: avoid_print
      print(
        'Изолятное чтение: 4000 намерений, 11955 связей, '
        '${stopwatch.elapsedMicroseconds} мкс; цикл событий обслужен до ответа',
      );
    } finally {
      await database.close();
      await isolate.shutdownAll();
    }
  });

  test('малые графы совпадают с независимым перебором простых путей', () async {
    for (var seed = 0; seed < 12; seed++) {
      final base = 100 + seed * 10;
      final ready = <int>{base + 5, if (seed.isEven) base + 7};
      for (var node = 1; node <= 7; node++) {
        fixture.intention(base + node, ready: ready.contains(base + node));
      }
      final edges = <int, List<int>>{};
      fixture.relation(6000 + seed * 100, base + 1, base + 2);
      edges[base + 1] = [base + 2];
      for (var from = 2; from <= 7; from++) {
        for (var to = 1; to <= 7; to++) {
          if (from == to || (from * 17 + to * 11 + seed) % 4 == 0) {
            continue;
          }
          final source = base + from;
          final related = base + to;
          fixture.relation(6000 + seed * 100 + from * 10 + to, source, related);
          edges.putIfAbsent(source, () => []).add(related);
        }
      }
      bool reachesAction(int node, Set<int> visited) {
        if (!visited.add(node)) return false;
        if (ready.contains(node)) return true;
        for (final next in edges[node] ?? const <int>[]) {
          if (reachesAction(next, {...visited})) return true;
        }
        return false;
      }

      final expected = {
        for (final next in edges[base + 2] ?? const <int>[])
          if (reachesAction(next, {base + 1, base + 2})) _intention(next),
      };
      final page = await fixture.page(
        fixture.progress(base + 1, [(6000 + seed * 100, base + 1, base + 2)]),
      );
      expect(
        page.items.map((item) => item.related.id).toSet(),
        expected,
        reason: 'граф $seed',
      );
    }
  });

  test('отсутствующий конец и архивный префикс различаются', () async {
    fixture.intention(1);
    final absent = await fixture.repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(draft: ChoicePathDraftStart(_intention(2))),
    );
    expect(
      (absent as ChoicePathContinuationError).failure,
      isA<ChoicePathContinuationIntentionNotFoundFailure>(),
    );
    fixture.intention(2);
    fixture.relation(101, 1, 2);
    fixture.raw.execute(
      'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
      [_uuid(101)],
    );
    fixture.raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
      _uuid(1),
    ]);
    final stale = await fixture.repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(draft: fixture.progress(1, [(101, 1, 2)])),
    );
    expect(
      (stale as ChoicePathContinuationError).failure,
      isA<ChoicePathContinuationSnapshotExpired>(),
    );
  });

  test('сбой диагностики не меняет результат чтения', () async {
    fixture.intention(1);
    fixture.intention(2, ready: true);
    fixture.relation(101, 1, 2);
    final repository = DriftPersonalGraphRepository(
      fixture.database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      _ThrowingDiagnosticsSink(),
    );
    final result = await repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(draft: ChoicePathDraftStart(_intention(1))),
    );
    expect(result, isA<ChoicePathContinuationSuccess>());
    expect((result as ChoicePathContinuationSuccess).value.items, hasLength(1));
  });
}
