part of 'app_shell_pages_above_test.dart';

void _registerUnnamedPageTests() {
  testWidgets('диалог над намерением блокирует страницу и панель до закрытия', (
    tester,
  ) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Гулять'), IntentionDetailsPage);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
      expectedPanel: true,
    );
    await _tap(tester, intentionOptionsButton);
    await _tap(tester, intentionOption(IntentionOption.delete));
    await _until(tester, find.byType(Dialog));
    await tester.pumpAndSettle();
    expect(_destinations.hitTestable(), findsNothing);
    expect(_announcedDestinations, findsNothing);
    expect(intentionOptionsButton.hitTestable(), findsNothing);
    expect(intentionDeletionConfirm.hitTestable(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _gone(tester, Dialog);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
      expectedPanel: true,
    );
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(tester.takeException(), isNull);
  });
}
