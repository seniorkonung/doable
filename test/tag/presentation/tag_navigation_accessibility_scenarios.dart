part of 'tag_accessibility_test.dart';

enum _NavigationEntry { catalog, intention, relation }

void _registerNavigationEntryScenarios() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'все входы навигации имеют доступные подписи при увеличении текста на ${locale.languageCode}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2.5;
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          late sqlite.Database raw;
          final runtime = AppRuntime(
            connectionFactory: () =>
                openInMemoryLocalDatabase(setup: (database) => raw = database),
            diagnosticsSink: InMemoryDiagnosticsSink(),
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await runtime.shutdown();
          });
          final ready =
              (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
          seedTagNavigationFixture(raw, extraPairsPerScope: 0);
          final longTag = 'Straße 🏷️ é ${'Длинное название ' * 7}'
              .trimRight();
          raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
            longTag,
            tagFixtureId(firstTagNumber),
          ]);
          final before = retainedTagFixtureGraph(raw);
          final assignments = raw
              .select('SELECT * FROM tag_assignments')
              .map((row) => row.values.toList())
              .toList();
          final router = ready.container.read(appRouterProvider);
          final l10n = await AppLocalizations.delegate.load(locale);
          await tester.pumpWidget(MainApp(runtime: runtime));
          await _until(tester, find.text('Одинаковое намерение'));
          final tagId = (TagId.decode(
            tagFixtureId(firstTagNumber),
          ) as TagIdDecodingSuccess).id;
          for (final entry in _NavigationEntry.values) {
            final page = switch (entry) {
              _NavigationEntry.catalog => find.byKey(
                const ValueKey('tag-catalog-list'),
              ),
              _NavigationEntry.intention => find.byType(IntentionDetailsPage),
              _NavigationEntry.relation => find.byType(RelationDetailsPage),
            };
            if (entry == _NavigationEntry.catalog) {
              await _tap(
                tester,
                find.byKey(const ValueKey('catalog-open-tags')),
              );
            } else {
              unawaited(
                router.push(switch (entry) {
                  _NavigationEntry.intention => IntentionDetailsRoute(
                    intentionId: (IntentionId.decode(
                      tagFixtureId(2),
                    ) as IntentionIdDecodingSuccess).id,
                  ),
                  _NavigationEntry.relation => RelationDetailsRoute(
                    relationId: (LongTermRelationId.decode(
                      tagFixtureId(102),
                    ) as LongTermRelationIdDecodingSuccess).id,
                  ),
                  _NavigationEntry.catalog => throw StateError(
                    'Каталог открыт отдельным действием',
                  ),
                }),
              );
            }
            await _until(tester, page);
            final scrollable = find
                .descendant(of: page, matching: find.byType(Scrollable))
                .first;
            if (entry != _NavigationEntry.catalog) {
              await _until(
                tester,
                find.byKey(
                  ValueKey(
                    entry == _NavigationEntry.intention
                        ? 'intention-details-title'
                        : 'relation-details-phrase',
                  ),
                ),
              );
              await tester.scrollUntilVisible(
                find.descendant(
                  of: page,
                  matching: find.byKey(
                    const ValueKey('tag-assignments-choose'),
                  ),
                ),
                300,
                scrollable: scrollable,
              );
            }
            final open = find.descendant(
              of: page,
              matching: find.byKey(
                ValueKey(
                  '${entry == _NavigationEntry.catalog ? 'tag-catalog-open' : 'tag-assignment-open'}-${tagFixtureId(firstTagNumber)}',
                ),
              ),
            );
            await _until(tester, open);
            await tester.scrollUntilVisible(open, 300, scrollable: scrollable);
            await tester.pumpAndSettle();
            _expectAction(tester.getSemantics(open));
            expect(
              _semanticTooltips(tester),
              contains(
                entry == _NavigationEntry.catalog
                    ? l10n.tagNavigationTitle
                    : l10n.tagNavigationTag(longTag),
              ),
            );
            if (entry != _NavigationEntry.catalog) {
              final remove = find.byKey(
                ValueKey(
                  'tag-assignment-remove-${tagFixtureId(firstTagNumber)}',
                ),
              );
              await tester.ensureVisible(remove);
              await tester.pumpAndSettle();
              _expectAction(tester.getSemantics(remove));
              expect(
                _traversalIndex(tester, l10n.tagNavigationTitle),
                lessThan(_traversalIndex(tester, l10n.tagAssignmentsRemove)),
              );
            }
            await _tap(tester, open);
            await _until(tester, find.text(l10n.tagNavigationTag(longTag)));
            expect(
              router.current.argsAs<TagNavigationRouteArgs>().tagId,
              tagId,
            );
            final active = find.byKey(
              const ValueKey(TaggedEntitiesScope.active),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              active,
              300,
              scrollable: find
                  .descendant(
                    of: find.byType(TagNavigationPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            expect(
              tester.getSemantics(active).flagsCollection.isSelected,
              Tristate.isTrue,
            );
            _expectAction(tester.getSemantics(active));
            router.pop();
            await _until(tester, open);
            router.pop();
            await _until(
              tester,
              find.byKey(const ValueKey('catalog-open-tags')),
            );
            await tester.pumpAndSettle();
          }
          expect(retainedTagFixtureGraph(raw), before);
          expect(
            raw
                .select('SELECT * FROM tag_assignments')
                .map((row) => row.values.toList())
                .toList(),
            assignments,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
