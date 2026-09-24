import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';

void main() {
  const revision = TestGraphRevision(1);

  testWidgets(
    'дневные роли показывают точные количества, строку и переход к пути',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final owner = testIntentionId(1);
      final sourceChoice = _dailyItem(
        owner: owner,
        role: DailyChoiceRelationRole.source,
      );
      final selectedChoice = _dailyItem(
        owner: owner,
        role: DailyChoiceRelationRole.selected,
      );
      final opened = <DailyChoiceId>[];
      await _pumpNeighborhoodSliver(
        tester,
        repository,
        owner,
        locale: const Locale('ru'),
        onOpenDailyChoice: opened.add,
      );
      const counts = (source: 1, selected: 1);
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: const [],
          counts: testRelationCounts(
            dailySource: counts.source,
            dailySelected: counts.selected,
          ),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Всего связей: 2'), findsOneWidget);
      expect(find.text('Исходное намерение: 1'), findsOneWidget);
      expect(find.text('Выбранное действие: 1'), findsOneWidget);

      final sourceGroup = find.byKey(
        const ValueKey('relation-neighborhood-daily-source'),
      );
      await _scrollTo(tester, sourceGroup);
      await tester.tap(sourceGroup);
      await tester.pump();
      expect(repository.pageQueryAt(1), isA<DailyChoiceGroupQuery>());
      expect(
        (repository.pageQueryAt(1) as DailyChoiceGroupQuery).role,
        DailyChoiceRelationRole.source,
      );
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: [sourceChoice],
          counts: testRelationCounts(dailySource: 1, dailySelected: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      final sourceRow = find.byKey(
        ValueKey(
          'relation-neighborhood-daily-row-${sourceChoice.id.toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, sourceRow);
      expect(
        find.text('Чтобы Намерение-владелец, я сегодня Действие'),
        findsOneWidget,
      );
      expect(find.text('Дата дневного выбора: 2026-09-24'), findsOneWidget);
      expect(find.text('Выполнено'), findsOneWidget);
      final sourceSemantics = tester.getSemantics(sourceRow).label;
      expect(sourceSemantics, contains('Исходное намерение'));
      expect(sourceSemantics, contains('Выполнено'));
      await tester.tap(sourceRow);
      expect(opened, [sourceChoice.id]);

      final selectedGroup = find.byKey(
        const ValueKey('relation-neighborhood-daily-selected'),
      );
      await _scrollTo(tester, selectedGroup);
      await tester.tap(selectedGroup);
      await tester.pump();
      expect(
        (repository.pageQueryAt(2) as DailyChoiceGroupQuery).role,
        DailyChoiceRelationRole.selected,
      );
      repository.completePage(
        2,
        DailyChoiceGroupFirstPage(
          items: [selectedChoice],
          counts: testRelationCounts(dailySource: 1, dailySelected: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      final selectedRow = find.byKey(
        ValueKey(
          'relation-neighborhood-daily-row-${selectedChoice.id.toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, selectedRow);
      expect(
        tester.getSemantics(selectedRow).label,
        contains('Выбранное действие'),
      );
      expect(tester.getSemantics(selectedRow).label, contains('Не выполнено'));
      semantics.dispose();
    },
  );

  testWidgets('пустая дневная группа не скрывает другие зависимости', (
    tester,
  ) async {
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final owner = testIntentionId(1);
    final selectedChoice = _dailyItem(
      owner: owner,
      role: DailyChoiceRelationRole.selected,
    );
    await _pumpNeighborhoodSliver(tester, repository, owner);
    expect(find.text('Loading relations and summary…'), findsOneWidget);
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: owner, from: 1, count: 1),
        counts: testRelationCounts(activeNeedOutgoing: 1, dailySelected: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final sourceGroup = find.byKey(
      const ValueKey('relation-neighborhood-daily-source'),
    );
    await _scrollTo(tester, sourceGroup);
    await tester.tap(sourceGroup);
    await tester.pump();
    expect(find.text('Loading relations and summary…'), findsOneWidget);
    expect(find.text('There are no relations in this group.'), findsNothing);
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: const [],
        counts: testRelationCounts(activeNeedOutgoing: 1, dailySelected: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('There are no relations in this group.'));
    expect(find.text('There are no relations in this group.'), findsOneWidget);
    await _scrollTo(tester, find.text('Total relations: 2'));
    expect(find.text('Total relations: 2'), findsOneWidget);
    expect(find.text('Selected action: 1'), findsOneWidget);
    final selectedGroup = find.byKey(
      const ValueKey('relation-neighborhood-daily-selected'),
    );
    await _scrollTo(tester, selectedGroup);
    await tester.tap(selectedGroup);
    await tester.pump();
    repository.completePage(
      2,
      DailyChoiceGroupFirstPage(
        items: [selectedChoice],
        counts: testRelationCounts(activeNeedOutgoing: 1, dailySelected: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(
      ValueKey(
        'relation-neighborhood-daily-row-${selectedChoice.id.toCanonicalString()}',
      ),
    );
    await _scrollTo(tester, row);
    expect(find.text('Not completed'), findsOneWidget);
  });

  testWidgets('подгрузка дневной группы не меняет выбранный набор', (
    tester,
  ) async {
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final owner = testIntentionId(1);
    final first = _dailyItem(
      owner: owner,
      role: DailyChoiceRelationRole.source,
    );
    final second = _dailyItem(
      owner: owner,
      role: DailyChoiceRelationRole.source,
      idNumber: 103,
    );
    final third = _dailyItem(
      owner: owner,
      role: DailyChoiceRelationRole.source,
      idNumber: 104,
    );
    await _pumpNeighborhoodSliver(
      tester,
      repository,
      owner,
      selectionMode: true,
      pageSize: 2,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: testRelationCounts(dailySource: 3),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final group = find.byKey(
      const ValueKey('relation-neighborhood-daily-source'),
    );
    await _scrollTo(tester, group);
    await tester.tap(group);
    await tester.pump();
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [first, second],
        counts: testRelationCounts(dailySource: 3),
        nextCursor: const _TestGroupCursor(),
        revision: revision,
      ),
    );
    await tester.pump();
    final secondRow = find.byKey(
      ValueKey(
        'relation-neighborhood-daily-row-${second.id.toCanonicalString()}',
      ),
    );
    await _scrollTo(tester, secondRow, settle: false);
    await _pumpUntilRequestCount(tester, repository, 3);
    repository.completePage(
      2,
      DailyChoiceGroupContinuationPage(
        items: [third],
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RelationNeighborhoodSliver)),
    );
    expect(
      container
          .read(blockingRelationsSelectionViewModelProvider(owner))
          .selected,
      isEmpty,
    );
    expect(find.text('Selected relations: 0'), findsOneWidget);
    final thirdRow = find.byKey(
      ValueKey(
        'relation-neighborhood-daily-row-${third.id.toCanonicalString()}',
      ),
    );
    await _scrollTo(tester, thirdRow);
    expect(thirdRow, findsOneWidget);
  });

  testWidgets('дневная строка читается при увеличенном тексте', (tester) async {
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final owner = testIntentionId(1);
    final item = _dailyItem(owner: owner, role: DailyChoiceRelationRole.source);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await _pumpNeighborhoodSliver(tester, repository, owner);
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final group = find.byKey(
      const ValueKey('relation-neighborhood-daily-source'),
    );
    await _scrollTo(tester, group);
    await tester.tap(group);
    await tester.pump();
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [item],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(
      ValueKey(
        'relation-neighborhood-daily-row-${item.id.toCanonicalString()}',
      ),
    );
    await _scrollTo(tester, row);
    expect(find.text('Daily choice date: 2026-09-24'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('после удаления флажки оставшейся связи снова доступны', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final ownerId = testIntentionId(1);
    final rows = testGroupRows(ownerId: ownerId, from: 1, count: 2);
    await _pumpNeighborhoodSliver(
      tester,
      repository,
      ownerId,
      selectionMode: true,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: rows,
        counts: testRelationCounts(activeNeedOutgoing: 2),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RelationNeighborhoodSliver)),
    );
    final provider = blockingRelationsSelectionViewModelProvider(ownerId);
    final viewModel = container.read(provider.notifier);
    final first = find.byKey(
      ValueKey(
        'relation-neighborhood-select-${testRelationId(1).toCanonicalString()}',
      ),
    );
    final second = find.byKey(
      ValueKey(
        'relation-neighborhood-select-${testRelationId(2).toCanonicalString()}',
      ),
    );
    await _scrollTo(tester, first);
    await tester.tap(first);
    await tester.pump();
    expect(viewModel.prepare(), isTrue);
    final command = (container.read(
      provider,
    ) as BlockingRelationsSelectionPrepared).snapshot.command;
    viewModel.confirm(presentationTitle: 'Намерение-владелец');
    await tester.pump();
    expect(tester.widget<Checkbox>(second).onChanged, isNull);

    const nextRevision = TestGraphRevision(2);
    repository.completeBlockingCommand(
      0,
      GraphCommandSucceeded<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(
        ConfirmedGraphResult(
          revision: nextRevision,
          value: BlockingRelationsDeleted(
            command: command,
            revision: nextRevision,
            deletedRelations: [rows.first.relation],
            counts: {
              ownerId: testRelationCounts(activeNeedOutgoing: 1),
              rows.first.related.id: testRelationCounts(),
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(provider).selected, isEmpty);
    await _pumpUntilRequestCount(tester, repository, 2);
    repository.completePage(
      1,
      RelationGroupFirstPage(
        items: [rows.last],
        counts: testRelationCounts(activeNeedOutgoing: 1),
        nextCursor: null,
        revision: nextRevision,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable), const Offset(0, 3000));
    await tester.pump();
    expect(find.text('Selected relations: 0'), findsOneWidget);
    await _scrollTo(tester, second);
    expect(tester.widget<Checkbox>(second).onChanged, isNotNull);
    expect(
      tester.getSemantics(second).flagsCollection.isChecked,
      CheckedState.isFalse,
    );
    await tester.tap(second);
    await tester.pump();
    expect(container.read(provider).selected.keys, {testRelationId(2)});
    await tester.drag(find.byType(Scrollable), const Offset(0, 3000));
    await tester.pump();
    expect(find.text('Selected relations: 1'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'выбирает только отмеченные связи и сохраняет набор между порциями и группами',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(
        activeNeedOutgoing: 3,
        archivedCanIncoming: 1,
      );

      await _pumpNeighborhoodSliver(
        tester,
        repository,
        ownerId,
        selectionMode: true,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 2),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(2),
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RelationNeighborhoodSliver)),
      );
      final selection = blockingRelationsSelectionViewModelProvider(ownerId);
      expect(find.text('Selected relations: 0'), findsOneWidget);
      final first = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${testRelationId(1).toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, first, settle: false);
      await _pumpUntilRequestCount(tester, repository, 2);
      repository.completePage(
        1,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: ownerId, from: 3, count: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(container.read(selection).selected.keys, {testRelationId(1)});
      expect(
        tester.getSemantics(first).label,
        contains('Remove from selection'),
      );
      expect(
        tester.getSemantics(first).flagsCollection.isChecked,
        CheckedState.isTrue,
      );

      final third = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${testRelationId(3).toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, third);
      expect(
        tester.getSemantics(third).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      expect(container.read(selection).selected.keys, {testRelationId(1)});

      await tester.drag(find.byType(Scrollable), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await tester.pump();
      final query = repository.queries.last;
      expect(find.text('Selected relations: 1'), findsOneWidget);
      expect(query.scope, RelationScope.archived);
      expect(query.type, LongTermRelationType.can);
      expect(query.direction, RelationDirection.incoming);
      final lastIndex = repository.requestCount - 1;
      repository.completePage(
        lastIndex,
        RelationGroupFirstPage(
          items: testGroupRows(
            ownerId: ownerId,
            from: 4,
            count: 1,
            scope: RelationScope.archived,
            type: LongTermRelationType.can,
            direction: RelationDirection.incoming,
          ),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(selection).selected.keys, {testRelationId(1)});
      final archived = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${testRelationId(4).toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, archived);
      expect(tester.getSemantics(archived).label, contains('Incoming'));
      expect(
        tester.getSemantics(archived).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      await tester.tap(archived);
      await tester.pumpAndSettle();
      expect(container.read(selection).selected.keys, {
        testRelationId(1),
        testRelationId(4),
      });
      expect(find.text('Selected relations: 2'), findsOneWidget);
      final review = find.byKey(const ValueKey('blocking-relations-review'));
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        find.text('To Намерение-владелец, you need Связанное 1'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(
          ValueKey(
            'blocking-relations-confirm-row-${testRelationId(4).toCanonicalString()}',
          ),
        ),
      );
      expect(find.text('Archived relation'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('blocking-relations-cancel')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-cancel')));
      await tester.pumpAndSettle();
      expect(container.read(selection).selected.keys, {
        testRelationId(1),
        testRelationId(4),
      });
      await _scrollTo(tester, archived);
      await tester.tap(archived);
      await tester.pumpAndSettle();
      expect(container.read(selection).selected.keys, {testRelationId(1)});
      expect(repository.queries, hasLength(5));
      semantics.dispose();
    },
  );

  testWidgets('просматривает весь выбор сверх порции на большом соседстве', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final ownerId = testIntentionId(1);
    final counts = testRelationCounts(
      activeNeedOutgoing: 250,
      archivedCanIncoming: 5000,
    );
    await _pumpNeighborhoodSliver(
      tester,
      repository,
      ownerId,
      selectionMode: true,
      pageSize: 50,
    );
    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: ownerId, from: 1, count: 50),
        counts: counts,
        nextCursor: const TestRelationGroupCursor(50),
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RelationNeighborhoodSliver)),
    );
    final neighborhood = container.read(
      relationNeighborhoodViewModelProvider(ownerId).notifier,
    );
    final selectionProvider = blockingRelationsSelectionViewModelProvider(
      ownerId,
    );
    final selection = container.read(selectionProvider.notifier);

    final pageWatch = Stopwatch()..start();
    for (var pageIndex = 1; pageIndex < 5; pageIndex++) {
      final loaded = container.read(
        relationNeighborhoodViewModelProvider(ownerId),
      ) as RelationGroupLoaded;
      final request = neighborhood.loadMoreIfNeeded(
        visibleIndex: loaded.items.length - 1,
      );
      await _pumpUntilRequestCount(tester, repository, pageIndex + 1);
      repository.completePage(
        pageIndex,
        RelationGroupContinuationPage(
          items: testGroupRows(
            ownerId: ownerId,
            from: pageIndex * 50 + 1,
            count: 50,
          ),
          nextCursor: pageIndex == 4
              ? null
              : TestRelationGroupCursor((pageIndex + 1) * 50),
          revision: revision,
        ),
      );
      await request;
      await tester.pumpAndSettle();
    }
    pageWatch.stop();
    final active = container.read(
      relationNeighborhoodViewModelProvider(ownerId),
    ) as RelationGroupLoaded;
    expect(active.items, hasLength(250));
    expect(active.nextCursor, isNull);
    expect(active.items.map((row) => row.relation.id).toSet(), hasLength(250));
    expect(repository.queries, hasLength(5));

    for (final row in active.items.take(50)) {
      expect(selection.select(row), isTrue);
    }
    final lastActive = find.byKey(
      ValueKey(
        'relation-neighborhood-select-${testRelationId(250).toCanonicalString()}',
      ),
    );
    await _scrollUntilBuiltAndVisible(tester, lastActive, maxAttempts: 300);
    await tester.tap(lastActive);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider).selected, hasLength(51));

    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
    await tester.pump();
    neighborhood.selectGroup(
      const RelationGroupSelection(
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
      ),
    );
    await _pumpUntilRequestCount(tester, repository, 6);
    repository.completePage(
      5,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: ownerId,
          from: 251,
          count: 50,
          type: LongTermRelationType.can,
          direction: RelationDirection.incoming,
          scope: RelationScope.archived,
        ),
        counts: counts,
        nextCursor: const TestRelationGroupCursor(300),
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries.last.scope, RelationScope.archived);
    expect(repository.queries.last.type, LongTermRelationType.can);
    final archived = find.byKey(
      ValueKey(
        'relation-neighborhood-select-${testRelationId(251).toCanonicalString()}',
      ),
    );
    await _scrollUntilBuiltAndVisible(tester, archived);
    await tester.tap(archived);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider).selected, hasLength(52));

    final rssBeforeReview = ProcessInfo.currentRss;
    final reviewWatch = Stopwatch()..start();
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
    await tester.pump();
    final review = find.byKey(const ValueKey('blocking-relations-review'));
    await _scrollTo(tester, review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    reviewWatch.stop();
    final rssAfterReview = ProcessInfo.currentRss;
    final prepared =
        container.read(selectionProvider) as BlockingRelationsSelectionPrepared;
    final selectedIds = {
      for (var index = 1; index <= 50; index++) testRelationId(index),
      testRelationId(250),
      testRelationId(251),
    };
    expect(
      prepared.snapshot.rows.map((row) => row.relation.id).toSet(),
      selectedIds,
    );
    expect(prepared.snapshot.command.relationIds, selectedIds);
    expect(repository.queries, hasLength(6));

    final browseWatch = Stopwatch()..start();
    for (final id in prepared.snapshot.command.relationIds) {
      final row = find.byKey(
        ValueKey('blocking-relations-confirm-row-${id.toCanonicalString()}'),
      );
      await tester.scrollUntilVisible(
        row,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(row, findsOneWidget);
      final selectedRow = prepared.snapshot.rows.singleWhere(
        (candidate) => candidate.relation.id == id,
      );
      final rowSemantics = find.byKey(
        ValueKey(
          'blocking-relations-confirm-semantics-${id.toCanonicalString()}',
        ),
      );
      expect(
        tester.getSemantics(rowSemantics).label,
        contains(selectedRow.source.title),
      );
      expect(
        tester.getSemantics(rowSemantics).label,
        contains(selectedRow.related.title),
      );
    }
    browseWatch.stop();
    expect(repository.queries, hasLength(6));
    stdout.writeln(
      'Измерения OpenSpec 6.17 UI: active=250, archived=5000, '
      'selected=52, pageLoad=${pageWatch.elapsedMicroseconds}us, '
      'review=${reviewWatch.elapsedMicroseconds}us, '
      'browse=${browseWatch.elapsedMicroseconds}us, '
      'reviewRssDelta=${rssAfterReview - rssBeforeReview}B, '
      'browseRssDelta=${ProcessInfo.currentRss - rssAfterReview}B',
    );
    semantics.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'сохраняет русский выбор при открытии связи и возврате с крупным текстом',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(activeNeedOutgoing: 1);
      await _pumpNeighborhoodSliver(
        tester,
        repository,
        ownerId,
        locale: const Locale('ru'),
        selectionMode: true,
        onOpenRelation: (_) =>
            Navigator.of(
              tester.element(find.byType(RelationNeighborhoodSliver)),
            ).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Просмотр связи')),
                  body: const Text('Подробности связи'),
                ),
              ),
            ),
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      final checkbox = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${testRelationId(1).toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, checkbox);
      expect(
        tester.getSemantics(checkbox).label,
        allOf(
          contains('Добавить в выбор'),
          contains('Исходящие'),
          contains('Активная связь'),
        ),
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RelationNeighborhoodSliver)),
      );
      expect(
        container
            .read(blockingRelationsSelectionViewModelProvider(ownerId))
            .selected
            .keys,
        {testRelationId(1)},
      );
      final phrase = find.text('Чтобы Намерение-владелец, нужно Связанное 1');
      await _scrollTo(tester, phrase);
      await tester.tap(phrase);
      await tester.pumpAndSettle();
      expect(find.text('Просмотр связи'), findsOneWidget);
      Navigator.of(tester.element(find.text('Просмотр связи'))).pop();
      await tester.pumpAndSettle();
      expect(
        container
            .read(blockingRelationsSelectionViewModelProvider(ownerId))
            .selected
            .keys,
        {testRelationId(1)},
      );
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );

  testWidgets(
    'новая связь при открытом подтверждении не входит в выбранный набор',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      await _pumpNeighborhoodSliver(
        tester,
        repository,
        ownerId,
        selectionMode: true,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
          counts: testRelationCounts(activeNeedOutgoing: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${testRelationId(1).toCanonicalString()}',
        ),
      );
      await _scrollTo(tester, first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('blocking-relations-review'));
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RelationNeighborhoodSliver)),
      );
      container
          .read(relationNeighborhoodViewModelProvider(ownerId).notifier)
          .showBlockingRelations();
      await tester.pump();
      repository.completePage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 2),
          counts: testRelationCounts(activeNeedOutgoing: 2),
          nextCursor: null,
          revision: const TestGraphRevision(2),
        ),
      );
      await tester.pumpAndSettle();
      final prepared = container.read(
        blockingRelationsSelectionViewModelProvider(ownerId),
      ) as BlockingRelationsSelectionPrepared;
      expect(prepared.snapshot.command.relationIds, {testRelationId(1)});
      expect(
        find.byKey(
          ValueKey(
            'blocking-relations-confirm-row-${testRelationId(2).toCanonicalString()}',
          ),
        ),
        findsNothing,
      );
      final cancel = find.byKey(const ValueKey('blocking-relations-cancel'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(repository.requestCount, 2);
    },
  );

  testWidgets(
    'открывает активные исходящие связи «нужно» и показывает полную сводку',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = _distinctCounts();

      await _pumpDetailsPage(tester, repository, ownerId);

      expect(repository.queries, hasLength(1));
      _expectQuery(
        repository.queryAt(0),
        intentionId: ownerId,
        type: LongTermRelationType.need,
        direction: RelationDirection.outgoing,
        scope: RelationScope.active,
      );

      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId, title: 'Моё намерение'),
        counts: counts,
        revision: revision,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(
            ownerId: ownerId,
            from: 1,
            count: counts.activeNeedOutgoing,
            ownerTitle: 'Моё намерение',
            neighborTitles: const {1: 'Сосед один', 2: 'Сосед два'},
          ),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Relations'), findsOneWidget);
      expect(find.text('Total relations: 36'), findsOneWidget);
      expect(find.text('Active relations: 10'), findsNWidgets(2));
      expect(find.text('Archived relations: 26'), findsNWidgets(2));
      expect(find.text('Need: 3'), findsOneWidget);
      expect(find.text('Can: 7'), findsOneWidget);
      expect(find.text('Need: 11'), findsOneWidget);
      expect(find.text('Can: 15'), findsOneWidget);
      for (final group in _groups) {
        expect(find.byKey(_groupKey(group)), findsOneWidget);
      }
      await _scrollTo(
        tester,
        find.text('To Моё намерение, you need Сосед один'),
      );
      expect(
        find.text('To Моё намерение, you need Сосед один'),
        findsOneWidget,
      );
      expect(find.text('Priority P2'), findsWidgets);
      await _scrollTo(
        tester,
        find.text('All relations in this group are loaded.'),
      );
    },
  );

  testWidgets(
    'восемь переходов открывают только выбранную группу и сохраняют параметры',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = _distinctCounts();

      await _pumpDetailsPage(tester, repository, ownerId);
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: counts,
        revision: revision,
      );
      _completeGroup(repository, 0, ownerId, counts, _groups[3]);
      await tester.pumpAndSettle();

      var requestIndex = 1;
      for (final group in [
        ..._groups.where((group) => group != _groups[3]),
        _groups[3],
      ]) {
        await _scrollTo(tester, find.byKey(_groupKey(group)));
        await tester.tap(find.byKey(_groupKey(group)));
        await tester.pump();

        expect(repository.queries, hasLength(requestIndex + 1));
        _expectQuery(
          repository.queryAt(requestIndex),
          intentionId: ownerId,
          type: group.type,
          direction: group.direction,
          scope: group.scope,
        );
        _completeGroup(repository, requestIndex, ownerId, counts, group);
        requestIndex += 1;
        await tester.pumpAndSettle();
      }

      await _scrollTo(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.pump();
      _expectQuery(
        repository.queryAt(requestIndex),
        intentionId: ownerId,
        type: LongTermRelationType.need,
        direction: RelationDirection.outgoing,
        scope: RelationScope.archived,
      );
      _completeGroup(repository, requestIndex, ownerId, counts, _groups[7]);
      await tester.pumpAndSettle();
      requestIndex += 1;

      await _scrollTo(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await tester.pump();
      _expectQuery(
        repository.queryAt(requestIndex),
        intentionId: ownerId,
        type: LongTermRelationType.can,
        direction: RelationDirection.outgoing,
        scope: RelationScope.archived,
      );
      _completeGroup(repository, requestIndex, ownerId, counts, _groups[5]);
      await tester.pumpAndSettle();
      requestIndex += 1;

      await _scrollTo(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await tester.pump();
      _expectQuery(
        repository.queryAt(requestIndex),
        intentionId: ownerId,
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
      );
      _completeGroup(repository, requestIndex, ownerId, counts, _groups[4]);
      await tester.pumpAndSettle();

      await _scrollTo(
        tester,
        find.text('To Исходное 1, you can Намерение-владелец'),
      );
      expect(
        find.text('To Исходное 1, you can Намерение-владелец'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'различает загрузку, ноль, обновление, ошибку и подтверждённый конец',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);

      await _pumpDetailsPage(tester, repository, ownerId);
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: testRelationCounts(),
        revision: revision,
      );
      await tester.pump();

      expect(find.text('Loading relations and summary…'), findsOneWidget);

      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: const [],
          counts: testRelationCounts(),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total relations: 0'), findsOneWidget);
      await _scrollTo(
        tester,
        find.text('There are no relations in this group.'),
      );
      expect(
        find.text('There are no relations in this group.'),
        findsOneWidget,
      );

      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: testRelationCounts(activeNeedOutgoing: 1),
        revision: const TestGraphRevision(2),
      );
      await tester.pump();
      expect(find.text('Refreshing relations…'), findsOneWidget);

      repository.failRead(1, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saved relation numbers are out of date because the refresh failed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Total relations: 0'), findsOneWidget);
      await _scrollTo(tester, find.text('Try again'));
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  testWidgets(
    'показывает состояние сохранённых чисел без построения footer списка',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(activeNeedOutgoing: 100);

      await _pumpDetailsPage(tester, repository, ownerId);
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: counts,
        revision: revision,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 50),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(50),
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      await _scrollUntilBuiltAndVisible(tester, _rowFinder(49), settle: false);
      await _pumpUntilRequestCount(tester, repository, 2);
      repository.failRead(1, const RelationGroupUnavailableFailure());
      await tester.pump();
      await tester.fling(
        find.byType(Scrollable),
        const Offset(0, 10000),
        10000,
      );
      await tester.pumpAndSettle();

      expect(find.text('The next relations couldn’t be loaded.'), findsNothing);
      expect(find.text('Updating saved relation numbers…'), findsNothing);
      expect(
        find.text(
          'Saved relation numbers are out of date because the refresh failed.',
        ),
        findsNothing,
      );

      final refreshedCounts = testRelationCounts(activeNeedOutgoing: 99);
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: refreshedCounts,
        revision: const TestGraphRevision(2),
      );
      await _pumpUntilRequestCount(tester, repository, 3);

      expect(find.text('Total relations: 100'), findsOneWidget);
      expect(find.text('Updating saved relation numbers…'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Total relations: 100.*Updating saved relation numbers',
            dotAll: true,
          ),
        ),
        findsOneWidget,
      );

      repository.failRead(2, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();

      expect(find.text('Total relations: 100'), findsOneWidget);
      expect(
        find.text(
          'Saved relation numbers are out of date because the refresh failed.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Total relations: 100.*Saved relation numbers are out of date',
            dotAll: true,
          ),
        ),
        findsOneWidget,
      );

      await _scrollTo(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Total relations: 100'), findsOneWidget);
      expect(find.text('Updating saved relation numbers…'), findsOneWidget);

      repository.completePage(
        3,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 50),
          counts: refreshedCounts,
          nextCursor: const TestRelationGroupCursor(50),
          revision: const TestGraphRevision(2),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total relations: 99'), findsOneWidget);
      expect(find.text('Total relations: 100'), findsNothing);
      expect(find.text('Updating saved relation numbers…'), findsNothing);
      expect(
        find.text(
          'Saved relation numbers are out of date because the refresh failed.',
        ),
        findsNothing,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'лениво подгружает порции и возвращает viewport к видимой связи',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(activeNeedOutgoing: 10);

      await _pumpDetailsPage(
        tester,
        repository,
        ownerId,
        pagingPolicy: RelationNeighborhoodPagingPolicy(
          pageSize: 6,
          prefetchRemaining: 2,
        ),
      );
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: counts,
        revision: revision,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 6),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(6),
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(tester, _rowFinder(5), settle: false);
      await _pumpUntilRequestCount(tester, repository, 2);
      expect(repository.queryAt(1).cursor, const TestRelationGroupCursor(6));
      repository.completePage(
        1,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: ownerId, from: 7, count: 4),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(tester, _rowFinder(9));
      await tester.pump();
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: counts,
        revision: const TestGraphRevision(2),
      );
      await _pumpUntilRequestCount(tester, repository, 3);
      repository.completePage(
        2,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 6),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(6),
          revision: const TestGraphRevision(2),
        ),
      );
      await _pumpUntilRequestCount(tester, repository, 4);
      repository.completePage(
        3,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: ownerId, from: 7, count: 4),
          nextCursor: null,
          revision: const TestGraphRevision(2),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntentionDetailsPage)),
      );
      final state = container.read(
        relationNeighborhoodViewModelProvider(ownerId),
      );
      expect(state, isA<RelationGroupLoaded>());
      final anchor = (state as RelationGroupLoaded).scrollAnchor;
      expect(anchor, isNotNull);
      final anchoredRow = _rowFinderById(
        anchor!.relationId.toCanonicalString(),
      );
      expect(anchoredRow, findsOneWidget);
      final rowRect = tester.getRect(anchoredRow);
      final viewportRect = tester.getRect(find.byType(Scrollable));
      expect(rowRect.bottom, greaterThan(viewportRect.top));
      expect(rowRect.top, lessThan(viewportRect.bottom));
    },
  );

  testWidgets(
    'связывает русское состояние обновления с числами при масштабе 200%',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(activeNeedOutgoing: 1);

      await _pumpNeighborhoodSliver(
        tester,
        repository,
        ownerId,
        locale: const Locale('ru'),
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: ownerId, from: 1, count: 1),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      final refreshRequestIndex = repository.requestCount;
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId),
        counts: testRelationCounts(activeNeedOutgoing: 2),
        revision: const TestGraphRevision(2),
      );
      await _pumpUntilRequestCount(tester, repository, refreshRequestIndex + 1);
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RelationNeighborhoodSliver)),
      );
      expect(
        (container.read(
          relationNeighborhoodViewModelProvider(ownerId),
        ) as RelationGroupConfirmedState).summaryFreshness,
        RelationSummaryFreshness.refreshing,
      );

      expect(find.text('Обновляем сохранённые числа связей…'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Всего связей: 1.*Обновляем сохранённые числа связей',
            dotAll: true,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'сохраняет пользовательский текст и доступность при русской локали и масштабе 200%',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = testRelationCounts(activeNeedOutgoing: 1);

      await _pumpDetailsPage(
        tester,
        repository,
        ownerId,
        locale: const Locale('ru'),
      );
      repository.emitIntention(
        testNeighborhoodIntention(id: ownerId, title: 'Build продукт'),
        counts: counts,
        revision: revision,
      );
      repository.completePage(
        0,
        RelationGroupFirstPage(
          items: [
            testGroupRow(
              ownerId: ownerId,
              index: 1,
              priority: RelationPriority.p1,
              ownerTitle: 'Build продукт',
              neighborTitle: 'Ship без перевода',
              neighborActiveRelationCount: 4,
            ),
          ],
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(
        tester,
        find.text('Чтобы Build продукт, нужно Ship без перевода'),
      );
      expect(
        find.text('Чтобы Build продукт, нужно Ship без перевода'),
        findsOneWidget,
      );
      expect(find.text('Активных связей: 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );
}

Future<void> _pumpNeighborhoodSliver(
  WidgetTester tester,
  ControlledNeighborhoodRepository repository,
  IntentionId ownerId, {
  Locale locale = const Locale('en'),
  bool selectionMode = false,
  int pageSize = 2,
  ValueChanged<LongTermRelationId>? onOpenRelation,
  ValueChanged<DailyChoiceId>? onOpenDailyChoice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        if (selectionMode)
          relationNeighborhoodPagingPolicyProvider.overrideWithValue(
            RelationNeighborhoodPagingPolicy(
              pageSize: pageSize,
              prefetchRemaining: 0,
            ),
          ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              RelationNeighborhoodSliver(
                intentionId: ownerId,
                intentionTitle: 'Намерение-владелец',
                selectionMode: selectionMode,
                onOpenRelation: onOpenRelation ?? (_) {},
                onOpenDailyChoice: onOpenDailyChoice ?? (_) {},
                onCreateRelation: (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _pumpUntilRequestCount(tester, repository, 1);
}

final class _TestGroupCursor implements RelationGroupCursor {
  const _TestGroupCursor();
}

DailyChoiceCatalogItem _dailyItem({
  required IntentionId owner,
  required DailyChoiceRelationRole role,
  int? idNumber,
}) {
  final id = (DailyChoiceId.decode(
    '00000000-0000-4000-8000-${(idNumber ?? (role == DailyChoiceRelationRole.source ? 101 : 102)).toString().padLeft(12, '0')}',
  ) as DailyChoiceIdDecodingSuccess).id;
  final source = DailyChoiceCatalogParticipant(
    id: role == DailyChoiceRelationRole.source ? owner : testIntentionId(2),
    title: role == DailyChoiceRelationRole.source
        ? 'Намерение-владелец'
        : 'Основание',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  );
  final selected = DailyChoiceCatalogParticipant(
    id: role == DailyChoiceRelationRole.selected ? owner : testIntentionId(2),
    title: role == DailyChoiceRelationRole.selected
        ? 'Намерение-владелец'
        : 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  );
  return DailyChoiceCatalogItem(
    id: id,
    source: source,
    selected: selected,
    date: CalendarDate.fromParts(2026, 9, 24),
    isCompleted: role == DailyChoiceRelationRole.source,
  );
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _scrollUntilBuiltAndVisible(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      await _scrollTo(tester, finder, settle: settle);
      return;
    }
    await tester.drag(find.byType(Scrollable), const Offset(0, -400));
    await tester.pump();
  }
  throw StateError('Строка соседства не была построена при прокрутке.');
}

Future<void> _pumpUntilRequestCount(
  WidgetTester tester,
  ControlledNeighborhoodRepository repository,
  int expected,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (repository.requestCount >= expected) {
      return;
    }
    await tester.pump();
  }
  throw StateError('Ожидаемая порция соседства не была запрошена.');
}

Finder _rowFinder(int index) =>
    _rowFinderById(testRelationId(index).toCanonicalString());

Finder _rowFinderById(String relationId) =>
    find.byKey(ValueKey('relation-neighborhood-row-$relationId'));

typedef _Group = ({
  RelationScope scope,
  LongTermRelationType type,
  RelationDirection direction,
});

const _groups = <_Group>[
  (
    scope: RelationScope.active,
    type: LongTermRelationType.can,
    direction: RelationDirection.incoming,
  ),
  (
    scope: RelationScope.active,
    type: LongTermRelationType.can,
    direction: RelationDirection.outgoing,
  ),
  (
    scope: RelationScope.active,
    type: LongTermRelationType.need,
    direction: RelationDirection.incoming,
  ),
  (
    scope: RelationScope.active,
    type: LongTermRelationType.need,
    direction: RelationDirection.outgoing,
  ),
  (
    scope: RelationScope.archived,
    type: LongTermRelationType.can,
    direction: RelationDirection.incoming,
  ),
  (
    scope: RelationScope.archived,
    type: LongTermRelationType.can,
    direction: RelationDirection.outgoing,
  ),
  (
    scope: RelationScope.archived,
    type: LongTermRelationType.need,
    direction: RelationDirection.incoming,
  ),
  (
    scope: RelationScope.archived,
    type: LongTermRelationType.need,
    direction: RelationDirection.outgoing,
  ),
];

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledNeighborhoodRepository repository,
  IntentionId ownerId, {
  Locale locale = const Locale('en'),
  RelationNeighborhoodPagingPolicy? pagingPolicy,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationNeighborhoodPagingPolicyProvider.overrideWithValue(
          pagingPolicy ??
              RelationNeighborhoodPagingPolicy(
                pageSize: 50,
                prefetchRemaining: 15,
              ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentionDetailsPage(intentionId: ownerId),
      ),
    ),
  );
  await tester.pump();
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (repository.intentionIds.length >= 2 && repository.requestCount >= 1) {
      return;
    }
    await tester.pump();
  }
  throw StateError('Страница не начала согласованное чтение соседства.');
}

void _completeGroup(
  ControlledNeighborhoodRepository repository,
  int requestIndex,
  IntentionId ownerId,
  RelationCounts counts,
  _Group group,
) {
  final query = repository.queryAt(requestIndex);
  final count = counts.forGroup(
    scope: group.scope,
    type: group.type,
    direction: group.direction,
  );
  repository.completePage(
    requestIndex,
    RelationGroupFirstPage(
      items: testGroupRows(
        ownerId: ownerId,
        from: 1,
        count: count,
        type: group.type,
        direction: group.direction,
        scope: group.scope,
      ),
      counts: counts,
      nextCursor: null,
      revision: const TestGraphRevision(1),
    ),
  );
  expect(query.cursor, isNull);
}

void _expectQuery(
  RelationGroupQuery query, {
  required IntentionId intentionId,
  required LongTermRelationType type,
  required RelationDirection direction,
  required RelationScope scope,
}) {
  expect(query.intentionId, intentionId);
  expect(query.type, type);
  expect(query.direction, direction);
  expect(query.scope, scope);
  expect(query.pageSize, 50);
  expect(query.cursor, isNull);
}

ValueKey<String> _groupKey(_Group group) => ValueKey(
  'relation-neighborhood-group-${group.scope.name}-${group.type.name}-${group.direction.name}',
);

RelationCounts _distinctCounts() => testRelationCounts(
  activeNeedIncoming: 1,
  activeNeedOutgoing: 2,
  activeCanIncoming: 3,
  activeCanOutgoing: 4,
  archivedNeedIncoming: 5,
  archivedNeedOutgoing: 6,
  archivedCanIncoming: 7,
  archivedCanOutgoing: 8,
);
