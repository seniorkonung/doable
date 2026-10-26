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
  dailyChoice,
  creation,
  condition,
  action,
  actionCandidate,
  relation,
  assignTags,
  draftTags,
  replaceChoice,
  replaceTopDown,
  choosePath,
  continuePath,
  selectAction,
  selectSource,
  confirmPath,
  editChoice,
  createRelation,
  incomingRelations,
  editRelation,
  changeSource,
  selectRelated;

  Finder get finder => switch (this) {
    _MatrixEntry.intention => _summary(IntentionCatalogPage, 'Читать'),
    _MatrixEntry.dailyChoice => find.byKey(
      const ValueKey('daily-choice-row-1'),
    ),
    _MatrixEntry.creation || _MatrixEntry.action => quickCreationAction(),
    _MatrixEntry.condition => find.byKey(
      const ValueKey('intention-tag-conditions-add'),
    ),
    _MatrixEntry.actionCandidate => _summary(
      DailyChoiceActionPickerPage,
      'Бегать',
    ),
    _MatrixEntry.relation => _relationRow,
    _MatrixEntry.assignTags => find.byKey(
      const ValueKey('tag-assignments-choose'),
    ),
    _MatrixEntry.draftTags => find.byKey(
      const ValueKey('intention-editor-choose-tags'),
    ),
    _MatrixEntry.replaceChoice => find.byKey(
      const ValueKey('daily-choice-replace-open'),
    ),
    _MatrixEntry.replaceTopDown => find.byKey(
      const ValueKey('daily-choice-replace-top-down'),
    ),
    _MatrixEntry.choosePath => find.byKey(
      const ValueKey('intention-details-choose-path'),
    ),
    _MatrixEntry.continuePath => _continuePath,
    _MatrixEntry.selectAction => find.byKey(
      const ValueKey('choice-path-select-action'),
    ),
    _MatrixEntry.selectSource => find.byKey(
      const ValueKey('choice-path-select-source'),
    ),
    _MatrixEntry.confirmPath => find.byKey(
      const ValueKey('choice-path-open-confirmation'),
    ),
    _MatrixEntry.editChoice => find.byKey(
      const ValueKey('daily-choice-edit-open'),
    ),
    _MatrixEntry.createRelation => find.byKey(
      const ValueKey('relation-neighborhood-create-relation'),
    ),
    _MatrixEntry.incomingRelations => find.byKey(
      const ValueKey('relation-neighborhood-direction-incoming'),
    ),
    _MatrixEntry.editRelation => find.byKey(
      const ValueKey('relation-details-edit-relation'),
    ),
    _MatrixEntry.changeSource => find.byKey(
      const ValueKey('relation-editor-change-source'),
    ),
    _MatrixEntry.selectRelated => find.byKey(
      const ValueKey('relation-editor-select-related'),
    ),
  };
}

void _registerPageMatrixTests() {
  testWidgets('матрица: каталог на дату — обычная страница поверх намерения', (
    tester,
  ) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await _open(
      tester,
      _summary(IntentionCatalogPage, 'Читать'),
      IntentionDetailsPage,
    );
    unawaited(router.push(DailyChoiceDateCatalogRoute(date: _choiceDate)));
    await _until(tester, find.byType(DailyChoiceDateCatalogPage));
    await tester.pumpAndSettle();
    _expectAboveShell(
      tester,
      DailyChoiceDateCatalogPage,
      AppDestination.intentionGraph,
      expectedPanel: true,
    );
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await _close(tester, DailyChoiceDateCatalogPage);
    _expectAboveShell(
      tester,
      IntentionDetailsPage,
      AppDestination.intentionGraph,
    );
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
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
    await _open(
      tester,
      _summary(IntentionCatalogPage, 'Читать'),
      IntentionDetailsPage,
    );
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
    final filter = find.byKey(const ValueKey('catalog-filter-field'));
    await tester.enterText(filter, 'Читать');
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
    expect(tester.widget<TextField>(filter).controller!.text, 'Читать');
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

  const read = _MatrixEntry.intention;
  const daily = _MatrixEntry.dailyChoice;
  const cases = <_PageCase>[
    (
      name: 'намерение',
      page: IntentionDetailsPage,
      panel: true,
      entries: [read],
    ),
    (
      name: 'долговременная связь',
      page: RelationDetailsPage,
      panel: true,
      entries: [read, _MatrixEntry.relation],
    ),
    (
      name: 'дневной выбор',
      page: DailyChoiceDetailsPage,
      panel: true,
      entries: [daily],
    ),
    (
      name: 'поиск действия',
      page: DailyChoiceActionPickerPage,
      panel: false,
      entries: [_MatrixEntry.action],
    ),
    (
      name: 'поиск основания',
      page: DailyChoiceSourcePickerPage,
      panel: false,
      entries: [daily, _MatrixEntry.replaceChoice, _MatrixEntry.replaceTopDown],
    ),
    (
      name: 'создание намерения',
      page: IntentionEditorPage,
      panel: false,
      entries: [_MatrixEntry.creation],
    ),
    (
      name: 'путь от намерения',
      page: ChoicePathPage,
      panel: false,
      entries: [read, _MatrixEntry.choosePath],
    ),
    (
      name: 'подтверждение дневного выбора сверху вниз',
      page: DailyChoiceCreationPage,
      panel: false,
      entries: [
        read,
        _MatrixEntry.choosePath,
        _MatrixEntry.continuePath,
        _MatrixEntry.selectAction,
        _MatrixEntry.confirmPath,
      ],
    ),
    (
      name: 'подтверждение дневного выбора снизу вверх',
      page: DailyChoiceCreationPage,
      panel: false,
      entries: [
        _MatrixEntry.action,
        _MatrixEntry.actionCandidate,
        _MatrixEntry.continuePath,
        _MatrixEntry.selectSource,
        _MatrixEntry.confirmPath,
      ],
    ),
    (
      name: 'изменение дневного выбора',
      page: DailyChoiceEditPage,
      panel: false,
      entries: [daily, _MatrixEntry.editChoice],
    ),
    (
      name: 'создание исходящей связи',
      page: RelationEditorPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation],
    ),
    (
      name: 'создание входящей связи',
      page: RelationEditorPage,
      panel: false,
      entries: [
        read,
        _MatrixEntry.incomingRelations,
        _MatrixEntry.createRelation,
      ],
    ),
    (
      name: 'изменение связи',
      page: RelationEditorPage,
      panel: false,
      entries: [read, _MatrixEntry.relation, _MatrixEntry.editRelation],
    ),
    (
      name: 'поиск исходного участника',
      page: RelationParticipantPickerPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation, _MatrixEntry.changeSource],
    ),
    (
      name: 'поиск связанного участника',
      page: RelationParticipantPickerPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation, _MatrixEntry.selectRelated],
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
          _MatrixEntry.dailyChoice ||
          _MatrixEntry.action => AppDestination.dailyChoices,
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
          case _MatrixEntry.action:
            await openDailyChoiceQuickCreation(
              tester,
              ChoicePathDraftDirection.bottomUp,
              openedPage: find.byType(DailyChoiceActionPickerPage),
              wait: _until,
            );
          default:
            await _tap(tester, entry.finder);
        }
        await tester.pumpAndSettle();
      }
      await _until(tester, find.byType(row.page));
      await tester.pumpAndSettle();
      final variant = switch (tester.widget(find.byType(row.page))) {
        RelationEditorPage(:final editorContext) => switch (editorContext) {
          RelationBlankCreationContext() => 'создание связи без участников',
          RelationCreationContext(:final direction) => switch (direction) {
            RelationDirection.outgoing => 'создание исходящей связи',
            RelationDirection.incoming => 'создание входящей связи',
          },
          RelationEditingContext() => 'изменение связи',
        },
        _ => null,
      };
      if (variant != null) expect(variant, row.name);
      for (final section in tester.widgetList<IntentionTagConditionsSection>(
        find.descendant(
          of: find.byType(row.page),
          matching: find.byType(IntentionTagConditionsSection),
        ),
      )) {
        expect(_pageForCatalogPurpose(section.purpose), row.page);
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
      expect(tester.takeException(), isNull);
    });
  }

  for (final scope in RelationScope.values) {
    final name = switch (scope) {
      RelationScope.active => 'активной связи',
      RelationScope.archived => 'архивной связи',
    };
    testWidgets('поиск участника $name без панели', (tester) async {
      final router = await _start(tester);
      final choice = RelationParticipantChoice(
        role: RelationParticipantRole.related,
        flow: RelationChangeChoiceFlow(relationScope: scope),
        type: LongTermRelationType.need,
        source: RelationParticipantSummary(
          id: _intentionId(_read),
          title: 'Читать',
          archiveState: IntentionArchiveState.active,
        ),
        related: RelationParticipantSummary(
          id: _intentionId(_run),
          title: 'Бегать',
          archiveState: IntentionArchiveState.active,
        ),
      );
      unawaited(router.push(RelationParticipantPickerRoute(choice: choice)));
      await _until(tester, _summary(RelationParticipantPickerPage, 'Бегать'));
      await tester.pumpAndSettle();
      _expectAboveShell(
        tester,
        RelationParticipantPickerPage,
        AppDestination.home,
        expectedPanel: false,
      );
      expect(
        tester
            .widget<RelationParticipantPickerPage>(
              find.byType(RelationParticipantPickerPage),
            )
            .choice,
        same(choice),
      );
      await _close(tester, RelationParticipantPickerPage);
      _expectRootPage(tester, router, AppDestination.home);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('матрица: создание связи без участников — задача без панели', (
    tester,
  ) async {
    final router = await _start(tester);
    unawaited(
      router.push(
        RelationEditorRoute(
          editorContext: const RelationBlankCreationContext(),
        ),
      ),
    );
    await _until(tester, find.byType(RelationEditorPage));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RelationEditorPage>(find.byType(RelationEditorPage))
          .editorContext,
      isA<RelationBlankCreationContext>(),
    );
    _expectAboveShell(
      tester,
      RelationEditorPage,
      AppDestination.home,
      expectedPanel: false,
    );
    await _close(tester, RelationEditorPage);
    _expectRootPage(tester, router, AppDestination.home);
    expect(tester.takeException(), isNull);
  });
}

/// Новый вариант назначения требует явно указать проверяемую страницу.
Type _pageForCatalogPurpose(IntentionCatalogPurpose purpose) =>
    switch (purpose) {
      BrowseIntentionCatalog() => IntentionCatalogPage,
      SelectDailyChoiceAction() => DailyChoiceActionPickerPage,
      SelectDailyChoiceSource() => DailyChoiceSourcePickerPage,
      SelectRelationParticipant() => RelationParticipantPickerPage,
    };
