import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show testSummary;
import '../../../long_term_relation/presentation/participant_picker/participant_picker_test_support.dart';

void main() {
  testWidgets(
    'выбирает одноимённое основание по идентификатору и открывает подробности',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);

      final selection = router.push<IntentionId>(
        const DailyChoiceSourcePickerRoute(),
      );
      await _settleRoute(tester);
      expect(repository.queryAt(1).scope, IntentionScope.active);
      expect(
        repository.queryAt(1).readinessFilter,
        IntentionReadinessFilter.all,
      );
      _completeFirst(repository, 1, [
        testSummary(
          index: 2,
          title: 'Позвонить',
          readiness: IntentionReadiness.notReady,
        ),
        testSummary(
          index: 3,
          title: 'Позвонить',
          readiness: IntentionReadiness.ready,
          hasDescription: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Позвонить'), findsNWidgets(2));
      expect(find.text('Has description'), findsOneWidget);
      expect(find.text('No description'), findsOneWidget);
      expect(find.text('Ready for action'), findsOneWidget);
      expect(find.text('Not ready for action'), findsOneWidget);

      await tester.tap(find.byTooltip('Open intention details').last);
      await _settleRoute(tester);
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        testSummary(index: 3).id,
      );

      await router.maybePop();
      await _settleRoute(tester);
      expect(find.text('Позвонить'), findsNWidgets(2));
      expect(repository.queries, hasLength(2));
      await tester.tap(find.text('Позвонить').last);
      await tester.pumpAndSettle();
      expect(await selection, testSummary(index: 3).id);
    },
  );

  testWidgets('различает загрузку, пустой результат и устранимую ошибку', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(tester, repository);
    addTearDown(router.dispose);

    unawaited(router.push<IntentionId>(const DailyChoiceSourcePickerRoute()));
    await _settleRoute(tester);
    expect(find.text('Loading intentions…'), findsOneWidget);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(
      find.text('Intentions couldn’t be loaded. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    _completeFirst(repository, 2, []);
    await tester.pumpAndSettle();
    expect(find.text('No active intentions are available.'), findsOneWidget);
  });

  testWidgets(
    'буквальный фильтр сохраняет режим выбора основания и отменяется',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);
      final selection = router.push<IntentionId>(
        const DailyChoiceSourcePickerRoute(),
      );
      await _settleRoute(tester);
      _completeFirst(repository, 1, [
        testSummary(
          index: 1,
          title: '100%',
          readiness: IntentionReadiness.ready,
        ),
      ]);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-source-filter')),
        '100%',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.queryAt(2).titleFilter?.map((value) => value), '100%');
      expect(repository.queryAt(2).scope, IntentionScope.active);
      expect(
        repository.queryAt(2).readinessFilter,
        IntentionReadinessFilter.all,
      );
      _completeFirst(repository, 2, []);
      await tester.pumpAndSettle();
      expect(find.text('No intentions match this title.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-source-cancel')),
      );
      await tester.pumpAndSettle();
      expect(await selection, isNull);
    },
  );

  testWidgets('подгружает пять порций по 50 из 250 намерений', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(tester, repository, pageSize: 50);
    addTearDown(router.dispose);

    final selection = router.push<IntentionId>(
      const DailyChoiceSourcePickerRoute(),
    );
    await _settleRoute(tester);
    expect(repository.queryAt(1).pageSize, 50);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: _intentions(1),
          totalCount: 250,
          nextCursor: const TestPickerCursor(),
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var page = 2; page <= 5; page++) {
      for (
        var attempt = 0;
        attempt < 30 && repository.queries.length <= page;
        attempt++
      ) {
        await tester.drag(
          find.byKey(const PageStorageKey<String>('daily-choice-source-list')),
          const Offset(0, -600),
        );
        await tester.pump();
      }
      expect(repository.queries.length, greaterThan(page));
      expect(repository.queryAt(page).pageSize, 50);
      repository.complete(
        page,
        ResultSuccess(
          IntentionCatalogContinuationPage(
            items: _intentions(page),
            nextCursor: page == 5 ? null : const TestPickerCursor(),
            revision: const TestPickerRevision(1),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    final list = find.byKey(
      const PageStorageKey<String>('daily-choice-source-list'),
    );
    expect(
      tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
      250,
    );
    await tester.scrollUntilVisible(
      find.text('Намерение 1'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
      maxScrolls: 100,
    );
    expect(find.text('Намерение 1'), findsOneWidget);
    await tester.tap(find.text('Намерение 1'));
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 1).id);
    expect(repository.queries, hasLength(6));
  });

  testWidgets('локализует выбор и сохраняет основания при крупном тексте', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(
      tester,
      repository,
      locale: const Locale('ru'),
      textScaler: const TextScaler.linear(2),
    );
    addTearDown(router.dispose);
    final selection = router.push<IntentionId>(
      const DailyChoiceSourcePickerRoute(),
    );
    await _settleRoute(tester);
    _completeFirst(repository, 1, [
      testSummary(
        index: 2,
        title: 'Быть здоровым',
        readiness: IntentionReadiness.ready,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Выбор основания'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-choice-source-filter')),
      findsOneWidget,
    );
    final option = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(option.label, contains('Быть здоровым'));
    expect(option.hint, 'Выбрать это намерение как новое основание');
    final details = tester.getSemantics(
      find.byTooltip('Открыть подробности намерения'),
    );
    expect(details.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.text('Быть здоровым'));
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 2).id);
    handle.dispose();
  });
}

List<IntentionSummary> _intentions(int page) => [
  for (
    var index = 250 - (page - 1) * 50;
    index > 200 - (page - 1) * 50;
    index--
  )
    testSummary(
      index: index,
      title: 'Намерение $index',
      readiness: index.isEven
          ? IntentionReadiness.ready
          : IntentionReadiness.notReady,
    ),
];

void _completeFirst(
  ControlledParticipantPickerRepository repository,
  int index,
  List<IntentionSummary> items,
) => repository.complete(
  index,
  ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestPickerRevision(1),
    ),
  ),
);

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<AppRouter> _pumpApp(
  WidgetTester tester,
  ControlledParticipantPickerRepository repository, {
  Locale locale = const Locale('en'),
  int pageSize = 50,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: 20,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  _completeFirst(repository, 0, []);
  await tester.pumpAndSettle();
  return router;
}
