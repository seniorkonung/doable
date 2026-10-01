part of 'tag_navigation_page_test.dart';

void _registerLatePageWidgetScenarios() {
  for (final locale in ['ru', 'en']) {
    for (final loaded in [false, true]) {
      for (final lateSuccess in [false, true]) {
        for (final (name, failure) in const [
          ('недоступность', TagReadUnavailableFailure()),
          ('повреждение', TagReadCorruptionFailure()),
          ('неизвестная причина', TagReadUnexpectedFailure()),
        ]) {
          testWidgets(
            '$name открытого наблюдения сохраняется после позднего ${lateSuccess ? 'успеха' : 'отказа'} ${loaded ? 'подгрузки' : 'первой порции'} на $locale',
            (tester) async {
              final semantics = tester.ensureSemantics();
              try {
                final reads = _Reads();
                addTearDown(reads.dispose);
                await _pumpPage(tester, reads, locale: locale);
                final context = tester.element(find.byType(TagNavigationPage));
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final provider = tagNavigationViewModelProvider(_tag.id);
                final model = container.read(provider.notifier);
                final l10n = AppLocalizations.of(context);
                final item = _intention(1);
                final lateItem = _intention(2);
                if (loaded) {
                  reads.page(0, [item], cursor: _Cursor());
                  await tester.pumpAndSettle();
                  await tester.tap(find.text(l10n.tagNavigationLoadMore));
                  await tester.pump();
                }
                final pendingIndex = loaded ? 1 : 0;
                expect(reads.pending[pendingIndex].isCompleted, isFalse);
                reads.watch.add(TagReadError(failure));
                await tester.pump();
                expect(reads.watch.isClosed, isFalse);
                if (lateSuccess) {
                  reads.page(pendingIndex, [lateItem]);
                } else {
                  reads.fail(
                    pendingIndex,
                    const TaggedIntentionsUnavailableFailure(),
                  );
                }
                await tester.runAsync(() => pumpEventQueue());
                await tester.pumpAndSettle();

                final message = switch (failure) {
                  TagReadUnavailableFailure() =>
                    loaded
                        ? l10n.tagNavigationRefreshUnavailable
                        : l10n.tagNavigationUnavailable,
                  TagReadCorruptionFailure() =>
                    loaded
                        ? l10n.tagNavigationRefreshCorruption
                        : l10n.tagNavigationCorruption,
                  TagReadUnexpectedFailure() =>
                    loaded
                        ? l10n.tagNavigationRefreshUnexpected
                        : l10n.tagNavigationUnexpected,
                };
                expect(find.text(message), findsOneWidget);
                expect(reads.queries, hasLength(pendingIndex + 1));
                expect(_row(lateItem), findsNothing);
                expect(find.text(l10n.tagNavigationLoadMore), findsNothing);
                expect(
                  find.text(l10n.tagNavigationLoadMoreUnavailable),
                  findsNothing,
                );
                expect(find.text(l10n.tagNavigationEmptyActive), findsNothing);
                expect(model.canActOn(item.id), isFalse);
                if (loaded) {
                  final stale = container.read(provider) as TagNavigationLoaded;
                  expect(stale.items, [item]);
                  expect(stale.freshness, TagNavigationFreshness.stale);
                  expect(stale.nextCursor, isNull);
                  expect(
                    tester
                        .widget<ListTile>(
                          find.descendant(
                            of: _row(item),
                            matching: find.byType(ListTile),
                          ),
                        )
                        .onTap,
                    isNull,
                  );
                  expect(
                    tester
                        .getSemantics(_row(item))
                        .getSemanticsData()
                        .hasAction(SemanticsAction.tap),
                    isFalse,
                  );
                } else {
                  expect(
                    container.read(provider),
                    isA<TagNavigationInitialFailure>(),
                  );
                  expect(find.byType(ListTile), findsNothing);
                }

                final retry = find.widgetWithText(
                  OutlinedButton,
                  l10n.commonRetry,
                );
                if (failure is TagReadUnavailableFailure) {
                  expect(retry, findsOneWidget);
                  final count = reads.queries.length;
                  // Успех прежней открытой подписки сам по себе не восстанавливает экран.
                  reads.watch.add(
                    TagReadSuccess(
                      GraphSnapshot(value: _tag, revision: const _Revision(1)),
                    ),
                  );
                  await tester.pumpAndSettle();
                  expect(find.text(message), findsOneWidget);
                  expect(model.canActOn(item.id), isFalse);
                  expect(reads.queries, hasLength(count));
                  await tester.tap(retry);
                  await tester.pump();
                  expect(reads.queries, hasLength(count + 1));
                  expect(reads.queries.last.tagId, _tag.id);
                  expect(
                    reads.queries.last.scope,
                    TaggedIntentionsScope.active,
                  );
                  expect(reads.queries.last.cursor, isNull);
                  reads.page(count, [item]);
                  await tester.pump();
                  expect(model.canActOn(item.id), isFalse);
                  reads.watch.add(
                    TagReadSuccess(
                      GraphSnapshot(value: _tag, revision: const _Revision(1)),
                    ),
                  );
                  await tester.pumpAndSettle();
                  final restored =
                      container.read(provider) as TagNavigationLoaded;
                  expect(restored.items, [item]);
                  expect(model.canActOn(item.id), isTrue);
                  expect(_row(lateItem), findsNothing);
                  expect(find.text(message), findsNothing);
                  expect(find.text(l10n.commonRetry), findsNothing);
                  expect(
                    tester
                        .getSemantics(_row(item))
                        .getSemanticsData()
                        .hasAction(SemanticsAction.tap),
                    isTrue,
                  );
                } else {
                  expect(retry, findsNothing);
                }
                expect(reads.watch.isClosed, isFalse);
                expect(tester.takeException(), isNull);
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }
}
