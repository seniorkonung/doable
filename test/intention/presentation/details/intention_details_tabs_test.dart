import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/components/count_tiles.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/relation_group.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'details_test_support.dart';

void main() {
  for (final (target, name, label, readsGroups, readsChoices) in [
    (const OverviewTarget(), 'Обзор', 'Overview', false, false),
    (
      const RelationsTarget(),
      'Связи',
      'Relations: 0 active, 0 archived',
      true,
      false,
    ),
    (const ChoicesTarget(), 'Выборы', 'Choices', false, true),
  ]) {
    testWidgets('цель «$name» открывает соответствующую вкладку', (
      tester,
    ) async {
      final repository = ControlledDetailsRepository();
      await _openPage(tester, repository, target: target);
      for (final request in repository.detailRequests) {
        request.add(ResultSuccess(testDetailsIntention()));
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(repository.relationGroupQueries, hasLength(readsGroups ? 1 : 0));
      if (readsChoices) {
        final query = repository.dailyChoiceGroupQueries.single;
        expect(query.role, DailyChoiceRelationRole.source);
        expect(query.cursor, isNull);
      } else {
        expect(repository.dailyChoiceGroupQueries, isEmpty);
      }
      expect(repository.statisticsQueries, isEmpty);
    });
  }

  testWidgets('полоса вкладок остаётся под панелью после прокрутки обзора', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    await _openPage(tester, repository);
    repository.detailRequests.single.add(
      ResultSuccess(
        testDetailsIntention(
          description: List.filled(30, 'Строка описания').join('\n'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectTabsLine(tester, visible: false);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    _expectTabsLine(tester, visible: true);

    final overview = find.text('Overview');
    expect(overview.hitTestable(), findsOneWidget);
    final barBottom = tester.getBottomLeft(find.byType(TopBar)).dy;
    expect(tester.getTopLeft(overview).dy, greaterThanOrEqualTo(barBottom));
    expect(
      tester.getBottomLeft(overview).dy,
      lessThanOrEqualTo(barBottom + 52),
    );
    _pagePosition(tester).jumpTo(0);
    await tester.pumpAndSettle();
    _expectTabsLine(tester, visible: false);
  });

  for (final (headHidden, height) in [
    (false, 600.0),
    (true, 600.0),
    (true, 1400.0),
  ]) {
    testWidgets(
      'смена вкладки ${headHidden ? 'оставляет скрытую шапку за панелью и начинает тело' : 'сохраняет смещение видимой шапки'} при высоте $height',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(800, height));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = ControlledDetailsRepository();
        await _openPage(tester, repository);
        repository.detailRequests.single.add(
          ResultSuccess(
            testDetailsIntention(
              title: 'Полное название намерения ' * 8,
              description: List.filled(60, 'Строка описания').join('\n'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final extent = tester.getSize(find.byType(PageHead)).height;
        final offset = headHidden ? extent + 300 : extent / 2;
        _pagePosition(tester).jumpTo(offset);
        await tester.pumpAndSettle();
        expect(_pagePosition(tester).pixels, offset);

        await tester.tap(find.text('Relations'));
        await tester.pumpAndSettle();

        expect(_pagePosition(tester).pixels, headHidden ? extent : offset);
        _expectTabsLine(tester, visible: headHidden);
        final tabs = find.byType(Tabs<IntentionDetailsTab>);
        final groups = find.byType(CountTiles<IntentionRelationGroup>);
        expect(
          tester.getTopLeft(groups).dy,
          closeTo(tester.getBottomLeft(tabs).dy + DoableMetrics.space2, 0.01),
        );
      },
    );
  }

  for (final (locale, overview, relations, label) in [
    ('ru', 'Обзор', 'Связи', 'Связи: активных — 5, архивированных — 3'),
    ('en', 'Overview', 'Relations', 'Relations: 5 active, 3 archived'),
  ]) {
    testWidgets('$locale: число и архив вкладки доступны без чтения групп', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      await _openPage(tester, repository, locale: Locale(locale));
      expect(repository.relationGroupQueries, isEmpty);
      expect(repository.dailyChoiceGroupQueries, isEmpty);
      final intention = testDetailsIntention();
      repository.detailRequests.single.add(
        ResultSuccess(intention),
        relationCounts: testRelationCounts(
          activeNeedIncoming: 2,
          activeCanOutgoing: 3,
          archivedCanIncoming: 3,
          dailySource: 7,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel(overview))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.text(relations), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon && widget.icon == DoableIconData.archive,
        ),
        findsOneWidget,
      );
      expect(repository.relationGroupQueries, isEmpty);
      expect(repository.dailyChoiceGroupQueries, isEmpty);

      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon && widget.icon == DoableIconData.archive,
        ),
        findsNothing,
      );
      semantics.dispose();
    });
  }

  testWidgets(
    'вкладка и группа переживают переключения и страницу сверху, назад закрывает страницу',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final router = await _openPage(tester, repository);
      repository.detailRequests.single.add(
        ResultSuccess(testDetailsIntention()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);

      await tester.tap(find.text('Relations'));
      await tester.pumpAndSettle();
      expect(repository.relationGroupQueries, hasLength(1));
      expect(find.text('Описание'), findsNothing);
      final can = find.byKey(
        const ValueKey('intention-relations-group-canUse'),
      );
      await tester.ensureVisible(can);
      await tester.pumpAndSettle();
      await tester.tap(can);
      await tester.pumpAndSettle();
      expect(
        repository.relationGroupQueries.last.type,
        LongTermRelationType.can,
      );
      final queries = repository.relationGroupQueries.length;

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Описание'), findsOneWidget);
      await tester.tap(find.text('Relations'));
      await tester.pumpAndSettle();
      // Возвращение получает заново только первую порцию активной части
      // сохранённой группы: архив её свёрнут.
      expect(repository.relationGroupQueries, hasLength(queries + 1));
      final reread = repository.relationGroupQueries.last;
      expect(reread.type, LongTermRelationType.can);
      expect(reread.direction, RelationDirection.outgoing);
      expect(reread.scope, RelationScope.active);
      expect(reread.cursor, isNull);
      expect(
        tester.getSemantics(can).getSemanticsData().flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      final queriesBeforeOpening = repository.relationGroupQueries.length;

      final other = testDetailsIntention(index: 2);
      _pagePosition(tester).jumpTo(100);
      await tester.pumpAndSettle();
      final offsetBeforeOpening = _pagePosition(tester).pixels;
      expect(offsetBeforeOpening, greaterThan(0));
      unawaited(router.push(IntentionDetailsRoute(intentionId: other.id)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      repository.detailRequests.last.add(ResultSuccess(other));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(_pagePosition(tester).pixels, offsetBeforeOpening);
      expect(can, findsOneWidget);
      expect(repository.relationGroupQueries, hasLength(queriesBeforeOpening));
      expect(find.text('Описание'), findsNothing);

      await tester.tap(find.text('Statistics').first);
      await tester.pumpAndSettle();
      expect(find.byType(AppNavigationBar), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectHomeRootPage(router);
      expect(find.byType(IntentionDetailsPage), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('цель статистики выбирает вкладку без чтения соседства', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    await _openPage(
      tester,
      repository,
      target: StatisticsTarget(
        IntentionStatisticsTarget(
          view: StatisticsView.intermediateIntentions,
          period: StatisticsYear(2025),
        ),
      ),
    );
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();
    expect(repository.relationGroupQueries, isEmpty);
    expect(repository.dailyChoiceGroupQueries, isEmpty);
    expect(find.text('Описание'), findsNothing);
    final query = repository.statisticsQueries.single;
    expect(query.view, StatisticsView.intermediateIntentions);
    expect(query.period, StatisticsYear(2025));
    expect(find.text('Statistics').first.hitTestable(), findsOneWidget);
  });
}

ScrollPosition _pagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void _expectTabsLine(WidgetTester tester, {required bool visible}) {
  final decoration =
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byType(Tabs<IntentionDetailsTab>),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;
  expect(decoration.border, visible ? isNotNull : isNull);
}

Future<AppRouter> _openPage(
  WidgetTester tester,
  ControlledDetailsRepository repository, {
  Locale locale = const Locale('en'),
  IntentionPageTarget target = const OverviewTarget(),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    router.push(
      IntentionDetailsRoute(
        intentionId: testDetailsIntention().id,
        target: target,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return router;
}
