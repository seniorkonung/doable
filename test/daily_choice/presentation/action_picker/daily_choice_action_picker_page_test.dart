import 'dart:async';
import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show testSummary;
import '../../../long_term_relation/presentation/participant_picker/participant_picker_test_support.dart';
import '../../../support/app_root_pages.dart';
import '../daily_choice_picker_tag_search_test_support.dart';
import '../daily_choice_picker_context_test_support.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  defineDailyChoicePickerContextTests(
    route: (pickerContext) =>
        DailyChoiceActionPickerRoute(pickerContext: pickerContext),
    keyPrefix: 'daily-choice-action',
    readinessFilter: IntentionReadinessFilter.readyOnly,
    emptyMessage: 'No active actions are available.',
    noMatchesMessage: 'No actions match this title.',
    detailsTooltip: 'Open action details',
  );
  defineDailyChoicePickerTagSearchTests(
    DailyChoicePickerTagSearchCase(
      route: DailyChoiceActionPickerRoute(),
      keyPrefix: 'daily-choice-action',
      readinessFilter: IntentionReadinessFilter.readyOnly,
      rowReadiness: const [IntentionReadiness.ready],
      totalCountLabel: (count) => 'Total actions: $count',
      emptyScopeMessage: 'No active actions are available.',
      unavailableMessage: 'Actions couldn’t be loaded. Try again.',
    ),
  );

  testWidgets(
    'выбирает одноимённое действие по идентификатору и открывает подробности',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);

      final selection = router.push<IntentionId>(
        DailyChoiceActionPickerRoute(),
      );
      await _settleRoute(tester);
      expect(repository.queryAt(1).scope, IntentionScope.active);
      expect(
        repository.queryAt(1).readinessFilter,
        IntentionReadinessFilter.readyOnly,
      );
      _completeFirst(repository, 1, [
        testSummary(
          index: 2,
          title: 'Позвонить',
          readiness: IntentionReadiness.ready,
        ),
        testSummary(
          index: 3,
          title: 'Позвонить',
          readiness: IntentionReadiness.ready,
          description: 'Описание',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Позвонить'), findsNWidgets(2));
      expect(find.text('Has description'), findsOneWidget);
      expect(find.text('No description'), findsOneWidget);

      await tester.tap(find.byTooltip('Open action details').last);
      await _settleRoute(tester);
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        testSummary(index: 3).id,
      );

      await router.maybePop();
      await _settleRoute(tester);
      expect(find.text('Позвонить'), findsNWidgets(2));
      await tester.tap(find.text('Позвонить').last);
      await tester.pumpAndSettle();
      expect(await selection, testSummary(index: 3).id);
    },
  );

  for (final (language, markLabel, totalCount) in [
    ('en', 'Favorite intention', 'Total actions: 2'),
  ]) {
    testWidgets(
      '$language: одноимённые действия показаны без отметки избранного '
      'и выбираются по идентификатору',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ControlledParticipantPickerRepository();
        addTearDown(repository.dispose);
        final router = await _pumpApp(
          tester,
          repository,
          locale: Locale(language),
        );
        addTearDown(router.dispose);

        final selection = router.push<IntentionId>(
          DailyChoiceActionPickerRoute(),
        );
        await _settleRoute(tester);
        expect(repository.queryAt(1).titleFilter, isNull);
        expect(repository.queryAt(1).tagFilter, IntentionTagFilter.empty);
        _completeFirst(repository, 1, [
          testSummary(
            index: 2,
            title: 'Гулять',
            readiness: IntentionReadiness.ready,
          ),
          testSummary(
            index: 3,
            title: 'Гулять',
            readiness: IntentionReadiness.ready,
          ),
        ]);
        await tester.pumpAndSettle();

        final rows = find.byType(IntentionSummaryView);
        expect(rows, findsNWidgets(2));
        expect(find.text(totalCount), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
        expect(
          tester.getSemantics(rows.at(0)).label,
          isNot(contains(markLabel)),
        );
        expect(
          tester.getSemantics(rows.at(1)).label,
          isNot(contains(markLabel)),
        );

        expect(find.byIcon(Icons.star_border), findsNothing);
        expect(find.text(markLabel), findsNothing);
        expect(find.byTooltip(markLabel), findsNothing);

        // Выбор по-прежнему возвращает намерение строки по идентификатору.
        await tester.tap(find.text('Гулять').first);
        await tester.pumpAndSettle();
        expect(await selection, testSummary(index: 2).id);

        semantics.dispose();
      },
    );
  }

  for (final (handoff, variant) in [
    (_PageFlingHandoff.listInertia, 'инерция списка, дошедшая до его края'),
    (_PageFlingHandoff.fromListEdge, 'флинг, начатый у края списка'),
  ]) {
    testWidgets('касание строки во время инерции к параметрам поиска, которую '
        'странице в режиме общей прокрутки параметров и выдачи передала '
        '$variant, не завершает выбор, а касание после остановки выбирает '
        'действие', (tester) async {
      // Открытая клавиатура на телефоне в альбомной ориентации оставляет
      // выдаче под параметрами меньше трети высоты: параметры и выдача
      // прокручиваются вместе.
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.reset);
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);
      var selected = false;
      final selection = router.push<IntentionId>(
        DailyChoiceActionPickerRoute(),
      );
      unawaited(selection.then((_) => selected = true));
      await _settleRoute(tester);
      final items = [
        for (var index = 1; index <= 8; index++)
          testSummary(
            index: index,
            title: 'Действие $index',
            readiness: IntentionReadiness.ready,
          ),
      ];
      _completeFirst(repository, 1, items);
      await tester.pumpAndSettle();
      final page = _pageScrollPosition(tester);
      final list = _actionListScrollPosition(tester);
      expect(page.maxScrollExtent, greaterThan(0));
      // Прокрученная до конца страница показывает список выдачи целиком.
      page.jumpTo(page.maxScrollExtent);
      if (handoff == _PageFlingHandoff.listInertia) {
        list.jumpTo(list.maxScrollExtent);
      }
      await tester.pumpAndSettle();

      await tester.flingFrom(
        _visibleActionList(tester).topLeft + const Offset(24, 24),
        const Offset(0, 60),
        handoff.speed,
      );
      // Касание приходится на ещё видимую часть списка, пока страница не
      // дошла до параметров поиска.
      await _pumpUntilPageInertia(
        tester,
        (page) =>
            page.pixels < page.maxScrollExtent &&
            _visibleActionList(tester).height >= 24,
      );

      expect(list.pixels, moreOrLessEquals(0));
      final stopped = page.pixels;
      final point = _visibleActionList(tester).center;
      final row = _actionRowAt(tester, point);
      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(selected, isFalse);
      expect(page.isScrollingNotifier.value, isFalse);
      expect(page.pixels, stopped);
      expect(page.pixels, greaterThan(0));

      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(
        await selection,
        items.singleWhere((summary) => summary.title == row).id,
      );
    });
  }

  testWidgets('различает загрузку, пустой результат и устранимую ошибку', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(tester, repository);
    addTearDown(router.dispose);

    unawaited(router.push<IntentionId>(DailyChoiceActionPickerRoute()));
    await _settleRoute(tester);
    expect(find.text('Loading actions…'), findsOneWidget);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(find.text('Actions couldn’t be loaded. Try again.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    _completeFirst(repository, 2, []);
    await tester.pumpAndSettle();
    expect(find.text('No active actions are available.'), findsOneWidget);
  });

  testWidgets(
    'буквальный фильтр сохраняет режим выбора действия и отменяется',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);
      final selection = router.push<IntentionId>(
        DailyChoiceActionPickerRoute(),
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
        find.byKey(const ValueKey('daily-choice-action-filter')),
        '100%',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.queryAt(2).titleFilter?.map((value) => value), '100%');
      expect(repository.queryAt(2).scope, IntentionScope.active);
      expect(
        repository.queryAt(2).readinessFilter,
        IntentionReadinessFilter.readyOnly,
      );
      _completeFirst(repository, 2, []);
      await tester.pumpAndSettle();
      expect(find.text('No actions match this title.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-action-cancel')),
      );
      await tester.pumpAndSettle();
      expect(await selection, isNull);
    },
  );

  testWidgets('подгружает пять порций по 50 из 250 действий', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(tester, repository, pageSize: 50);
    addTearDown(router.dispose);

    final selection = router.push<IntentionId>(DailyChoiceActionPickerRoute());
    await _settleRoute(tester);
    expect(repository.queryAt(1).pageSize, 50);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: _actions(1),
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
          find.byKey(const PageStorageKey<String>('daily-choice-action-list')),
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
            items: _actions(page),
            nextCursor: page == 5 ? null : const TestPickerCursor(),
            revision: const TestPickerRevision(1),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    final list = find.byKey(
      const PageStorageKey<String>('daily-choice-action-list'),
    );
    await tester.scrollUntilVisible(
      find.text('Действие 1'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
    expect(find.text('Действие 1'), findsOneWidget);
    await tester.tap(find.text('Действие 1'));
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 1).id);
    expect(repository.queries, hasLength(6));
  });

  testWidgets('локализует выбор и сохраняет действия', (tester) async {
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
    );
    addTearDown(router.dispose);
    final selection = router.push<IntentionId>(DailyChoiceActionPickerRoute());
    await _settleRoute(tester);
    _completeFirst(repository, 1, [
      testSummary(
        index: 2,
        title: 'Прогуляться',
        readiness: IntentionReadiness.ready,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Выбор действия'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-choice-action-filter')),
      findsOneWidget,
    );
    final option = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(option.label, contains('Прогуляться'));
    expect(option.hint, 'Выбрать это действие для поиска основания');
    final details = tester.getSemantics(
      find.byTooltip('Открыть подробности действия'),
    );
    expect(details.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.text('Прогуляться'));
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 2).id);
    handle.dispose();
  });
}

/// Путь, которым инерция флинга по списку выдачи переходит к странице.
enum _PageFlingHandoff {
  /// Флинг начат при списке в начале: страница продолжает инерцию списка,
  /// дошедшую до его края.
  listInertia(speed: 6000),

  /// Флинг начат при списке уже у края: список не сдвигается, и инерцию
  /// пальца сразу продолжает страница.
  fromListEdge(speed: 2000);

  const _PageFlingHandoff({required this.speed});

  /// Скорость флинга, с которой страница ещё движется, когда касание
  /// приходится на строку.
  final double speed;
}

/// Общая прокрутка параметров поиска и выдачи страницы выбора.
ScrollPosition _pageScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(IntentionSearchLayout),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

ScrollPosition _actionListScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(
          const PageStorageKey<String>('daily-choice-action-list'),
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// Видимая часть списка выдачи: под шапкой и над клавиатурой.
Rect _visibleActionList(WidgetTester tester) {
  final list = tester.getRect(
    find.byKey(const PageStorageKey<String>('daily-choice-action-list')),
  );
  final view = tester.view;
  final bodyBottom =
      (view.physicalSize.height - view.viewInsets.bottom) /
      view.devicePixelRatio;
  return Rect.fromLTRB(
    list.left,
    math.max(list.top, tester.getRect(find.byType(AppBar)).bottom),
    list.right,
    math.min(list.bottom, bodyBottom),
  );
}

/// Название действия в строке под точкой [point].
String _actionRowAt(WidgetTester tester, Offset point) => find
    .byType(IntentionSummaryView)
    .evaluate()
    .map((element) => element.widget as IntentionSummaryView)
    .singleWhere((row) => tester.getRect(find.byWidget(row)).contains(point))
    .title;

/// Ведёт кадры с частотой экрана, пока страница не продолжает инерцию за
/// списком выдачи и не выполнено [ready], и останавливается посреди
/// инерции.
Future<void> _pumpUntilPageInertia(
  WidgetTester tester,
  bool Function(ScrollPosition page) ready,
) async {
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final page = _pageScrollPosition(tester);
    if (page.isScrollingNotifier.value && ready(page)) return;
  }
  fail('Страница не продолжила инерцию списка выдачи.');
}

List<IntentionSummary> _actions(int page) => [
  for (
    var index = 250 - (page - 1) * 50;
    index > 200 - (page - 1) * 50;
    index--
  )
    testSummary(
      index: index,
      title: 'Действие $index',
      readiness: IntentionReadiness.ready,
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
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
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
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  _completeFirst(repository, 0, []);
  await tester.pumpAndSettle();
  return router;
}
