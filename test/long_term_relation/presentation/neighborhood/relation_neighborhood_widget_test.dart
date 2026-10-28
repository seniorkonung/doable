import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
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

  testWidgets('дневная строка читается', (tester) async {
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final owner = testIntentionId(1);
    final item = _dailyItem(owner: owner, role: DailyChoiceRelationRole.source);

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

  testWidgets(
    'открывает активные исходящие связи «нужно» и показывает полную сводку',
    (tester) async {
      final repository = ControlledNeighborhoodRepository();
      addTearDown(repository.dispose);
      final ownerId = testIntentionId(1);
      final counts = _distinctCounts();

      await _pumpDetailsPage(tester, repository, ownerId);

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

      await _scrollTo(tester, find.text('Relations').last);
      expect(find.text('Relations'), findsNWidgets(2));
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
    'переходы открывают только выбранную группу и сохраняют параметры',
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
      // Плитки строятся одним циклом по перечислениям: достаточно группы, где
      // все три параметра отличаются от исходной, и возврата к исходной.
      for (final group in [_groups[0], _groups[3]]) {
        await _scrollTo(tester, find.byKey(_groupKey(group)));
        await tester.tap(find.byKey(_groupKey(group)));
        await tester.pump();

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

      await _scrollTo(
        tester,
        find.text('Loading relations and summary…'),
        settle: false,
      );
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
        find.byType(Scrollable).first,
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

      await _scrollTo(tester, find.text('Total relations: 100'), settle: false);
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

      // После замены списка показанная пользователю связь остаётся в области
      // прокрутки.
      final anchoredRow = _rowFinder(9);
      expect(anchoredRow, findsOneWidget);
      final rowRect = tester.getRect(anchoredRow);
      final viewportRect = tester.getRect(find.byType(Scrollable).first);
      expect(rowRect.bottom, greaterThan(viewportRect.top));
      expect(rowRect.top, lessThan(viewportRect.bottom));
    },
  );

  testWidgets('связывает русское состояние обновления с числами', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

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
  });

  testWidgets(
    'сохраняет пользовательский текст и доступность при русской локали',
    (tester) async {
      final semantics = tester.ensureSemantics();

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
      await Scrollable.ensureVisible(
        tester.element(
          find.byKey(const ValueKey('relation-neighborhood-create-relation')),
        ),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Контракт дизайн-системы задаёт область нажатия 44.
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
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
  int pageSize = 2,
  ValueChanged<LongTermRelationId>? onOpenRelation,
  ValueChanged<DailyChoiceId>? onOpenDailyChoice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
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

DailyChoiceCatalogItem _dailyItem({
  required IntentionId owner,
  required DailyChoiceRelationRole role,
}) {
  final id = (DailyChoiceId.decode(
    '00000000-0000-4000-8000-${(role == DailyChoiceRelationRole.source ? 101 : 102).toString().padLeft(12, '0')}',
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
    schedule: const DailyChoiceAllDay(),
    priority: DailyChoicePriority.p4,
    description: null,
    pathIntentionCount: 2,
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
    scrollable: find.byType(Scrollable).first,
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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
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
      child: OrdinaryPageTestApp(
        locale: locale,
        home: IntentionDetailsPage(intentionId: ownerId),
      ),
    ),
  );
  await tester.pump();
  repository.emitIntention(
    testNeighborhoodIntention(id: ownerId),
    counts: testRelationCounts(),
    revision: const TestGraphRevision(0),
  );
  await tester.pumpAndSettle();
  final texts = AppLocalizations.of(
    tester.element(find.byType(IntentionDetailsPage)),
  );
  await tester.tap(find.text(texts.detailsRelationsTab));
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
