part of 'tag_catalog_search_page_test.dart';

final _addToDraft = find.byKey(const ValueKey('tag-catalog-add-to-draft'));

/// Поиск общего выбора для сессии черновика принадлежит одному открытию:
/// переходы в редактор, отказы чтения и изменения набора его сохраняют,
/// а новое открытие начинает заново.
void _registerDraftSearchScenarios() {
  testWidgets(
    'черновик: корректный и некорректный поиск применяет последний корректный фильтр и полный case folding, не меняя набор',
    (tester) async {
      final (host, repository) = await _pumpDraftHost(tester);
      final draft = host.tagSet;
      await host.openChooser(tester, draft);
      final l10n = _draftLocalizations(tester);
      final tags = [
        _tag(1, 'Работа'),
        _tag(2, 'Дом'),
        _tag(3, 'Для дома'),
        _tag(4, 'Straße'),
      ];
      repository.complete(tags);
      await tester.pumpAndSettle();
      await tester.tap(_row(tags[1]));
      await tester.pump();
      await tester.tap(_addToDraft);
      await tester.pump();
      final included = draft.current.tagIds;
      expect(included, [tags[1].id]);

      await tester.enterText(_search, 'ДОМ');
      await tester.pump();
      expect(_visibleNames(tester), ['Дом', 'Для дома']);
      expect(_draftStatus(tags[1], l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _draftStatus(tags[2], l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );

      await tester.enterText(_search, 'STRASS');
      await tester.pump();
      expect(_visibleNames(tester), ['Straße']);

      for (final input in ['спорт\u0000', '\ud800', '\udc00']) {
        await tester.enterText(_search, input);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.text, input);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(_visibleNames(tester), ['Straße']);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(draft.current.tagIds, same(included));
      }

      await tester.enterText(_search, 'спорт');
      await tester.pump();
      expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('tag-catalog-create')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(_search, '\u0000');
      await tester.pump();
      expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
      expect(_visibleNames(tester), isEmpty);

      await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
      await tester.pump();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(_visibleNames(tester), tags.map((tag) => tag.name.value));
      expect(_draftStatus(tags[1], l10n.tagCatalogInDraft), findsOneWidget);
      expect(draft.current.tagIds, same(included));
      expect(repository.reads, hasLength(1));
      expect(repository.commands, isEmpty);
      expect(repository.statusQueries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ru', 'en']) {
    testWidgets(
      'черновик: пустой каталог и отсутствие совпадений различаются на $language',
      (tester) async {
        final (host, repository) = await _pumpDraftHost(
          tester,
          language: language,
        );
        await host.openChooser(tester, host.tagSet);
        final l10n = _draftLocalizations(tester);
        repository.complete([]);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
        expect(find.text(l10n.tagCatalogSearch), findsOneWidget);
        expect(tester.widget<FilledButton>(_addToDraft).onPressed, isNull);

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
        expect(find.text(l10n.tagCatalogEmpty), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('tag-catalog-create')),
              )
              .onPressed,
          isNotNull,
        );

        await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
        await tester.pump();
        expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(host.tagSet.current.tagIds, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'черновик: отказ первоначального чтения и обновления с повтором сохраняет сырой ввод, применённый фильтр и набор',
    (tester) async {
      final (host, repository) = await _pumpDraftHost(tester);
      final draft = host.tagSet;
      await host.openChooser(tester, draft);
      final l10n = _draftLocalizations(tester);
      await tester.enterText(_search, 'спорт');
      await tester.pump();
      expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
      expect(find.text(l10n.tagCatalogNoMatches), findsNothing);

      repository.reads.last.complete(
        const TagCatalogError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
      expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
      expect(tester.widget<TextField>(_search).controller!.text, 'спорт');

      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
      final work = _tag(1, 'Работа');
      final home = _tag(2, 'Дом');
      final forHome = _tag(3, 'Для дома');
      repository.complete([work, home, forHome]);
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      expect(tester.widget<TextField>(_search).controller!.text, 'спорт');

      await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
      await tester.pump();
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(_addToDraft);
      await tester.pump();
      final included = draft.current.tagIds;
      expect(included, [home.id]);
      await tester.enterText(_search, 'дом');
      await tester.pump();
      const invalid = 'работ\udc00';
      await tester.enterText(_search, invalid);
      await tester.pump();

      await _beginDraftRefresh(tester, host, repository);
      expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
      repository.reads.last.complete(
        const TagCatalogError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
      expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
      expect(tester.widget<TextField>(_search).controller!.text, invalid);
      expect(_visibleNames(tester), ['Дом', 'Для дома']);
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(of: _list, matching: find.byType(ListTile)),
      )) {
        expect(tile.onTap, isNull);
      }
      expect(tester.widget<FilledButton>(_addToDraft).onPressed, isNull);
      expect(draft.current.tagIds, same(included));

      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
      repository.complete([_tag(1, 'Рабочее'), home, forHome], revision: 2);
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagCatalogUnavailable), findsNothing);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
      expect(tester.widget<TextField>(_search).controller!.text, invalid);
      expect(_visibleNames(tester), ['Дом', 'Для дома']);
      expect(_draftStatus(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _draftStatus(forHome, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      await tester.enterText(_search, 'раб');
      await tester.pump();
      expect(_visibleNames(tester), ['Рабочее']);
      expect(draft.current.tagIds, same(included));
      expect(repository.commands.single, isA<RenameTag>());
      expect(repository.statusQueries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'черновик: одновременные открытия одной и разных сессий не разделяют поиск и кандидата, а новое открытие начинает заново',
    (tester) async {
      final (host, repository) = await _pumpDraftHost(tester);
      final first = host.tagSet;
      final tags = [_tag(1, 'Дом'), _tag(2, 'Работа'), _tag(3, 'Спорт')];
      final [home, work, sport] = tags;
      await host.openChooser(tester, first);
      final l10n = _draftLocalizations(tester);
      repository.complete(tags);
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'работ');
      await tester.pump();
      await tester.tap(_row(work));
      await tester.pump();
      final firstInput = tester.widget<TextField>(_search).controller!;

      // Второе открытие той же сессии получает собственные поиск и кандидата.
      await host.openChooser(tester, first);
      repository.complete(tags);
      await tester.pumpAndSettle();
      final secondInput = tester.widget<TextField>(_search).controller!;
      expect(secondInput, isNot(same(firstInput)));
      expect(secondInput.text, isEmpty);
      expect(_visibleNames(tester), ['Дом', 'Работа', 'Спорт']);
      expect(_draftSelected(tester, work), isFalse);
      await tester.enterText(_search, 'дом');
      await tester.pump();
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(_addToDraft);
      await tester.pump();
      expect(first.current.tagIds, [home.id]);
      expect(firstInput.text, 'работ');

      await host.closeChooser(tester);
      expect(tester.widget<TextField>(_search).controller, same(firstInput));
      expect(firstInput.text, 'работ');
      expect(_visibleNames(tester), ['Работа']);
      expect(_draftSelected(tester, work), isTrue);
      await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
      await tester.pump();
      expect(_draftStatus(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _draftStatus(work, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(_draftSelected(tester, work), isTrue);
      await tester.enterText(_search, 'работ');
      await tester.pump();

      // Открытие другой сессии не видит набор и поиск первой.
      final second = host.openSession();
      await host.openChooser(tester, second);
      repository.complete(tags);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(
        _draftStatus(home, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      await tester.tap(_row(sport));
      await tester.pump();
      await tester.tap(_addToDraft);
      await tester.pump();
      expect(second.current.tagIds, [sport.id]);
      expect(first.current.tagIds, [home.id]);

      await host.closeChooser(tester);
      expect(tester.widget<TextField>(_search).controller, same(firstInput));
      expect(firstInput.text, 'работ');
      expect(_draftSelected(tester, work), isTrue);

      // Закрытие и новое открытие сбрасывают поиск и кандидата, но не набор.
      await host.closeChooser(tester);
      await host.openChooser(tester, first);
      repository.complete(tags);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(_visibleNames(tester), ['Дом', 'Работа', 'Спорт']);
      expect(_draftSelected(tester, work), isFalse);
      expect(_draftStatus(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _draftStatus(sport, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(first.current.tagIds, [home.id]);
      expect(second.current.tagIds, [sport.id]);
      expect(repository.reads, hasLength(4));
      expect(repository.readModes.toSet(), {const TagCatalogBrowseMode()});
      expect(repository.commands, isEmpty);
      expect(repository.statusQueries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'черновик: возврат из настоящего редактора после отмены и сохранения сохраняет поиск, а новый тег сохраняется самостоятельно и становится кандидатом без включения в набор',
    (tester) async {
      final (host, raw) = await _pumpStoredDraftHost(tester);
      final draft = host.tagSet;
      await host.openChooser(tester, draft);
      await _pumpUntil(tester, () => _visibleNames(tester).contains('Работа'));
      final l10n = _draftLocalizations(tester);
      final home = _tag(firstTagNumber, 'Дом 🏷️');
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(_addToDraft);
      await tester.pump();
      final included = draft.current.tagIds;
      expect(included, [home.id]);
      int count(String table) =>
          raw.select('SELECT COUNT(*) AS n FROM $table').single['n'] as int;
      final tagCount = count('tags');
      final assignmentCount = count('tag_assignments');
      final intentionCount = count('intentions');

      await tester.enterText(_search, 'дом');
      await tester.pump();
      const invalid = 'спорт\u0000';
      await tester.enterText(_search, invalid);
      await tester.pump();
      final editingValue = tester.widget<TextField>(_search).controller!.value;
      const matches = ['Дом 🏷️', 'Дом без назначений', 'Дом в архиве'];
      expect(_visibleNames(tester), matches);

      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pumpAndSettle();
      expect(host.router.current.name, TagEditorRoute.name);
      await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
      await tester.pumpAndSettle();
      expect(host.router.current.name, _draftChooserRoute);
      expect(tester.widget<TextField>(_search).controller!.value, editingValue);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
      expect(_visibleNames(tester), matches);
      expect(_draftSelected(tester, home), isTrue);
      expect(draft.current.tagIds, same(included));
      expect(count('tags'), tagCount);

      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Домашнее',
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      await _pumpUntil(
        tester,
        () =>
            host.router.current.name == _draftChooserRoute &&
            find.text(l10n.tagCatalogRefreshing).evaluate().isEmpty &&
            _visibleNames(tester).contains('Домашнее'),
      );
      await tester.pumpAndSettle();
      final createdRows = raw.select('SELECT id FROM tags WHERE name = ?', [
        'Домашнее',
      ]);
      final created = Tag(
        id: (TagId.decode(
          createdRows.single['id'] as String,
        ) as TagIdDecodingSuccess).id,
        name: TagName.fromInput('Домашнее'),
      );
      expect(tester.widget<TextField>(_search).controller!.value, editingValue);
      expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
      expect(_visibleNames(tester), [...matches, 'Домашнее']);
      expect(_draftSelected(tester, created), isTrue);
      expect(
        _draftStatus(created, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(draft.current.tagIds, same(included));
      expect(count('tags'), tagCount + 1);
      expect(count('tag_assignments'), assignmentCount);
      expect(count('intentions'), intentionCount);

      await tester.tap(_addToDraft);
      await tester.pump();
      expect(draft.current.tagIds, [home.id, created.id]);
      expect(_draftStatus(created, l10n.tagCatalogInDraft), findsOneWidget);
      expect(tester.widget<TextField>(_search).controller!.value, editingValue);
      expect(count('tag_assignments'), assignmentCount);
      expect(count('intentions'), intentionCount);
      expect(tester.takeException(), isNull);
    },
  );
}

const _draftChooserRoute = 'DraftTagChooserRoute';

AppLocalizations _draftLocalizations(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TagCatalogView)));

Finder _draftStatus(Tag tag, String status) =>
    find.descendant(of: _row(tag), matching: find.text(status));

bool _draftSelected(WidgetTester tester, Tag tag) =>
    tester.widget<Semantics>(_row(tag)).properties.selected ?? false;

Future<void> _beginDraftRefresh(
  WidgetTester tester,
  _DraftSearchHost host,
  TagCatalogTestRepository repository,
) async {
  final before = _tag(1, 'Работа');
  final after = _tag(1, 'Рабочее');
  final accepted = host.coordinator.acceptTagRename(
    RenameTag(tagId: before.id, name: after.name),
  ) as TagCommandAccepted;
  repository.command.complete(
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: const TagCatalogTestRevision(2),
        value: TagRenamed(
          TagRenamedChange(
            revision: const TagCatalogTestRevision(2),
            before: before,
            after: after,
          ),
        ),
      ),
    ),
  );
  await accepted.future;
  await tester.pump();
}

Future<(_DraftSearchHost, TagCatalogTestRepository)> _pumpDraftHost(
  WidgetTester tester, {
  String language = 'ru',
}) async {
  final repository = TagCatalogTestRepository();
  final host = _DraftSearchHost(repository);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    host.dispose();
    await repository.dispose();
  });
  await host.pump(tester, language: language);
  return (host, repository);
}

Future<(_DraftSearchHost, sqlite.Database)> _pumpStoredDraftHost(
  WidgetTester tester,
) async {
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  seedTagNavigationFixture(raw, extraPairsPerScope: 0);
  for (final (number, name) in [
    (303, 'Дом без назначений'),
    (304, 'Дом в архиве'),
  ]) {
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [name, _id(number)]);
  }
  final host = _DraftSearchHost(
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    host.dispose();
    await database.close();
  });
  await host.pump(tester);
  return (host, raw);
}

/// Сессии черновика и общий выбор в собственном маршрутном стеке с
/// настоящим редактором тегов. Каждое открытие выбора связано с сессией,
/// переданной при открытии.
final class _DraftSearchHost {
  _DraftSearchHost(PersonalGraphRepository repository)
    : container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      ) {
    tagSet = openSession();
    router = _DraftSearchRouter();
  }

  final ProviderContainer container;
  final _sessions = <ProviderSubscription<IntentionEditorState>>[];
  late final IntentionDraftTagSet tagSet;
  late final _DraftSearchRouter router;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Начинает новую сессию черновика и возвращает контракт её набора.
  IntentionDraftTagSet openSession() {
    final session = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    _sessions.add(container.listen(session, (_, _) {}));
    return container.read(session.notifier).draftTagSet;
  }

  Future<void> pump(WidgetTester tester, {String language = 'ru'}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openChooser(
    WidgetTester tester,
    IntentionDraftTagSet session,
  ) async {
    unawaited(router.push<void>(NamedRoute(_draftChooserRoute, args: session)));
    // Маршрут добавляется после асинхронной навигации, а индикатор загрузки
    // каталога анимируется, поэтому переход завершается явным ожиданием
    // вместо pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> closeChooser(WidgetTester tester) async {
    await router.maybePop();
    await tester.pumpAndSettle();
  }

  void dispose() {
    router.dispose();
    for (final session in _sessions) {
      session.close();
    }
    container.dispose();
  }
}

/// Исходная страница и выбор для черновика; «+» открывает настоящий
/// маршрут редактора тега поверх выбора.
final class _DraftSearchRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'DraftPanelRoute',
      path: '/',
      builder: (_, _) => const Scaffold(),
    ),
    NamedRouteDef(
      name: _draftChooserRoute,
      path: '/draft-tags',
      builder: (context, data) => TagCatalogView(
        selectionContext: TagDraftContext(data.argsAs<IntentionDraftTagSet>()),
        onOpenEditor: (editorContext) => context.router.push<Tag>(
          TagEditorRoute(editorContext: editorContext),
        ),
        onOpenNavigation: (_) {},
      ),
    ),
    AutoRoute(page: TagEditorRoute.page),
  ];
}
