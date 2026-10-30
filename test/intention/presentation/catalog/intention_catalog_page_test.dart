import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/catalog_row.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/intention_catalog_controls.dart';
import '../../../support/quick_creation.dart';
import 'catalog_test_support.dart';
import 'catalog_reconciliation_test_support.dart';
import '../../../support/tag_condition_cycles.dart';
import '../../../support/tag_positions.dart';

void main() {
  testWidgets('показывает загрузку до подтверждённой первой страницы', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    expect(_inListState(find.text('Loading intentions…')), findsOneWidget);

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
              description: 'Описание',
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
    // Кольцо подгрузки вращается, пока есть следующая порция: покоя кадров
    // не будет.
    await tester.pump();
    await tester.pump();

    expect(intentionCatalogTotal(12), findsOneWidget);
    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Выбрать страховку'), findsOneWidget);
    expect(find.text('Описание'), findsOneWidget);
    expect(find.text('Ready for action'), findsNothing);
    expect(find.text('Has description'), findsNothing);
    expect(_shownMarks(tester), [DoableIconData.bolt]);
  });

  testWidgets('явно сообщает архивное состояние строки в охвате всех', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
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

    await selectIntentionCatalogScope(tester, IntentionScope.all);

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
    expect(_shownMarks(tester), [DoableIconData.archive]);
    expect(
      find.bySemanticsLabel(
        'Open: Архивное намерение, archived, intention, No tags',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('каталог проходит accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();

    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(
              title: 'Доступное намерение',
              description: 'Описание',
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

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
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
      expect(find.text('Try again'), hasRetry ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('заголовок списка открывает лист с числами охватов и типов', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [for (var i = 1; i <= 7; i++) testSummary(index: i)],
          totalCount: 7,
          counts: IntentionCountsByScopeAndType(
            active: IntentionTypeCounts(all: 7, actions: 4),
            archived: IntentionTypeCounts(all: 3, actions: 2),
          ),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CatalogHeader));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(_shownMenu(tester), [
      'Active',
      '7',
      'Archived',
      '3',
      'All, archived included',
      '10',
    ]);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    expect(_shownMenu(tester), [
      'Intentions and actions',
      '7',
      'Intentions only',
      '3',
      'Actions only',
      '4',
    ]);
  });

  testWidgets('смена типа в листе начинает новую выдачу с верхней позиции', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(0, _firstPage(_taggedSummaries(const [], last: 31)));
    await tester.pumpAndSettle();
    _catalogScrollPosition(tester).jumpTo(100);
    await tester.pump();

    await selectIntentionCatalogType(tester, IntentionTypeChoice.actions);
    expect(
      repository.queryAt(1).readinessFilter,
      IntentionReadinessFilter.readyOnly,
    );
    repository.complete(1, _firstPage(_taggedSummaries(const [], last: 31)));
    await tester.pumpAndSettle();

    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(
      shownIntentionCatalogParameters(tester).type,
      IntentionTypeChoice.actions,
    );
  });

  testWidgets('каталог предлагает сортировку по названию в обоих порядках', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(0, _firstPage(_taggedSummaries(const [], last: 58)));
    await tester.pumpAndSettle();

    await selectIntentionCatalogOrder(
      tester,
      IntentionCatalogOrder.titleDescending,
    );

    expect(
      repository.queries.last.order,
      IntentionCatalogOrder.titleDescending,
    );
    repository.complete(
      repository.queries.length - 1,
      _firstPage(_taggedSummaries(const [], last: 58)),
    );
    await tester.pumpAndSettle();
    expect(
      shownIntentionCatalogParameters(tester).order,
      IntentionCatalogOrder.titleDescending,
    );
  });

  testWidgets('применяет фильтр через 250 мс без кнопки отправки', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    await enterIntentionCatalogTitle(tester, 'milk');
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

    await enterIntentionCatalogTitle(tester, invalidFilter);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(repository.queries, hasLength(1));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('intention-catalog-filter')),
        matching: find.text('Use no more than 255 characters.'),
      ),
      findsOneWidget,
    );
    expect(shownIntentionCatalogParameters(tester).titleFilter, invalidFilter);
  });

  testWidgets('при прокрутке списка заголовок страницы, поиск и заголовок '
      'списка остаются на месте', (tester) async {
    _usePhoneScreen(tester);
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(0, _firstPage(_twentySummaries()));
    await tester.pumpAndSettle();
    final pinned = [
      intentionCatalogHeading(tester),
      intentionCatalogTitleField,
      intentionCatalogTagFilterControl,
      find.byType(CatalogHeader),
    ];
    final before = [for (final part in pinned) tester.getRect(part)];

    // Жест уходит дальше конца списка: дальше прокручивать нечего.
    await _dragCatalogList(tester, const Offset(0, -3000));

    final list = _catalogScrollPosition(tester);
    expect(list.pixels, list.maxScrollExtent);
    expect([for (final part in pinned) tester.getRect(part)], before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('при двукратном тексте и открытой клавиатуре на узком экране '
      'страница не переполняется, а список прокручивается под неподвижным '
      'полем поиска', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository, locale: const Locale('ru')));
    repository.complete(0, _firstPage(_twentySummaries()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(intentionCatalogList).height, greaterThan(0));
    final field = tester.getRect(intentionCatalogTitleField);

    await _dragCatalogList(tester, const Offset(0, -60));

    expect(_catalogScrollPosition(tester).pixels, greaterThan(0));
    expect(tester.getRect(intentionCatalogTitleField), field);
    expect(tester.takeException(), isNull);
  });

  for (final (brightness, icons) in [
    (Brightness.light, Brightness.dark),
    (Brightness.dark, Brightness.light),
  ]) {
    testWidgets('значки системной строки контрастны теме ${brightness.name}', (
      tester,
    ) async {
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository, brightness: brightness));
      repository.queryAt(0);
      await tester.pump();

      expect(SystemChrome.latestStyle?.statusBarIconBrightness, icons);
    });
  }

  testWidgets('повтор после отказа первой загрузки перечитывает каталог и '
      'показывает пустую выдачу', (tester) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.queryAt(0);

    repository.complete(0, ResultFailure(const IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(
      find.text('Intentions couldn’t be loaded. Try again.'),
      findsOneWidget,
    );
    final retry = find.text('Try again');
    expect(retry.hitTestable(), findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    repository.complete(1, _firstPage(const []));
    await tester.pumpAndSettle();

    expect(find.text('No intentions yet'), findsOneWidget);
    expect(retry, findsNothing);
    expect(tester.takeException(), isNull);
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

    await _dragCatalogList(tester, const Offset(0, -600));
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

  testWidgets('одиночное назначение и снятие тега сохраняют экранное '
      'положение видимого намерения либо переводят его к ближайшему '
      'соседу', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final items = _taggedSummaries([health], first: 60, last: 2, step: 2);
    await _loadTaggedCatalog(
      tester,
      container,
      repository,
      IntentionTagFilter(requiredTagIds: [health.id]),
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final anchor = await _scrollToMiddle(tester, items);
    final loadingStates = _observeCatalogLoading(container);

    // Назначение обязательного тега добавляет строку перед видимым
    // намерением.
    final untagged = testSummary(index: 59, title: 'Намерение 59');
    final assigned = testSummary(
      index: 59,
      title: 'Намерение 59',
      tags: [health],
    );
    await _completeCatalogWidgetTagAssignment(
      tester,
      container,
      repository,
      state: TagAssignmentState.assigned,
      tagId: health.id,
      before: untagged,
      after: assigned,
      revision: const TestCatalogRevision(2),
    );

    expect(_loadedCatalog(container).items[1].id, assigned.id);
    expect(intentionCatalogTotal(31), findsOneWidget);
    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    // Снятие обязательного тега убирает строку перед видимым намерением.
    await _completeCatalogWidgetTagAssignment(
      tester,
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: items.first,
      after: testSummary(index: 60, title: items.first.title),
      revision: const TestCatalogRevision(3),
    );

    expect(
      _loadedCatalog(container).items.map((item) => item.id),
      isNot(contains(items.first.id)),
    );
    expect(intentionCatalogTotal(30), findsOneWidget);
    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    // Снятие обязательного тега с самого видимого намерения переводит
    // позицию к ближайшему соседу.
    final anchorSummary = items[anchor.index];
    final nearestSummary = items[anchor.index + 1];
    await _completeCatalogWidgetTagAssignment(
      tester,
      container,
      repository,
      state: TagAssignmentState.absent,
      tagId: health.id,
      before: anchorSummary,
      after: testSummary(
        index: _summaryIndex(anchorSummary),
        title: anchorSummary.title,
      ),
      revision: const TestCatalogRevision(4),
    );

    expect(find.text(anchor.title), findsNothing);
    expect(intentionCatalogTotal(29), findsOneWidget);
    expect(
      _catalogTileTop(tester, nearestSummary.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );
    expect(loadingStates, isEmpty);
  });

  testWidgets('сохраняет порции и позицию под панелью создания и после её '
      'закрытия нажатием вне панели', (tester) async {
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
    await openIntentionGraph(tester);
    repository.queryAt(0);
    await enterIntentionCatalogTitle(tester, 'Намерение');
    await tester.pump(const Duration(milliseconds: 250));
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

    await _dragCatalogList(tester, const Offset(0, -2000));
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
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expect(beforeState.items, hasLength(30));
    expect(beforePosition, greaterThan(0));
    expect(beforeState.query.titleFilter?.map((value) => value), 'Намерение');

    await openQuickCreation(
      tester,
      QuickCreationMode.intention,
      openedPage: find.byType(IntentionEditorPage),
    );
    expect(router.current.name, IntentionEditorRoute.name);
    // Панель открыта над тем же каталогом: его выдача и прокрутка на месте,
    // а результат маршрута не запрашивает выдачу повторно.
    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(
      _catalogScrollPosition(tester).pixels,
      moreOrLessEquals(beforePosition, epsilon: 0.01),
    );

    // Нажатие вне неизменённой панели над заголовком каталога закрывает её.
    await tester.tapAt(tester.getCenter(intentionCatalogHeading(tester)));
    await tester.pumpAndSettle();

    final afterState =
        container
                .read(
                  intentionCatalogViewModelProvider(
                    const BrowseIntentionCatalog(),
                  ),
                )
                .requireValue
            as IntentionCatalogLoaded;
    expectIntentionGraphRootPage(router);
    expect(repository.queries, hasLength(3));
    expect(
      afterState.items.map((item) => item.id),
      beforeState.items.map((item) => item.id),
    );
    expect(
      _catalogScrollPosition(tester).pixels,
      moreOrLessEquals(beforePosition, epsilon: 0.01),
    );
  });

  testWidgets('возврат со страницы намерения сохраняет смещение и первую '
      'видимую строку без нового чтения', (tester) async {
    final repository = ControlledCatalogRepository()
      ..intentionObservations = (_) => const Stream.empty();
    final container = reconciliationCatalogContainer(repository);
    final router = AppRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerTestAppWithContainer(container, router));
    await tester.pump();
    await openIntentionGraph(tester);
    repository.complete(0, _firstPage(_taggedSummaries(const [], last: 31)));
    await tester.pumpAndSettle();
    await _dragCatalogList(tester, const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = _catalogScrollPosition(tester).pixels;
    final visible = _firstVisibleCatalogTile(tester);
    expect(offset, greaterThan(0));

    // Вторая видимая строка целиком в списке, в отличие от первой.
    final opened = shownIntentionCatalogRows(tester)
        .firstWhere((row) => row.rect.top > visible.top);
    await tester.tapAt(opened.rect.center);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(await router.maybePop(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expectIntentionGraphRootPage(router);
    expect(_catalogScrollPosition(tester).pixels, offset);
    expect(_firstVisibleCatalogTile(tester), visible);
    expect(repository.queries, hasLength(1));
  });

  // Выдача под параметрами и выдача на всю высоту тела страницы.
  for (final (state, result) in <(String, Result<IntentionCatalogFirstPage>?)>[
    ('загрузка', null),
    ('загруженная выдача', _firstPage([testSummary(title: 'Намерение')])),
  ]) {
    testWidgets('каталог, $state: создание доступно '
        'только через общую панель, а вход в теги сохраняется', (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final router = AppRouter();
      addTearDown(container.dispose);
      addTearDown(router.dispose);
      await tester.pumpWidget(_routerTestAppWithContainer(container, router));
      await tester.pump();
      await openIntentionGraph(tester);
      repository.queryAt(0);
      if (result != null) repository.complete(0, result);
      // Загрузка продолжает анимироваться, поэтому ждём только переход.
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('catalog-create-intention')),
        findsNothing,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(intentionCatalogTagFilterControl.hitTestable(), findsOneWidget);
      final create = quickCreationAction();
      expect(create.hitTestable(), findsOneWidget);
      await tester.tap(create);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(router.current.name, IntentionEditorRoute.name);
      expect(find.byType(IntentionEditorPage), findsOneWidget);
      expect(repository.commands, isEmpty);
      expect(await router.maybePop(), isTrue);
      if (result == null) repository.complete(0, _firstPage(const []));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(router);
      expect(create.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('автоматически загружает у порога и повторяет ту же порцию', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(
      _testApp(repository, pageSize: 30, prefetchRemaining: 2),
    );
    const cursor = TestCatalogCursor();
    const revision = TestCatalogRevision(3);
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            for (var index = 1; index <= 30; index++)
              testSummary(index: index, title: 'Намерение $index'),
          ],
          totalCount: 31,
          nextCursor: cursor,
          revision: revision,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(1));

    await _dragCatalogList(tester, const Offset(0, -3000));
    await _pumpUntilQueries(tester, repository, 2);
    await tester.pump();
    expect(repository.queryAt(1).cursor, same(cursor));
    await _scrollCatalogToEnd(tester);
    expect(_loadingMore, findsOneWidget);

    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(find.text('More intentions couldn’t be loaded.'), findsOneWidget);

    final retryButton = find.text('Try again');
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await _pumpUntilQueries(tester, repository, 3);
    expect(repository.queryAt(2).cursor, same(cursor));
    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [testSummary(index: 31, title: 'Последнее намерение')],
          nextCursor: null,
          revision: revision,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(intentionCatalogTotal(31), findsOneWidget);
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
      expect(find.text('Try again'), findsNothing);
    }
  });

  testWidgets('архивный охват показывает намерения с меткой архива и без '
      'отметки избранного', (tester) async {
    final semantics = tester.ensureSemantics();
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

    await selectIntentionCatalogScope(tester, IntentionScope.archived);
    expect(repository.queryAt(1).scope, IntentionScope.archived);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(
              index: 1,
              title: 'Архивное первое',
              archiveState: IntentionArchiveState.archived,
            ),
            testSummary(
              index: 2,
              title: 'Архивное второе',
              archiveState: IntentionArchiveState.archived,
            ),
          ],
          totalCount: 2,
          nextCursor: null,
          revision: const TestCatalogRevision(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsNothing);
    expect(_shownMarks(tester), [
      DoableIconData.archive,
      DoableIconData.archive,
    ]);
    expect(
      find.bySemanticsLabel(
        'Open: Архивное первое, archived, intention, No tags',
      ),
      findsOneWidget,
    );
    expect(intentionCatalogTotal(2), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('условие, добавленное в панели тегов, сразу начинает выдачу с '
      'верхней позиции', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [health, sport];
    final container = reconciliationCatalogContainer(repository);
    final router = AppRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerTestAppWithContainer(container, router));
    await tester.pump();
    await openIntentionGraph(tester);
    repository.complete(0, _firstPage(_taggedSummaries(const [], last: 1)));
    await tester.pumpAndSettle();

    await _scrollCatalogDown(tester);

    await tester.tap(intentionCatalogTagFilterControl);
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsOneWidget);
    await tester.tap(_panelRow(health));
    await _pumpUntilQueries(tester, repository, 2);

    expect(
      repository.queryAt(1).tagFilter,
      IntentionTagFilter(requiredTagIds: [health.id]),
    );
    expect(repository.queryAt(1).cursor, isNull);
    repository.complete(
      1,
      _firstPage(_taggedSummaries([health], last: 2, step: 2), revision: 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expectIntentionGraphRootPage(router);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
    expect(_rowChips('Здоровье'), findsWidgets);
    expect(repository.tagCommands, isEmpty);
  });

  testWidgets('смена охвата и порядка сохраняет условия по тегам', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [sport.id],
    );
    await _openCatalogWithConditions(tester, container, repository, [
      (health, IntentionTagRequirement.mustBePresent),
      (sport, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(_taggedSummaries([health], last: 58)));

    await selectIntentionCatalogScope(tester, IntentionScope.archived);
    await _pumpUntilQueries(tester, repository, 5);
    expect(repository.queryAt(4).scope, IntentionScope.archived);
    expect(repository.queryAt(4).tagFilter, filter);
    repository.complete(4, _firstPage(_taggedSummaries([health], last: 59)));
    await tester.pumpAndSettle();
    expect(shownIntentionCatalogParameters(tester).tagConditions, 2);

    await selectIntentionCatalogOrder(
      tester,
      IntentionCatalogOrder.createdAtAscending,
    );
    await _pumpUntilQueries(tester, repository, 6);
    expect(repository.queryAt(5).scope, IntentionScope.archived);
    expect(
      repository.queryAt(5).order,
      IntentionCatalogOrder.createdAtAscending,
    );
    expect(repository.queryAt(5).tagFilter, filter);
    repository.complete(5, _firstPage(_taggedSummaries([health], last: 59)));
    await tester.pumpAndSettle();
    expect(shownIntentionCatalogParameters(tester).tagConditions, 2);
  });

  testWidgets('пустая выдача при условиях по тегам сообщает об '
      'отсутствии совпадений по условиям, а не о пустом охвате', (
    tester,
  ) async {
    const byConditions = 'No intentions match these tags';
    const byScope = 'No intentions yet';
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(_testAppWithContainer(container));
    repository.complete(0, _firstPage(const []));
    await tester.pumpAndSettle();
    expect(find.text(byScope), findsOneWidget);
    expect(find.text(byConditions), findsNothing);

    await _selectCondition(
      tester,
      container,
      _tag(1, 'Здоровье'),
      IntentionTagRequirement.mustBePresent,
    );
    await _pumpUntilQueries(tester, repository, 2);
    repository.complete(1, _firstPage(const []));
    await tester.pumpAndSettle();

    expect(find.text(byConditions), findsOneWidget);
    expect(find.text('Reset filters'), findsOneWidget);
    expect(find.text(byScope), findsNothing);
  });

  group('пустая выдача каталога', () {
    final none = IntentionTypeCounts(all: 0, actions: 0);
    final intentionsOnly = IntentionTypeCounts(all: 3, actions: 0);

    for (final (name, scope, type, counts, icon, title, text) in [
      (
        'все намерения в архиве',
        IntentionScope.active,
        IntentionTypeChoice.all,
        IntentionCountsByScopeAndType(active: none, archived: intentionsOnly),
        DoableIconData.intention,
        'Нет активных намерений',
        'Новое создаётся кнопкой с плюсом внизу, а архивированные показывает '
            'строка «Показать».',
      ),
      (
        'при типе «Только действия» в архиве только намерения',
        IntentionScope.active,
        IntentionTypeChoice.actions,
        IntentionCountsByScopeAndType(active: none, archived: intentionsOnly),
        DoableIconData.intention,
        'Нет активных намерений',
        'Новое создаётся кнопкой с плюсом внизу, а архивированные показывает '
            'строка «Показать».',
      ),
      (
        'активный охват без намерений',
        IntentionScope.active,
        IntentionTypeChoice.all,
        IntentionCountsByScopeAndType(active: none, archived: none),
        DoableIconData.intention,
        'Намерений пока нет',
        'Ваши намерения появятся здесь. Первое создаётся кнопкой с плюсом '
            'внизу.',
      ),
      (
        'охват всех без намерений',
        IntentionScope.all,
        IntentionTypeChoice.all,
        IntentionCountsByScopeAndType(active: none, archived: none),
        DoableIconData.intention,
        'Намерений пока нет',
        'Ваши намерения появятся здесь. Первое создаётся кнопкой с плюсом '
            'внизу.',
      ),
      (
        'пустой архив',
        IntentionScope.archived,
        IntentionTypeChoice.all,
        IntentionCountsByScopeAndType(active: intentionsOnly, archived: none),
        DoableIconData.archive,
        'В архиве ничего нет',
        'Архивированное намерение уходит из активного списка и остаётся здесь.',
      ),
    ]) {
      testWidgets('$name: заголовок показывает 0, а сообщение называет охват '
          'без действий сброса', (tester) async {
        await _openEmptyCatalog(
          tester,
          scope: scope,
          type: type,
          counts: counts,
        );

        expect(intentionCatalogTotal(0), findsOneWidget);
        expect(shownIntentionCatalogParameters(tester).scope, scope);
        expect(_inEmptyState(find.text(title)), findsOneWidget);
        expect(_inEmptyState(find.text(text)), findsOneWidget);
        expect(_inEmptyState(_icon(icon)), findsOneWidget);
        expect(_inEmptyState(find.byType(Button)), findsNothing);
      });
    }

    testWidgets('пустой тип в архиве называет охват и предлагает оба типа', (
      tester,
    ) async {
      await _openEmptyCatalog(
        tester,
        scope: IntentionScope.archived,
        type: IntentionTypeChoice.actions,
        counts: IntentionCountsByScopeAndType(
          active: none,
          archived: intentionsOnly,
        ),
      );

      final shown = shownIntentionCatalogParameters(tester);
      expect(
        (shown.scope, shown.type),
        (IntentionScope.archived, IntentionTypeChoice.actions),
      );
      expect(intentionCatalogTotal(0), findsOneWidget);
      expect(_inEmptyState(find.text('Нет действий в архиве')), findsOneWidget);
      expect(_inEmptyState(find.text('Показать оба типа')), findsOneWidget);
    });

    testWidgets('фильтр названия без совпадений называет причину вместо '
        'пустого охвата и оставляет 0 в заголовке', (tester) async {
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository, locale: const Locale('ru')));
      repository.complete(0, _firstPage(_twentySummaries()));
      await tester.pumpAndSettle();

      await enterIntentionCatalogTitle(tester, 'плавать');
      await _pumpUntilQueries(tester, repository, 2);
      repository.complete(1, _firstPage(const []));
      await tester.pumpAndSettle();

      expect(intentionCatalogTotal(0), findsOneWidget);
      expect(
        shownIntentionCatalogParameters(tester).scope,
        IntentionScope.active,
      );
      final message = find.text('Нет намерений с таким названием');
      expect(_inEmptyState(message), findsOneWidget);
      expect(
        _inEmptyState(find.text('Попробуйте название короче.')),
        findsOneWidget,
      );
      expect(_inEmptyState(find.text('Сбросить фильтры')), findsOneWidget);
    });

    testWidgets('«Сбросить фильтры» очищает поле и снимает условия, сохраняя '
        'тип', (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      await tester.pumpWidget(_testAppWithContainer(container));
      repository.complete(0, _firstPage(const []));
      await tester.pumpAndSettle();
      await selectIntentionCatalogType(tester, IntentionTypeChoice.actions);
      await _pumpUntilQueries(tester, repository, 2);
      repository.complete(1, _firstPage(const []));
      await tester.pumpAndSettle();
      await _selectCondition(
        tester,
        container,
        _tag(1, 'Здоровье'),
        IntentionTagRequirement.mustBePresent,
      );
      await _pumpUntilQueries(tester, repository, 3);
      await enterIntentionCatalogTitle(tester, 'бег');
      await _pumpUntilQueries(tester, repository, 4);
      repository.complete(3, _firstPage(const []));
      await tester.pumpAndSettle();

      await tester.tap(_inEmptyState(find.text('Reset filters')));
      await tester.pump();
      final answered = repository.queries.length;
      expect(answered, greaterThan(4));
      repository.complete(
        answered - 1,
        _firstPage(_taggedSummaries(const [], first: 3, last: 1)),
      );
      await tester.pumpAndSettle();

      final query = repository.queries.last;
      expect(query.titleFilter, isNull);
      expect(query.tagFilter, IntentionTagFilter.empty);
      expect(query.readinessFilter, IntentionReadinessFilter.readyOnly);
      final shown = shownIntentionCatalogParameters(tester);
      expect(shown.titleFilter, isEmpty);
      expect(shown.tagConditions, 0);
      expect(shown.type, IntentionTypeChoice.actions);
      expect(intentionCatalogRows, findsNWidgets(3));
    });
  });

  testWidgets('отказ новой выдачи после удаления исключённого тега показан '
      'отказом первой порции, а повтор показывает прежде отсечённые '
      'намерения', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    await _loadTaggedCatalog(
      tester,
      container,
      repository,
      filter,
      IntentionCatalogFirstPage(
        items: _taggedSummaries([health], first: 4, last: 2, step: 2),
        totalCount: 2,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    final restarted = repository.queries.length;

    await _completeCatalogWidgetTagCommand(
      tester,
      container,
      repository,
      DeleteTag(rest.id),
      tagDeletionSuccess(
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      ),
    );
    await _pumpUntilQueries(tester, repository, restarted + 1);
    final remaining = IntentionTagFilter(requiredTagIds: [health.id]);
    expect(repository.queryAt(restarted).tagFilter, remaining);
    expect(repository.queryAt(restarted).cursor, isNull);
    repository.complete(
      restarted,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    final message = find.text('Intentions couldn’t be loaded. Try again.');
    expect(message, findsOneWidget);
    expect(find.byType(CatalogRow), findsNothing);

    await tester.tap(find.text('Try again'));
    await _pumpUntilQueries(tester, repository, restarted + 2);
    expect(repository.queryAt(restarted + 1).tagFilter, remaining);
    repository.complete(
      restarted + 1,
      _firstPage(_taggedSummaries([health], first: 4, last: 1), revision: 2),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(intentionCatalogTotal(4), findsOneWidget);
    expect(find.byType(CatalogRow), findsNWidgets(4));
  });

  testWidgets('после подтверждённого переименования тега строки показывают '
      'новое название, а удаление снимает условие и показывает выдачу по '
      'оставшимся условиям', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final renamed = _tag(1, 'Самочувствие');
    await _openCatalogWithConditions(tester, container, repository, [
      (health, IntentionTagRequirement.mustBePresent),
    ], _firstPage(_taggedSummaries([health], first: 3, last: 1), revision: 1));
    expect(_rowChips('Здоровье'), findsNWidgets(3));

    await _completeCatalogWidgetTagCommand(
      tester,
      container,
      repository,
      UpdateTag(tagId: health.id, name: renamed.name, color: health.color),
      tagRenameSuccess(
        before: health,
        after: renamed,
        revision: const TestCatalogRevision(2),
      ),
    );

    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    expect(_rowChips('Самочувствие'), findsNWidgets(3));
    expect(intentionCatalogTotal(3), findsOneWidget);

    final restarted = repository.queries.length;
    await _completeCatalogWidgetTagCommand(
      tester,
      container,
      repository,
      DeleteTag(health.id),
      tagDeletionSuccess(
        tagId: health.id,
        revision: const TestCatalogRevision(3),
      ),
    );
    await _pumpUntilQueries(tester, repository, restarted + 1);
    expect(repository.queryAt(restarted).tagFilter, IntentionTagFilter.empty);
    repository.complete(
      restarted,
      _firstPage(_taggedSummaries(const [], first: 5, last: 1), revision: 3),
    );
    await tester.pumpAndSettle();

    expect(shownIntentionCatalogParameters(tester).tagConditions, 0);
    expect(intentionCatalogTotal(5), findsOneWidget);
    expect(find.byType(CatalogRow), findsNWidgets(5));
    expect(repository.queries, hasLength(restarted + 1));
  });
}

/// Виды состояния списка — закрытые наследники [ListState].
final _listState = find.byWidgetPredicate((widget) => widget is ListState);

/// Кольцо подгрузки: видимого текста у него нет, только доступное название.
final _loadingMore = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == 'Loading more intentions',
);

Finder _inListState(Finder finder) =>
    find.descendant(of: _listState, matching: finder);

Finder _inEmptyState(Finder finder) =>
    find.descendant(of: find.byType(EmptyState), matching: finder);

Finder _icon(DoableIconData icon) => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == icon,
);

/// Открывает на русском каталог с охватом [scope] и типом [type], в котором
/// подтверждена пустая первая порция с числами [counts].
Future<void> _openEmptyCatalog(
  WidgetTester tester, {
  required IntentionScope scope,
  required IntentionTypeChoice type,
  required IntentionCatalogCounts counts,
}) async {
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    _testAppWithContainer(container, locale: const Locale('ru')),
  );
  container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
          .notifier,
    )
    ..changeScope(scope)
    ..changeType(type);
  await tester.pump();
  repository.complete(
    repository.queries.length - 1,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        counts: counts,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _catalogScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const PageStorageKey<String>('intention-catalog-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// Экран телефона, на котором двадцать строк выдачи не помещаются.
const _phone = Size(400, 800);

/// Открывает страницу на экране телефона.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Двадцать строк выдачи: на экран телефона они не помещаются.
List<IntentionSummary> _twentySummaries() => [
  for (var index = 1; index <= 20; index++)
    testSummary(index: index, title: 'Намерение $index'),
];

/// Ведёт жест [offset] из середины списка выдачи.
Future<void> _dragCatalogList(WidgetTester tester, Offset offset) =>
    tester.dragFrom(tester.getCenter(intentionCatalogList), offset);

Future<void> _scrollCatalogToEnd(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    final position = _catalogScrollPosition(tester);
    if (position.pixels >= position.maxScrollExtent) {
      return;
    }
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
  }
}

Widget _testApp(
  ControlledCatalogRepository repository, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
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
    theme: doableTheme(brightness),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const IntentionCatalogPage(),
  ),
);

Widget _testAppWithContainer(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: doableTheme(Brightness.light),
    locale: locale,
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
    theme: doableTheme(Brightness.light),
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
  for (final row in tester.widgetList<CatalogRow>(find.byType(CatalogRow))) {
    final rect = tester.getRect(find.byWidget(row));
    if (rect.bottom > listRect.top && rect.top < listRect.bottom) {
      visible.add((title: row.name, top: rect.top));
    }
  }
  visible.sort((left, right) => left.top.compareTo(right.top));
  return visible.first;
}

double _catalogTileTop(WidgetTester tester, String title) => tester
    .getTopLeft(
      find.byWidgetPredicate(
        (widget) => widget is CatalogRow && widget.name == title,
      ),
    )
    .dy;

/// Чипы тега с названием [name] в строках каталога.
Finder _rowChips(String name) => find.descendant(
  of: find.byType(CatalogRow),
  matching: find.widgetWithText(TagChip, name),
);

/// Тексты открытого меню листа сверху вниз: названия вариантов и их числа.
List<String?> _shownMenu(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.byType(Text),
    ),
  ))
    text.data,
];

/// Значки меток построенных строк каталога в порядке показа.
List<DoableIconData> _shownMarks(WidgetTester tester) => [
  for (final badge in tester.widgetList<Badge>(find.byType(Badge))) badge.icon,
];

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
  await accepted.future;
  await tester.pump();
  await tester.pump();
}

/// Экранное положение намерения, видимого у верхнего края списка.
typedef _VisibleCatalogAnchor = ({String title, double top, int index});

/// Загружает страницу каталога с заданными условиями по тегам.
///
/// Условия задаются сразу моделью каталога, минуя панель тегов.
Future<void> _loadTaggedCatalog(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionTagFilter filter,
  IntentionCatalogFirstPage page,
) async {
  await tester.pumpWidget(_testAppWithContainer(container));
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
  container
      .read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      )
      .changeTagFilter(filter);
  await _pumpUntilQueries(tester, repository, 2);
  expect(repository.queryAt(1).tagFilter, filter);
  repository.complete(1, ResultSuccess(page));
  await tester.pumpAndSettle();
}

/// Прокручивает список так, чтобы перед видимым намерением были строки.
Future<_VisibleCatalogAnchor> _scrollToMiddle(
  WidgetTester tester,
  List<IntentionSummary> items, {
  double distance = 600,
}) async {
  await _dragCatalogList(tester, Offset(0, -distance));
  await tester.pumpAndSettle();
  final visible = _firstVisibleCatalogTile(tester);
  final index = items.indexWhere((item) => item.title == visible.title);
  expect(index, greaterThan(1));
  expect(index, lessThan(items.length - 1));
  return (title: visible.title, top: visible.top, index: index);
}

List<IntentionSummary> _taggedSummaries(
  List<Tag> tags, {
  int first = 60,
  required int last,
  int step = 1,
}) => [
  for (var index = first; index >= last; index -= step)
    testSummary(index: index, title: 'Намерение $index', tags: tags),
];

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

Result<IntentionCatalogFirstPage> _firstPage(
  List<IntentionSummary> items, {
  int revision = 0,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: items.length,
    nextCursor: null,
    revision: TestCatalogRevision(revision),
  ),
);

Future<void> _scrollCatalogDown(WidgetTester tester) async {
  await _dragCatalogList(tester, const Offset(0, -800));
  await tester.pumpAndSettle();
  expect(_catalogScrollPosition(tester).pixels, greaterThan(0));
}

/// Задаёт условие переключениями модели условий, как нажатиями в панели
/// тегов; каждое переключение сразу начинает новую выдачу.
Future<void> _selectCondition(
  WidgetTester tester,
  ProviderContainer container,
  Tag tag,
  IntentionTagRequirement requirement,
) async {
  final conditions = container.read(
    intentionTagConditionsViewModelProvider(const BrowseIntentionCatalog())
        .notifier,
  );
  for (var i = 0; i < tagConditionCycles(requirement); i++) {
    conditions.cycle(tag.id);
    await tester.pump();
  }
}

/// Открывает каталог и задаёт условия через модель условий.
///
/// Каждое переключение сразу начинает новую выдачу; [page] отвечает на
/// последнюю.
Future<void> _openCatalogWithConditions(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  List<(Tag, IntentionTagRequirement)> conditions,
  Result<IntentionCatalogFirstPage> page,
) async {
  await tester.pumpWidget(_testAppWithContainer(container));
  repository.complete(0, _firstPage(const []));
  await tester.pumpAndSettle();
  var queries = 1;
  for (final (tag, requirement) in conditions) {
    await _selectCondition(tester, container, tag, requirement);
    queries += tagConditionCycles(requirement);
  }
  await _pumpUntilQueries(tester, repository, queries);
  repository.complete(queries - 1, page);
  await tester.pumpAndSettle();
}

int _summaryIndex(IntentionSummary summary) =>
    int.parse(summary.title.split(' ').last);

Tag _tag(int index, String name) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(index),
);

IntentionCatalogLoaded _loadedCatalog(ProviderContainer container) =>
    container
            .read(
              intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
            )
            .requireValue
        as IntentionCatalogLoaded;

/// Собирает состояния, которые заменили бы загруженный список и позицию.
List<AsyncValue<IntentionCatalogState>> _observeCatalogLoading(
  ProviderContainer container,
) {
  final replaced = <AsyncValue<IntentionCatalogState>>[];
  final subscription = container.listen(
    intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
    (_, next) {
      if (next.isLoading || next.value is! IntentionCatalogLoaded) {
        replaced.add(next);
      }
    },
  );
  addTearDown(subscription.close);
  return replaced;
}

Future<void> _completeCatalogWidgetTagCommand(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  TagCommand command,
  TagCommandResult result,
) async {
  final accepted = acceptTagCommand(container, repository, command, result);
  await accepted.future;
  await tester.pump();
  await tester.pump();
}

Future<void> _completeCatalogWidgetTagAssignment(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required TagAssignmentState state,
  required TagId tagId,
  required IntentionSummary before,
  required IntentionSummary after,
  required GraphRevision revision,
}) {
  final (command, result) = intentionTagAssignment(
    state: state,
    tagId: tagId,
    before: before,
    after: after,
    revision: revision,
  );
  return _completeCatalogWidgetTagCommand(
    tester,
    container,
    repository,
    command,
    result,
  );
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
