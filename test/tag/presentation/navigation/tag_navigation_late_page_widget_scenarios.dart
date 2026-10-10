part of 'tag_navigation_page_test.dart';

void _registerLatePageWidgetScenarios() {
  // Отбрасывание позднего чтения проверяет модель представления; здесь важно,
  // что экран сохраняет видимое сообщение и действия. Случаи различают
  // допустимость повтора и состояние до и после загрузки.
  for (final (loaded, lateSuccess, (name, failure)) in const [
    (false, true, ('недоступность', TagReadUnavailableFailure())),
    (true, false, ('недоступность', TagReadUnavailableFailure())),
    (true, true, ('повреждение', TagReadCorruptionFailure())),
  ]) {
    testWidgets(
      '$name открытого наблюдения сохраняется после позднего ${lateSuccess ? 'успеха' : 'отказа'} ${loaded ? 'подгрузки' : 'первой порции'}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final reads = _Reads();
          addTearDown(reads.dispose);
          await _pumpPage(tester, reads);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(TagNavigationPage)),
          );
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
          expect(_row(lateItem), findsNothing);
          expect(find.text(l10n.tagNavigationLoadMore), findsNothing);
          expect(
            find.text(l10n.tagNavigationLoadMoreUnavailable),
            findsNothing,
          );
          expect(find.text(l10n.tagNavigationEmptyActive), findsNothing);
          final tile = find.descendant(
            of: _row(item),
            matching: find.byType(ListTile),
          );
          if (loaded) {
            expect(_row(item), findsOneWidget);
            expect(tester.widget<ListTile>(tile).onTap, isNull);
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

          final retry = find.widgetWithText(OutlinedButton, l10n.commonRetry);
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
            await tester.tap(retry);
            await tester.pump();
            expect(reads.queries.last.tagId, _tag.id);
            expect(reads.queries.last.scope, TaggedIntentionsScope.active);
            expect(reads.queries.last.cursor, isNull);
            reads.page(count, [item]);
            await tester.pump();
            // Пока наблюдение не подтвердило восстановление, переходов нет.
            expect(
              tester
                  .widgetList<ListTile>(tile)
                  .every((row) => row.onTap == null),
              isTrue,
            );
            reads.watch.add(
              TagReadSuccess(
                GraphSnapshot(value: _tag, revision: const _Revision(1)),
              ),
            );
            await tester.pumpAndSettle();
            expect(_row(item), findsOneWidget);
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
