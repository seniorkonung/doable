part of 'tag_navigation_app_lifecycle_test.dart';

void _registerPrimaryNavigationAppScenarios() {
  for (final origin in AppDestination.values) {
    for (final sameDestination in [true, false]) {
      final destination = sameDestination
          ? origin
          : AppDestination.values[(origin.index + 1) %
                AppDestination.values.length];
      testWidgets('тег над пунктом ${origin.index + 1} сохраняет выдачу при '
          'возврате и сбрасывает историю к пункту ${destination.index + 1}', (
        tester,
      ) async {
        final app = await _App.pump(tester);
        final filter = find.byKey(const ValueKey('catalog-filter-field'));
        await tester.enterText(filter, 'Получатель');
        await tester.pump(const Duration(milliseconds: 400));
        await _waitFor(
          tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        await tester.pumpAndSettle();
        final rootField = tester.element(filter);
        await _selectPrimaryDestination(tester, origin);
        await app.openNavigation(tester);
        await app.loaded(tester);
        _expectPrimaryDestination(tester, origin);

        await _changeScope(tester, TaggedIntentionsScope.archived);
        await app.loaded(tester);
        unawaited(app.model(tester).loadMore());
        final before = await app.loaded(tester);
        expect(before.items, hasLength(52));
        expect(before.hasReachedEnd, isTrue);
        final model = app.model(tester);
        final queryCount = app.repository.queries.length;
        final target = find.byKey(ValueKey(_intention(1150)));
        final scrolling = find.descendant(
          of: find.byType(TagNavigationPage),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(target, 800, scrollable: scrolling);
        await tester.pumpAndSettle();
        final offset = tester.state<ScrollableState>(scrolling).position.pixels;
        await _tap(tester, target);
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('intention-details-title'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(app.router.current.name, IntentionDetailsRoute.name);
        _expectPrimaryDestination(tester, origin);

        await tester.binding.handlePopRoute();
        await _waitFor(
          tester,
          () => find.byType(TagNavigationPage).evaluate().isNotEmpty,
        );
        final after = await app.loaded(tester);
        expect(app.router.current.name, TagNavigationRoute.name);
        expect(app.model(tester), same(model));
        expect(after.scope, before.scope);
        expect(after.items, before.items);
        expect(after.revision, before.revision);
        expect(after.nextCursor, before.nextCursor);
        expect(app.repository.queries, hasLength(queryCount));
        expect(
          tester.state<ScrollableState>(scrolling).position.pixels,
          offset,
        );
        _expectPrimaryDestination(tester, origin);

        await _tap(tester, target);
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('intention-details-title'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        await _selectPrimaryDestination(tester, destination);
        expect(app.router.stack.map((route) => route.name), [
          AppShellRoute.name,
        ]);
        expect(app.router.topRoute.name, destination.page.name);
        expect(
          find.byType(TagNavigationPage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('intention-details-title'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(find.byType(AlertDialog), findsNothing);
        _expectPrimaryDestination(tester, destination);

        await _selectPrimaryDestination(tester, AppDestination.intentionGraph);
        expect(tester.element(filter), same(rootField));
        expect(tester.widget<TextField>(filter).controller!.text, 'Получатель');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(app.router.topRoute.name, AppDestination.home.page.name);
        expect(app.router.stack, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _expectPrimaryDestination(
  WidgetTester tester,
  AppDestination destination,
) {
  final bar = find.byType(AppNavigationBar);
  expect(bar, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsNWidgets(3));
  for (final item in AppDestination.values) {
    final entry = appNavigationDestination(item);
    expect(entry.hitTestable(), findsOneWidget);
    expect(
      tester.getSemantics(entry),
      containsSemantics(
        hasSelectedState: true,
        isSelected: item == destination,
        hasTapAction: true,
      ),
      reason: 'Пункт ${item.name}',
    );
  }
}

Future<void> _selectPrimaryDestination(
  WidgetTester tester,
  AppDestination destination,
) async {
  final entry = appNavigationDestination(destination);
  expect(entry.hitTestable(), findsOneWidget);
  await tester.tap(entry);
  await tester.pump();
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}
