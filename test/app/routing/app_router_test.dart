import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_test_support.dart';
import '../../long_term_relation/presentation/details/relation_details_test_support.dart';
import '../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart'
    hide testRelationCounts;

void main() {
  testWidgets('верхний обход открывается из активного намерения', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final router = AppRouter();
    addTearDown(router.dispose);
    final sourceId = testIntentionId(51);
    final relatedId = testIntentionId(52);

    await _pumpRouter(tester, repository, router);
    unawaited(router.push(IntentionDetailsRoute(intentionId: sourceId)));
    await _settleNeighborhood(
      tester,
      repository,
      expectedWatches: 2,
      expectedQueries: 1,
    );
    const revision = TestGraphRevision(1);
    final source = testNeighborhoodIntention(id: sourceId, title: 'Действие');
    repository.emitIntention(
      Intention(
        id: source.id,
        title: source.title,
        description: source.description,
        readiness: IntentionReadiness.ready,
        archiveState: source.archiveState,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
      ),
      counts: testRelationCounts(activeNeedOutgoing: 1),
      revision: revision,
    );
    repository.completeGroupPage(
      0,
      RelationGroupFirstPage(
        items: [
          _row(
            relationId: testRelationId(51),
            sourceId: sourceId,
            relatedId: relatedId,
            sourceTitle: 'Действие',
            relatedTitle: 'Другое действие',
          ),
        ],
        counts: testRelationCounts(activeNeedOutgoing: 1),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();

    final open = find.byKey(const ValueKey('intention-details-choose-path'));
    expect(open, findsOneWidget);
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(router.current.name, ChoicePathRoute.name);
    expect(
      router.current.argsAs<ChoicePathRouteArgs>().sourceIntentionId,
      sourceId,
    );
    expect(find.byType(ChoicePathPage), findsOneWidget);
  });

  testWidgets('архивное намерение не предлагает верхний обход', (tester) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final router = AppRouter();
    addTearDown(router.dispose);
    final sourceId = testIntentionId(53);

    await _pumpRouter(tester, repository, router);
    unawaited(router.push(IntentionDetailsRoute(intentionId: sourceId)));
    await _settleNeighborhood(
      tester,
      repository,
      expectedWatches: 2,
      expectedQueries: 1,
    );
    const revision = TestGraphRevision(1);
    repository.emitIntention(
      testNeighborhoodIntention(
        id: sourceId,
        archiveState: IntentionArchiveState.archived,
      ),
      counts: testRelationCounts(),
      revision: revision,
    );
    repository.completeGroupPage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: testRelationCounts(),
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('intention-details-choose-path')),
      findsNothing,
    );
  });

  testWidgets(
    'открывает начальный каталог через сгенерированный PageRouteInfo',
    (tester) async {
      final repository = ControlledCatalogRepository();
      final router = AppRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          retry: (retryCount, error) => null,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      await tester.pump();
      repository.queryAt(0);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const route = IntentionCatalogRoute();
      expect(route, isA<PageRouteInfo<void>>());
      expect(router.current.name, IntentionCatalogRoute.name);
      expect(find.byType(IntentionCatalogPage), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('catalog-open-daily-choices')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(router.current.name, DailyChoiceCatalogRoute.name);
      expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);

      unawaited(router.push<IntentionId>(const DailyChoiceSourcePickerRoute()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(router.current.name, DailyChoiceSourcePickerRoute.name);
      expect(find.byType(DailyChoiceSourcePickerPage), findsOneWidget);
      expect(repository.queryAt(1).scope, IntentionScope.active);
      expect(
        repository.queryAt(1).readinessFilter,
        IntentionReadinessFilter.all,
      );
    },
  );

  testWidgets(
    'подробный просмотр связи открывается по типизированному идентификатору',
    (tester) async {
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final router = AppRouter();
      addTearDown(router.dispose);
      final relationId = testRelationId(1);

      await _pumpRouter(tester, repository, router);
      // Future перехода завершается только при возврате назад.
      unawaited(router.push(RelationDetailsRoute(relationId: relationId)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(router.current.name, RelationDetailsRoute.name);
      expect(repository.relationWatches, hasLength(1));
      expect(repository.watchAt(0).relationId, relationId);

      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
            ),
            revision: const TestGraphRevision(1),
          );
      await tester.pumpAndSettle();

      expect(find.byType(RelationDetailsPage), findsOneWidget);
    },
  );

  testWidgets('навигация по циклу А → Б → А открывает запрошенные соседства', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final router = AppRouter();
    addTearDown(router.dispose);
    final idA = testIntentionId(1);
    final idB = testIntentionId(2);
    final relationAb = testRelationId(1);
    final relationBa = testRelationId(2);

    await _pumpRouter(tester, repository, router);
    unawaited(router.push(IntentionDetailsRoute(intentionId: idA)));
    await _settleNeighborhood(
      tester,
      repository,
      expectedWatches: 2,
      expectedQueries: 1,
    );
    _serveNeighborhood(
      repository,
      intentionId: idA,
      title: 'А',
      queryIndex: 0,
      row: _row(
        relationId: relationAb,
        sourceId: idA,
        relatedId: idB,
        sourceTitle: 'А',
        relatedTitle: 'Б',
      ),
    );
    await tester.pumpAndSettle();

    await _openRelation(tester, relationAb);
    expect(router.current.name, RelationDetailsRoute.name);
    repository
        .latestWatchOf(relationAb)
        .emitDetails(
          testRelationDetails(
            relationId: relationAb,
            sourceId: idA,
            relatedId: idB,
            sourceTitle: 'А',
            relatedTitle: 'Б',
          ),
          revision: const TestGraphRevision(1),
        );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('relation-details-related-participant')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await _settleNeighborhood(
      tester,
      repository,
      expectedWatches: 4,
      expectedQueries: 2,
    );
    expect(router.current.name, IntentionDetailsRoute.name);
    expect(router.current.argsAs<IntentionDetailsRouteArgs>().intentionId, idB);
    _serveNeighborhood(
      repository,
      intentionId: idB,
      title: 'Б',
      queryIndex: 1,
      row: _row(
        relationId: relationBa,
        sourceId: idB,
        relatedId: idA,
        sourceTitle: 'Б',
        relatedTitle: 'А',
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.groupQueries[1].intentionId, idB);

    await _openRelation(tester, relationBa);
    repository
        .latestWatchOf(relationBa)
        .emitDetails(
          testRelationDetails(
            relationId: relationBa,
            sourceId: idB,
            relatedId: idA,
            sourceTitle: 'Б',
            relatedTitle: 'А',
          ),
          revision: const TestGraphRevision(1),
        );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('relation-details-related-participant')),
    );
    await tester.pumpAndSettle();

    expect(router.current.name, IntentionDetailsRoute.name);
    expect(router.current.argsAs<IntentionDetailsRouteArgs>().intentionId, idA);
    expect(find.byType(IntentionDetailsPage), findsWidgets);
    expect(find.text('To А, you need Б'), findsWidgets);
    // Повторный вход в уже открытое намерение не разворачивает граф заново.
    expect(repository.groupQueries, hasLength(2));
  });

  testWidgets(
    'создание из группы соседства открывает форму с контекстом направления',
    (tester) async {
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final router = AppRouter();
      addTearDown(router.dispose);
      final ownerId = testIntentionId(1);
      final neighborId = testIntentionId(2);

      await _pumpRouter(tester, repository, router);
      unawaited(router.push(IntentionDetailsRoute(intentionId: ownerId)));
      await _settleNeighborhood(
        tester,
        repository,
        expectedWatches: 2,
        expectedQueries: 1,
      );
      _serveNeighborhood(
        repository,
        intentionId: ownerId,
        title: 'А',
        queryIndex: 0,
        row: _row(
          relationId: testRelationId(1),
          sourceId: ownerId,
          relatedId: neighborId,
          sourceTitle: 'А',
          relatedTitle: 'Б',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-create-relation')),
      );
      await tester.pumpAndSettle();

      expect(router.current.name, RelationEditorRoute.name);
      expect(
        tester
            .widget<RelationEditorPage>(find.byType(RelationEditorPage))
            .editorContext,
        RelationCreationContext(
          participant: testParticipant(
            ownerId,
            title: 'А',
            activeRelationCount: 1,
          ),
          direction: RelationDirection.outgoing,
        ),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await _settleNeighborhood(
        tester,
        repository,
        expectedWatches: 2,
        expectedQueries: 2,
      );
      repository.completeGroupPage(
        1,
        RelationGroupFirstPage(
          items: const [],
          counts: testRelationCounts(activeNeedOutgoing: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-create-relation')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RelationEditorPage>(find.byType(RelationEditorPage))
            .editorContext,
        RelationCreationContext(
          participant: testParticipant(
            ownerId,
            title: 'А',
            activeRelationCount: 1,
          ),
          direction: RelationDirection.incoming,
        ),
      );
    },
  );
}

Future<void> _pumpRouter(
  WidgetTester tester,
  ControlledRelationDetailsRepository repository,
  AppRouter router,
) async {
  // Высокая поверхность держит соседство и переходы видимыми без прокрутки.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
}

/// Ожидает, пока открытая страница намерения начнёт согласованное чтение.
Future<void> _settleNeighborhood(
  WidgetTester tester,
  ControlledRelationDetailsRepository repository, {
  required int expectedWatches,
  required int expectedQueries,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (repository.watchedIntentionIds.length >= expectedWatches &&
        repository.groupQueries.length >= expectedQueries) {
      await tester.pump();
      return;
    }
    await tester.pump();
  }
  throw StateError('Страница намерения не начала чтение соседства.');
}

void _serveNeighborhood(
  ControlledRelationDetailsRepository repository, {
  required IntentionId intentionId,
  required String title,
  required int queryIndex,
  required LongTermRelationSummary row,
}) {
  const revision = TestGraphRevision(1);
  final counts = testRelationCounts(activeNeedOutgoing: 1);
  repository.emitIntention(
    testNeighborhoodIntention(id: intentionId, title: title),
    counts: counts,
    revision: revision,
  );
  repository.completeGroupPage(
    queryIndex,
    RelationGroupFirstPage(
      items: [row],
      counts: counts,
      nextCursor: null,
      revision: revision,
    ),
  );
}

LongTermRelationSummary _row({
  required LongTermRelationId relationId,
  required IntentionId sourceId,
  required IntentionId relatedId,
  required String sourceTitle,
  required String relatedTitle,
}) => LongTermRelationSummary(
  relation: LongTermRelation(
    id: relationId,
    sourceIntentionId: sourceId,
    relatedIntentionId: relatedId,
    type: LongTermRelationType.need,
    priority: RelationPriority.p2,
    scope: RelationScope.active,
    creationSequence: RelationCreationSequence(1),
  ),
  source: testParticipant(sourceId, title: sourceTitle, activeRelationCount: 1),
  related: testParticipant(
    relatedId,
    title: relatedTitle,
    activeRelationCount: 1,
  ),
  hasDescription: false,
);

Future<void> _openRelation(
  WidgetTester tester,
  LongTermRelationId relationId,
) async {
  final row = find.byKey(
    ValueKey('relation-neighborhood-row-${relationId.toCanonicalString()}'),
  );
  await tester.scrollUntilVisible(
    row,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  // Открытая связь читается: индикатор чтения не даёт дождаться покоя.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
