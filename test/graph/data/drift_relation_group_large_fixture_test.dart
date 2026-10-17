import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

const _activeGroupSize = 250;
const _archivedGroupSize = 5000;
const _pageSize = 50;

void main() {
  test('полностью читает большие активную и архивную группы ограниченными порциями', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final trace = _RelationReadTrace();
    final database = await harness.openReadyDatabase(observer: trace);
    final repository = _repository(database);

    await _populateLargeFixture(database);
    trace.clear();

    final active = await _traverseGroup(
      repository,
      trace,
      RelationScope.active,
      expectedCount: _activeGroupSize,
      expectedOtherCount: _archivedGroupSize,
    );
    final archived = await _traverseGroup(
      repository,
      trace,
      RelationScope.archived,
      expectedCount: _archivedGroupSize,
      expectedOtherCount: _activeGroupSize,
    );

    final movedActiveId = _decodedRelationId(_activeGroupSize - 1);
    final movedActiveCanonicalId = movedActiveId.toCanonicalString();
    final initialActivePosition = active.indexOf(movedActiveCanonicalId);
    await _expectCommandSuccess(
      repository.execute(
        UpdateLongTermRelation(
          relationId: movedActiveId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      ),
    );
    final movedActive = await _traverseGroup(
      repository,
      trace,
      RelationScope.active,
      expectedCount: _activeGroupSize,
      expectedOtherCount: _archivedGroupSize,
    );
    expect(
      movedActive.indexOf(movedActiveCanonicalId),
      lessThan(initialActivePosition),
    );

    await _expectCommandSuccess(
      repository.execute(
        UpdateLongTermRelation(
          relationId: movedActiveId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p2),
          ),
        ),
      ),
    );
    final restoredActive = await _traverseGroup(
      repository,
      trace,
      RelationScope.active,
      expectedCount: _activeGroupSize,
      expectedOtherCount: _archivedGroupSize,
    );
    expect(restoredActive, active);

    final unviewedArchivedId = _decodedRelationId(_activeGroupSize);
    final unviewedArchivedCanonicalId = unviewedArchivedId.toCanonicalString();
    final initialArchivedPosition = archived.indexOf(
      unviewedArchivedCanonicalId,
    );
    await _expectCommandSuccess(
      repository.execute(
        UpdateLongTermRelation(
          relationId: unviewedArchivedId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      ),
    );
    final activeAfterUnviewedMutation = await _traverseGroup(
      repository,
      trace,
      RelationScope.active,
      expectedCount: _activeGroupSize,
      expectedOtherCount: _archivedGroupSize,
    );
    expect(activeAfterUnviewedMutation, active);
    final archivedAfterMutation = await _traverseGroup(
      repository,
      trace,
      RelationScope.archived,
      expectedCount: _archivedGroupSize,
      expectedOtherCount: _activeGroupSize,
    );
    expect(
      archivedAfterMutation.indexOf(unviewedArchivedCanonicalId),
      lessThan(initialArchivedPosition),
    );
  });

  test('после повторного открытия обнаруживает скрытое фильтром повреждение без startup-аудита', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final database = await harness.openReadyDatabase();
    await _insertIntention(database, _ownerIdValue, 'Владелец');
    await _insertIntention(database, _participantId(1), 'Участник');
    await database.customStatement(
      '''
          INSERT INTO long_term_relations (
            id,
            source_intention_id,
            related_intention_id,
            type,
            priority,
            description,
            is_archived
          ) VALUES (?, ?, ?, 'can', 1, CAST(x'80' AS TEXT), 1)
        ''',
      [_relationId(1), _participantId(1), _ownerIdValue],
    );
    await harness.closePersistenceObjectGraph();

    // Повреждение не мешает повторному открытию хранилища.
    final reopened = await harness.openReadyDatabase();
    final repository = _repository(reopened);

    final result = await repository.getRelationGroupPage(
      _query(RelationScope.active),
    );

    expect(
      result,
      isA<RelationGroupPageFailure>().having(
        (failure) => failure.failure,
        'failure',
        isA<RelationGroupCorruptionFailure>(),
      ),
    );
  });

  test(
    'читает 401 и более 999 явно выбранных связей пакетно на одной ревизии',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _RelationReadTrace();
      final database = await harness.openReadyDatabase(observer: trace);
      final repository = _repository(database);
      await _populateLargeFixture(database);

      final selected401 = [
        for (var index = 0; index < 201; index++) _decodedRelationId(index),
        for (var index = 250; index < 450; index++) _decodedRelationId(index),
      ];
      final first = await repository.getSelectedRelations(
        SelectedRelationsQuery(intentionId: _ownerId, relationIds: selected401),
      );
      expect(first, isA<SelectedRelationsReadSuccess>());
      final firstSnapshot = (first as SelectedRelationsReadSuccess).value;
      expect(firstSnapshot.value.entries.keys.toSet(), selected401.toSet());
      expect(
        firstSnapshot.value.entries.values,
        everyElement(isA<SelectedRelationPresent>()),
      );

      final selected1100 = [
        for (var index = 0; index < 1100; index++) _decodedRelationId(index),
      ];
      final second = await repository.getSelectedRelations(
        SelectedRelationsQuery(
          intentionId: _ownerId,
          relationIds: selected1100,
        ),
      );
      expect(second, isA<SelectedRelationsReadSuccess>());
      final secondSnapshot = (second as SelectedRelationsReadSuccess).value;
      expect(
        secondSnapshot.revision.compareTo(firstSnapshot.revision),
        GraphRevisionOrder.same,
      );
      expect(secondSnapshot.value.entries.keys.toSet(), selected1100.toSet());
      expect(
        secondSnapshot.value.entries.values,
        everyElement(isA<SelectedRelationPresent>()),
      );

      trace.failSelectedReadAt(2);
      final interrupted = await repository.getSelectedRelations(
        SelectedRelationsQuery(intentionId: _ownerId, relationIds: selected401),
      );
      expect(
        interrupted,
        isA<SelectedRelationsReadError>().having(
          (error) => error.failure,
          'отказ второй SQL-порции',
          isA<SelectedRelationsReadUnavailableFailure>(),
        ),
      );
    },
  );

  test(
    'массовый выбор читает только посещённые порции и выбранные связи',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final trace = _RelationReadTrace();
      final database = await harness.openReadyDatabase(observer: trace);
      final repository = _repository(database);
      await _populateLargeFixture(database);
      trace.clear();

      final activeRows = <LongTermRelationSummary>[];
      RelationGroupCursor? cursor;
      do {
        final page = _page(
          await repository.getRelationGroupPage(
            _query(RelationScope.active, cursor: cursor),
          ),
        );
        activeRows.addAll(_longTermItems(page));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(activeRows.map((row) => row.relation.id).toSet(), hasLength(250));

      final archivedRows = <LongTermRelationSummary>[];
      cursor = null;
      for (var pageIndex = 0; pageIndex < 4; pageIndex++) {
        final page = _page(
          await repository.getRelationGroupPage(
            _query(RelationScope.archived, cursor: cursor),
          ),
        );
        archivedRows.addAll(_longTermItems(page));
        cursor = page.nextCursor;
        expect(cursor, isNotNull);
      }
      expect(
        archivedRows.map((row) => row.relation.id).toSet(),
        hasLength(200),
      );
      // Просмотр порций группы не читает остальные строки архива.
      expect(trace.rowCounts, everyElement(lessThanOrEqualTo(_pageSize + 1)));

      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final provider = blockingRelationsSelectionViewModelProvider(_ownerId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final selection = container.read(provider.notifier);
      final chosenRows = [...activeRows.take(201), ...archivedRows];
      for (final row in chosenRows) {
        expect(selection.select(row), isTrue);
      }
      final chosenIds = chosenRows.map((row) => row.relation.id).toSet();
      expect(chosenIds, hasLength(401));
      expect(container.read(provider).selected.keys.toSet(), chosenIds);
      expect(container.read(provider).selected.length, greaterThan(_pageSize));

      trace.clear();
      expect(await selection.refreshSelection(), isTrue);
      expect(selection.prepare(), isTrue);
      final prepared =
          container.read(provider) as BlockingRelationsSelectionPrepared;
      expect(
        prepared.snapshot.rows.map((row) => row.relation.id).toSet(),
        chosenIds,
      );
      expect(prepared.snapshot.command.relationIds, chosenIds);
      // Обновление выбора читает только выбранные связи, а не всю группу.
      expect(
        trace.rowCounts,
        everyElement(lessThanOrEqualTo(chosenIds.length)),
      );

      trace.clear();
      final result = await repository.execute(prepared.snapshot.command);
      expect(result, isA<GraphCommandSucceeded>());
      final deleted =
          (result as GraphCommandSucceeded).value.value
              as BlockingRelationsDeleted;
      expect(
        deleted.deletedRelations.map((relation) => relation.id).toSet(),
        chosenIds,
      );

      trace.clear();
      final activeAfter = _page(
        await repository.getRelationGroupPage(_query(RelationScope.active)),
      ) as RelationGroupFirstPage;
      expect(activeAfter.counts.activeNeedOutgoing, 49);
      expect(activeAfter.counts.archivedNeedOutgoing, 4800);
      expect(activeAfter.items, hasLength(49));
      expect(activeAfter.nextCursor, isNull);
      expect(
        activeAfter.items.map((row) => row.relation.id).toSet(),
        activeRows.skip(201).map((row) => row.relation.id).toSet(),
      );
      expect(trace.rowCounts, everyElement(lessThanOrEqualTo(_pageSize + 1)));
    },
  );
}

Future<void> _populateLargeFixture(AppDatabase database) =>
    database.batch((batch) {
      const timestamp = 1789862400000000;
      batch.insert(
        database.intentions,
        IntentionsCompanion.insert(
          id: _ownerIdValue,
          title: 'Владелец большого соседства',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      final total = _activeGroupSize + _archivedGroupSize;
      for (var index = 0; index < total; index++) {
        final participantId = _participantId(index);
        batch
          ..insert(
            database.intentions,
            IntentionsCompanion.insert(
              id: participantId,
              title: 'Участник $index',
              createdAt: timestamp + index + 1,
              updatedAt: timestamp + index + 1,
            ),
          )
          ..insert(
            database.longTermRelations,
            LongTermRelationsCompanion.insert(
              id: _relationId(index),
              sourceIntentionId: _ownerIdValue,
              relatedIntentionId: participantId,
              type: 'need',
              priority: index % 4 + 1,
              description: Value(index % 17 == 0 ? 'Описание $index' : null),
              isArchived: Value(index >= _activeGroupSize),
            ),
          );
      }
    });

/// Обходит всю группу порциями и возвращает идентификаторы связей в порядке
/// выдачи.
Future<List<String>> _traverseGroup(
  DriftPersonalGraphRepository repository,
  _RelationReadTrace trace,
  RelationScope scope, {
  required int expectedCount,
  required int expectedOtherCount,
}) async {
  trace.clear();
  final ids = <String>{};
  final orderedIds = <String>[];
  var pageCount = 0;
  var previousPriority = 0;
  var previousSequence = 0;
  GraphRevision? revision;
  RelationGroupCursor? cursor;

  do {
    final page = _page(
      await repository.getRelationGroupPage(_query(scope, cursor: cursor)),
    );
    pageCount++;
    expect(_longTermItems(page), hasLength(lessThanOrEqualTo(_pageSize)));
    final establishedRevision = revision;
    if (establishedRevision == null) {
      revision = page.revision;
    } else {
      expect(
        page.revision.compareTo(establishedRevision),
        GraphRevisionOrder.same,
      );
    }

    if (pageCount == 1) {
      final firstPage = page as RelationGroupFirstPage;
      expect(
        firstPage.counts.forGroup(
          scope: scope,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
        ),
        expectedCount,
      );
      expect(
        firstPage.counts.forGroup(
          scope: scope == RelationScope.active
              ? RelationScope.archived
              : RelationScope.active,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
        ),
        expectedOtherCount,
      );
    } else {
      expect(page, isA<RelationGroupContinuationPage>());
    }

    for (final summary in _longTermItems(page)) {
      final relation = summary.relation;
      final priority = relation.priority.index + 1;
      final sequence = relation.creationSequence.value;
      expect(
        priority > previousPriority ||
            (priority == previousPriority && sequence > previousSequence),
        isTrue,
      );
      previousPriority = priority;
      previousSequence = sequence;
      final canonicalId = relation.id.toCanonicalString();
      expect(ids.add(canonicalId), isTrue);
      orderedIds.add(canonicalId);
      expect(relation.scope, scope);
      expect(relation.type, LongTermRelationType.need);
      expect(relation.sourceIntentionId, _ownerId);
    }

    cursor = page.nextCursor;
  } while (cursor != null);

  expect(ids, hasLength(expectedCount));
  expect(pageCount, (expectedCount / _pageSize).ceil());
  // Ни одно чтение не возвращает больше порции и признака продолжения.
  expect(trace.rowCounts, everyElement(lessThanOrEqualTo(_pageSize + 1)));

  return List.unmodifiable(orderedIds);
}

Future<void> _insertIntention(AppDatabase database, String id, String title) =>
    database.customStatement(
      '''
    INSERT INTO intentions (id, title, created_at, updated_at)
    VALUES (?, ?, ?, ?)
  ''',
      [id, title, 1789862400000000, 1789862400000000],
    );

DriftPersonalGraphRepository _repository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 20),
      InMemoryDiagnosticsSink(),
    );

RelationGroupQuery _query(RelationScope scope, {RelationGroupCursor? cursor}) =>
    RelationGroupQuery(
      intentionId: _ownerId,
      type: LongTermRelationType.need,
      direction: RelationDirection.outgoing,
      scope: scope,
      pageSize: _pageSize,
      cursor: cursor,
    );

RelationGroupPage _page(RelationGroupPageResult result) {
  expect(result, isA<RelationGroupPageSuccess>());
  return (result as RelationGroupPageSuccess).value;
}

List<LongTermRelationSummary> _longTermItems(RelationGroupPage page) =>
    switch (page) {
      RelationGroupFirstPage(:final items) ||
      RelationGroupContinuationPage(:final items) => items,
      DailyChoiceGroupFirstPage() || DailyChoiceGroupContinuationPage() =>
        throw StateError('Ожидалась группа долговременных связей.'),
    };

Future<void> _expectCommandSuccess(
  Future<LongTermRelationCommandResult> result,
) async {
  expect(await result, isA<GraphCommandSucceeded>());
}

IntentionId get _ownerId =>
    (IntentionId.decode(_ownerIdValue) as IntentionIdDecodingSuccess).id;

const _ownerIdValue = '018f0b5d-6b2e-7c80-8000-000000000000';

String _participantId(int index) =>
    '018f0b5d-6b2e-7c80-8001-${index.toRadixString(16).padLeft(12, '0')}';

String _relationId(int index) =>
    '018f0b5d-6b2e-7c80-8002-${index.toRadixString(16).padLeft(12, '0')}';

LongTermRelationId _decodedRelationId(int index) => (LongTermRelationId.decode(
  _relationId(index),
) as LongTermRelationIdDecodingSuccess).id;

/// Запоминает число строк каждого чтения и однократно отказывает на заданной
/// порции чтения выбранных связей.
final class _RelationReadTrace extends LocalDatabaseConnectionObserver {
  final rowCounts = <int>[];
  int? _selectedReadFailureCountdown;

  void clear() => rowCounts.clear();

  void failSelectedReadAt(int selectNumber) {
    _selectedReadFailureCountdown = selectNumber;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    final remaining = _selectedReadFailureCountdown;
    if (statement.statements.single.contains('WHERE id IN (') &&
        remaining != null) {
      if (remaining == 1) {
        _selectedReadFailureCountdown = null;
        throw SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'Временная недоступность',
        );
      }
      _selectedReadFailureCountdown = remaining - 1;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    rowCounts.add(rows.length);
    return rows;
  }
}
