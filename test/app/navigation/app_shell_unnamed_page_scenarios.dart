part of 'app_shell_pages_above_test.dart';

void _registerUnnamedPageTests() {
  // Направление пути не влияет на панель: нужны оба назначения, а направление
  // достаточно сменить между ними.
  for (final (purpose, direction) in [
    (ChoicePathPurpose.refreshCreation, ChoicePathDraftDirection.topDown),
    (ChoicePathPurpose.replace, ChoicePathDraftDirection.bottomUp),
  ]) {
    testWidgets(
      'безымянное построение пути: ${_purposeName(purpose)}, ${_directionName(direction)}',
      (tester) async {
        final router = await _start(tester);
        final startingId = _intentionId(
          direction == ChoicePathDraftDirection.topDown ? _read : _run,
        );
        final page = switch (purpose) {
          ChoicePathPurpose.create => throw StateError(
            'Создание открывается типизированным маршрутом',
          ),
          ChoicePathPurpose.refreshCreation =>
            ChoicePathPage.forCreationRefresh(
              startingIntentionId: startingId,
              direction: direction,
            ),
          ChoicePathPurpose.replace => ChoicePathPage.forReplacement(
            startingIntentionId: startingId,
            direction: direction,
          ),
        };
        unawaited(
          Navigator.of(tester.element(find.byType(HomePage)))
              .push<void>(MaterialPageRoute(builder: (_) => page)),
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
      },
    );
  }

  for (final direction in ChoicePathDraftDirection.values) {
    testWidgets(
      'безымянное подтверждение замены пути: ${_directionName(direction)}',
      (tester) async {
        final router = await _start(tester);
        const destination = AppDestination.dailyChoices;
        await _select(tester, destination);
        await _open(
          tester,
          find.byKey(const ValueKey('daily-choice-row-1')),
          DailyChoiceDetailsPage,
        );
        await _open(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-open')),
          DailyChoicePathReplacementFlow,
        );
        _expectAboveShell(
          tester,
          DailyChoicePathReplacementFlow,
          destination,
          expectedPanel: false,
        );
        final topDown = direction == ChoicePathDraftDirection.topDown;
        final picker = topDown
            ? DailyChoiceSourcePickerPage
            : DailyChoiceActionPickerPage;
        await _open(
          tester,
          find.byKey(
            ValueKey(
              topDown
                  ? 'daily-choice-replace-top-down'
                  : 'daily-choice-replace-bottom-up',
            ),
          ),
          picker,
        );
        await _open(
          tester,
          _summary(picker, topDown ? 'Читать' : 'Бегать'),
          ChoicePathPage,
        );
        _expectAboveShell(
          tester,
          ChoicePathPage,
          destination,
          expectedPanel: false,
        );
        await _confirmPath(tester, direction, DailyChoicePathReplacePage);
        _expectAboveShell(
          tester,
          DailyChoicePathReplacePage,
          destination,
          expectedPanel: false,
        );
        await _close(tester, DailyChoicePathReplacePage);
        _expectAboveShell(
          tester,
          DailyChoicePathReplacementFlow,
          destination,
          expectedPanel: false,
        );
        await _close(tester, DailyChoicePathReplacementFlow);
        _expectAboveShell(
          tester,
          DailyChoiceDetailsPage,
          destination,
          expectedPanel: true,
        );
        await _closeAll(tester);
        _expectRootPage(tester, router, destination);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('диалог над намерением блокирует страницу и панель до закрытия', (
    tester,
  ) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(
      tester,
      _summary(IntentionCatalogPage, 'Гулять'),
      IntentionDetailsPage,
    );
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

Future<void> _confirmPath(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
  Type confirmation,
) async {
  await _tap(tester, _continuePath);
  await _tap(
    tester,
    find.byKey(
      ValueKey(switch (direction) {
        ChoicePathDraftDirection.topDown => 'choice-path-select-action',
        ChoicePathDraftDirection.bottomUp => 'choice-path-select-source',
      }),
    ),
  );
  await _open(
    tester,
    find.byKey(const ValueKey('choice-path-open-confirmation')),
    confirmation,
  );
}

String _directionName(ChoicePathDraftDirection direction) =>
    switch (direction) {
      ChoicePathDraftDirection.topDown => 'сверху вниз',
      ChoicePathDraftDirection.bottomUp => 'снизу вверх',
    };

String _purposeName(ChoicePathPurpose purpose) => switch (purpose) {
  ChoicePathPurpose.create => 'создание',
  ChoicePathPurpose.refreshCreation => 'пересчёт перед созданием',
  ChoicePathPurpose.replace => 'замена',
};
