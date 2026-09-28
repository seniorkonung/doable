part of 'tag_navigation_app_lifecycle_test.dart';

void _registerLatePageAppScenarios() {
  _registerLateSuccessAppScenarios();
  _registerLatePageSessionScenarios();
  for (final locale in ['ru', 'en']) {
    testWidgets(
      'конечное повреждение наблюдения сохраняется после поздней недоступности подгрузки через хранение и экран на $locale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final app = await _App.pump(tester, locale: locale);
          await app.openNavigation(tester);
          await app.loaded(tester);
          await _changeScope(tester, TaggedEntitiesScope.archived);
          final before = await app.loaded(tester);
          final target = _intention(2);
          final oldOpen = tester.widget<ListTile>(_latePageTile(target)).onTap!;
          final l10n = app.l10n(tester);
          final writes = app.raw
              .select('SELECT total_changes() AS count')
              .single['count'];
          final queryCount = app.repository.queries.length;
          final held = app.repository.holdNextPage();
          app.readProbe.failure = sqlite.SqliteException(
            extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
            message: 'занято',
          );
          await _scrollAndTap(
            tester,
            find.widgetWithText(OutlinedButton, l10n.tagNavigationLoadMore),
          );
          await _waitFor(tester, () => held.ready.isCompleted);
          expect(
            await held.ready.future,
            isA<TaggedEntitiesPageError>().having(
              (result) => result.failure,
              'причина позднего продолжения',
              isA<TaggedEntitiesUnavailableFailure>(),
            ),
          );
          expect(app.repository.queries.last.cursor, same(before.nextCursor));

          app.readProbe.failure = sqlite.SqliteException(
            extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
            message: 'повреждение',
          );
          app.database.markTablesUpdated({app.database.tags});
          await _waitFor(tester, () => app.repository.completedWatches == 1);
          expect(
            app.repository.watchResults.last,
            isA<TagReadError>().having(
              (result) => result.failure,
              'конечная причина настоящего наблюдения',
              isA<TagReadCorruptionFailure>(),
            ),
          );
          expect(app.repository.activePages, 1);
          final failed = app.state(tester) as TagNavigationLoaded;
          expect(failed.refreshFailure, isA<TaggedEntitiesCorruptionFailure>());

          app.repository.releasePage(held);
          await _waitFor(tester, () => app.repository.activePages == 0);
          await tester.runAsync(() => pumpEventQueue());
          await _latePageScrollToStart(tester);
          final stale = app.state(tester) as TagNavigationLoaded;
          expect(stale.items, before.items);
          expect(stale.freshness, TagNavigationFreshness.stale);
          expect(stale.nextCursor, isNull);
          expect(stale.pageStatus, isA<TagNavigationPageIdle>());
          expect(
            find.text(l10n.tagNavigationRefreshCorruption),
            findsOneWidget,
          );
          expect(find.text(l10n.tagNavigationRefreshUnavailable), findsNothing);
          expect(
            find.text(l10n.tagNavigationLoadMoreUnavailable),
            findsNothing,
          );
          expect(find.text(l10n.commonRetry), findsNothing);
          expect(find.text(l10n.tagNavigationLoadMore), findsNothing);
          _expectLatePageTransitionBlocked(tester, app, target, oldOpen);
          expect(app.repository.commands, isEmpty);
          expect(app.repository.queries, hasLength(queryCount + 1));
          expect(
            app.raw.select('SELECT total_changes() AS count').single['count'],
            writes,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

void _registerLateSuccessAppScenarios() {
  for (final locale in ['ru', 'en']) {
    for (final loaded in [false, true]) {
      for (final (name, injected, failure) in [
        (
          'недоступность',
          sqlite.SqliteException(
            extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
            message: 'занято',
          ),
          const TagReadUnavailableFailure(),
        ),
        (
          'повреждение',
          sqlite.SqliteException(
            extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
            message: 'повреждение',
          ),
          const TagReadCorruptionFailure(),
        ),
        (
          'неизвестная причина',
          StateError('неизвестная причина'),
          const TagReadUnexpectedFailure(),
        ),
      ]) {
        testWidgets(
          'конечный отказ наблюдения ($name) не снимается поздним успехом ${loaded ? 'подгрузки' : 'первой порции'} через хранение и экран на $locale',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final app = await _App.pump(tester, locale: locale);
              TagNavigationLoaded? before;
              VoidCallback? oldOpen;
              final scope = loaded
                  ? TaggedEntitiesScope.archived
                  : TaggedEntitiesScope.active;
              final target = _intention(loaded ? 2 : 1);
              if (loaded) {
                await app.openNavigation(tester);
                await app.loaded(tester);
                await _changeScope(tester, scope);
                before = await app.loaded(tester);
                oldOpen = tester.widget<ListTile>(_latePageTile(target)).onTap!;
              }
              final held = app.repository.holdNextPage();
              if (loaded) {
                await _scrollAndTap(
                  tester,
                  find.widgetWithText(
                    OutlinedButton,
                    app.l10n(tester).tagNavigationLoadMore,
                  ),
                );
              } else {
                await app.openNavigation(tester);
              }
              await _waitFor(tester, () => held.ready.isCompleted);
              expect(await held.ready.future, isA<TaggedEntitiesPageSuccess>());
              final queryCount = app.repository.queries.length;
              final oldCallbacks = app.repository.watchCallbacks.single;
              app.readProbe.failure = injected;
              app.database.markTablesUpdated({app.database.tags});
              await _waitFor(
                tester,
                () => app.repository.completedWatches == 1,
              );
              final watchError =
                  app.repository.watchResults.last as TagReadError;
              expect(watchError.failure.category, failure.category);
              expect(app.repository.activePages, 1);

              app.repository.releasePage(held);
              await _waitFor(tester, () => app.repository.activePages == 0);
              await tester.runAsync(() => pumpEventQueue());
              await _latePageScrollToStart(tester);
              final l10n = app.l10n(tester);
              final message = _lateWatchMessage(l10n, failure, loaded: loaded);
              expect(find.text(message), findsOneWidget);
              expect(app.repository.queries, hasLength(queryCount));
              expect(find.text(l10n.tagNavigationLoadMore), findsNothing);
              expect(app.model(tester).canActOn(target), isFalse);
              if (loaded) {
                final stale = app.state(tester) as TagNavigationLoaded;
                expect(stale.items, before!.items);
                expect(stale.freshness, TagNavigationFreshness.stale);
                expect(stale.nextCursor, isNull);
                expect(stale.refreshFailure!.category, failure.category);
                _expectLatePageTransitionBlocked(tester, app, target, oldOpen!);
              } else {
                final initial =
                    app.state(tester) as TagNavigationInitialFailure;
                expect(initial.failure.category, failure.category);
                expect(find.byType(ListTile), findsNothing);
              }
              if (failure is TagReadUnavailableFailure) {
                await _restoreAfterLatePage(
                  tester,
                  app,
                  target,
                  scope,
                  oldCallbacks,
                  watchError,
                  oldOpen,
                  pageFirst: loaded,
                );
              } else {
                expect(find.text(l10n.commonRetry), findsNothing);
                expect(app.repository.commands, isEmpty);
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

void _registerLatePageSessionScenarios() {
  for (final locale in ['ru', 'en']) {
    testWidgets(
      'поздняя подгрузка и обработчики закрытой сессии не меняют новый экран на $locale',
      (tester) async {
        final app = await _App.pump(tester, locale: locale);
        await app.openNavigation(tester);
        await app.loaded(tester);
        final target = _intention(1);
        final oldOpen = tester.widget<ListTile>(_latePageTile(target)).onTap!;
        final oldCallbacks = app.repository.watchCallbacks.single;
        final held = app.repository.holdNextPage();
        await _scrollAndTap(
          tester,
          find.widgetWithText(
            OutlinedButton,
            app.l10n(tester).tagNavigationLoadMore,
          ),
        );
        await _waitFor(tester, () => held.ready.isCompleted);
        expect(await held.ready.future, isA<TaggedEntitiesPageSuccess>());
        app.readProbe.failure = sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'занято',
        );
        app.database.markTablesUpdated({app.database.tags});
        await _waitFor(tester, () => app.repository.completedWatches == 1);
        final oldFailure = app.repository.watchResults.last as TagReadError;
        await _latePageScrollToStart(tester);
        final retry = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, app.l10n(tester).commonRetry),
            )
            .onPressed!;
        final oldModel = app.model(tester);
        expect(app.repository.activePages, 1);

        app.router.pop();
        await tester.pumpAndSettle();
        await _waitFor(
          tester,
          () => find
              .byType(TagNavigationPage, skipOffstage: false)
              .evaluate()
              .isEmpty,
        );
        app.readProbe.failure = null;
        await app.openNavigation(tester);
        final current = await app.loaded(tester);
        expect(app.model(tester), isNot(same(oldModel)));
        final count = app.repository.queries.length;
        final writes = app.raw
            .select('SELECT total_changes() AS count')
            .single['count'];
        oldCallbacks.onData?.call(oldFailure);
        oldCallbacks.onDone?.call();
        retry();
        oldOpen();
        app.repository.releasePage(held);
        await _waitFor(tester, () => app.repository.activePages == 0);
        await tester.runAsync(() => pumpEventQueue());
        await tester.pumpAndSettle();

        expect(app.state(tester), same(current));
        expect(current.items, hasLength(50));
        expect(current.items.map((item) => item.target).toSet(), hasLength(50));
        expect(current.canUseCurrentItems, isTrue);
        expect(current.refreshFailure, isNull);
        expect(app.model(tester).canActOn(target), isTrue);
        expect(app.router.current.name, TagNavigationRoute.name);
        expect(app.repository.queries, hasLength(count));
        expect(app.repository.watchedIds, [_tagId, _tagId]);
        expect(app.repository.commands, isEmpty);
        expect(
          app.raw.select('SELECT total_changes() AS count').single['count'],
          writes,
        );
        expect(
          find.text(app.l10n(tester).tagNavigationRefreshUnavailable),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

String _lateWatchMessage(
  AppLocalizations l10n,
  TagReadFailure failure, {
  required bool loaded,
}) => switch (failure) {
  TagReadUnavailableFailure() =>
    loaded
        ? l10n.tagNavigationRefreshUnavailable
        : l10n.tagNavigationUnavailable,
  TagReadCorruptionFailure() =>
    loaded ? l10n.tagNavigationRefreshCorruption : l10n.tagNavigationCorruption,
  TagReadUnexpectedFailure() =>
    loaded ? l10n.tagNavigationRefreshUnexpected : l10n.tagNavigationUnexpected,
};

Future<void> _restoreAfterLatePage(
  WidgetTester tester,
  _App app,
  IntentionTagTarget target,
  TaggedEntitiesScope scope,
  _WatchCallbacks oldCallbacks,
  TagReadError oldFailure,
  VoidCallback? oldOpen, {
  required bool pageFirst,
}) async {
  final l10n = app.l10n(tester);
  final writes = app.raw
      .select('SELECT total_changes() AS count')
      .single['count'];
  final count = app.repository.queries.length;
  final observed = app.repository.watchResults.length;
  final recovery = app.repository.holdNextPage();
  app.repository.holdObservations = pageFirst;
  app.readProbe.failure = null;
  await _tap(tester, find.widgetWithText(OutlinedButton, l10n.commonRetry));
  await _waitFor(
    tester,
    () =>
        recovery.ready.isCompleted &&
        app.repository.watchResults.length > observed,
  );
  expect(app.repository.watchResults.last, isA<TagReadSuccess>());
  expect(app.model(tester).canActOn(target), isFalse);
  oldOpen?.call();
  expect(app.router.current.name, TagNavigationRoute.name);
  oldCallbacks.onData?.call(oldFailure);
  oldCallbacks.onDone?.call();
  app.repository.releasePage(recovery);
  await _waitFor(tester, () => app.repository.activePages == 0);
  if (pageFirst) {
    // Новая страница без доставленного нового наблюдения ещё не подтверждает восстановление.
    expect(app.model(tester).canActOn(target), isFalse);
    app.repository.holdObservations = false;
    app.repository.flushObservations(newestFirst: false);
  }
  final restored = await app.loaded(tester);
  final snapshot =
      (await recovery.ready.future as TaggedEntitiesPageSuccess).value;
  expect(restored.tagId, _tagId);
  expect(restored.scope, scope);
  expect(restored.items, snapshot.items);
  expect(
    restored.items.map((item) => item.target).toSet(),
    hasLength(restored.items.length),
  );
  expect(restored.refreshFailure, isNull);
  expect(app.repository.queries, hasLength(count + 1));
  expect(app.repository.queries.last.tagId, _tagId);
  expect(app.repository.queries.last.scope, scope);
  expect(app.repository.queries.last.cursor, isNull);
  expect(app.repository.watchedIds, [_tagId, _tagId]);
  expect(app.repository.commands, isEmpty);
  expect(
    app.raw.select('SELECT total_changes() AS count').single['count'],
    writes,
  );
  oldCallbacks.onData?.call(oldFailure);
  oldCallbacks.onDone?.call();
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
  expect(app.state(tester), same(restored));
  expect(app.model(tester).canActOn(target), isTrue);

  // Пакет координатора удержан: подтверждённое переименование достигает экрана через новое наблюдение.
  final command = app.repository.holdNextCommand(
    delay: _CommandDelay.afterWrite,
  );
  final accepted = app.runtime.commandCoordinator.acceptTagRename(
    RenameTag(tagId: _tagId, name: TagName.fromInput('Быт после повтора')),
  ) as TagCommandAccepted;
  await _waitFor(tester, () => command.written.isCompleted);
  await _waitFor(
    tester,
    () => app.repository.watchResults.whereType<TagReadSuccess>().any(
      (result) => result.value.value?.name.value == 'Быт после повтора',
    ),
  );
  final renamed = await app.loaded(tester);
  expect(renamed.tag.name.value, 'Быт после повтора');
  expect(renamed.scope, scope);
  await _latePageScrollToStart(tester);
  expect(find.text(l10n.tagNavigationTag('Быт после повтора')), findsOneWidget);
  expect(
    tester
        .getSemantics(find.byKey(ValueKey<TagTarget>(target)))
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isTrue,
  );
  command.release.complete();
  expect((await _completed(tester, accepted.future)).isFailure, isFalse);
  expect(app.repository.commands.whereType<RenameTag>(), hasLength(1));
  await _tap(tester, _latePageTile(target));
  await tester.pumpAndSettle();
  expect(app.router.current.name, IntentionDetailsRoute.name);
  expect(
    app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
    target.intentionId,
  );
  app.router.pop();
  await tester.pumpAndSettle();
  expect((await app.loaded(tester)).scope, scope);
}

Finder _latePageTile(TagTarget target) => find.descendant(
  of: find.byKey(ValueKey<TagTarget>(target)),
  matching: find.byType(ListTile),
);

Future<void> _latePageScrollToStart(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void _expectLatePageTransitionBlocked(
  WidgetTester tester,
  _App app,
  TagTarget target,
  VoidCallback oldOpen,
) {
  expect(app.model(tester).canActOn(target), isFalse);
  expect(tester.widget<ListTile>(_latePageTile(target)).onTap, isNull);
  expect(
    tester
        .getSemantics(find.byKey(ValueKey<TagTarget>(target)))
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isFalse,
  );
  oldOpen();
  expect(app.router.current.name, TagNavigationRoute.name);
}
