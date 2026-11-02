part of 'app_shell_pages_above_test.dart';

void _registerUnnamedPageTests() {
  testWidgets('безымянное построение пути: пересчёт перед созданием', (
    tester,
  ) async {
    final router = await _start(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(HomePage))).push<void>(
        MaterialPageRoute(
          builder: (_) => ChoicePathPage.forCreationRefresh(
            startingIntentionId: _intentionId(_read),
            direction: ChoicePathDraftDirection.topDown,
          ),
        ),
      ),
    );
    await _until(tester, find.byType(ChoicePathPage));
    await tester.pumpAndSettle();
    _expectAboveShell(
      tester,
      ChoicePathPage,
      AppDestination.home,
      expectedPanel: false,
    );
    await _close(tester, ChoicePathPage);
    _expectRootPage(tester, router, AppDestination.home);
    expect(tester.takeException(), isNull);
  });

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
