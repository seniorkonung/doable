import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          'The relations couldn’t be refreshed. Previously loaded data is still shown.',
        ),
        findsOneWidget,
      );
      expect(find.text('Total relations: 0'), findsOneWidget);
      await _scrollTo(tester, find.text('Try again'));
      expect(find.text('Try again'), findsOneWidget);
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
