part of 'app_shell_pages_above_test.dart';

/// Ожидания следуют требованию «Панель на обычных страницах» независимо
/// от каркаса, которым реализована страница. Каждая строка запускает тест.
typedef _PageCase = ({
  String name,
  String route,
  Type page,
  bool panel,
  List<_MatrixEntry> entries,
});

enum _MatrixEntry {
  intention,
  dailyChoice,
  tags,
  creation,
  condition,
  action,
  actionCandidate,
  relation,
  tag,
  renameTag,
  assignTags,
  draftTags,
  createTag,
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
    _MatrixEntry.intention => find.byType(HomeIntentionRow),
    _MatrixEntry.dailyChoice => find.byKey(
      const ValueKey('daily-choice-row-1'),
    ),
    _MatrixEntry.tags => _openTags,
    _MatrixEntry.creation => find.byKey(
      const ValueKey('catalog-create-intention'),
    ),
    _MatrixEntry.condition => find.byKey(
      const ValueKey('intention-tag-conditions-add'),
    ),
    _MatrixEntry.action => find.byKey(
      const ValueKey('daily-choice-create-from-action'),
    ),
    _MatrixEntry.actionCandidate => _summary(
      DailyChoiceActionPickerPage,
      'Бегать',
    ),
    _MatrixEntry.relation => _relationRow,
    _MatrixEntry.tag => find.byKey(
      ValueKey('tag-catalog-open-${tagFixtureId(_tag)}'),
    ),
    _MatrixEntry.renameTag => find.byTooltip('Rename tag'),
    _MatrixEntry.assignTags => find.byKey(
      const ValueKey('tag-assignments-choose'),
    ),
    _MatrixEntry.draftTags => find.byKey(
      const ValueKey('intention-editor-choose-tags'),
    ),
    _MatrixEntry.createTag => find.byKey(const ValueKey('tag-catalog-create')),
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
  const read = _MatrixEntry.intention;
  const daily = _MatrixEntry.dailyChoice;
  const tags = _MatrixEntry.tags;
  const cases = <_PageCase>[
    (
      name: 'намерение',
      route: IntentionDetailsRoute.name,
      page: IntentionDetailsPage,
      panel: true,
      entries: [read],
    ),
    (
      name: 'долговременная связь',
      route: RelationDetailsRoute.name,
      page: RelationDetailsPage,
      panel: true,
      entries: [read, _MatrixEntry.relation],
    ),
    (
      name: 'дневной выбор',
      route: DailyChoiceDetailsRoute.name,
      page: DailyChoiceDetailsPage,
      panel: true,
      entries: [daily],
    ),
    (
      name: 'навигация по тегу',
      route: TagNavigationRoute.name,
      page: TagNavigationPage,
      panel: true,
      entries: [tags, _MatrixEntry.tag],
    ),
    (
      name: 'просмотр тегов',
      route: TagCatalogRoute.name,
      page: TagCatalogPage,
      panel: true,
      entries: [tags],
    ),
    (
      name: 'назначение тегов',
      route: TagCatalogRoute.name,
      page: TagCatalogPage,
      panel: false,
      entries: [read, _MatrixEntry.assignTags],
    ),
    (
      name: 'теги черновика',
      route: TagCatalogRoute.name,
      page: TagCatalogPage,
      panel: false,
      entries: [_MatrixEntry.creation, _MatrixEntry.draftTags],
    ),
    (
      name: 'создание тега',
      route: TagEditorRoute.name,
      page: TagEditorPage,
      panel: false,
      entries: [tags, _MatrixEntry.createTag],
    ),
    (
      name: 'изменение тега',
      route: TagEditorRoute.name,
      page: TagEditorPage,
      panel: false,
      entries: [tags, _MatrixEntry.renameTag],
    ),
    (
      name: 'условие по тегу',
      route: TagConditionPickerRoute.name,
      page: TagConditionPickerPage,
      panel: false,
      entries: [_MatrixEntry.condition],
    ),
    (
      name: 'поиск действия',
      route: DailyChoiceActionPickerRoute.name,
      page: DailyChoiceActionPickerPage,
      panel: false,
      entries: [_MatrixEntry.action],
    ),
    (
      name: 'поиск основания',
      route: DailyChoiceSourcePickerRoute.name,
      page: DailyChoiceSourcePickerPage,
      panel: false,
      entries: [daily, _MatrixEntry.replaceChoice, _MatrixEntry.replaceTopDown],
    ),
    (
      name: 'создание намерения',
      route: IntentionEditorRoute.name,
      page: IntentionEditorPage,
      panel: false,
      entries: [_MatrixEntry.creation],
    ),
    (
      name: 'путь от намерения',
      route: ChoicePathRoute.name,
      page: ChoicePathPage,
      panel: false,
      entries: [read, _MatrixEntry.choosePath],
    ),
    (
      name: 'подтверждение дневного выбора сверху вниз',
      route: DailyChoiceCreationRoute.name,
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
      route: DailyChoiceCreationRoute.name,
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
      route: DailyChoiceEditRoute.name,
      page: DailyChoiceEditPage,
      panel: false,
      entries: [daily, _MatrixEntry.editChoice],
    ),
    (
      name: 'создание исходящей связи',
      route: RelationEditorRoute.name,
      page: RelationEditorPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation],
    ),
    (
      name: 'создание входящей связи',
      route: RelationEditorRoute.name,
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
      route: RelationEditorRoute.name,
      page: RelationEditorPage,
      panel: false,
      entries: [read, _MatrixEntry.relation, _MatrixEntry.editRelation],
    ),
    (
      name: 'поиск исходного участника',
      route: RelationParticipantPickerRoute.name,
      page: RelationParticipantPickerPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation, _MatrixEntry.changeSource],
    ),
    (
      name: 'поиск связанного участника',
      route: RelationParticipantPickerRoute.name,
      page: RelationParticipantPickerPage,
      panel: false,
      entries: [read, _MatrixEntry.createRelation, _MatrixEntry.selectRelated],
    ),
  ];

  test('матрица проверяет каждый зарегистрированный маршрут приложения', () {
    final router = AppRouter();
    addTearDown(router.dispose);
    Iterable<String> names(List<AutoRoute> routes) sync* {
      for (final route in routes) {
        yield route.name;
        yield* names(route.children ?? const []);
      }
    }

    expect(names(router.routes).toSet(), {
      AppShellRoute.name,
      for (final destination in _rootPages.keys) destination.page.name,
      for (final row in cases) row.route,
    });
    expect(_rootPages.keys, unorderedEquals(AppDestination.values));
  });

  for (final row in cases) {
    testWidgets('матрица: ${row.name}', (tester) async {
      final router = await _start(tester);
      var destination = AppDestination.home;
      for (final entry in row.entries) {
        final root = switch (entry) {
          _MatrixEntry.tags ||
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
        await _tap(tester, entry.finder);
        await tester.pumpAndSettle();
      }
      await _until(tester, find.byType(row.page));
      await tester.pumpAndSettle();
      expect(router.current.name, row.route);
      final variant = switch (tester.widget(find.byType(row.page))) {
        TagCatalogPage(:final selectionContext) => switch (selectionContext) {
          TagBrowseContext() => 'просмотр тегов',
          TagAssignmentContext() => 'назначение тегов',
          TagDraftContext() => 'теги черновика',
        },
        TagEditorPage(:final editorContext) => switch (editorContext) {
          TagEditorCreating() => 'создание тега',
          TagEditorRenaming() => 'изменение тега',
        },
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
        _expectCreationSheetAboveCatalog(tester, router);
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

  for (final context in RelationParticipantSelectionContext.values) {
    final name = switch (context) {
      RelationParticipantSelectionContext.activeRelation => 'активной связи',
      RelationParticipantSelectionContext.archivedRelation => 'архивной связи',
    };
    testWidgets('поиск участника $name без панели', (tester) async {
      final router = await _start(tester);
      unawaited(
        router.push(
          RelationParticipantPickerRoute(
            excludedIntentionId: _intentionId(_read),
            selectionContext: context,
          ),
        ),
      );
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
            .selectionContext,
        context,
      );
      await _close(tester, RelationParticipantPickerPage);
      _expectRootPage(tester, router, AppDestination.home);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Новый вариант назначения требует явно указать проверяемую страницу.
Type _pageForCatalogPurpose(IntentionCatalogPurpose purpose) =>
    switch (purpose) {
      BrowseIntentionCatalog() => IntentionCatalogPage,
      SelectDailyChoiceAction() => DailyChoiceActionPickerPage,
      SelectDailyChoiceSource() => DailyChoiceSourcePickerPage,
      SelectRelationParticipant() => RelationParticipantPickerPage,
    };
