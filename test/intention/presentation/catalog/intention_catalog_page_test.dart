import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';
import 'catalog_reconciliation_test_support.dart';

void main() {
  testWidgets('показывает загрузку до подтверждённой первой страницы', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    expect(find.text('Loading intentions…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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
  });

  testWidgets('показывает подтверждённые сводки и точное количество', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(
              index: 1,
              title: 'Позвонить врачу',
              hasDescription: true,
              readiness: IntentionReadiness.ready,
            ),
            testSummary(index: 2, title: 'Выбрать страховку'),
          ],
          totalCount: 12,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total intentions: 12'), findsOneWidget);
    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Выбрать страховку'), findsOneWidget);
    expect(find.text('Ready for action'), findsOneWidget);
    expect(find.text('Has description'), findsOneWidget);
  });

  testWidgets('явно сообщает архивное состояние строки в охвате всех', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
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

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pump();

    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(
              title: 'Архивное намерение',
              archiveState: IntentionArchiveState.archived,
            ),
          ],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Архивное намерение'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Архивное намерение.*Archived', dotAll: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('каталог проходит accessibility guidelines при масштабе 200%', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(
              title: 'Доступное намерение',
              hasDescription: true,
              readiness: IntentionReadiness.ready,
            ),
          ],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('показывает отдельное пустое состояние активного охвата', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
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

    expect(find.text('No active intentions yet.'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('предлагает повтор только при устранимой недоступности', (
    tester,
  ) async {
    final scenarios = <(IntentionFailure, String, bool)>[
      (
        const IntentionUnavailableFailure(),
        'Intentions couldn’t be loaded. Try again.',
        true,
      ),
      (
        const IntentionCorruptionFailure(),
        'Stored intention data is damaged and can’t be shown.',
        false,
      ),
      (
        const IntentionUnexpectedFailure(),
        'Intentions couldn’t be loaded because of an unexpected error.',
        false,
      ),
    ];

    for (final (failure, message, hasRetry) in scenarios) {
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository));
      repository.queryAt(0);
      repository.complete(0, ResultFailure(failure));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Try again'),
        hasRetry ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('показывает локализованные параметры каталога и четыре порядка', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    expect(find.text('Scope'), findsOneWidget);
    expect(find.text('Filter by title'), findsOneWidget);
    expect(find.text('Order'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Created: newest first'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Active'), findsWidgets);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.text('Active').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('catalog-order-control')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Created: newest first'), findsWidgets);
    expect(find.text('Created: oldest first'), findsOneWidget);
    expect(find.text('Updated: newest first'), findsOneWidget);
    expect(find.text('Updated: oldest first'), findsOneWidget);
  });

  testWidgets('применяет фильтр через 250 мс без кнопки отправки', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    await tester.enterText(
      find.byKey(const ValueKey('catalog-filter-field')),
      'milk',
    );
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.queries, hasLength(1));
    expect(find.widgetWithText(FilledButton, 'Search'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.queries, hasLength(2));
    expect(repository.queryAt(1).titleFilter?.map((value) => value), 'milk');
  });

  testWidgets('сохраняет недопустимый фильтр и показывает ошибку поля', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);
    final invalidFilter = List.filled(256, 'a').join();

    await tester.enterText(
      find.byKey(const ValueKey('catalog-filter-field')),
      invalidFilter,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(repository.queries, hasLength(1));
    expect(find.text('Use no more than 255 characters.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('catalog-filter-field')))
          .controller
          ?.text,
      invalidFilter,
    );
  });

  testWidgets('начинает новый охват с верхней позиции', (tester) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            for (var index = 1; index <= 30; index++)
              testSummary(index: index, title: 'Намерение $index'),
          ],
          totalCount: 30,
          nextCursor: null,
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    expect(_catalogScrollPosition(tester).pixels, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived').last);
    await tester.pump();
    expect(repository.queryAt(1).scope, IntentionScope.archived);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            for (var index = 31; index <= 60; index++)
              testSummary(index: index, title: 'Архивное $index'),
          ],
          totalCount: 30,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_catalogScrollPosition(tester).pixels, 0);
  });

  testWidgets('сохраняет позицию списка через постоянный PageStorageKey', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 1)],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<ListView>(find.byType(ListView)).key,
      const PageStorageKey<String>('intention-catalog-list'),
    );
  });

  testWidgets('сохраняет visual anchor при изменениях перед видимой позицией', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(_testAppWithContainer(container));
    final items = [
      for (var index = 30; index >= 1; index--)
        testSummary(index: index, title: 'Намерение $index'),
    ];
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: items,
          totalCount: items.length,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    final anchor = _firstVisibleCatalogTile(tester);
    final anchorIndex = items.indexWhere((item) => item.title == anchor.title);
    final anchorSummary = items[anchorIndex];
    final nearestSummary = items[anchorIndex + 1];

    final inserted = testSummary(index: 31, title: 'Новое намерение');
    await _completeCatalogWidgetCommand(
      tester,
      container,
      repository,
      const CreateIntention(title: 'Новое намерение', description: null),
      IntentionSaved(
        testIntention(index: 31, title: 'Новое намерение'),
        catalogMutation: IntentionCatalogCreated(
          revision: const TestCatalogRevision(2),
          entry: TestCatalogEntrySnapshot(inserted),
        ),
      ),
    );

    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    final movedBeforeAnchor = testSummary(
      index: 1,
      title: 'Намерение 1',
      createdDay: 32,
    );
    await _completeCatalogWidgetCommand(
      tester,
      container,
      repository,
      UpdateIntention(
        id: movedBeforeAnchor.id,
        title: movedBeforeAnchor.title,
        description: null,
      ),
      IntentionSaved(
        testIntention(index: 1, title: 'Намерение 1'),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(3),
          before: TestCatalogEntrySnapshot(items.last),
          after: TestCatalogEntrySnapshot(movedBeforeAnchor),
        ),
      ),
    );

    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    await _completeCatalogWidgetCommand(
      tester,
      container,
      repository,
      DeleteIntention(movedBeforeAnchor.id),
      IntentionDeleted(
        movedBeforeAnchor.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const TestCatalogRevision(4),
          entry: TestCatalogEntrySnapshot(movedBeforeAnchor),
        ),
      ),
    );

    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    await _completeCatalogWidgetCommand(
      tester,
      container,
      repository,
      DeleteIntention(anchorSummary.id),
      IntentionDeleted(
        anchorSummary.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const TestCatalogRevision(5),
          entry: TestCatalogEntrySnapshot(anchorSummary),
        ),
      ),
    );

    expect(find.text(anchor.title), findsNothing);
    expect(
      _catalogTileTop(tester, nearestSummary.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );
  });

  testWidgets('сохраняет порции и позицию после типизированного перехода', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 20,
      prefetchRemaining: 2,
    );
    final router = AppRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerTestAppWithContainer(container, router));
    await tester.pump();
    repository.queryAt(0);
    await tester.enterText(
      find.byKey(const ValueKey('catalog-filter-field')),
      'Намерение',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(repository.queries, hasLength(2));
    expect(
      repository.queryAt(1).titleFilter?.map((value) => value),
      'Намерение',
    );
    const cursor = TestCatalogCursor();
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            for (var index = 30; index >= 11; index--)
              testSummary(index: index, title: 'Намерение $index'),
          ],
          totalCount: 30,
          nextCursor: cursor,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
      const Offset(0, -1000),
    );
    await _pumpUntilQueries(tester, repository, 3);
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [
            for (var index = 10; index >= 1; index--)
              testSummary(index: index, title: 'Намерение $index'),
          ],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final beforePosition = _catalogScrollPosition(tester).pixels;
    final beforeState =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(beforeState.items, hasLength(30));
    expect(beforePosition, greaterThan(0));
    expect(beforeState.query.titleFilter?.map((value) => value), 'Намерение');

    await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
    await tester.pumpAndSettle();
    expect(router.current.name, IntentionEditorRoute.name);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final afterState =
        container.read(intentionCatalogViewModelProvider).requireValue
            as IntentionCatalogLoaded;
    expect(router.current.name, IntentionCatalogRoute.name);
    expect(repository.queries, hasLength(3));
    expect(afterState.query, same(beforeState.query));
    expect(
      afterState.items.map((item) => item.id),
      beforeState.items.map((item) => item.id),
    );
    expect(
      _catalogScrollPosition(tester).pixels,
      moreOrLessEquals(beforePosition, epsilon: 0.01),
    );
  });

  testWidgets('локализует параметры каталога на русский язык', (tester) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository, locale: const Locale('ru')));
    repository.queryAt(0);

    expect(find.text('Охват'), findsOneWidget);
    expect(find.text('Фильтр по названию'), findsOneWidget);
    expect(find.text('Порядок'), findsOneWidget);
    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('По созданию: сначала новые'), findsOneWidget);
  });

  testWidgets('автоматически загружает у порога и повторяет ту же порцию', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(
      _testApp(repository, pageSize: 20, prefetchRemaining: 2),
    );
    const cursor = TestCatalogCursor();
    const revision = TestCatalogRevision(3);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            for (var index = 1; index <= 20; index++)
              testSummary(index: index, title: 'Намерение $index'),
          ],
          totalCount: 21,
          nextCursor: cursor,
          revision: revision,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(1));

    await tester.drag(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
      const Offset(0, -1000),
    );
    await _pumpUntilQueries(tester, repository, 2);
    await tester.pump();
    expect(repository.queryAt(1).cursor, same(cursor));
    await tester.drag(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('Loading more intentions…'), findsOneWidget);

    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(find.text('More intentions couldn’t be loaded.'), findsOneWidget);

    final retryButton = find.widgetWithText(FilledButton, 'Try again');
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await _pumpUntilQueries(tester, repository, 3);
    expect(repository.queryAt(2).cursor, same(cursor));
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 21, title: 'Последнее намерение')],
          nextCursor: null,
          revision: revision,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total intentions: 21'), findsOneWidget);
    expect(repository.queries, hasLength(3));
  });

  testWidgets('не предлагает retry для terminal-ошибки продолжения', (
    tester,
  ) async {
    final scenarios = <(IntentionFailure, String)>[
      (
        const IntentionCorruptionFailure(),
        'Stored intention data is damaged; no more intentions can be shown.',
      ),
      (
        const IntentionUnexpectedFailure(),
        'More intentions couldn’t be loaded because of an unexpected error.',
      ),
    ];

    for (final (failure, message) in scenarios) {
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(
        _testApp(repository, pageSize: 2, prefetchRemaining: 1),
      );
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [testSummary(index: 1), testSummary(index: 2)],
            totalCount: 3,
            nextCursor: const TestCatalogCursor(),
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await _pumpUntilQueries(tester, repository, 2);
      repository.complete(1, ResultFailure(failure));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Reload catalog'), findsNothing);
    }
  });

  testWidgets('восстанавливает validation продолжения с первой страницы', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(
      _testApp(repository, pageSize: 2, prefetchRemaining: 1),
    );
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(index: 1, title: 'Прежнее первое'),
            testSummary(index: 2, title: 'Прежнее второе'),
          ],
          totalCount: 3,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await _pumpUntilQueries(tester, repository, 2);
    repository.complete(
      1,
      const ResultFailure(IntentionGenericValidationFailure()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The saved catalog position is no longer valid.'),
      findsOneWidget,
    );
    expect(find.text('Прежнее первое'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reload catalog'));
    await _pumpUntilQueries(tester, repository, 3);
    expect(repository.queryAt(2).cursor, isNull);
    expect(find.text('Прежнее первое'), findsOneWidget);
    expect(find.text('Reloading catalog…'), findsOneWidget);

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testSummary(index: 3, title: 'Актуальное')],
          totalCount: 1,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Актуальное'), findsOneWidget);
    expect(find.text('Прежнее первое'), findsNothing);
    expect(find.text('Total intentions: 1'), findsOneWidget);
  });
}

ScrollPosition _catalogScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const PageStorageKey<String>('intention-catalog-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Widget _testApp(
  ControlledCatalogRepository repository, {
  Locale locale = const Locale('en'),
  int pageSize = 100,
  int prefetchRemaining = 30,
}) => ProviderScope(
  overrides: [
    personalGraphRepositoryProvider.overrideWithValue(repository),
    catalogPagingPolicyProvider.overrideWithValue(
      CatalogPagingPolicy(
        pageSize: pageSize,
        prefetchRemaining: prefetchRemaining,
        filterDebounce: const Duration(milliseconds: 250),
      ),
    ),
  ],
  retry: (retryCount, error) => null,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const IntentionCatalogPage(),
  ),
);

Widget _testAppWithContainer(ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const IntentionCatalogPage(),
      ),
    );

Widget _routerTestAppWithContainer(
  ProviderContainer container,
  AppRouter router,
) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router.config(),
  ),
);

({String title, double top}) _firstVisibleCatalogTile(WidgetTester tester) {
  final listRect = tester.getRect(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
  );
  final visible = <({String title, double top})>[];
  for (final element in find.byType(ListTile).evaluate()) {
    final tile = element.widget as ListTile;
    final title = tile.title;
    if (title is! Text || title.data == null) {
      continue;
    }
    final finder = find.byElementPredicate(
      (candidate) => identical(candidate, element),
    );
    final rect = tester.getRect(finder);
    if (rect.bottom > listRect.top && rect.top < listRect.bottom) {
      visible.add((title: title.data!, top: rect.top));
    }
  }
  visible.sort((left, right) => left.top.compareTo(right.top));
  return visible.first;
}

double _catalogTileTop(WidgetTester tester, String title) => tester
    .getTopLeft(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == title,
      ),
    )
    .dy;

Future<void> _completeCatalogWidgetCommand(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionCommand command,
  IntentionCommandSuccess success,
) async {
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final commandIndex = repository.commands.length;
  final start = switch (command) {
    CreateIntention() => coordinator.acceptCreation(
      IntentionCreationFormKey(),
      command,
    ),
    ExistingIntentionCommand() => coordinator.acceptExisting(
      command,
      presentationTitle: 'Намерение',
    ),
  };
  expect(start, isA<IntentionCommandAccepted>());
  final accepted = start as IntentionCommandAccepted;
  repository.completeCommand(commandIndex, ResultSuccess(success));
  final completion = await accepted.future;
  final claim = coordinator.claimInitiator(completion.token);
  if (claim != null) {
    coordinator.confirmPresentation(claim);
  }
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpUntilQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (repository.queries.length >= count) {
      return;
    }
  }
  fail('Не дождались $count запросов каталога.');
}
