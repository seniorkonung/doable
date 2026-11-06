part of 'app_shell_pages_above_test.dart';

/// Ожидания следуют требованию «Панель на обычных страницах» независимо
/// от каркаса, которым реализована страница. Каждая строка запускает тест.
typedef _PageCase = ({
  String name,
  Type page,
  bool panel,
  List<_MatrixEntry> entries,
});

enum _MatrixEntry {
  intention,
  editIntention,
  creation,
  condition,
  assignTags,
  draftTags,
  createRelation,
  outgoingRelations,
  incomingRelations;

  Finder get finder => switch (this) {
    _MatrixEntry.intention => intentionCatalogRow('Читать'),
    _MatrixEntry.editIntention => intentionHeadTitle,
    _MatrixEntry.creation => quickCreationAction(),
    _MatrixEntry.condition => intentionCatalogTagFilterControl,
    _MatrixEntry.assignTags => find.byKey(
      const ValueKey('tag-assignments-choose'),
    ),
    _MatrixEntry.draftTags => find.byKey(
      const ValueKey('intention-editor-choose-tags'),
    ),
    _MatrixEntry.createRelation => find.byKey(
      const ValueKey('intention-relations-add'),
    ),
    _MatrixEntry.outgoingRelations => _outgoingNeedGroup,
    _MatrixEntry.incomingRelations => find.byKey(
      const ValueKey('intention-relations-group-neededFor'),
    ),
  };
}

void _registerPageMatrixTests() {
  testWidgets('страницы над поиском показывают панель и сохраняют отметку', (
    tester,
  ) async {
    await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    await _tap(tester, find.text('Relations').first);
    await _tap(tester, _outgoingNeedGroup);
    await _tap(tester, find.byKey(const ValueKey('intention-relations-add')));
    await _until(tester, _summary(RelationBatchPickerPage, 'Гулять'));
    await _tap(
      tester,
      find.descendant(
        of: _summary(RelationBatchPickerPage, 'Гулять'),
        matching: find.text('Гулять'),
      ),
    );
    await _until(tester, find.text('Add 1 relation'));

    final underlying = find.byType(IntentionDetailsPage, skipOffstage: false);
    tester.element(underlying).markNeedsBuild();
    await tester.pump();
    await _tap(
      tester,
      find.descendant(
        of: _summary(RelationBatchPickerPage, 'Бегать'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon &&
              widget.icon == DoableIconData.arrowUpRight,
        ),
      ),
    );
    await _until(tester, find.byType(IntentionDetailsPage));
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(find.byType(DockedFooter), findsNothing);
    await openIntentionChoicesTab(tester, waitFor: _until, tap: _tap);
    final selectedRole = find.byKey(
      const ValueKey('intention-choices-role-selected'),
    );
    expect(selectedRole, findsOneWidget);
    await _tap(tester, selectedRole);
    expect(selectedRole, findsOneWidget);
    await _tap(tester, find.text('Relations').first);
    await _tap(
      tester,
      find.byKey(const ValueKey('intention-relations-group-neededFor')),
    );
    await _until(tester, _relationRow);
    expect(
      find.byKey(const ValueKey('intention-relations-add')),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.descendant(
        of: _relationRow,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon &&
              widget.icon == DoableIconData.arrowUpRight,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(find.byType(DockedFooter), findsNothing);
    expect(
      find.byKey(const ValueKey('intention-relations-add')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _until(tester, find.byType(RelationBatchPickerPage));
    expect(find.text('Add 1 relation'), findsOneWidget);
    await _tap(tester, find.text('Add 1 relation'));
    await _until(tester, find.byType(IntentionDetailsPage));
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intention-relations-add')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('каталог на дату над поиском показывает панель', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    await _tap(tester, find.text('Relations').first);
    await _tap(tester, _outgoingNeedGroup);
    await _tap(tester, find.byKey(const ValueKey('intention-relations-add')));
    await _until(tester, find.byType(RelationBatchPickerPage));
    tester
        .element(find.byType(IntentionDetailsPage, skipOffstage: false))
        .markNeedsBuild();
    await tester.pump();
    unawaited(router.push(ActionDayDateRoute(date: _choiceDate)));
    await _until(tester, find.byType(ActionDayDatePage));
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _until(tester, find.byType(RelationBatchPickerPage));
    await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
    await _until(tester, find.byType(IntentionDetailsPage));
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intention-relations-add')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: каталог на дату — обычная страница поверх намерения', (
    tester,
  ) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    unawaited(router.push(ActionDayDateRoute(date: _choiceDate)));
    await _until(tester, find.byType(ActionDayDatePage));
    await tester.pumpAndSettle();
    _expectAboveShell(
      tester,
      ActionDayDatePage,
      AppDestination.intentionGraph,
      expectedPanel: true,
    );
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await _close(tester, ActionDayDatePage);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
    );
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: сценарий «Правка на странице намерения не скрывает '
      'панель»', (tester) async {
    await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    final types = find.byType(OptionTiles<IntentionReadiness>);
    final removeTag = find.byKey(
      ValueKey('tag-assignment-remove-${tagFixtureId(_tag)}'),
    );

    await _tap(
      tester,
      find.descendant(of: types, matching: find.text('Intention')),
    );
    await _waitFor(
      tester,
      () =>
          tester.widget<OptionTiles<IntentionReadiness>>(types).value ==
          IntentionReadiness.notReady,
    );
    // Индикатор выполняющейся команды не даёт кадрам успокоиться.
    await _waitFor(tester, () => !tester.binding.hasScheduledFrame);
    await _tap(tester, removeTag);
    await _waitFor(tester, () => removeTag.evaluate().isEmpty);
    await _waitFor(tester, () => !tester.binding.hasScheduledFrame);

    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: настройки — обычная страница поверх Главной', (
    tester,
  ) async {
    final router = await _start(tester, graphFiles: TemporaryGraphFiles());
    await _open(tester, find.byTooltip('Settings'), SettingsPage);
    _expectAboveShell(
      tester,
      SettingsPage,
      AppDestination.home,
      expectedPanel: true,
    );
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await _close(tester, SettingsPage);
    _expectRootPage(tester, router, AppDestination.home);
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: панель тегов перекрывает страницу намерения и панель '
      'навигации, а «назад» закрывает только её', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    await _tap(tester, _MatrixEntry.assignTags.finder);
    await _until(
      tester,
      find.byKey(ValueKey('tags-panel-row-${tagFixtureId(_tag)}')),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(Sheet);
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, _screen(tester).height);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(_MatrixEntry.assignTags.finder.hitTestable(), findsNothing);
    final bar = find.byType(AppNavigationBar);
    expect(bar, findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(bar).selected,
      AppDestination.intentionGraph,
    );
    expect(_destinations.hitTestable(), findsNothing);
    expect(_announcedDestinations, findsNothing);

    await tester.binding.handlePopRoute();
    await _gone(tester, Sheet);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
    );
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: сценарий «Каталог тегов открывается поверх каталога '
      'намерений» — панель фильтра перекрывает панель навигации, а «назад» '
      'возвращает каталог с прежними параметрами', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await enterIntentionCatalogTitle(tester, 'Читать');
    await _tap(tester, _MatrixEntry.condition.finder);
    await _until(
      tester,
      find.byKey(ValueKey('tags-panel-row-${tagFixtureId(_tag)}')),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(Sheet);
    expect(panel, findsOneWidget);
    expect(find.text('Filter by tags'), findsOneWidget);
    expect(tester.getRect(panel).bottom, _screen(tester).height);
    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(_MatrixEntry.condition.finder.hitTestable(), findsNothing);
    final bar = find.byType(AppNavigationBar);
    expect(bar, findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(bar).selected,
      AppDestination.intentionGraph,
    );
    expect(_destinations.hitTestable(), findsNothing);
    expect(_announcedDestinations, findsNothing);

    await tester.binding.handlePopRoute();
    await _gone(tester, Sheet);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(shownIntentionCatalogParameters(tester).titleFilter, 'Читать');
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: панель тегов перекрывает панель создания и панель '
      'навигации, а «назад» закрывает только её', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await openQuickCreation(
      tester,
      QuickCreationMode.intention,
      openedPage: find.byType(IntentionEditorPage),
      wait: _until,
    );
    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-title')),
      'Черновик',
    );
    await _tap(tester, _MatrixEntry.draftTags.finder);
    await _until(
      tester,
      find.byKey(ValueKey('tags-panel-row-${tagFixtureId(_tag)}')),
    );
    await tester.pumpAndSettle();

    // Панель тегов — не маршрут: над формой в стеке ничего не появляется.
    final panel = find.byType(Sheet);
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, _screen(tester).height);
    expect(router.current.name, IntentionEditorRoute.name);
    expect(_MatrixEntry.draftTags.finder.hitTestable(), findsNothing);
    final bar = find.byType(AppNavigationBar);
    expect(bar, findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(bar).selected,
      AppDestination.intentionGraph,
    );
    expect(_destinations.hitTestable(), findsNothing);
    expect(_announcedDestinations, findsNothing);

    await tester.binding.handlePopRoute();
    await _gone(tester, Sheet);
    expect(router.current.name, IntentionEditorRoute.name);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('intention-editor-title')),
          )
          .controller!
          .text,
      'Черновик',
    );
    _expectCreationSheetAboveCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('матрица: панель связи перекрывает страницу намерения и панель '
      'навигации, а «назад» закрывает только её', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(tester, intentionCatalogRow('Читать'), IntentionDetailsPage);
    await _tap(tester, find.text('Relations').first);
    await _tap(tester, _outgoingNeedGroup);
    await _tap(tester, _relationRow);
    await _until(tester, find.byType(RelationHead));
    await tester.pumpAndSettle();

    // Панель — не маршрут-страница: в стеке по-прежнему страница намерения.
    final panel = find.byType(Sheet);
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, _screen(tester).height);
    expect(router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
    ]);
    expect(router.hasPagelessTopRoute, isTrue);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(_relationRow.hitTestable(), findsNothing);
    final bar = find.byType(AppNavigationBar);
    expect(bar, findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(bar).selected,
      AppDestination.intentionGraph,
    );
    expect(_destinations.hitTestable(), findsNothing);
    expect(_announcedDestinations, findsNothing);

    await tester.binding.handlePopRoute();
    await _gone(tester, Sheet);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
    );
    expect(router.hasPagelessTopRoute, isFalse);
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(tester.takeException(), isNull);
  });

  const read = _MatrixEntry.intention;
  const cases = <_PageCase>[
    (
      name: 'намерение',
      page: IntentionDetailsPage,
      panel: true,
      entries: [read],
    ),
    (
      name: 'изменение намерения',
      page: IntentionEditPage,
      panel: false,
      entries: [read, _MatrixEntry.editIntention],
    ),
    (
      name: 'создание намерения',
      page: IntentionEditorPage,
      panel: false,
      entries: [_MatrixEntry.creation],
    ),
    (
      name: 'поиск участника исходящей группы',
      page: RelationBatchPickerPage,
      panel: false,
      entries: [
        read,
        _MatrixEntry.outgoingRelations,
        _MatrixEntry.createRelation,
      ],
    ),
    (
      name: 'поиск участника входящей группы',
      page: RelationBatchPickerPage,
      panel: false,
      entries: [
        read,
        _MatrixEntry.incomingRelations,
        _MatrixEntry.createRelation,
      ],
    ),
  ];

  for (final row in cases) {
    testWidgets('матрица: ${row.name}', (tester) async {
      await _start(tester);
      var destination = AppDestination.home;
      for (final entry in row.entries) {
        final root = switch (entry) {
          _MatrixEntry.intention ||
          _MatrixEntry.creation ||
          _MatrixEntry.condition => AppDestination.intentionGraph,
          _ => null,
        };
        if (root != null) {
          destination = root;
          await _select(tester, destination);
        }
        switch (entry) {
          case _MatrixEntry.creation:
            await openQuickCreation(
              tester,
              QuickCreationMode.intention,
              openedPage: find.byType(IntentionEditorPage),
              wait: _until,
            );
          default:
            if (entry == _MatrixEntry.createRelation ||
                entry == _MatrixEntry.outgoingRelations ||
                entry == _MatrixEntry.incomingRelations) {
              await _tap(tester, find.text('Relations').first);
            }
            await _tap(tester, entry.finder);
        }
        await tester.pumpAndSettle();
      }
      await _until(tester, find.byType(row.page));
      await tester.pumpAndSettle();
      for (final searchBar in tester.widgetList<IntentionSearchBar>(
        find.descendant(
          of: find.byType(row.page),
          matching: find.byType(IntentionSearchBar),
        ),
      )) {
        expect(_pageForCatalogPurpose(searchBar.purpose), row.page);
      }
      if (row.page == IntentionEditorPage) {
        _expectCreationSheetAboveCatalog(tester);
      } else {
        _expectAboveShell(
          tester,
          row.page,
          destination,
          expectedPanel: row.panel,
        );
      }
      if (row.page == IntentionEditPage) {
        // Страница намерения под закрытым экраном изменения снова с панелью.
        await _close(tester, IntentionEditPage);
        _expectAboveShell(tester, IntentionDetailsPage, destination);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

/// Новый вариант назначения требует явно указать проверяемую страницу.
Type _pageForCatalogPurpose(IntentionCatalogPurpose purpose) =>
    switch (purpose) {
      BrowseIntentionCatalog() => IntentionCatalogPage,
      SelectRelationParticipant() => RelationBatchPickerPage,
    };
