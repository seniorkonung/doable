part of 'tag_navigation_page_test.dart';

void _registerTerminalNavigationScenarios() {
  for (final locale in ['ru', 'en']) {
    for (final loaded in [false, true]) {
      for (final (name, failure) in const [
        ('временная недоступность', TagReadUnavailableFailure()),
        ('повреждение', TagReadCorruptionFailure()),
        ('типизированная неизвестная причина', TagReadUnexpectedFailure()),
        ('необъяснённое окончание', null),
      ]) {
        testWidgets(
          '$name при окончании наблюдения ${loaded ? 'после загрузки' : 'до первой порции'} сохраняет допустимые действия на $locale',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final reads = _Reads();
              addTearDown(reads.dispose);
              await _pumpPage(tester, reads, locale: locale);
              final l10n = AppLocalizations.of(
                tester.element(find.byType(TagNavigationPage)),
              );
              final item = _intention(1);
              VoidCallback? oldOpen;
              if (loaded) {
                reads.page(0, [item], cursor: _Cursor());
                await tester.pumpAndSettle();
                oldOpen = tester
                    .widget<ListTile>(
                      find.descendant(
                        of: _row(item),
                        matching: find.byType(ListTile),
                      ),
                    )
                    .onTap;
              }

              if (failure != null) reads.watch.add(TagReadError(failure));
              await reads.watch.close();
              await tester.runAsync(() => pumpEventQueue());
              oldOpen?.call();
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
                TagReadUnexpectedFailure() || null =>
                  loaded
                      ? l10n.tagNavigationRefreshUnexpected
                      : l10n.tagNavigationUnexpected,
              };
              expect(find.text(message), findsOneWidget);
              expect(find.text(l10n.tagNavigationLoadMore), findsNothing);
              expect(find.text(l10n.tagNavigationEmptyActive), findsNothing);
              expect(find.text(l10n.tagNotFound), findsNothing);
              expect(reads.queries, hasLength(1));
              if (loaded) {
                expect(_row(item), findsOneWidget);
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
                expect(find.byType(ListTile), findsNothing);
              }
              final retry = find.widgetWithText(
                OutlinedButton,
                l10n.commonRetry,
              );
              if (failure is TagReadUnavailableFailure) {
                expect(retry, findsOneWidget);
                expect(
                  tester.widget<OutlinedButton>(retry).onPressed,
                  isNotNull,
                );
                expect(
                  tester
                      .getSemantics(retry)
                      .getSemanticsData()
                      .hasAction(SemanticsAction.tap),
                  isTrue,
                );
              } else {
                expect(retry, findsNothing);
                expect(find.byType(OutlinedButton), findsNothing);
              }
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
