import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/intention_relations/intention_relations_state.dart';
import 'package:doable/src/long_term_relation/presentation/intention_relations/intention_relations_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/relation_list_reconciliation.dart';
import 'package:doable/src/shared/domain/text_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_reconciliation_fixture.dart';
import '../relation_graph_test_support.dart';

void main() {
  for (final (readiness, expected) in [
    (IntentionReadiness.notReady, IntentionRelationGroup.needs),
    (IntentionReadiness.ready, IntentionRelationGroup.neededFor),
  ]) {
    test('без группы в цели ${readiness.name} открывает первую порцию '
        'группы ${expected.name}', () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(
        repository,
        readiness: readiness,
      );
      addTearDown(harness.dispose);

      expect(harness.state, isA<IntentionRelationsInitialLoad>());
      expect(harness.state.group, expected);
      expect(harness.pageInstance.relations?.group, expected);
      expect(harness.pageInstance.relations?.expandedArchives, isEmpty);
      expect(repository.requestCount, 1);
      _expectFirstPageOf(repository.queryAt(0), expected);
    });
  }

  test('группа цели открывается вместо группы по готовности', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(
      repository,
      target: const RelationsTarget(IntentionRelationGroup.canBeUsedFor),
    );
    addTearDown(harness.dispose);

    expect(harness.state.group, IntentionRelationGroup.canBeUsedFor);
    expect(repository.requestCount, 1);
    _expectFirstPageOf(
      repository.queryAt(0),
      IntentionRelationGroup.canBeUsedFor,
    );
  });

  test(
    'новая модель экземпляра сохраняет группу после смены готовности',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository);
      addTearDown(harness.dispose);
      expect(harness.state.group, IntentionRelationGroup.needs);

      await harness.release();
      repository.emitIntention(
        _intention(harness.intentionId, IntentionReadiness.ready),
        counts: testRelationCounts(),
        revision: const TestGraphRevision(2),
      );
      await pumpEventQueue();
      final details = harness.details as IntentionDetailsLoaded;
      expect(details.intention.readiness, IntentionReadiness.ready);
      harness.retain();

      expect(harness.state.group, IntentionRelationGroup.needs);
      _expectFirstPageOf(repository.queryAt(1), IntentionRelationGroup.needs);
    },
  );

  test(
    'группа, выбранная после открытия по цели, переживает новую модель',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(
        repository,
        target: const RelationsTarget(IntentionRelationGroup.canUse),
      );
      addTearDown(harness.dispose);

      harness.viewModel.selectGroup(IntentionRelationGroup.neededFor);
      await harness.release();
      harness.retain();

      expect(harness.state.group, IntentionRelationGroup.neededFor);
      _expectFirstPageOf(
        repository.queryAt(2),
        IntentionRelationGroup.neededFor,
      );
    },
  );

  test(
    'смена группы записывается в экземпляр и отбрасывает строки прежней',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.intentionId, from: 1, count: 2),
          counts: testRelationCounts(
            activeNeedOutgoing: 2,
            activeCanOutgoing: 1,
          ),
          nextCursor: null,
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      expect(harness.loaded.items, hasLength(2));

      harness.viewModel.selectGroup(IntentionRelationGroup.canUse);

      expect(
        harness.pageInstance.relations?.group,
        IntentionRelationGroup.canUse,
      );
      expect(harness.state, isA<IntentionRelationsInitialLoad>());
      expect(harness.state.group, IntentionRelationGroup.canUse);
      expect(repository.requestCount, 2);
      _expectFirstPageOf(repository.queryAt(1), IntentionRelationGroup.canUse);
      repository.completePage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(
            ownerId: harness.intentionId,
            from: 10,
            count: 1,
            type: LongTermRelationType.can,
          ),
          counts: testRelationCounts(
            activeNeedOutgoing: 2,
            activeCanOutgoing: 1,
          ),
          nextCursor: null,
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      expect(harness.relationIds, [testRelationId(10)]);
      expect(harness.loaded.hasConfirmedEnd, isTrue);
    },
  );

  test('группы не читаются до создания модели и после освобождения', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository, retain: false);
    addTearDown(harness.dispose);
    expect(repository.requestCount, 0);

    harness.retain();
    expect(repository.requestCount, 1);
    harness.completeNeedsPage(0, count: 1);
    await pumpEventQueue();
    await harness.release();

    repository.emitIntention(
      _intention(harness.intentionId, IntentionReadiness.notReady),
      counts: testRelationCounts(activeNeedOutgoing: 2),
      revision: const TestGraphRevision(9),
    );
    await pumpEventQueue();
    expect(repository.requestCount, 1);
  });

  test('две страницы одного намерения не делят группу и порции', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final other = IntentionPageInstance(
      target: const RelationsTarget(IntentionRelationGroup.canUse),
    );
    final otherProvider = intentionRelationsViewModelProvider(
      harness.intentionId,
      other,
    );
    final otherSubscription = harness.container.listen(
      otherProvider,
      (_, _) {},
    );
    addTearDown(otherSubscription.close);

    harness.viewModel.selectGroup(IntentionRelationGroup.neededFor);
    expect(other.relations?.group, IntentionRelationGroup.canUse);
    expect(
      harness.container.read(otherProvider).group,
      IntentionRelationGroup.canUse,
    );
    _expectFirstPageOf(repository.queryAt(1), IntentionRelationGroup.canUse);
    _expectFirstPageOf(repository.queryAt(2), IntentionRelationGroup.neededFor);

    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: harness.intentionId,
          from: 1,
          count: 1,
          type: LongTermRelationType.can,
        ),
        counts: testRelationCounts(activeCanOutgoing: 1, activeNeedIncoming: 1),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    expect(harness.state, isA<IntentionRelationsInitialLoad>());
    final otherLoaded =
        harness.container.read(otherProvider) as IntentionRelationsLoaded;
    expect(otherLoaded.items.single.relation.id, testRelationId(1));
  });

  for (final initiallyEmpty in [false, true]) {
    test(
      initiallyEmpty
          ? 'пустая выбранная группа не задерживает обновление сводки'
          : 'изменение непросматриваемой группы обновляет полностью '
                'загруженную группу',
      () async {
        final repository = ControlledRelationGraphRepository();
        final harness = await _RelationsHarness.open(repository);
        addTearDown(harness.dispose);
        final ownerId = harness.intentionId;
        final outgoing = initiallyEmpty ? 0 : 2;
        final rows = testGroupRows(ownerId: ownerId, from: 1, count: outgoing);
        repository.completePage(
          0,
          RelationGroupFirstPage(
            items: rows,
            counts: testRelationCounts(
              activeNeedOutgoing: outgoing,
              activeNeedIncoming: 1,
            ),
            nextCursor: null,
            revision: const TestGraphRevision(4),
          ),
        );
        await pumpEventQueue();
        final incoming = testGroupRow(
          ownerId: ownerId,
          index: 20,
          direction: RelationDirection.incoming,
        ).relation;
        final retyped = _copyRelation(incoming, type: LongTermRelationType.can);

        await harness.completeRelationCommand(
          UpdateLongTermRelation(
            relationId: incoming.id,
            patch: const LongTermRelationPatch(
              type: LongTermRelationFieldSet(LongTermRelationType.can),
            ),
          ),
          _relationUpdateSuccess(
            revision: const TestGraphRevision(9),
            before: incoming,
            after: retyped,
            counts: {
              ownerId: testRelationCounts(
                activeNeedOutgoing: outgoing,
                activeCanIncoming: 1,
              ),
            },
          ),
        );
        final refreshing = harness.state as IntentionRelationsConfirmed;
        expect(refreshing.summaryStatus, isA<RelationListSummaryRefreshing>());
        expect(refreshing.counts.activeNeedIncoming, 1);

        repository.completePage(
          1,
          RelationGroupFirstPage(
            items: rows,
            counts: testRelationCounts(
              activeNeedOutgoing: outgoing,
              activeCanIncoming: 1,
            ),
            nextCursor: null,
            revision: const TestGraphRevision(9),
          ),
        );
        await pumpEventQueue();
        final updated = harness.state as IntentionRelationsConfirmed;
        expect(updated.counts.activeNeedIncoming, 0);
        expect(updated.counts.activeCanIncoming, 1);
        expect(updated.summaryStatus, isA<RelationListSummaryCurrent>());
        if (initiallyEmpty) {
          expect(updated, isA<IntentionRelationsEmpty>());
        } else {
          expect(harness.relationIds, [testRelationId(1), testRelationId(2)]);
          expect(harness.loaded.hasConfirmedEnd, isTrue);
        }
        _expectFirstPageOf(repository.queryAt(1), IntentionRelationGroup.needs);
      },
    );
  }

  test('приоритет связи другой группы не требует новой основы', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final ownerId = harness.intentionId;
    final counts = testRelationCounts(
      activeNeedOutgoing: 1,
      activeCanOutgoing: 1,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    final other = testGroupRow(
      ownerId: ownerId,
      index: 20,
      type: LongTermRelationType.can,
    ).relation;

    await harness.completeRelationCommand(
      UpdateLongTermRelation(
        relationId: other.id,
        patch: const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p1),
        ),
      ),
      _relationUpdateSuccess(
        revision: const TestGraphRevision(9),
        before: other,
        after: _copyRelation(other, priority: RelationPriority.p1),
        counts: {ownerId: counts},
      ),
    );

    expect(harness.loaded.summaryStatus, isA<RelationListSummaryCurrent>());
    expect(repository.requestCount, 1);
  });

  test(
    'приоритет незагруженной связи группы пересобирает загруженную часть',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository, pageSize: 2);
      addTearDown(harness.dispose);
      final ownerId = harness.intentionId;
      final counts = testRelationCounts(activeNeedOutgoing: 4);
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 2),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(2),
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      final fourth = testGroupRow(ownerId: ownerId, index: 4).relation;
      final prioritized = _copyRelation(fourth, priority: RelationPriority.p1);

      await harness.completeRelationCommand(
        UpdateLongTermRelation(
          relationId: fourth.id,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
        _relationUpdateSuccess(
          revision: const TestGraphRevision(9),
          before: fourth,
          after: prioritized,
          counts: {ownerId: counts},
        ),
      );
      expect(
        harness.loaded.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );

      repository.completePage(
        1,
        RelationGroupFirstPage(
          items: [
            _entryForRelation(ownerId, prioritized),
            testGroupRow(ownerId: ownerId, index: 1),
          ],
          counts: counts,
          nextCursor: const TestRelationGroupCursor(2),
          revision: const TestGraphRevision(9),
        ),
      );
      await pumpEventQueue();
      expect(harness.relationIds, [fourth.id, testRelationId(1)]);
      expect(harness.loaded.summaryStatus, isA<RelationListSummaryCurrent>());
    },
  );

  test('описание загруженной связи пересобирает её строку', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final ownerId = harness.intentionId;
    final counts = testRelationCounts(activeNeedOutgoing: 1);
    final row = testGroupRow(ownerId: ownerId, index: 1);
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: [row],
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    await harness.completeRelationCommand(
      UpdateLongTermRelation(
        relationId: row.relation.id,
        patch: const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p2),
        ),
      ),
      _relationUpdateSuccess(
        revision: const TestGraphRevision(9),
        before: row.relation,
        after: row.relation,
        counts: {ownerId: counts},
      ),
    );
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryRefreshing>());

    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: [
          RelationGroupEntry(
            relation: row.relation,
            neighbor: row.neighbor,
            descriptionPreview: TextPreview.fromText('Новое описание'),
          ),
        ],
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();
    expect(
      harness.loaded.items.single.descriptionPreview?.text,
      'Новое описание',
    );
  });

  test('переименование соседа загруженной строки пересобирает её', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    harness.completeNeedsPage(0, count: 1);
    await pumpEventQueue();
    final neighborId = harness.loaded.items.single.neighbor.id;
    final before = testGraphIntention(id: neighborId);
    final after = testGraphIntention(id: neighborId, title: 'Новое название');
    final start = harness.coordinator.acceptExisting(
      UpdateIntention(
        id: neighborId,
        title: after.title,
        description: after.description,
      ),
      presentationTitle: before.title,
    ) as IntentionCommandAccepted;
    repository.completeIntentionCommand(
      0,
      testIntentionSavedResult(
        before: before,
        after: after,
        revision: const TestGraphRevision(9),
      ),
    );
    await start.future;
    await pumpEventQueue();
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryRefreshing>());

    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: harness.intentionId,
          from: 1,
          count: 1,
          neighborTitles: const {1: 'Новое название'},
        ),
        counts: testRelationCounts(activeNeedOutgoing: 1),
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.items.single.neighbor.title, 'Новое название');
  });

  test(
    'дневной выбор владельца обновляет сводку при выбранной группе',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository);
      addTearDown(harness.dispose);
      final ownerId = harness.intentionId;
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 1, dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(4),
        ),
      );
      await pumpEventQueue();
      final choice = reconciliationChoice(
        source: ownerId,
        selected: testIntentionId(2),
      );
      final start = harness.coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(choice.id),
      ) as DailyChoiceCommandAccepted;
      repository.completeDailyChoiceCommand(
        0,
        reconciliationChoiceDeleted(
          choice: choice,
          pathRelationId: testRelationId(1),
          revision: const TestGraphRevision(9),
          counts: {
            ownerId: testRelationCounts(activeNeedOutgoing: 1),
            testIntentionId(2): testRelationCounts(),
          },
        ),
      );
      await start.future;
      await pumpEventQueue();
      expect(
        harness.loaded.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );

      repository.completePage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 1),
          nextCursor: null,
          revision: const TestGraphRevision(9),
        ),
      );
      await pumpEventQueue();
      expect(harness.loaded.counts.dailySource, 0);
      expect(harness.loaded.summaryStatus, isA<RelationListSummaryCurrent>());
    },
  );

  test(
    'замена на новой ревизии возвращает прокрутку к видимой связи',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository);
      addTearDown(harness.dispose);
      harness.completeNeedsPage(0, count: 3);
      await pumpEventQueue();
      harness.viewModel.rememberVisibleRelation(testRelationId(2));

      repository.emitIntention(
        _intention(harness.intentionId, IntentionReadiness.notReady),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        revision: const TestGraphRevision(9),
      );
      await pumpEventQueue();
      repository.completePage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.intentionId, from: 2, count: 2),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: null,
          revision: const TestGraphRevision(9),
        ),
      );
      await pumpEventQueue();

      final anchor = harness.loaded.scrollAnchor;
      expect(anchor?.id, testRelationId(2));
      expect(anchor?.index, 0);
    },
  );

  test(
    'после отсутствия намерения смена группы не читает и не меняет экземпляр',
    () async {
      final repository = ControlledRelationGraphRepository();
      final harness = await _RelationsHarness.open(repository);
      addTearDown(harness.dispose);
      repository.emitIntentionNotFound(revision: const TestGraphRevision(9));
      await pumpEventQueue();
      expect(harness.state, isA<IntentionRelationsIntentionNotFound>());

      harness.viewModel.selectGroup(IntentionRelationGroup.canUse);

      expect(harness.state, isA<IntentionRelationsIntentionNotFound>());
      expect(
        harness.pageInstance.relations?.group,
        IntentionRelationGroup.needs,
      );
      expect(repository.requestCount, 1);
    },
  );

  test('архив архивированного намерения раскрыт сразу', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(
      repository,
      archiveState: IntentionArchiveState.archived,
    );
    addTearDown(harness.dispose);

    expect(
      harness.pageInstance.relations?.expandedArchives,
      IntentionRelationGroup.values.toSet(),
    );
    expect(repository.requestCount, 2);
    _expectFirstPageOf(repository.queryAt(0), IntentionRelationGroup.needs);
    _expectFirstPageOf(
      repository.queryAt(1),
      IntentionRelationGroup.needs,
      scope: RelationScope.archived,
    );
    final counts = testRelationCounts(archivedNeedOutgoing: 2);
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: harness.intentionId,
          from: 1,
          count: 2,
          scope: RelationScope.archived,
        ),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.state, isA<IntentionRelationsEmpty>());
    expect(harness.archivedIds, [testRelationId(1), testRelationId(2)]);
    expect(repository.requestCount, 2);
  });

  test('раскрытие архива читает первую порцию тех же типа и направления, а '
      'сворачивание отбрасывает её строки', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(
      repository,
      target: const RelationsTarget(IntentionRelationGroup.neededFor),
    );
    addTearDown(harness.dispose);
    final ownerId = harness.intentionId;
    final counts = testRelationCounts(
      activeNeedIncoming: 1,
      archivedNeedIncoming: 2,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: ownerId,
          from: 1,
          count: 1,
          direction: RelationDirection.incoming,
        ),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.hasConfirmedEnd, isTrue);
    expect(harness.loaded.archive, isA<IntentionRelationsArchiveFolded>());

    harness.viewModel.expandArchive();

    expect(harness.pageInstance.relations?.expandedArchives, {
      IntentionRelationGroup.neededFor,
    });
    expect(harness.loaded.archive, isA<IntentionRelationsArchivePending>());
    expect(harness.relationIds, [testRelationId(1)]);
    expect(repository.requestCount, 2);
    _expectFirstPageOf(
      repository.queryAt(1),
      IntentionRelationGroup.neededFor,
      scope: RelationScope.archived,
    );
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: ownerId,
          from: 10,
          count: 2,
          direction: RelationDirection.incoming,
          scope: RelationScope.archived,
        ),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.relationIds, [testRelationId(1)]);
    expect(harness.archivedIds, [testRelationId(10), testRelationId(11)]);
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryCurrent>());
    expect(repository.requestCount, 2);

    harness.viewModel.collapseArchive();

    expect(harness.pageInstance.relations?.expandedArchives, isEmpty);
    expect(harness.loaded.archive, isA<IntentionRelationsArchiveFolded>());
    expect(harness.relationIds, [testRelationId(1)]);
    expect(repository.requestCount, 2);
  });

  test('смена группы сохраняет раскрытие архивов, а новая модель экземпляра '
      'снова получает раскрытый архив', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final ownerId = harness.intentionId;
    final counts = testRelationCounts(
      activeNeedOutgoing: 1,
      archivedNeedOutgoing: 1,
      activeCanOutgoing: 1,
      archivedCanOutgoing: 1,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    harness.viewModel.expandArchive();
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: ownerId,
          from: 10,
          count: 1,
          scope: RelationScope.archived,
        ),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    harness.viewModel.selectGroup(IntentionRelationGroup.canUse);
    expect(repository.requestCount, 3);
    _expectFirstPageOf(repository.queryAt(2), IntentionRelationGroup.canUse);
    repository.completePage(
      2,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: ownerId,
          from: 20,
          count: 1,
          type: LongTermRelationType.can,
        ),
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.archive, isA<IntentionRelationsArchiveFolded>());
    expect(repository.requestCount, 3);

    harness.viewModel.selectGroup(IntentionRelationGroup.needs);
    expect(repository.requestCount, 5);
    _expectFirstPageOf(repository.queryAt(3), IntentionRelationGroup.needs);
    _expectFirstPageOf(
      repository.queryAt(4),
      IntentionRelationGroup.needs,
      scope: RelationScope.archived,
    );

    await harness.release();
    repository.emitIntention(
      _intention(
        ownerId,
        IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.archived,
      ),
      counts: counts,
      revision: const TestGraphRevision(9),
    );
    await pumpEventQueue();
    harness.retain();

    expect(harness.pageInstance.relations?.expandedArchives, {
      IntentionRelationGroup.needs,
    });
    expect(repository.requestCount, 7);
    _expectFirstPageOf(repository.queryAt(5), IntentionRelationGroup.needs);
    _expectFirstPageOf(
      repository.queryAt(6),
      IntentionRelationGroup.needs,
      scope: RelationScope.archived,
    );
  });

  test('многолетний архив раскрывается одной порцией', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final counts = testRelationCounts(archivedNeedOutgoing: 5000);
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: counts,
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    harness.viewModel.expandArchive();
    expect(repository.queryAt(1).pageSize, 50);
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: harness.intentionId,
          from: 1,
          count: 50,
          scope: RelationScope.archived,
        ),
        counts: counts,
        nextCursor: const TestRelationGroupCursor(50),
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    final archive =
        harness.confirmed.archive as IntentionRelationsArchiveExpanded;
    expect(archive.items, hasLength(50));
    expect(archive.nextCursor, isNotNull);
    expect(harness.confirmed.counts.archivedNeedOutgoing, 5000);
    expect(repository.requestCount, 2);

    unawaited(
      harness.viewModel.loadMoreIfNeeded(
        scope: RelationScope.archived,
        visibleIndex: 49,
      ),
    );
    expect(repository.requestCount, 3);
    final continuation = repository.queryAt(2);
    expect(continuation.scope, RelationScope.archived);
    expect(continuation.cursor, const TestRelationGroupCursor(50));
  });

  test('архивирование, восстановление связи и каскад публикуют обе части на '
      'одной ревизии', () async {
    final repository = ControlledRelationGraphRepository();
    final harness = await _RelationsHarness.open(repository);
    addTearDown(harness.dispose);
    final ownerId = harness.intentionId;
    RelationGroupEntry active(int index) =>
        testGroupRow(ownerId: ownerId, index: index);
    RelationGroupEntry archived(int index) => testGroupRow(
      ownerId: ownerId,
      index: index,
      scope: RelationScope.archived,
    );
    void completePair(
      int index, {
      required List<RelationGroupEntry> activeRows,
      required List<RelationGroupEntry> archivedRows,
      required int revision,
    }) {
      final counts = testRelationCounts(
        activeNeedOutgoing: activeRows.length,
        archivedNeedOutgoing: archivedRows.length,
      );
      // Архивная часть отвечает раньше активной.
      for (final (offset, rows) in [(1, archivedRows), (0, activeRows)]) {
        repository.completePage(
          index + offset,
          RelationGroupFirstPage(
            items: rows,
            counts: counts,
            nextCursor: null,
            revision: TestGraphRevision(revision),
          ),
        );
      }
    }

    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: [active(1), active(2)],
        counts: testRelationCounts(
          activeNeedOutgoing: 2,
          archivedNeedOutgoing: 1,
        ),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    harness.viewModel.expandArchive();
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: [archived(10)],
        counts: testRelationCounts(
          activeNeedOutgoing: 2,
          archivedNeedOutgoing: 1,
        ),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    harness.viewModel.rememberVisibleRelation(testRelationId(2));

    await harness.completeRelationCommand(
      ArchiveLongTermRelation(testRelationId(2)),
      _relationUpdateSuccess(
        revision: const TestGraphRevision(9),
        before: active(2).relation,
        after: archived(2).relation,
        counts: {
          ownerId: testRelationCounts(
            activeNeedOutgoing: 1,
            archivedNeedOutgoing: 2,
          ),
        },
      ),
    );
    completePair(
      2,
      activeRows: [active(1)],
      archivedRows: [archived(2), archived(10)],
      revision: 9,
    );
    await pumpEventQueue();
    expect(harness.relationIds, [testRelationId(1)]);
    expect(harness.archivedIds, [testRelationId(2), testRelationId(10)]);
    expect(harness.confirmed.scrollAnchor?.id, testRelationId(2));

    await harness.completeRelationCommand(
      RestoreLongTermRelation(testRelationId(2)),
      _relationUpdateSuccess(
        revision: const TestGraphRevision(11),
        before: archived(2).relation,
        after: active(2).relation,
        counts: {
          ownerId: testRelationCounts(
            activeNeedOutgoing: 2,
            archivedNeedOutgoing: 1,
          ),
        },
      ),
    );
    completePair(
      4,
      activeRows: [active(1), active(2)],
      archivedRows: [archived(10)],
      revision: 11,
    );
    await pumpEventQueue();
    expect(harness.relationIds, [testRelationId(1), testRelationId(2)]);
    expect(harness.archivedIds, [testRelationId(10)]);

    final owner = _intention(ownerId, IntentionReadiness.notReady);
    final start = harness.coordinator.acceptExisting(
      ArchiveIntention(ownerId),
      presentationTitle: owner.title,
    ) as IntentionCommandAccepted;
    repository.completeIntentionCommand(
      0,
      testIntentionSavedResult(
        before: owner,
        after: _intention(
          ownerId,
          IntentionReadiness.notReady,
          archiveState: IntentionArchiveState.archived,
        ),
        revision: const TestGraphRevision(13),
      ),
    );
    await start.future;
    await pumpEventQueue();
    completePair(
      6,
      activeRows: const [],
      archivedRows: [archived(1), archived(2), archived(10)],
      revision: 13,
    );
    await pumpEventQueue();
    expect(harness.state, isA<IntentionRelationsEmpty>());
    expect(harness.archivedIds, [
      testRelationId(1),
      testRelationId(2),
      testRelationId(10),
    ]);
    expect(repository.requestCount, 8);

    // На каждой опубликованной ревизии связь видна ровно в одной части.
    for (final state
        in harness.published.whereType<IntentionRelationsConfirmed>()) {
      final ids = [
        if (state case IntentionRelationsLoaded(:final items))
          for (final item in items) item.relation.id,
        if (state.archive case IntentionRelationsArchiveExpanded(:final items))
          for (final item in items) item.relation.id,
      ];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, contains(testRelationId(2)));
    }
  });
}

void _expectFirstPageOf(
  RelationGroupQuery query,
  IntentionRelationGroup group, {
  RelationScope scope = RelationScope.active,
}) {
  expect(query.type, group.type);
  expect(query.direction, group.direction);
  expect(query.scope, scope);
  expect(query.cursor, isNull);
}

Intention _intention(
  IntentionId id,
  IntentionReadiness readiness, {
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 9, 20));
  return Intention(
    id: id,
    title: 'Намерение',
    description: null,
    readiness: readiness,
    archiveState: archiveState,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

LongTermRelation _copyRelation(
  LongTermRelation relation, {
  LongTermRelationType? type,
  RelationPriority? priority,
}) => LongTermRelation(
  id: relation.id,
  sourceIntentionId: relation.sourceIntentionId,
  relatedIntentionId: relation.relatedIntentionId,
  type: type ?? relation.type,
  priority: priority ?? relation.priority,
  scope: relation.scope,
  creationSequence: relation.creationSequence,
);

RelationGroupEntry _entryForRelation(
  IntentionId ownerId,
  LongTermRelation relation,
) => RelationGroupEntry(
  relation: relation,
  neighbor: RelationNeighbor(
    id: relation.sourceIntentionId == ownerId
        ? relation.relatedIntentionId
        : relation.sourceIntentionId,
    title: 'Намерение',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  ),
);

LongTermRelationCommandResult _relationUpdateSuccess({
  required GraphRevision revision,
  required LongTermRelation before,
  required LongTermRelation after,
  required Map<IntentionId, RelationCounts> counts,
}) => GraphResultSuccess(
  ConfirmedGraphResult(
    revision: revision,
    value: LongTermRelationUpdated(
      before: before,
      relation: after,
      description: null,
      changes: [
        for (final entry in counts.entries)
          IntentionRelationCountsChanged(
            revision: revision,
            intentionId: entry.key,
            counts: entry.value,
          ),
        LongTermRelationUpdatedChange(
          revision: revision,
          before: before,
          after: after,
        ),
      ],
    ),
  ),
);

final class _RelationsHarness {
  _RelationsHarness._(this.repository, this.pageInstance, this.container)
    : intentionId = testIntentionId(1);

  /// Модель «Связей» создаётся над полученными подробными данными, как на
  /// странице намерения.
  static Future<_RelationsHarness> open(
    ControlledRelationGraphRepository repository, {
    IntentionPageTarget target = const OverviewTarget(),
    IntentionReadiness readiness = IntentionReadiness.notReady,
    IntentionArchiveState archiveState = IntentionArchiveState.active,
    int pageSize = 50,
    bool retain = true,
  }) async {
    final harness = _RelationsHarness._(
      repository,
      IntentionPageInstance(target: target),
      ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          relationGroupPagingPolicyProvider.overrideWithValue(
            RelationGroupPagingPolicy(
              pageSize: pageSize,
              prefetchRemaining: pageSize - 1,
            ),
          ),
        ],
        retry: (retryCount, error) => null,
      ),
    );
    harness._detailsSubscription = harness.container.listen(
      intentionDetailsViewModelProvider(harness.intentionId),
      (_, _) {},
    );
    repository.emitIntention(
      _intention(harness.intentionId, readiness, archiveState: archiveState),
      counts: testRelationCounts(),
      revision: const TestGraphRevision(1),
    );
    await pumpEventQueue();
    expect(harness.details, isA<IntentionDetailsLoaded>());
    if (retain) harness.retain();
    return harness;
  }

  final ControlledRelationGraphRepository repository;
  final IntentionPageInstance pageInstance;
  final ProviderContainer container;
  final IntentionId intentionId;
  ProviderSubscription<IntentionDetailsState>? _detailsSubscription;
  ProviderSubscription<IntentionRelationsState>? _subscription;

  /// Состояния, опубликованные удерживаемой моделью.
  final published = <IntentionRelationsState>[];

  IntentionRelationsViewModelProvider get _provider =>
      intentionRelationsViewModelProvider(intentionId, pageInstance);

  IntentionRelationsViewModel get viewModel =>
      container.read(_provider.notifier);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  IntentionDetailsState get details =>
      container.read(intentionDetailsViewModelProvider(intentionId));

  IntentionRelationsState get state => container.read(_provider);

  IntentionRelationsLoaded get loaded => state as IntentionRelationsLoaded;

  IntentionRelationsConfirmed get confirmed =>
      state as IntentionRelationsConfirmed;

  List<LongTermRelationId> get relationIds => [
    for (final item in loaded.items) item.relation.id,
  ];

  List<LongTermRelationId> get archivedIds => [
    for (final item
        in (confirmed.archive as IntentionRelationsArchiveExpanded).items)
      item.relation.id,
  ];

  /// Слушатель удерживает модель, как выбранная вкладка страницы.
  void retain() {
    _subscription = container.listen(
      _provider,
      (_, next) => published.add(next),
    );
  }

  /// Снимает слушателя и ждёт автоматического освобождения модели.
  Future<void> release() async {
    _subscription?.close();
    _subscription = null;
    await container.pump();
    expect(container.exists(_provider), isFalse);
  }

  void completeNeedsPage(int index, {required int count}) {
    repository.completePage(
      index,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: intentionId, from: 1, count: count),
        counts: testRelationCounts(activeNeedOutgoing: count),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
  }

  Future<void> completeRelationCommand(
    LongTermRelationCommand command,
    LongTermRelationCommandResult result,
  ) async {
    final commandIndex = repository.relationCommands.length;
    final start = switch (command) {
      UpdateLongTermRelation() => coordinator.acceptRelationUpdate(command),
      ArchiveLongTermRelation() => coordinator.acceptRelationArchive(command),
      RestoreLongTermRelation() => coordinator.acceptRelationRestore(command),
      _ => throw UnsupportedError('Команда не используется в этих проверках.'),
    };
    expect(start, isA<LongTermRelationCommandAccepted>());
    repository.completeRelationCommand(commandIndex, result);
    await (start as LongTermRelationCommandAccepted).future;
    await pumpEventQueue();
  }

  void dispose() {
    _subscription?.close();
    _detailsSubscription?.close();
    container.dispose();
    unawaited(repository.dispose());
  }
}
