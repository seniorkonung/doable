@Tags(['slow'])
library;

import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
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
  test('полностью читает большие активную и архивную группы с ограниченной стоимостью', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final trace = _RelationReadTrace();
    final database = await harness.openReadyDatabase(observer: trace);
    final repository = _repository(database);

    await _populateLargeFixture(database);
    trace.clear();

    await _expectGroupQueryPlans(database);
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
    final initialActivePosition = active.orderedIds.indexOf(
      movedActiveCanonicalId,
    );
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
      movedActive.orderedIds.indexOf(movedActiveCanonicalId),
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
    expect(restoredActive.orderedIds, active.orderedIds);

    final unviewedArchivedId = _decodedRelationId(_activeGroupSize);
    final unviewedArchivedCanonicalId = unviewedArchivedId.toCanonicalString();
    final initialArchivedPosition = archived.orderedIds.indexOf(
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
    expect(activeAfterUnviewedMutation.orderedIds, active.orderedIds);
    final archivedAfterMutation = await _traverseGroup(
      repository,
      trace,
      RelationScope.archived,
      expectedCount: _archivedGroupSize,
      expectedOtherCount: _activeGroupSize,
    );
    expect(
      archivedAfterMutation.orderedIds.indexOf(unviewedArchivedCanonicalId),
      lessThan(initialArchivedPosition),
    );

    trace.clear();
    trace.blockNextGroupRowsSelect();
    final read = repository.getRelationGroupPage(_query(RelationScope.active));
    await trace.waitUntilGroupRowsSelectIsBlocked;
    var commandCompleted = false;
    final commandStopwatch = Stopwatch()..start();
    final command = repository
        .execute(EnableIntentionReadiness(_ownerId))
        .whenComplete(() => commandCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(commandCompleted, isFalse);

    trace.releaseGroupRowsSelect();
    _page(await read);
    final commandResult = await command;
    commandStopwatch.stop();
    expect(
      commandResult,
      isA<
        GraphResultSuccess<
          ConfirmedGraphResult<IntentionCommandSuccess>,
          IntentionFailure
        >
      >(),
    );

    _recordMeasurements(
      'active: ${active.describe()}; archived: ${archived.describe()}; '
      'commandQueueWait=${commandStopwatch.elapsedMicroseconds}us',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('после повторного открытия обнаруживает скрытое фильтром повреждение без startup-аудита', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final database = await harness.openReadyDatabase();
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
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

    final trace = _RelationReadTrace();
    final reopened = await harness.openReadyDatabase(observer: trace);
    final repository = _repository(reopened);

    expect(trace.graphContentSelects, isEmpty);

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
    expect(trace.aggregateSelects, isNotEmpty);
    expect(trace.groupRowsSelects, isEmpty);
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
      trace.clear();

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
      expect(trace.aggregateSelects.length, lessThanOrEqualTo(5));
      expect(trace.groupRowsSelects, isEmpty);
      expect(trace.relationContentSelects, hasLength(2));
      expect(
        trace.relationContentSelects
            .expand((select) => select.arguments)
            .toSet(),
        selected401.map((id) => id.toCanonicalString()).toSet(),
      );
      expect(
        trace.relationContentSelects,
        everyElement(
          isA<_TracedSelect>().having(
            (select) => select.arguments.length,
            'SQL-порция',
            lessThanOrEqualTo(400),
          ),
        ),
      );

      trace.clear();
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
      expect(trace.relationContentSelects, hasLength(3));
      expect(trace.aggregateSelects, hasLength(3));
      expect(trace.groupRowsSelects, isEmpty);

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
    timeout: const Timeout(Duration(minutes: 3)),
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

      final rssBefore = ProcessInfo.currentRss;
      final accessWatch = Stopwatch()..start();
      final pageLatencies = <Duration>[];
      final activeRows = <LongTermRelationSummary>[];
      RelationGroupCursor? cursor;
      do {
        final pageWatch = Stopwatch()..start();
        final page = _page(
          await repository.getRelationGroupPage(
            _query(RelationScope.active, cursor: cursor),
          ),
        );
        pageWatch.stop();
        pageLatencies.add(pageWatch.elapsed);
        activeRows.addAll(_longTermItems(page));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(activeRows.map((row) => row.relation.id).toSet(), hasLength(250));

      final archivedRows = <LongTermRelationSummary>[];
      cursor = null;
      for (var pageIndex = 0; pageIndex < 4; pageIndex++) {
        final pageWatch = Stopwatch()..start();
        final page = _page(
          await repository.getRelationGroupPage(
            _query(RelationScope.archived, cursor: cursor),
          ),
        );
        pageWatch.stop();
        pageLatencies.add(pageWatch.elapsed);
        archivedRows.addAll(_longTermItems(page));
        cursor = page.nextCursor;
        expect(cursor, isNotNull);
      }
      accessWatch.stop();
      final rssAfterAccess = ProcessInfo.currentRss;
      expect(
        archivedRows.map((row) => row.relation.id).toSet(),
        hasLength(200),
      );
      expect(trace.groupRowsSelects, hasLength(9));
      expect(trace.relationContentSelects, hasLength(9));
      expect(trace.groupRowsSelects.map((select) => select.arguments[2]), [
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
      ]);
      expect(
        trace.groupRowsSelects,
        everyElement(
          isA<_TracedSelect>().having(
            (select) => select.rowCount,
            'ограничение порции SQL',
            lessThanOrEqualTo(_pageSize + 1),
          ),
        ),
      );
      expect(trace.aggregateSelects, hasLength(11));
      final accessAggregateQueries = trace.aggregateSelects.length;
      final accessAggregateTime = _elapsedSelects(trace.aggregateSelects);

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
      final selectionWatch = Stopwatch()..start();
      for (final row in chosenRows) {
        expect(selection.select(row), isTrue);
      }
      selectionWatch.stop();
      final rssAfterSelection = ProcessInfo.currentRss;
      final chosenIds = chosenRows.map((row) => row.relation.id).toSet();
      expect(chosenIds, hasLength(401));
      expect(container.read(provider).selected.keys.toSet(), chosenIds);
      expect(container.read(provider).selected.length, greaterThan(_pageSize));

      trace.clear();
      final reviewWatch = Stopwatch()..start();
      expect(await selection.refreshSelection(), isTrue);
      expect(selection.prepare(), isTrue);
      reviewWatch.stop();
      final rssAfterReview = ProcessInfo.currentRss;
      final prepared =
          container.read(provider) as BlockingRelationsSelectionPrepared;
      expect(
        prepared.snapshot.rows.map((row) => row.relation.id).toSet(),
        chosenIds,
      );
      expect(prepared.snapshot.command.relationIds, chosenIds);
      expect(trace.groupRowsSelects, isEmpty);
      expect(trace.relationContentSelects, hasLength(2));
      expect(trace.selectedRelationSelects, isEmpty);
      expect(
        trace.relationContentSelects
            .expand((select) => select.arguments)
            .toSet(),
        chosenIds.map((id) => id.toCanonicalString()).toSet(),
      );
      expect(
        trace.relationContentSelects,
        everyElement(
          isA<_TracedSelect>().having(
            (select) => select.arguments.length,
            'размер SQL-порции выбранных связей',
            lessThanOrEqualTo(400),
          ),
        ),
      );
      expect(trace.aggregateSelects.length, lessThanOrEqualTo(6));
      final reviewAggregateTime = _elapsedSelects(trace.aggregateSelects);
      final reviewAggregateQueries = trace.aggregateSelects.length;

      trace.clear();
      final deleteWatch = Stopwatch()..start();
      final result = await repository.execute(prepared.snapshot.command);
      deleteWatch.stop();
      final rssAfterDelete = ProcessInfo.currentRss;
      expect(result, isA<GraphCommandSucceeded>());
      final deleted =
          (result as GraphCommandSucceeded).value.value
              as BlockingRelationsDeleted;
      expect(
        deleted.deletedRelations.map((relation) => relation.id).toSet(),
        chosenIds,
      );
      expect(trace.groupRowsSelects, isEmpty);
      expect(trace.relationContentSelects, hasLength(chosenIds.length));
      expect(trace.selectedRelationSelects, hasLength(chosenIds.length));
      expect(
        trace.selectedRelationSelects
            .map((select) => select.arguments.single)
            .toSet(),
        chosenIds.map((id) => id.toCanonicalString()).toSet(),
      );
      final deleteAggregateTime = _elapsedSelects(trace.aggregateSelects);
      final deleteAggregateQueries = trace.aggregateSelects.length;

      trace.clear();
      final reconcileWatch = Stopwatch()..start();
      final activeAfter = _page(
        await repository.getRelationGroupPage(_query(RelationScope.active)),
      ) as RelationGroupFirstPage;
      reconcileWatch.stop();
      expect(activeAfter.counts.activeNeedOutgoing, 49);
      expect(activeAfter.counts.archivedNeedOutgoing, 4800);
      expect(activeAfter.items, hasLength(49));
      expect(activeAfter.nextCursor, isNull);
      expect(
        activeAfter.items.map((row) => row.relation.id).toSet(),
        activeRows.skip(201).map((row) => row.relation.id).toSet(),
      );
      expect(trace.groupRowsSelects, hasLength(1));
      expect(trace.relationContentSelects, hasLength(1));
      expect(
        trace.groupRowsSelects.single.rowCount,
        lessThanOrEqualTo(_pageSize + 1),
      );
      expect(trace.aggregateSelects, hasLength(2));
      final reconcileAggregateTime = _elapsedSelects(trace.aggregateSelects);

      stdout.writeln(
        'Измерения OpenSpec 6.17: active=250, archived=5000, selected=401, '
        'readPages=9, access=${accessWatch.elapsedMicroseconds}us, '
        'p95Page=${_percentile95(pageLatencies).inMicroseconds}us, '
        'accessAggregateQueries=$accessAggregateQueries, '
        'accessAggregates=${accessAggregateTime.inMicroseconds}us, '
        'selection=${selectionWatch.elapsedMicroseconds}us, '
        'review=${reviewWatch.elapsedMicroseconds}us, '
        'reviewAggregateQueries=$reviewAggregateQueries, '
        'reviewAggregates=${reviewAggregateTime.inMicroseconds}us, '
        'delete=${deleteWatch.elapsedMicroseconds}us, '
        'deleteAggregateQueries=$deleteAggregateQueries, '
        'deleteAggregates=${deleteAggregateTime.inMicroseconds}us, '
        'reconcile=${reconcileWatch.elapsedMicroseconds}us, '
        'reconcileAggregates=${reconcileAggregateTime.inMicroseconds}us, '
        'rssAccess=${rssAfterAccess - rssBefore}B, '
        'rssSelection=${rssAfterSelection - rssAfterAccess}B, '
        'rssReview=${rssAfterReview - rssAfterSelection}B, '
        'rssDelete=${rssAfterDelete - rssAfterReview}B, '
        'rssReconcile=${ProcessInfo.currentRss - rssAfterDelete}B',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Duration _elapsedSelects(Iterable<_TracedSelect> selects) =>
    selects.fold(Duration.zero, (total, select) => total + select.elapsed);

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

Future<_TraversalMeasurements> _traverseGroup(
  DriftPersonalGraphRepository repository,
  _RelationReadTrace trace,
  RelationScope scope, {
  required int expectedCount,
  required int expectedOtherCount,
}) async {
  trace.clear();
  final rssBefore = ProcessInfo.currentRss;
  var peakRss = rssBefore;
  final totalStopwatch = Stopwatch()..start();
  final pageLatencies = <Duration>[];
  final ids = <String>{};
  final orderedIds = <String>[];
  var pageCount = 0;
  var previousPriority = 0;
  var previousSequence = 0;
  GraphRevision? revision;
  RelationGroupCursor? cursor;

  do {
    final pageStopwatch = Stopwatch()..start();
    final page = _page(
      await repository.getRelationGroupPage(_query(scope, cursor: cursor)),
    );
    pageStopwatch.stop();
    pageLatencies.add(pageStopwatch.elapsed);
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

    peakRss = peakRss < ProcessInfo.currentRss
        ? ProcessInfo.currentRss
        : peakRss;
    cursor = page.nextCursor;
  } while (cursor != null);
  totalStopwatch.stop();

  expect(ids, hasLength(expectedCount));
  expect(pageCount, (expectedCount / _pageSize).ceil());
  expect(trace.groupRowsSelects, hasLength(pageCount));
  expect(
    trace.groupRowsSelects,
    everyElement(
      isA<_TracedSelect>()
          .having(
            (select) => select.rowCount,
            'строк SQL',
            lessThanOrEqualTo(_pageSize + 1),
          )
          .having(
            (select) => select.statement,
            'OFFSET',
            isNot(contains('OFFSET')),
          )
          .having((select) => select.arguments.take(3), 'параметры группы', [
            _ownerIdValue,
            'need',
            scope == RelationScope.active ? 0 : 1,
          ]),
    ),
  );
  expect(trace.participantSelects, hasLength(pageCount));
  expect(
    trace.participantSelects,
    everyElement(
      isA<_TracedSelect>().having(
        (select) => select.rowCount,
        'пакет участников',
        lessThanOrEqualTo(_pageSize + 1),
      ),
    ),
  );
  expect(trace.aggregateSelects, hasLength(pageCount + 1));
  expect(
    trace.aggregateSelects,
    everyElement(
      isA<_TracedSelect>()
          .having(
            (select) => select.rowCount,
            'строк агрегатов',
            lessThanOrEqualTo(_pageSize),
          )
          .having(
            (select) => select.arguments.length,
            'размер пакета агрегатов',
            lessThanOrEqualTo(_pageSize),
          ),
    ),
  );

  return _TraversalMeasurements(
    itemCount: ids.length,
    orderedIds: List.unmodifiable(orderedIds),
    pageCount: pageCount,
    total: totalStopwatch.elapsed,
    pageP95: _percentile95(pageLatencies),
    aggregateTotal: trace.aggregateSelects.fold(
      Duration.zero,
      (total, select) => total + select.elapsed,
    ),
    peakRssDelta: peakRss - rssBefore,
  );
}

Future<void> _expectGroupQueryPlans(AppDatabase database) async {
  for (final scope in RelationScope.values) {
    final firstPageRows = await database
        .customSelect(
          '''
            EXPLAIN QUERY PLAN
            SELECT
              creation_sequence,
              id,
              source_intention_id,
              related_intention_id,
              type,
              priority,
              description,
              is_archived
            FROM long_term_relations
              INDEXED BY long_term_relations_source_group_order
            WHERE
              source_intention_id = ? AND
              type = ? AND
              is_archived = ?
            ORDER BY priority, creation_sequence
            LIMIT ?
          ''',
          variables: [
            Variable<String>(_ownerIdValue),
            const Variable<String>('need'),
            Variable<int>(scope == RelationScope.active ? 0 : 1),
            const Variable<int>(_pageSize + 1),
          ],
        )
        .get();
    final continuationRows = await database
        .customSelect(
          '''
            EXPLAIN QUERY PLAN
            SELECT
              creation_sequence,
              id,
              source_intention_id,
              related_intention_id,
              type,
              priority,
              description,
              is_archived
            FROM long_term_relations
              INDEXED BY long_term_relations_source_group_order
            WHERE
              source_intention_id = ? AND
              type = ? AND
              is_archived = ? AND
              (priority > ? OR (priority = ? AND creation_sequence > ?))
            ORDER BY priority, creation_sequence
            LIMIT ?
          ''',
          variables: [
            Variable<String>(_ownerIdValue),
            const Variable<String>('need'),
            Variable<int>(scope == RelationScope.active ? 0 : 1),
            const Variable<int>(1),
            const Variable<int>(1),
            const Variable<int>(1),
            const Variable<int>(_pageSize + 1),
          ],
        )
        .get();
    for (final rows in [firstPageRows, continuationRows]) {
      final details = rows.map((row) => row.read<String>('detail')).join('\n');
      expect(details, contains('long_term_relations_source_group_order'));
      expect(details, contains('SEARCH long_term_relations'));
    }
  }
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

Duration _percentile95(List<Duration> samples) {
  final sorted = [...samples]..sort();
  final index = ((sorted.length * 95 + 99) ~/ 100) - 1;
  return sorted[index];
}

void _recordMeasurements(String value) =>
    stdout.writeln('Измерения OpenSpec 3.16: $value');

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

final class _TraversalMeasurements {
  const _TraversalMeasurements({
    required this.itemCount,
    required this.orderedIds,
    required this.pageCount,
    required this.total,
    required this.pageP95,
    required this.aggregateTotal,
    required this.peakRssDelta,
  });

  final int itemCount;
  final List<String> orderedIds;
  final int pageCount;
  final Duration total;
  final Duration pageP95;
  final Duration aggregateTotal;
  final int peakRssDelta;

  String describe() =>
      'items=$itemCount, pages=$pageCount, '
      'total=${total.inMicroseconds}us, p95Page=${pageP95.inMicroseconds}us, '
      'aggregates=${aggregateTotal.inMicroseconds}us, '
      'peakRssDelta=${peakRssDelta}B';
}

final class _RelationReadTrace extends LocalDatabaseConnectionObserver {
  final selects = <_TracedSelect>[];
  final _started = <LocalDatabaseSqlStatement, Stopwatch>{};
  Completer<void>? _groupRowsBlocked;
  Completer<void>? _releaseGroupRows;
  int? _selectedReadFailureCountdown;

  Iterable<_TracedSelect> get groupRowsSelects =>
      selects.where((select) => _isGroupRowsSelect(select.statement));

  Iterable<_TracedSelect> get aggregateSelects =>
      selects.where((select) => _isAggregateSelect(select.statement));

  Iterable<_TracedSelect> get participantSelects =>
      selects.where((select) => _isParticipantSelect(select.statement));

  Iterable<_TracedSelect> get selectedRelationSelects => selects.where(
    (select) =>
        select.statement.contains('FROM long_term_relations') &&
        select.statement.contains('WHERE id = ?'),
  );

  Iterable<_TracedSelect> get relationContentSelects => selects.where(
    (select) => select.statement.contains('FROM long_term_relations'),
  );

  Iterable<_TracedSelect> get graphContentSelects => selects.where(
    (select) =>
        _isGroupRowsSelect(select.statement) ||
        _isAggregateSelect(select.statement),
  );

  Future<void> get waitUntilGroupRowsSelectIsBlocked =>
      (_groupRowsBlocked ??
              (throw StateError('Блокировка чтения группы не включена.')))
          .future;

  void clear() => selects.clear();

  void failSelectedReadAt(int selectNumber) {
    _selectedReadFailureCountdown = selectNumber;
  }

  void blockNextGroupRowsSelect() {
    _groupRowsBlocked = Completer<void>();
    _releaseGroupRows = Completer<void>();
  }

  void releaseGroupRowsSelect() {
    final release = _releaseGroupRows;
    if (release == null || release.isCompleted) {
      throw StateError('Нет заблокированного чтения группы.');
    }
    release.complete();
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
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
    _started[statement] = Stopwatch()..start();
    final blocked = _groupRowsBlocked;
    final release = _releaseGroupRows;
    if (blocked != null &&
        release != null &&
        !blocked.isCompleted &&
        _isGroupRowsSelect(statement.statements.single)) {
      blocked.complete();
      await release.future;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final stopwatch = _started.remove(statement)?..stop();
    selects.add(
      _TracedSelect(
        statement: statement.statements.single,
        arguments: statement.arguments,
        rowCount: rows.length,
        elapsed: stopwatch?.elapsed ?? Duration.zero,
      ),
    );
    return rows;
  }
}

final class _TracedSelect {
  const _TracedSelect({
    required this.statement,
    required this.arguments,
    required this.rowCount,
    required this.elapsed,
  });

  final String statement;
  final List<Object?> arguments;
  final int rowCount;
  final Duration elapsed;
}

bool _isGroupRowsSelect(String statement) =>
    statement.contains('FROM long_term_relations INDEXED BY') &&
    statement.contains('ORDER BY priority, creation_sequence') &&
    statement.contains('LIMIT ?');

bool _isAggregateSelect(String statement) =>
    statement.contains('doable_relation_count_aggregates');

bool _isParticipantSelect(String statement) =>
    !_isAggregateSelect(statement) &&
    (statement.contains('FROM "intentions"') ||
        statement.contains('FROM intentions')) &&
    statement.contains(' IN ');
