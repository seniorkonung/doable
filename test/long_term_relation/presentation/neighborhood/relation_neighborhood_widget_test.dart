import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import 'neighborhood_test_support.dart';

void main() {
  const revision = TestGraphRevision(1);

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

      await _scrollTo(tester, find.text('To Исходное 1, you can Намерение'));
      expect(find.text('To Исходное 1, you can Намерение'), findsOneWidget);
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
        pagingPolicy: RelationGroupPagingPolicy(
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

  for (final headHidden in [false, true]) {
    testWidgets(
      'возврат на связи после согласования ${headHidden ? 'начинает тело под закреплёнными вкладками' : 'сохраняет видимую шапку'} без старого якоря',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = ControlledNeighborhoodRepository();
        addTearDown(repository.dispose);
        final ownerId = testIntentionId(1);
        final intention = testNeighborhoodIntention(
          id: ownerId,
          description: List.filled(60, 'Строка описания').join('\n'),
        );
        final counts = testRelationCounts(activeNeedOutgoing: 4);
        await _pumpDetailsPage(
          tester,
          repository,
          ownerId,
          pagingPolicy: RelationGroupPagingPolicy(
            pageSize: 3,
            prefetchRemaining: 1,
          ),
        );
        repository.emitIntention(intention, counts: counts, revision: revision);
        repository.completePage(
          0,
          RelationGroupFirstPage(
            items: testGroupRows(ownerId: ownerId, from: 1, count: 3),
            counts: counts,
            nextCursor: const TestRelationGroupCursor(3),
            revision: revision,
          ),
        );
        await tester.pumpAndSettle();
        final extent = tester.getSize(find.byType(PageHead)).height;
        await _scrollTo(tester, _rowFinder(3), settle: false);
        await _pumpUntilRequestCount(tester, repository, 2);
        repository.completePage(
          1,
          RelationGroupContinuationPage(
            items: testGroupRows(ownerId: ownerId, from: 4, count: 1),
            nextCursor: null,
            revision: revision,
          ),
        );
        await tester.pumpAndSettle();
        await _scrollTo(tester, _rowFinder(1));
        repository.emitIntention(
          intention,
          counts: counts,
          revision: const TestGraphRevision(2),
        );
        await _pumpUntilRequestCount(tester, repository, 3);
        repository.completePage(
          2,
          RelationGroupFirstPage(
            items: testGroupRows(ownerId: ownerId, from: 1, count: 3),
            counts: counts,
            nextCursor: const TestRelationGroupCursor(3),
            revision: const TestGraphRevision(2),
          ),
        );
        await _pumpUntilRequestCount(tester, repository, 4);
        repository.completePage(
          3,
          RelationGroupContinuationPage(
            items: testGroupRows(ownerId: ownerId, from: 4, count: 1),
            nextCursor: null,
            revision: const TestGraphRevision(2),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Overview'));
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        final offset = headHidden ? extent + 20 : extent / 2;
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Relations'));
        await tester.pumpAndSettle();

        // Прежняя строка построена: ошибочное восстановление смогло бы
        // прокрутить к ней и скрыть заголовок с выбором группы.
        expect(_rowFinder(1), findsOneWidget);
        expect(position.pixels, headHidden ? extent : offset);
        final tabs = find.byType(Tabs<IntentionDetailsTab>);
        expect(
          tester.getTopLeft(find.text('Relations').last).dy,
          closeTo(tester.getBottomLeft(tabs).dy + 24, 0.01),
        );
        expect(repository.requestCount, 4);
      },
    );
  }

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
        tester.element(find.byKey(const ValueKey('intention-relations-add'))),
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationGroupPagingPolicyProvider.overrideWithValue(
          RelationGroupPagingPolicy(pageSize: pageSize, prefetchRemaining: 0),
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
                owner: testParticipant(ownerId),
                onOpenRelation: onOpenRelation ?? (_) {},
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
    find.byKey(ValueKey('intention-relations-row-$relationId'));

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
  RelationGroupPagingPolicy? pagingPolicy,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationGroupPagingPolicyProvider.overrideWithValue(
          pagingPolicy ??
              RelationGroupPagingPolicy(pageSize: 50, prefetchRemaining: 15),
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
