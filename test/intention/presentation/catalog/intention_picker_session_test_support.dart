import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_results.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';
import '../../../support/app_root_pages.dart';

/// Проверяет жизнь поисков одного назначения в настоящем стеке маршрутов.
void defineIntentionPickerSessionTests({
  required PageRouteInfo route,
  required String filterKey,
  required String listKey,
  IntentionScope scope = IntentionScope.active,
  IntentionId? excludedIntentionId,
  required IntentionReadinessFilter readinessFilter,
}) {
  testWidgets('вложенные поиски сохраняют свои параметры, порции и прокрутку', (
    tester,
  ) async {
    final (container, repository, router) = await _openApp(tester);
    final browse = container.read(
      intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
    );
    unawaited(router.push<void>(route));
    await _settleRoute(tester);
    final first = _purpose(tester);
    repository.complete(1, _page('Первая', hasMore: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ValueKey(filterKey)), 'Первая');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.complete(2, _page('Первая', hasMore: true));
    await tester.pumpAndSettle();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final conditions = container.read(
      intentionTagConditionsViewModelProvider(first).notifier,
    );
    for (final (tag, requirement) in [
      (health, IntentionTagRequirement.mustBePresent),
      (rest, IntentionTagRequirement.mustBeAbsent),
    ]) {
      conditions.applySelection(
        IntentionTagConditionSelection(
          tag: tag,
          requirement: requirement,
          snapshotRevision: const TestCatalogRevision(1),
        ),
      );
      await tester.pump();
    }
    repository.complete(4, _page('Первая', hasMore: true));
    await tester.pumpAndSettle();
    final continuation = container
        .read(intentionCatalogViewModelProvider(first).notifier)
        .loadNextPageIfNeeded(visibleIndex: 59);
    repository.complete(
      5,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: _items('Первая', 60),
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await continuation;
    await tester.pumpAndSettle();
    final firstState =
        container.read(intentionCatalogViewModelProvider(first)).requireValue
            as IntentionCatalogLoaded;
    expect(firstState.items, hasLength(120));
    final firstPosition = _position(tester, listKey);
    firstPosition.jumpTo(500);
    await tester.pumpAndSettle();
    final firstOffset = firstPosition.pixels;
    expect(firstOffset, greaterThan(0));

    unawaited(router.push<void>(route));
    await _settleRoute(tester);
    final second = _purpose(tester);
    expect(second, isNot(first));
    expect(repository.queries, hasLength(7));
    final initialQuery = repository.queryAt(6);
    expect(initialQuery.titleFilter, isNull);
    expect(initialQuery.tagFilter, IntentionTagFilter.empty);
    expect(initialQuery.scope, scope);
    expect(initialQuery.excludedIntentionId, excludedIntentionId);
    expect(initialQuery.readinessFilter, readinessFilter);
    expect(initialQuery.pageSize, 60);
    repository.complete(6, _page('Вторая'));
    await tester.pumpAndSettle();
    expect(_position(tester, listKey).pixels, 0);

    await tester.enterText(find.byKey(ValueKey(filterKey)), 'Вторая');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.complete(7, _page('Вторая'));
    await tester.pumpAndSettle();
    final secondConditions = container.read(
      intentionTagConditionsViewModelProvider(second).notifier,
    );
    for (final (tag, requirement) in [
      (health, IntentionTagRequirement.mustBeAbsent),
      (rest, IntentionTagRequirement.mustBePresent),
    ]) {
      secondConditions.applySelection(
        IntentionTagConditionSelection(
          tag: tag,
          requirement: requirement,
          snapshotRevision: const TestCatalogRevision(1),
        ),
      );
      await tester.pump();
    }
    repository.complete(9, _page('Вторая'));
    await tester.pumpAndSettle();
    _position(tester, listKey).jumpTo(200);
    await tester.pumpAndSettle();
    expect(_purpose(tester), same(second));
    expect(
      tester
          .widget<IntentionSearchResults>(find.byType(IntentionSearchResults))
          .purpose,
      same(second),
    );

    await router.maybePop();
    await tester.pumpAndSettle();
    expect(
      container.exists(intentionCatalogViewModelProvider(second)),
      isFalse,
    );
    expect(
      container.exists(intentionTagConditionsViewModelProvider(second)),
      isFalse,
    );
    expect(_purpose(tester), same(first));
    expect(_position(tester, listKey).pixels, firstOffset);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey(filterKey)))
          .controller!
          .text,
      'Первая',
    );
    expect(
      container.read(intentionCatalogViewModelProvider(first)).requireValue,
      same(firstState),
    );
    expect(
      container.read(intentionTagConditionsViewModelProvider(first)).tagFilter,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [rest.id],
      ),
    );
    expect(
      container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
      ),
      same(browse),
    );
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(container.exists(intentionCatalogViewModelProvider(first)), isFalse);
    expect(
      container.exists(intentionTagConditionsViewModelProvider(first)),
      isFalse,
    );
  });

  testWidgets(
    'новое открытие чистое, поздний ответ закрытого поиска изолирован',
    (tester) async {
      final (container, repository, router) = await _openApp(tester);
      unawaited(router.push<void>(route));
      await _settleRoute(tester);
      final closed = _purpose(tester);
      await tester.enterText(find.byKey(ValueKey(filterKey)), 'Закрытый поиск');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.queries, hasLength(3));
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(
        container.exists(intentionCatalogViewModelProvider(closed)),
        isFalse,
      );
      expect(
        container.exists(intentionTagConditionsViewModelProvider(closed)),
        isFalse,
      );

      unawaited(router.push<void>(route));
      await _settleRoute(tester);
      final current = _purpose(tester);
      expect(current, isNot(closed));
      expect(repository.queryAt(3).titleFilter, isNull);
      expect(repository.queryAt(3).tagFilter, IntentionTagFilter.empty);
      repository.complete(3, _page('Новая выдача'));
      await tester.pumpAndSettle();
      final currentState = container.read(
        intentionCatalogViewModelProvider(current),
      );
      repository.complete(2, _page('Поздняя выдача'));
      repository.complete(1, _page('Устаревшая первая порция'));
      await tester.pumpAndSettle();
      expect(
        container.read(intentionCatalogViewModelProvider(current)),
        same(currentState),
      );
      expect(find.text('Новая выдача 120'), findsOneWidget);
      expect(find.text('Поздняя выдача 120'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

IntentionCatalogPurpose _purpose(WidgetTester tester) => tester
    .widget<IntentionTagConditionsSection>(
      find.byType(IntentionTagConditionsSection),
    )
    .purpose;

ScrollPosition _position(WidgetTester tester, String listKey) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(PageStorageKey<String>(listKey)),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

List<IntentionSummary> _items(String title, int last) => [
  for (var index = last; index > last - 60; index--)
    testSummary(
      index: index,
      title: '$title $index',
      readiness: IntentionReadiness.ready,
    ),
];

Result<IntentionCatalogFirstPage> _page(String title, {bool hasMore = false}) =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: _items(title, 120),
        totalCount: hasMore ? 120 : 60,
        nextCursor: hasMore ? const TestCatalogCursor() : null,
        revision: const TestCatalogRevision(1),
      ),
    );

Tag _tag(int index, String name) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError('Некорректный ID тега в тесте.'),
  },
  name: TagName.fromInput(name),
);

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<(ProviderContainer, ControlledCatalogRepository, AppRouter)> _openApp(
  WidgetTester tester,
) async {
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository, pageSize: 60);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(
    0,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, repository, router);
}
