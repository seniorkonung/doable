import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
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
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/quick_creation.dart';
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

  for (final (keyboard, variant) in [
    (0.0, 'без клавиатуры'),
    (300.0, 'при открытой клавиатуре'),
  ]) {
    testWidgets('жест по списку $variant прокручивает сначала список, а на его '
        'краю — страницу с параметрами, и последняя строка достижима', (
      tester,
    ) async {
      _usePhoneScreen(tester, keyboard: keyboard);
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository));
      repository.complete(
        0,
        _firstPage([
          for (var index = 1; index <= 20; index++)
            testSummary(index: index, title: 'Намерение $index'),
        ]),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(
        const PageStorageKey<String>('intention-catalog-list'),
      );

      expect(_pageScrollPosition(tester).pixels, 0);

      await tester.dragFrom(
        tester.getTopLeft(list) + const Offset(24, 24),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(_catalogScrollPosition(tester).pixels, greaterThan(0));
      expect(_pageScrollPosition(tester).pixels, 0);

      await _dragCatalogToEnd(tester);

      final page = _pageScrollPosition(tester);
      expect(page.pixels, page.maxScrollExtent);
      expect(page.maxScrollExtent, greaterThan(0));
      // Выдача сохраняет порядок порции: последним стоит двадцатое намерение.
      final lastRow = find.widgetWithText(IntentionSummaryView, 'Намерение 20');
      expect(lastRow.hitTestable(), findsOneWidget);

      // Обратный жест тоже сначала прокручивает список, а страница остаётся
      // в конце.
      await tester.dragFrom(
        tester.getTopLeft(list) + const Offset(24, 24),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(_pageScrollPosition(tester).pixels, page.maxScrollExtent);
      expect(
        _catalogScrollPosition(tester).pixels,
        lessThan(_catalogScrollPosition(tester).maxScrollExtent),
      );
      expect(tester.takeException(), isNull);
    });

    // Порция оболочки из 100 строк длиннее пути одного флинга, поэтому
    // получение следующей порции после флинга проверяется здесь, на порции
    // из 20 строк.
    testWidgets('флинг $variant, начатый при списке и странице в начале, '
        'доводит до конца список и страницу, и получение следующей порции '
        'видно целиком до границы тела страницы, а обратный флинг возвращает '
        'список и страницу к параметрам поиска', (tester) async {
      _usePhoneScreen(tester, keyboard: keyboard);
      final bodyBottom = _phone.height - keyboard;
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(
        _testApp(repository, pageSize: 20, prefetchRemaining: 2),
      );
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [
              for (var index = 1; index <= 20; index++)
                testSummary(index: index, title: 'Намерение $index'),
            ],
            totalCount: 21,
            nextCursor: const TestCatalogCursor(),
            revision: const TestCatalogRevision(0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Конец списка запрашивает следующую порцию; пока хранилище не
      // ответило, её получение стоит в конце выдачи.
      await _scrollCatalogToEnd(tester);
      await _pumpUntilQueries(tester, repository, 2);
      _catalogScrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(_catalogScrollPosition(tester).pixels, 0);
      expect(_pageScrollPosition(tester).pixels, 0);

      await _flingCatalogList(tester, const Offset(0, -300));

      final list = _catalogScrollPosition(tester);
      final page = _pageScrollPosition(tester);
      expect(list.pixels, moreOrLessEquals(list.maxScrollExtent));
      expect(page.pixels, moreOrLessEquals(page.maxScrollExtent));
      expect(page.maxScrollExtent, greaterThan(0));
      _expectFullyVisibleInList(
        tester,
        find.text('Loading more intentions…'),
        bodyBottom: bodyBottom,
      );
      expect(repository.queries, hasLength(2));

      await _flingCatalogList(tester, const Offset(0, 300));

      expect(
        _catalogScrollPosition(tester).pixels,
        moreOrLessEquals(_catalogScrollPosition(tester).minScrollExtent),
      );
      expect(
        _pageScrollPosition(tester).pixels,
        moreOrLessEquals(_pageScrollPosition(tester).minScrollExtent),
      );
      final filter = find.byKey(const ValueKey('catalog-filter-field'));
      final shownFilter = tester.getRect(filter);
      expect(
        shownFilter.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(shownFilter.bottom, lessThanOrEqualTo(bodyBottom));
      expect(filter.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('флинг прокручивает страницу только от края списка: '
      'слабый флинг внутри списка оставляет страницу на месте, а флинг при '
      'списке уже в конце сдвигает страницу дальше хода пальца', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final repository = ControlledCatalogRepository();
    await tester.pumpWidget(_testApp(repository));
    repository.complete(
      0,
      _firstPage([
        for (var index = 1; index <= 20; index++)
          testSummary(index: index, title: 'Намерение $index'),
      ]),
    );
    await tester.pumpAndSettle();

    await _flingCatalogList(tester, const Offset(0, -100), speed: 300);

    final list = _catalogScrollPosition(tester);
    expect(list.pixels, greaterThan(0));
    expect(list.pixels, lessThan(list.maxScrollExtent));
    expect(_pageScrollPosition(tester).pixels, 0);

    list.jumpTo(list.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_pageScrollPosition(tester).pixels, 0);

    const fingerTravel = 60.0;
    await _flingCatalogList(
      tester,
      const Offset(0, -fingerTravel),
      speed: 4000,
    );

    final page = _pageScrollPosition(tester);
    expect(page.pixels, greaterThan(fingerTravel));
    expect(page.pixels, lessThanOrEqualTo(page.maxScrollExtent));
    expect(
      _catalogScrollPosition(tester).pixels,
      _catalogScrollPosition(tester).maxScrollExtent,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (handoff, variant) in _pageFlingHandoffs) {
    testWidgets('касание строки во время инерции к концу, которую странице '
        'передала $variant, только останавливает страницу, а касание после '
        'остановки открывает страницу намерения', (tester) async {
      _usePhoneScreen(tester);
      final items = [
        for (var index = 1; index <= 20; index++)
          testSummary(index: index, title: 'Намерение $index'),
      ];
      final router = await _openRoutedCatalog(tester, items);
      if (handoff == _PageFlingHandoff.fromListEdge) {
        _catalogScrollPosition(tester)
            .jumpTo(_catalogScrollPosition(tester).maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(_pageScrollPosition(tester).pixels, 0);

      await _releaseCatalogListFling(
        tester,
        const Offset(0, -_pageFlingTravel),
        speed: handoff.speed,
      );
      await _pumpUntilPageInertia(tester, (page) => page.pixels > 0);

      final list = _catalogScrollPosition(tester);
      final page = _pageScrollPosition(tester);
      expect(list.pixels, moreOrLessEquals(list.maxScrollExtent));
      final stopped = page.pixels;
      final (point, row) = _catalogRowAtListCenter(tester);
      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(router.current.name, isNot(IntentionDetailsRoute.name));
      expect(page.isScrollingNotifier.value, isFalse);
      expect(page.pixels, stopped);
      expect(page.pixels, lessThan(page.maxScrollExtent));
      expect(list.pixels, moreOrLessEquals(list.maxScrollExtent));

      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        items.singleWhere((summary) => summary.title == row).id,
      );
    });

    testWidgets('касание поля фильтра названия во время обратной инерции, '
        'которую странице передала $variant, не ставит в него фокус и '
        'останавливает страницу, а касание после остановки ставит', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await _openRoutedCatalog(tester, [
        for (var index = 1; index <= 20; index++)
          testSummary(index: index, title: 'Намерение $index'),
      ]);
      await _dragCatalogToEnd(tester);
      if (handoff == _PageFlingHandoff.fromListEdge) {
        _catalogScrollPosition(tester).jumpTo(0);
        await tester.pumpAndSettle();
      }
      final page = _pageScrollPosition(tester);
      expect(page.pixels, page.maxScrollExtent);
      final filter = find.byKey(const ValueKey('catalog-filter-field'));
      final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;

      await _releaseCatalogListFling(
        tester,
        const Offset(0, _pageFlingTravel),
        speed: handoff.speed,
      );
      // Касание приходится на видимую под шапкой часть поля, пока страница
      // ещё не дошла до начала.
      await _pumpUntilPageInertia(
        tester,
        (page) =>
            page.pixels > 0 &&
            tester.getRect(filter).bottom > appBarBottom + 16,
      );

      final stopped = page.pixels;
      final shown = tester.getRect(filter);
      final point = Offset(
        shown.center.dx,
        (math.max(shown.top, appBarBottom) + shown.bottom) / 2,
      );
      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(_hasFocus(tester, filter), isFalse);
      expect(page.isScrollingNotifier.value, isFalse);
      expect(page.pixels, stopped);
      expect(page.pixels, greaterThan(0));

      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(_hasFocus(tester, filter), isTrue);
    });

    // Собственная инерция страницы от трекпада пропускает касания к
    // содержимому, поэтому и переданная странице — тоже.
    testWidgets('щелчок во время инерции от трекпада, которую странице '
        'передала $variant, срабатывает на строке, как во время собственной '
        'инерции страницы от трекпада', (tester) async {
      _usePhoneScreen(tester);
      final items = [
        for (var index = 1; index <= 20; index++)
          testSummary(index: index, title: 'Намерение $index'),
      ];
      final router = await _openRoutedCatalog(tester, items);
      if (handoff == _PageFlingHandoff.fromListEdge) {
        _catalogScrollPosition(tester)
            .jumpTo(_catalogScrollPosition(tester).maxScrollExtent);
        await tester.pumpAndSettle();
      }

      await tester.trackpadFlingFrom(
        _catalogListFlingStart(tester),
        const Offset(0, -_pageFlingTravel),
        handoff.speed,
      );
      await _pumpUntilPageInertia(tester, (page) => page.pixels > 0);

      final (point, row) = _catalogRowAtListCenter(tester);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        items.singleWhere((summary) => summary.title == row).id,
      );
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
    final retry = find.widgetWithText(FilledButton, 'Try again');
    expect(retry.hitTestable(), findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    repository.complete(1, _firstPage(const []));
    await tester.pumpAndSettle();

    expect(find.text('No active intentions yet.'), findsOneWidget);
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

  testWidgets('массовое согласование после удаления исключённого тега '
      'сохраняет экранное положение видимого намерения', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final items = _taggedSummaries([health], first: 60, last: 2, step: 2);
    await _loadTaggedCatalog(
      tester,
      container,
      repository,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );
    // Перед видимым намерением откроется больше строк, чем помещается в
    // построенную область списка.
    final anchor = await _scrollToMiddle(tester, items, distance: 1800);
    final positionBefore = _catalogScrollPosition(tester).pixels;
    final loadingStates = _observeCatalogLoading(container);

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
    await _pumpUntilReconciliationQueries(tester, repository, 1);

    // Ожидание чтения согласования не заменяет загруженный список.
    expect(
      _catalogScrollPosition(tester).pixels,
      moreOrLessEquals(positionBefore, epsilon: 0.01),
    );
    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );

    final missing = _taggedSummaries([health], first: 59, last: 1, step: 2);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        missing,
        totalCount: items.length + missing.length,
        revision: 2,
      ),
    );
    await tester.pumpAndSettle();

    final current = _loadedCatalog(container);
    expect(current.items, hasLength(items.length + missing.length));
    expect(
      current.items.indexWhere((item) => item.title == anchor.title),
      greaterThan(anchor.index),
    );
    expect(find.text('Total intentions: 60'), findsOneWidget);
    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );
    expect(loadingStates, isEmpty);
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
    expect(find.text('Total intentions: 31'), findsOneWidget);
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
    expect(find.text('Total intentions: 30'), findsOneWidget);
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
    expect(find.text('Total intentions: 29'), findsOneWidget);
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
    await tester.enterText(
      find.byKey(const ValueKey('catalog-filter-field')),
      'Намерение',
    );
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

    // Нажатие вне неизменённой панели над шапкой каталога закрывает её.
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IntentionCatalogPage),
          matching: find.byType(AppBar),
        ),
      ),
    );
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
      expect(
        find.byKey(const ValueKey('catalog-open-tags')).hitTestable(),
        findsOneWidget,
      );
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

    await _dragCatalogList(tester, const Offset(0, -2000));
    await _pumpUntilQueries(tester, repository, 2);
    await tester.pump();
    expect(repository.queryAt(1).cursor, same(cursor));
    await _scrollCatalogToEnd(tester);
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
    }
  });

  // Архивное состояние строки в охвате всех показывает тест архивного
  // состояния в охвате всех.
  testWidgets('архивный охват показывает намерения без отметки '
      'избранного', (tester) async {
    const scopeName = 'Archived';
    const scope = IntentionScope.archived;
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

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(scopeName).last);
    await tester.pump();
    expect(repository.queryAt(1).scope, scope);
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

    final row = find.ancestor(
      of: find.text('Архивное первое'),
      matching: find.byType(IntentionSummaryView),
    );
    expect(find.byIcon(Icons.star), findsNothing);
    final label = tester.getSemantics(row).label;
    expect(label, contains('Архивное первое'));
    expect(label, isNot(contains('Favorite intention')));
    // Архивный охват сообщает архивное состояние самим выбранным охватом.
    expect(label.contains('Archived'), isFalse);
    expect(find.text('Total intentions: 2'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets(
    'показывает количество активных связей в каждой строке каталога',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository, locale: const Locale('ru')));
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [
              testSummary(
                index: 1,
                title: 'Быть здоровым',
                activeRelationCount: 3,
              ),
              testSummary(index: 2, title: 'Выбрать страховку'),
            ],
            totalCount: 2,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Быть здоровым'), findsOneWidget);
      expect(find.text('Активных связей: 3'), findsOneWidget);
      expect(find.text('Активных связей: 0'), findsOneWidget);

      final row = tester.getSemantics(
        find.ancestor(
          of: find.text('Быть здоровым'),
          matching: find.byType(IntentionSummaryView),
        ),
      );
      expect(row.label, contains('Быть здоровым'));
      expect(row.label, contains('Не готово к действию'));
      expect(row.label, contains('Активных связей: 3'));

      semantics.dispose();
    },
  );

  testWidgets('условие, добавленное через экран поиска тега, сразу начинает '
      'выдачу с верхней позиции', (tester) async {
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

    await tester.tap(_addCondition);
    await tester.pumpAndSettle();
    expect(router.current.name, TagConditionPickerRoute.name);
    await tester.tap(
      _pickerAction(health, IntentionTagRequirement.mustBePresent),
    );
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

    expectIntentionGraphRootPage(router);
    expect(_shownConditions(tester), ['Здоровье']);
    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
    expect(find.text('Tags: Здоровье'), findsWidgets);
    expect(find.text('No tags'), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived').last);
    await _pumpUntilQueries(tester, repository, 4);
    expect(repository.queryAt(3).scope, IntentionScope.archived);
    expect(repository.queryAt(3).tagFilter, filter);
    repository.complete(3, _firstPage(_taggedSummaries([health], last: 59)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), ['Здоровье', 'not Спорт']);

    await tester.tap(find.byKey(const ValueKey('catalog-order-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Created: oldest first').last);
    await _pumpUntilQueries(tester, repository, 5);
    expect(repository.queryAt(4).scope, IntentionScope.archived);
    expect(
      repository.queryAt(4).order,
      IntentionCatalogOrder.createdAtAscending,
    );
    expect(repository.queryAt(4).tagFilter, filter);
    repository.complete(4, _firstPage(_taggedSummaries([health], last: 59)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), ['Здоровье', 'not Спорт']);
  });

  testWidgets('пустая выдача при условиях по тегам сообщает об '
      'отсутствии совпадений по условиям, а не о пустом охвате', (
    tester,
  ) async {
    const byConditions = 'No intentions match the tag conditions.';
    const byScope = 'No active intentions yet.';
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
    expect(find.text(byScope), findsNothing);
  });

  testWidgets('отказ обновления из-за недоступности показан над сохранённым '
      'списком, а повтор согласует выдачу', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final items = _taggedSummaries([health], last: 2, step: 2);
    await _failCatalogRefresh(
      tester,
      container,
      repository,
      required: health,
      deletedExcluded: rest,
      items: items,
      failure: const IntentionUnavailableFailure(),
    );

    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    expect(find.text('Total intentions: 30'), findsOneWidget);
    expect(_loadedCatalog(container).items, items);
    // Отказ виден и не закрывает первую строку списка.
    final list = tester.getRect(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
    );
    expect(message.hitTestable(), findsOneWidget);
    expect(find.text('Намерение 60').hitTestable(), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    final missing = _taggedSummaries([health], first: 59, last: 1, step: 2);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(
        missing,
        totalCount: items.length + missing.length,
        revision: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(find.text('Total intentions: 60'), findsOneWidget);
    expect(_loadedCatalog(container).items, hasLength(60));
    expect(
      _catalogTileTop(tester, 'Намерение 60'),
      moreOrLessEquals(list.top, epsilon: 0.01),
    );
  });

  testWidgets('после подтверждённых переименования и удаления тега строки '
      'и чипы показывают согласованные данные', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final renamed = _tag(1, 'Самочувствие');
    await _openCatalogWithConditions(tester, container, repository, [
      (health, IntentionTagRequirement.mustBePresent),
    ], _firstPage(_taggedSummaries([health], first: 3, last: 1), revision: 1));
    expect(find.text('Tags: Здоровье'), findsNWidgets(3));

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

    expect(_shownConditions(tester), ['Самочувствие']);
    expect(find.text('Tags: Самочувствие'), findsNWidgets(3));
    expect(find.text('Total intentions: 3'), findsOneWidget);

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
    await tester.pumpAndSettle();

    expect(_shownConditions(tester), ['Самочувствие (tag deleted)']);
    expect(find.byType(IntentionSummaryView), findsNothing);
    expect(
      find.text('No intentions match the tag conditions.'),
      findsOneWidget,
    );
    expect(
      repository.queries.last.tagFilter,
      IntentionTagFilter(requiredTagIds: [health.id]),
    );
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

/// Экран телефона, на котором параметры поиска и выдача делят высоту.
const _phone = Size(400, 800);

/// Открывает страницу на экране телефона с клавиатурой высотой [keyboard].
void _usePhoneScreen(WidgetTester tester, {double keyboard = 0}) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

/// Общая прокрутка параметров поиска и выдачи страницы.
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

/// Ведёт жест [offset] из середины видимой части списка выдачи: пока
/// страница не прокручена, нижняя часть списка под параметрами поиска лежит
/// за нижним краем экрана.
Future<void> _dragCatalogList(WidgetTester tester, Offset offset) {
  final list = tester.getRect(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
  );
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final top = math.max(list.top, tester.getRect(find.byType(AppBar)).bottom);
  final bottom = math.min(list.bottom, screen.height);
  return tester.dragFrom(Offset(list.center.dx, (top + bottom) / 2), offset);
}

/// Прокручивает жестами по списку выдачи до конца списка и страницы.
Future<void> _dragCatalogToEnd(WidgetTester tester) async {
  final list = find.byKey(
    const PageStorageKey<String>('intention-catalog-list'),
  );
  for (var attempt = 0; attempt < 50; attempt++) {
    final before = (
      _catalogScrollPosition(tester).pixels,
      _pageScrollPosition(tester).pixels,
    );
    final top = math.max(
      tester.getRect(list).top,
      tester.getRect(find.byType(AppBar)).bottom,
    );
    await tester.dragFrom(
      Offset(tester.getRect(list).left + 24, top + 24),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final after = (
      _catalogScrollPosition(tester).pixels,
      _pageScrollPosition(tester).pixels,
    );
    if (after == before) return;
  }
  fail('Список не дошёл до конца.');
}

/// Флинг на [offset] со скоростью [speed] из точки у верхнего левого края
/// видимой части списка выдачи; скорости по умолчанию с запасом хватает на
/// список и страницу.
///
/// Кадры идут с частотой экрана: в кадре, где список упирается в край, он
/// уходит за край лишь на малую долю пути, и дальше страницу ведёт только
/// переданная ей инерция флинга.
Future<void> _flingCatalogList(
  WidgetTester tester,
  Offset offset, {
  double speed = 6000,
}) async {
  await _releaseCatalogListFling(tester, offset, speed: speed);
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

/// Выполняет флинг [_flingCatalogList] и отпускает палец, не дожидаясь
/// конца инерции.
Future<void> _releaseCatalogListFling(
  WidgetTester tester,
  Offset offset, {
  required double speed,
}) => tester.flingFrom(_catalogListFlingStart(tester), offset, speed);

/// Точка у верхнего левого края видимой части списка выдачи, из которой
/// начинается флинг.
Offset _catalogListFlingStart(WidgetTester tester) {
  final list = tester.getRect(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
  );
  final top = math.max(list.top, tester.getRect(find.byType(AppBar)).bottom);
  return Offset(list.left + 24, top + 24);
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
  /// приходится на строку или поле фильтра.
  final double speed;
}

/// Ход пальца флинга, инерцию которого продолжает страница: короткий ход
/// оставляет странице путь и после флинга, начатого у края списка.
const _pageFlingTravel = 60.0;

const _pageFlingHandoffs = [
  (_PageFlingHandoff.listInertia, 'инерция списка, дошедшая до его края'),
  (_PageFlingHandoff.fromListEdge, 'флинг, начатый у края списка'),
];

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

/// Середина видимой части списка выдачи и название строки под ней.
(Offset, String) _catalogRowAtListCenter(WidgetTester tester) {
  final list = tester.getRect(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
  );
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final top = math.max(list.top, tester.getRect(find.byType(AppBar)).bottom);
  final bottom = math.min(list.bottom, screen.height);
  final point = Offset(list.center.dx, (top + bottom) / 2);
  final rows = find.byWidgetPredicate(
    (widget) => widget is IntentionSummaryView,
  );
  final row = rows
      .evaluate()
      .map((element) => element.widget as IntentionSummaryView)
      .singleWhere((row) => tester.getRect(find.byWidget(row)).contains(point));
  return (point, row.title);
}

/// Стоит ли фокус ввода в текстовом поле [field].
bool _hasFocus(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

/// Открывает каталог намерений как корневую страницу приложения, в котором
/// нажатие строки открывает страницу намерения, и показывает выдачу
/// [items].
Future<AppRouter> _openRoutedCatalog(
  WidgetTester tester,
  List<IntentionSummary> items,
) async {
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(_routerTestAppWithContainer(container, router));
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(0, _firstPage(items));
  await tester.pumpAndSettle();
  return router;
}

/// Элемент [finder] виден целиком в видимой части списка выдачи.
///
/// Та же проверка, что у свидетельств раскладки оболочки: элемент лежит под
/// шапкой, над нижним краем тела страницы [bodyBottom] и в видимой части
/// каждой объемлющей прокрутки, а нажатия у его верхнего и нижнего края
/// попадают в него.
void _expectFullyVisibleInList(
  WidgetTester tester,
  Finder finder, {
  required double bodyBottom,
}) {
  expect(finder, findsOneWidget);
  final element = finder.evaluate().single;
  final rect = tester.getRect(finder);
  var visibleTop = tester.getRect(find.byType(AppBar)).bottom;
  var visibleBottom = bodyBottom;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Scrollable) {
      final viewport = ancestor.renderObject! as RenderBox;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      visibleTop = math.max(visibleTop, viewportTop);
      visibleBottom = math.min(
        visibleBottom,
        viewportTop + viewport.size.height,
      );
    }
    return true;
  });
  // Прокрутка до края даёт координаты с ошибкой округления.
  expect(
    rect.top,
    greaterThanOrEqualTo(visibleTop - precisionErrorTolerance),
    reason: '$finder: верхний край видимой части',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(visibleBottom + precisionErrorTolerance),
    reason: '$finder: нижний край видимой части',
  );
  // Нажатие ровно на границе элементу не принадлежит, поэтому точки
  // отступают от краёв внутрь.
  for (final y in [rect.top + 1, rect.bottom - 1]) {
    final hit = tester.hitTestOnBinding(Offset(rect.center.dx, y));
    expect(
      [for (final entry in hit.path) entry.target],
      contains(element.renderObject),
      reason: '$finder: нажатие на высоте $y',
    );
  }
}

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
  await accepted.future;
  await tester.pump();
  await tester.pump();
}

/// Экранное положение намерения, видимого у верхнего края списка.
typedef _VisibleCatalogAnchor = ({String title, double top, int index});

/// Загружает страницу каталога с заданными условиями по тегам.
///
/// Условия задаются сразу моделью каталога, минуя раздел условий страницы.
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

final _addCondition = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

Finder _pickerAction(Tag tag, IntentionTagRequirement requirement) =>
    find.byKey(
      ValueKey(
        'tag-condition-picker-${requirement.name}-'
        '${tag.id.toCanonicalString()}',
      ),
    );

/// Тексты чипов раздела условий в порядке показа.
List<String> _shownConditions(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(IntentionTagConditionsSection),
      matching: find.byKey(const ValueKey('intention-tag-condition-label')),
    ),
  ))
    text.data!,
];

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

/// Передаёт модели условий выбор так же, как его возвращает экран поиска
/// тега.
Future<void> _selectCondition(
  WidgetTester tester,
  ProviderContainer container,
  Tag tag,
  IntentionTagRequirement requirement,
) async {
  container
      .read(
        intentionTagConditionsViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      )
      .applySelection(
        IntentionTagConditionSelection(
          tag: tag,
          requirement: requirement,
          snapshotRevision: const TestCatalogRevision(0),
        ),
      );
  await tester.pump();
}

/// Открывает каталог и выбирает условия через модель раздела условий.
///
/// Каждое условие сразу начинает новую выдачу; [page] отвечает на последнюю.
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
  for (final (tag, requirement) in conditions) {
    await _selectCondition(tester, container, tag, requirement);
  }
  await _pumpUntilQueries(tester, repository, conditions.length + 1);
  repository.complete(conditions.length, page);
  await tester.pumpAndSettle();
}

/// Доводит каталог до отказа обновления после удаления исключённого тега.
Future<void> _failCatalogRefresh(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required Tag required,
  required Tag deletedExcluded,
  required List<IntentionSummary> items,
  required IntentionFailure failure,
}) async {
  await _loadTaggedCatalog(
    tester,
    container,
    repository,
    IntentionTagFilter(
      requiredTagIds: [required.id],
      excludedTagIds: [deletedExcluded.id],
    ),
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestCatalogRevision(1),
    ),
  );
  await _completeCatalogWidgetTagCommand(
    tester,
    container,
    repository,
    DeleteTag(deletedExcluded.id),
    tagDeletionSuccess(
      tagId: deletedExcluded.id,
      revision: const TestCatalogRevision(2),
    ),
  );
  await _pumpUntilReconciliationQueries(tester, repository, 1);
  repository.completeReconciliation(0, ResultFailure(failure));
  await tester.pump();
  await tester.pump();
  await tester.pump();
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

Future<void> _pumpUntilReconciliationQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.reconciliationQueries.length >= count) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count чтений согласования каталога.');
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
