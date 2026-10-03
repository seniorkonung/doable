part of 'tag_accessibility_test.dart';

final _searchModes = <(String, IntentionId?)>[
  ('каталог', null),
  (
    'выбор для намерения',
    (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id,
  ),
  (
    'выбор для архивированного действия',
    (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id,
  ),
];

void _registerCatalogSearchScenarios() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'отсутствие намерения доступно диктору с клавиатурой при тексте 2.5: ${locale.languageCode}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final language = ValueNotifier(locale);
        addTearDown(language.dispose);
        try {
          final l10n = await AppLocalizations.delegate.load(locale);
          final message = find.text(l10n.tagAssignmentIntentionNotFound);
          await _showAccessibleSearch(
            tester,
            (IntentionId.decode(
              tagFixtureId(999),
            ) as IntentionIdDecodingSuccess).id,
            language,
            readyMarker: message,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          final text = tester.widget<Text>(message).data!;
          expect(
            text,
            contains(locale.languageCode == 'ru' ? 'намерения' : 'intention'),
          );
          expect(
            text,
            isNot(
              contains(
                locale.languageCode == 'ru' ? 'получателя' : 'recipient',
              ),
            ),
          );
          await tester.ensureVisible(message);
          expect(tester.getSemantics(message).label, contains(text));
          expect(
            tester.getSemantics(message).flagsCollection.isLiveRegion,
            isTrue,
          );
          expect(
            tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
            isFalse,
          );
          expect(
            find.byKey(const ValueKey('tag-catalog-assign')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    for (final (description, target) in _searchModes) {
      testWidgets(
        'ошибка поиска полностью читается с клавиатурой при тексте 2.5: $description, ${locale.languageCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final language = ValueNotifier(locale);
          addTearDown(language.dispose);
          try {
            await _showAccessibleSearch(tester, target, language);
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            final search = find.byKey(const ValueKey('tag-catalog-search'));
            await tester.enterText(search, '\u0000');
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            var l10n = await AppLocalizations.delegate.load(locale);
            final error = find.text(l10n.tagCatalogInvalidSearch);
            expect(
              tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
              isFalse,
              reason:
                  'Объяснение неприменённого ввода должно читаться полностью',
            );
            expect(
              tester.getSemantics(error).label,
              contains(l10n.tagCatalogInvalidSearch),
            );
            expect(
              tester.getSemantics(error).flagsCollection.isLiveRegion,
              isTrue,
            );
            final explanation = find.ancestor(
              of: error,
              matching: find.byType(CustomScrollView),
            );
            await Scrollable.ensureVisible(tester.element(error), alignment: 1);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(error).bottom,
              lessThanOrEqualTo(tester.getRect(explanation).bottom + 1),
            );
            expect(
              tester
                  .state<EditableTextState>(find.byType(EditableText))
                  .widget
                  .focusNode
                  .hasFocus,
              isTrue,
            );
            language.value = Locale(locale.languageCode == 'ru' ? 'en' : 'ru');
            await tester.pumpAndSettle();
            l10n = await AppLocalizations.delegate.load(language.value);
            expect(tester.widget<TextField>(search).controller!.text, '\u0000');
            expect(
              tester
                  .getSemantics(find.text(l10n.tagCatalogInvalidSearch))
                  .label,
              contains(l10n.tagCatalogInvalidSearch),
            );
            final clear = find.byTooltip(l10n.tagCatalogClearSearch);
            await tester.ensureVisible(clear);
            await tester.pumpAndSettle();
            expect(clear.hitTestable(), findsOneWidget);
            _expectAction(tester.getSemantics(clear));
            await tester.tap(clear);
            await tester.pumpAndSettle();
            expect(error, findsNothing);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
            expect(tester.widget<TextField>(search).controller!.text, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'поиск и скрытый выбор доступны при тексте 2.5 и смене языка: $description, ${locale.languageCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final language = ValueNotifier(locale);
          addTearDown(language.dispose);
          final tagName = 'Straße 🏷️ é ${'Длинное название ' * 7}'
              .trimRight();
          try {
            await _showAccessibleSearch(
              tester,
              target,
              language,
              tagName: tagName,
            );
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            var l10n = await AppLocalizations.delegate.load(locale);
            final search = find.byKey(const ValueKey('tag-catalog-search'));
            final create = find.byKey(const ValueKey('tag-catalog-create'));
            await tester.enterText(search, 'STRASS');
            await tester.pumpAndSettle();
            final input = tester.state<EditableTextState>(
              find.byType(EditableText),
            );
            expect(
              tester.getSemantics(find.byType(EditableText)).label,
              contains(l10n.tagCatalogSearch),
            );
            expect(
              tester
                  .getSemantics(find.byType(EditableText))
                  .flagsCollection
                  .isTextField,
              isTrue,
            );
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(tagName))
                  .didExceedMaxLines,
              isFalse,
            );
            if (target != null) {
              await _tap(tester, find.text(l10n.tagCatalogAvailable));
              await tester.ensureVisible(
                find.byKey(
                  const ValueKey('tag-catalog-search'),
                  skipOffstage: false,
                ),
              );
              await tester.pumpAndSettle();
            }
            await tester.enterText(search, 'спорт');
            await tester.pumpAndSettle();
            expect(
              tester.getSemantics(find.text(l10n.tagCatalogNoMatches)).label,
              contains(l10n.tagCatalogNoMatches),
            );
            expect(
              tester
                  .getSemantics(find.text(l10n.tagCatalogNoMatches))
                  .flagsCollection
                  .isLiveRegion,
              isTrue,
            );
            expect(
              tester.state<EditableTextState>(find.byType(EditableText)),
              same(input),
            );
            expect(input.widget.focusNode.hasFocus, isTrue);
            _expectAction(tester.getSemantics(create));
            expect(tester.getSemantics(create).tooltip, l10n.tagCatalogCreate);
            final hidden = find.byKey(
              const ValueKey('tag-catalog-hidden-selection'),
            );
            final assign = find.byKey(const ValueKey('tag-catalog-assign'));
            if (target != null) {
              _expectHiddenSelection(
                tester,
                hidden,
                l10n,
                tagName,
                assigned: false,
              );
              _expectAction(tester.getSemantics(assign));
              expect(
                tester.getSemantics(assign).label,
                contains(l10n.tagCatalogAssignNamed(tagName)),
              );
              await tester.ensureVisible(
                find.descendant(
                  of: hidden,
                  matching: find.text(l10n.tagCatalogAvailable),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                find.text(l10n.tagCatalogAvailable).hitTestable(),
                findsOneWidget,
              );
              expect(assign.hitTestable(), findsOneWidget);
            }
            language.value = Locale(locale.languageCode == 'ru' ? 'en' : 'ru');
            await tester.pumpAndSettle();
            l10n = await AppLocalizations.delegate.load(language.value);
            expect(tester.widget<TextField>(search).controller!.text, 'спорт');
            expect(
              tester.getSemantics(find.byType(EditableText)).label,
              contains(l10n.tagCatalogSearch),
            );
            expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
            if (target != null) {
              _expectHiddenSelection(
                tester,
                hidden,
                l10n,
                tagName,
                assigned: false,
              );
              await _tap(tester, assign);
              await _until(
                tester,
                find.descendant(
                  of: hidden,
                  matching: find.text(l10n.tagCatalogAssigned),
                ),
              );
              await tester.pumpAndSettle();
              _expectHiddenSelection(
                tester,
                hidden,
                l10n,
                tagName,
                assigned: true,
              );
              expect(
                tester
                    .getSemantics(assign)
                    .getSemanticsData()
                    .hasAction(SemanticsAction.tap),
                isFalse,
              );
            }
            await tester.showKeyboard(search);
            final clear = find.byTooltip(l10n.tagCatalogClearSearch);
            expect(clear.hitTestable(), findsOneWidget);
            _expectAction(tester.getSemantics(clear));
            await tester.tap(clear);
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(search).controller!.text, isEmpty);
            expect(input.widget.focusNode.hasFocus, isTrue);
            expect(find.text('Дом'), findsOneWidget);
            expect(find.text(tagName), findsOneWidget);
            if (target != null) {
              final row = find.byKey(
                ValueKey('tag-catalog-row-${tagFixtureId(lastTagNumber)}'),
              );
              await tester.ensureVisible(
                find.descendant(
                  of: row,
                  matching: find.text(l10n.tagCatalogAssigned),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.getSemantics(row).flagsCollection.isSelected,
                Tristate.isTrue,
              );
            }
            await tester.ensureVisible(
              find.byKey(
                const ValueKey('tag-catalog-search'),
                skipOffstage: false,
              ),
            );
            await tester.pumpAndSettle();
            await tester.enterText(search, 'спорт');
            await tester.pumpAndSettle();
            await _tap(tester, create);
            await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

void _expectHiddenSelection(
  WidgetTester tester,
  Finder hidden,
  AppLocalizations l10n,
  String tagName, {
  required bool assigned,
}) {
  final node = tester.getSemantics(hidden);
  expect(node.flagsCollection.isSelected, Tristate.isTrue);
  expect(node.flagsCollection.isLiveRegion, isTrue);
  expect(node.label, contains(l10n.tagCatalogSelected));
  expect(node.label, contains(tagName));
  expect(
    node.label,
    contains(assigned ? l10n.tagCatalogAssigned : l10n.tagCatalogAvailable),
  );
  expect(
    tester.renderObject<RenderParagraph>(find.text(tagName)).didExceedMaxLines,
    isFalse,
  );
}

Future<void> _showAccessibleSearch(
  WidgetTester tester,
  IntentionId? intentionId,
  ValueNotifier<Locale> language, {
  String? tagName,
  Finder? readyMarker,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (connection) => raw = connection),
  );
  await database.open();
  addTearDown(database.close);
  seedTagStorageFixture(raw);
  if (tagName != null) {
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
      tagName,
      tagFixtureId(lastTagNumber),
    ]);
  }
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 9, 28),
    InMemoryDiagnosticsSink(),
  );
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (context, locale, child) => MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.5),
              supportsAnnounce: true,
            ),
            child: child!,
          ),
          routerConfig: router.config(),
        ),
      ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await openIntentionGraph(tester, waitFor: _until);
  await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
  unawaited(router.push(TagCatalogRoute(intentionId: intentionId)));
  await _until(tester, readyMarker ?? find.text(tagName ?? 'Работа'));
  await tester.pumpAndSettle();
}
