import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
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
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

  for (final (name, change) in <(String, Future<void> Function(WidgetTester))>[
    (
      'фильтр названия',
      (tester) async {
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          'Намерение',
        );
        await tester.pump(const Duration(milliseconds: 250));
      },
    ),
    (
      'порядок',
      (tester) async {
        await tester.tap(find.byKey(const ValueKey('catalog-order-control')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Created: oldest first').last);
        await tester.pump();
      },
    ),
  ]) {
    testWidgets('новый $name начинает выдачу с верхней позиции', (
      tester,
    ) async {
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository));
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [
              for (var index = 30; index >= 1; index--)
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

      await change(tester);
      expect(repository.queries, hasLength(2));
      repository.complete(
        1,
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

      expect(_catalogScrollPosition(tester).pixels, 0);
    });
  }

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
    final before = _loadedCatalog(container);
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
    expect(_loadedCatalog(container), same(before));
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
    expect(current.query, same(before.query));
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
    expect(repository.queries, hasLength(2));
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
    final before = _loadedCatalog(container);
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
    expect(_loadedCatalog(container).query, same(before.query));
    expect(loadingStates, isEmpty);
    expect(repository.queries, hasLength(2));
  });

  testWidgets('отказ чтения согласования оставляет список и экранную '
      'позицию без изменений', (tester) async {
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
    final before = _loadedCatalog(container);
    final anchor = await _scrollToMiddle(tester, items);
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
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pump();
    await tester.pump();

    final failed = _loadedCatalog(container);
    expect(failed.refresh, isA<IntentionCatalogRefreshUnavailable>());
    expect(failed.query, same(before.query));
    expect(failed.items, before.items);
    expect(find.text('Total intentions: 30'), findsOneWidget);
    expect(
      _catalogScrollPosition(tester).pixels,
      moreOrLessEquals(positionBefore, epsilon: 0.01),
    );
    expect(
      _catalogTileTop(tester, anchor.title),
      moreOrLessEquals(anchor.top, epsilon: 0.01),
    );
    expect(loadingStates, isEmpty);
    expect(repository.queries, hasLength(2));
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
      const Offset(0, -2000),
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

    await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
    await tester.pumpAndSettle();
    expect(router.current.name, IntentionEditorRoute.name);

    await tester.pageBack();
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
      const Offset(0, -2000),
    );
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

    final reloadButton = find.widgetWithText(FilledButton, 'Reload catalog');
    await tester.ensureVisible(reloadButton);
    await tester.pumpAndSettle();
    await tester.tap(reloadButton);
    await _pumpUntilQueries(tester, repository, 3);
    expect(repository.queryAt(2).cursor, isNull);
    // Действие стоит выше кнопки создания намерения, поэтому первая строка
    // сохранённой выдачи уходит за верхний край списка.
    expect(find.text('Прежнее первое', skipOffstage: false), findsOneWidget);
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

  for (final (language, ownTags, otherTags, noTags) in [
    ('en', 'Tags: Здоровье, Отдых', 'Tags: Семья', 'No tags'),
    ('ru', 'Теги: Здоровье, Отдых', 'Теги: Семья', 'Без тегов'),
  ]) {
    testWidgets('$language: строки без условий показывают собственные теги, '
        'а одноимённые намерения их не объединяют', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledCatalogRepository();
      await tester.pumpWidget(_testApp(repository, locale: Locale(language)));
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [
              testSummary(
                index: 3,
                title: 'Гулять',
                tags: [_tag(1, 'Здоровье'), _tag(2, 'Отдых')],
              ),
              testSummary(index: 2, title: 'Гулять', tags: [_tag(3, 'Семья')]),
              testSummary(index: 1, title: 'Читать'),
            ],
            totalCount: 3,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.queryAt(0).tagFilter, IntentionTagFilter.empty);
      expect(_shownConditions(tester), isEmpty);
      final rows = find.byType(IntentionSummaryView);
      expect(rows, findsNWidgets(3));
      for (final (index, title, tagsLine) in [
        (0, 'Гулять', ownTags),
        (1, 'Гулять', otherTags),
        (2, 'Читать', noTags),
      ]) {
        final row = rows.at(index);
        expect(
          find.descendant(of: row, matching: find.text(tagsLine)),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(row).label,
          allOf(contains(title), contains(tagsLine)),
        );
      }
      semantics.dispose();
    });
  }

  testWidgets('условие, добавленное через экран поиска тега под полем '
      'названия, сразу начинает выдачу с верхней позиции', (tester) async {
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
    repository.complete(0, _firstPage(_taggedSummaries(const [], last: 1)));
    await tester.pumpAndSettle();

    final section = tester.getRect(find.byType(IntentionTagConditionsSection));
    expect(
      section.top,
      greaterThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('catalog-filter-field')))
            .bottom,
      ),
    );
    expect(
      section.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('catalog-order-control'))).top,
      ),
    );
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

    expect(router.current.name, IntentionCatalogRoute.name);
    expect(_shownConditions(tester), ['Здоровье']);
    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
    expect(find.text('Tags: Здоровье'), findsWidgets);
    expect(find.text('No tags'), findsNothing);
    expect(repository.tagCommands, isEmpty);
  });

  testWidgets('переключение и снятие условия сразу начинают выдачу с '
      'верхней позиции', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final sport = _tag(2, 'Спорт');
    await _openCatalogWithConditions(tester, container, repository, [
      (sport, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(_taggedSummaries(const [], last: 1)));
    expect(_shownConditions(tester), ['not Спорт']);
    await _scrollCatalogDown(tester);

    await tester.tap(_conditionToggle(sport));
    await _pumpUntilQueries(tester, repository, 3);
    expect(
      repository.queryAt(2).tagFilter,
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    expect(repository.queryAt(2).cursor, isNull);
    repository.complete(2, _firstPage(_taggedSummaries([sport], last: 1)));
    await tester.pumpAndSettle();

    expect(_shownConditions(tester), ['Спорт']);
    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
    await _scrollCatalogDown(tester);

    await tester.tap(_conditionRemove(sport));
    await _pumpUntilQueries(tester, repository, 4);
    expect(repository.queryAt(3).tagFilter, IntentionTagFilter.empty);
    expect(repository.queryAt(3).cursor, isNull);
    repository.complete(3, _firstPage(_taggedSummaries(const [], last: 1)));
    await tester.pumpAndSettle();

    expect(_shownConditions(tester), isEmpty);
    expect(_catalogScrollPosition(tester).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
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

  for (final (language, byConditions, byScope) in [
    (
      'en',
      'No intentions match the tag conditions.',
      'No active intentions yet.',
    ),
    (
      'ru',
      'По условиям по тегам совпадений нет.',
      'Активных намерений пока нет.',
    ),
  ]) {
    testWidgets('$language: пустая выдача при условиях по тегам сообщает об '
        'отсутствии совпадений по условиям, а не о пустом охвате', (
      tester,
    ) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _testAppWithContainer(container, locale: Locale(language)),
      );
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
  }

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
    // Отказ стоит над списком и не закрывает его первую строку.
    final list = tester.getRect(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
    );
    final status = tester.getRect(_refreshStatus);
    expect(status.top, moreOrLessEquals(list.top, epsilon: 0.01));
    expect(
      _catalogTileTop(tester, 'Намерение 60'),
      moreOrLessEquals(status.bottom, epsilon: 0.01),
    );

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

  testWidgets('отказ обновления над списком, который помещается на экране, '
      'отводит место без ошибок компоновки', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final items = _taggedSummaries([health], first: 2, last: 2);
    await _failCatalogRefresh(
      tester,
      container,
      repository,
      required: health,
      deletedExcluded: rest,
      items: items,
      failure: const IntentionUnavailableFailure(),
    );

    // Появление отказа делает короткий список прокручиваемым: его первая
    // строка уходит из-под отказа.
    expect(tester.takeException(), isNull);
    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    final status = tester.getRect(_refreshStatus);
    expect(
      _catalogTileTop(tester, 'Намерение 2'),
      moreOrLessEquals(status.bottom, epsilon: 0.01),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(
        const [],
        totalCount: items.length,
        revision: 2,
      ),
    );
    await tester.pumpAndSettle();

    // Снятие отказа возвращает строки на место.
    expect(tester.takeException(), isNull);
    expect(message, findsNothing);
    final list = tester.getRect(
      find.byKey(const PageStorageKey<String>('intention-catalog-list')),
    );
    expect(
      _catalogTileTop(tester, 'Намерение 2'),
      moreOrLessEquals(list.top, epsilon: 0.01),
    );
  });

  for (final (name, failure, text) in <(String, IntentionFailure, String)>[
    (
      'повреждения',
      const IntentionCorruptionFailure(),
      'The intention list isn’t up to date: stored data is damaged.',
    ),
    (
      'неожиданной ошибки',
      const IntentionUnexpectedFailure(),
      'The intention list isn’t up to date because of an unexpected error.',
    ),
  ]) {
    testWidgets('отказ обновления из-за $name показан без повтора и не '
        'закрывает начало прокрученного списка', (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      final health = _tag(1, 'Здоровье');
      final items = _taggedSummaries([health], last: 2, step: 2);
      await _failCatalogRefresh(
        tester,
        container,
        repository,
        required: health,
        deletedExcluded: _tag(2, 'Отдых'),
        items: items,
        failure: failure,
        scrollBeforeFailure: true,
      );

      expect(find.text(text), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(_loadedCatalog(container).items, items);
      expect(repository.reconciliationQueries, hasLength(1));

      // Начало сохранённой выдачи достижимо прокруткой и при отказе.
      final list = find.byKey(
        const PageStorageKey<String>('intention-catalog-list'),
      );
      await tester.drag(list, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(
        _catalogTileTop(tester, 'Намерение 60'),
        moreOrLessEquals(tester.getRect(_refreshStatus).bottom, epsilon: 0.01),
      );
    });
  }

  testWidgets('успешная пустая выдача показывает только сообщение о пустоте, '
      'без представления отказа обновления', (tester) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    await _loadTaggedCatalog(
      tester,
      container,
      repository,
      IntentionTagFilter(requiredTagIds: [health.id]),
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    );

    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(tester.getSize(_refreshStatus).height, 0);
    expect(
      find.descendant(of: _refreshStatus, matching: find.byType(Text)),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
  });

  testWidgets('отказ обновления из-за недоступности показан над исходно '
      'пустой выдачей, а повтор согласует её с прежними условиями', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    await _failCatalogRefresh(
      tester,
      container,
      repository,
      required: health,
      deletedExcluded: rest,
      items: const [],
      failure: const IntentionUnavailableFailure(),
      selectConditions: true,
    );

    // Сообщение о пустоте остаётся, но выдача явно названа не обновлённой.
    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(
      tester.getRect(_refreshStatus).bottom,
      lessThanOrEqualTo(tester.getRect(find.text(_emptyByConditions)).top),
    );
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
    final failedQuery = repository.reconciliationQueryAt(0).catalogQuery;
    expect(failedQuery.scope, IntentionScope.active);
    expect(
      failedQuery.tagFilter,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
    );

    final retry = find.descendant(
      of: _refreshStatus,
      matching: find.widgetWithText(FilledButton, 'Try again'),
    );
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    // Повтор читает ту же область с прежними условиями и охватом.
    expect(repository.reconciliationQueryAt(1).catalogQuery, same(failedQuery));
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(const [], totalCount: 0, revision: 2),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(retry, findsNothing);
    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
  });

  for (final (name, failure, text) in <(String, IntentionFailure, String)>[
    (
      'повреждения',
      const IntentionCorruptionFailure(),
      'The intention list isn’t up to date: stored data is damaged.',
    ),
    (
      'неожиданной ошибки',
      const IntentionUnexpectedFailure(),
      'The intention list isn’t up to date because of an unexpected error.',
    ),
  ]) {
    testWidgets('отказ обновления из-за $name показан над исходно пустой '
        'выдачей без повтора', (tester) async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      await _failCatalogRefresh(
        tester,
        container,
        repository,
        required: _tag(1, 'Здоровье'),
        deletedExcluded: _tag(2, 'Отдых'),
        items: const [],
        failure: failure,
        selectConditions: true,
      );

      expect(find.text(text), findsOneWidget);
      expect(find.text(_emptyByConditions), findsOneWidget);
      expect(
        tester.getRect(_refreshStatus).bottom,
        lessThanOrEqualTo(tester.getRect(find.text(_emptyByConditions)).top),
      );
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
      expect(repository.reconciliationQueries, hasLength(1));
    });
  }

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
      RenameTag(tagId: health.id, name: renamed.name),
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

  testWidgets('каталог с условиями, тегами строк и отказом обновления '
      'проходит accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(repository);
    addTearDown(container.dispose);
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    await _failCatalogRefresh(
      tester,
      container,
      repository,
      required: health,
      deletedExcluded: rest,
      items: _taggedSummaries([health], last: 2, step: 2),
      failure: const IntentionUnavailableFailure(),
      selectConditions: true,
    );
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(
      tester.getSemantics(_refreshStatus),
      isSemantics(isLiveRegion: true),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
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

Widget _testAppWithContainer(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
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
  await tester.drag(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
    Offset(0, -distance),
  );
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

const _emptyByConditions = 'No intentions match the tag conditions.';

final _refreshStatus = find.byType(IntentionCatalogRefreshStatusView);
final _addCondition = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

Finder _conditionToggle(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-toggle-${tag.id.toCanonicalString()}'),
);

Finder _conditionRemove(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-remove-${tag.id.toCanonicalString()}'),
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
  await tester.drag(
    find.byKey(const PageStorageKey<String>('intention-catalog-list')),
    const Offset(0, -800),
  );
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
  bool scrollBeforeFailure = false,
  bool selectConditions = false,
}) async {
  final page = IntentionCatalogFirstPage(
    items: items,
    totalCount: items.length,
    nextCursor: null,
    revision: const TestCatalogRevision(1),
  );
  if (selectConditions) {
    await _openCatalogWithConditions(tester, container, repository, [
      (required, IntentionTagRequirement.mustBePresent),
      (deletedExcluded, IntentionTagRequirement.mustBeAbsent),
    ], ResultSuccess(page));
  } else {
    await _loadTaggedCatalog(
      tester,
      container,
      repository,
      IntentionTagFilter(
        requiredTagIds: [required.id],
        excludedTagIds: [deletedExcluded.id],
      ),
      page,
    );
  }
  if (scrollBeforeFailure) {
    await _scrollCatalogDown(tester);
  }
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
