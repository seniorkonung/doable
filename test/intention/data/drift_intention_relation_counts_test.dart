import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 19),
      diagnostics,
    );
  });

  tearDown(() => database.close());

  test(
    'возвращает самостоятельную точную сводку существующего намерения',
    () async {
      final owner = _id(_uuid(1));
      final neighbors = [
        for (var index = 2; index <= 9; index++) _id(_uuid(index)),
      ];
      for (final id in [owner, ...neighbors]) {
        await _insertIntention(database, id);
      }
      await _insertAllGroups(database, owner, neighbors);

      final result = await repository.getRelationCounts(owner);

      expect(result, isA<ResultSuccess<GraphSnapshot<RelationCounts>>>());
      final snapshot =
          (result as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
      expect(snapshot.value.total, 8);
      expect([
        snapshot.value.activeNeedIncoming,
        snapshot.value.activeNeedOutgoing,
        snapshot.value.activeCanIncoming,
        snapshot.value.activeCanOutgoing,
        snapshot.value.archivedNeedIncoming,
        snapshot.value.archivedNeedOutgoing,
        snapshot.value.archivedCanIncoming,
        snapshot.value.archivedCanOutgoing,
      ], everyElement(1));
      expect(diagnostics.events, [
        isA<RelationCountsReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsStarted>(),
        ),
        isA<RelationCountsReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsSucceeded>(),
        ),
      ]);
    },
  );

  test('отличает отсутствующее намерение от подтверждённого нуля', () async {
    final existing = _id(_uuid(20));
    await _insertIntention(database, existing);

    final existingResult = await repository.getRelationCounts(existing);
    final missingResult = await repository.getRelationCounts(_id(_uuid(21)));

    expect(
      (existingResult as ResultSuccess<GraphSnapshot<RelationCounts>>)
          .value
          .value
          .total,
      0,
    );
    expect(
      missingResult,
      isA<ResultFailure<GraphSnapshot<RelationCounts>>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionNotFoundFailure>(),
      ),
    );
  });

  test('наблюдает подробные поля и сводку на одной ревизии', () async {
    final owner = _id(_uuid(30));
    final neighbor = _id(_uuid(31));
    await _insertIntention(database, owner, title: 'Владелец');
    await _insertIntention(database, neighbor, title: 'Сосед');
    await _insertRelation(
      database,
      id: _uuid(130),
      sourceId: owner,
      relatedId: neighbor,
      type: 'need',
      isArchived: false,
    );

    final result = await repository.watchIntention(owner).first;

    expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
    final snapshot =
        (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;
    expect(snapshot.value?.intention.title, 'Владелец');
    expect(snapshot.value?.relationCounts.activeNeedOutgoing, 1);
    expect(snapshot.value?.activeRelationCount, 1);
  });

  test(
    'пакетно возвращает активные количества только для порции каталога',
    () async {
      final trace = _SelectTrace();
      await database.close();
      database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          trace,
        ),
      );
      await database.open();
      repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 19),
        diagnostics,
      );
      final owners = [_id(_uuid(40)), _id(_uuid(41))];
      final hiddenNeighbors = [_id(_uuid(42)), _id(_uuid(43))];
      for (var index = 0; index < owners.length; index++) {
        await _insertIntention(
          database,
          owners[index],
          title: 'Видимое ${index + 1}',
        );
        await _insertIntention(
          database,
          hiddenNeighbors[index],
          title: 'Скрытый сосед ${index + 1}',
        );
        await _insertRelation(
          database,
          id: _uuid(140 + index),
          sourceId: owners[index],
          relatedId: hiddenNeighbors[index],
          type: 'need',
          isArchived: false,
        );
      }
      trace.statements.clear();

      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: 'Видимое',
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 2,
        ),
      );

      final page =
          (result as ResultSuccess<IntentionCatalogPage>).value
              as IntentionCatalogFirstPage;
      expect(page.totalCount, 2);
      expect(
        page.items.map((item) => item.activeRelationCount),
        everyElement(1),
      );
      expect(
        trace.statements.where(
          (statement) => statement.contains('doable_relation_count_aggregates'),
        ),
        hasLength(1),
      );
    },
  );

  test('не публикует частичный успех при повреждении соседства', () async {
    final owner = _id(_uuid(50));
    final neighbor = _id(_uuid(51));
    await _insertIntention(database, owner, title: 'Владелец');
    await _insertIntention(database, neighbor, title: 'Сосед');
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
    await _insertRelation(
      database,
      id: _uuid(150),
      sourceId: owner,
      relatedId: neighbor,
      type: 'повреждённый-тип',
      isArchived: false,
    );

    final counts = await repository.getRelationCounts(owner);
    final details = await repository.watchIntention(owner).first;
    final catalog = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'Владелец',
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 10,
      ),
    );

    expect(
      counts,
      isA<ResultFailure<GraphSnapshot<RelationCounts>>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionCorruptionFailure>(),
      ),
    );
    expect(
      details,
      isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionCorruptionFailure>(),
      ),
    );
    expect(
      catalog,
      isA<ResultFailure<IntentionCatalogPage>>().having(
        (result) => result.failure,
        'failure',
        isA<IntentionCorruptionFailure>(),
      ),
    );
  });

  test('сбой диагностики не меняет успешную сводку', () async {
    final owner = _id(_uuid(60));
    await _insertIntention(database, owner);
    final failingDiagnostics = _ThrowingDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 19),
      failingDiagnostics,
    );

    final result = await repository.getRelationCounts(owner);

    expect(result, isA<ResultSuccess<GraphSnapshot<RelationCounts>>>());
    expect(
      failingDiagnostics.attemptedEvents,
      everyElement(isA<RelationCountsReadDiagnosticsEvent>()),
    );
    expect(failingDiagnostics.attemptedEvents, hasLength(2));
  });

  test('не перечитывает наблюдение при изменении другого намерения', () async {
    await database.close();
    final trace = _SelectTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 19),
      diagnostics,
    );
    final watchedId = _id(_uuid(70));
    final changedId = _id(_uuid(71));
    await _insertIntention(database, watchedId, title: 'Наблюдаемое');
    await _insertIntention(database, changedId, title: 'Изменяемое');
    final events = StreamIterator(repository.watchIntention(watchedId));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    trace.statements.clear();

    final result = await repository.execute(
      UpdateIntention(id: changedId, title: 'Изменённое', description: null),
    );
    expect(
      result,
      isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    );
    await pumpEventQueue();
    expect(
      trace.statements.where(
        (statement) =>
            statement.contains('FROM intentions') &&
            statement.contains('description') &&
            !statement.contains('title_search_key'),
      ),
      isEmpty,
    );
  });
}

Future<void> _insertAllGroups(
  AppDatabase database,
  IntentionId owner,
  List<IntentionId> neighbors,
) async {
  final groups = [
    (incoming: true, type: 'need', archived: false),
    (incoming: false, type: 'need', archived: false),
    (incoming: true, type: 'can', archived: false),
    (incoming: false, type: 'can', archived: false),
    (incoming: true, type: 'need', archived: true),
    (incoming: false, type: 'need', archived: true),
    (incoming: true, type: 'can', archived: true),
    (incoming: false, type: 'can', archived: true),
  ];
  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    await _insertRelation(
      database,
      id: _uuid(100 + index),
      sourceId: group.incoming ? neighbors[index] : owner,
      relatedId: group.incoming ? owner : neighbors[index],
      type: group.type,
      isArchived: group.archived,
    );
  }
}

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  String title = 'Намерение',
}) => database.customStatement(
  '''
    INSERT INTO intentions (id, title, created_at, updated_at)
    VALUES (?, ?, 1, 1)
  ''',
  [id.toCanonicalString(), title],
);

Future<void> _insertRelation(
  AppDatabase database, {
  required String id,
  required IntentionId sourceId,
  required IntentionId relatedId,
  required String type,
  required bool isArchived,
}) => database.customStatement(
  '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      is_archived
    ) VALUES (?, ?, ?, ?, 1, ?)
  ''',
  [
    id,
    sourceId.toCanonicalString(),
    relatedId.toCanonicalString(),
    type,
    isArchived ? 1 : 0,
  ],
);

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  final List<String> statements = [];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      statements.add(statement.statements.single);
    }
  }
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-диагностика');
  }
}
