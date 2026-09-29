part of 'tag_navigation_app_lifecycle_test.dart';

void _registerTerminalAppScenarios() {
  for (final locale in ['ru', 'en']) {
    for (final loaded in [false, true]) {
      testWidgets(
        'повтор конечного наблюдения ${loaded ? 'после загрузки' : 'до первой порции'} восстанавливает хранение и экран на $locale',
        (tester) async {
          final app = await _App.pump(tester, locale: locale);
          TagNavigationLoaded? before;
          VoidCallback? oldOpen;
          if (loaded) {
            await app.openNavigation(tester);
            await app.loaded(tester);
            await _changeScope(tester, TaggedIntentionsScope.archived);
            before = await app.loaded(tester);
            oldOpen = tester
                .widget<ListTile>(
                  find.descendant(
                    of: find.byKey(ValueKey<IntentionId>(_intention(2))),
                    matching: find.byType(ListTile),
                  ),
                )
                .onTap;
          }
          app.readProbe.failure = sqlite.SqliteException(
            extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
            message: 'занято',
          );
          if (loaded) {
            app.database.markTablesUpdated({app.database.tags});
          } else {
            await app.openNavigation(tester);
          }
          await _waitFor(tester, () => app.repository.completedWatches == 1);
          await _waitFor(tester, () => app.repository.activePages == 0);
          await tester.pumpAndSettle();
          if (!loaded) {
            await _changeScope(tester, TaggedIntentionsScope.archived);
            await _waitFor(tester, () => app.repository.activePages == 0);
          }
          final l10n = app.l10n(tester);
          final message = loaded
              ? l10n.tagNavigationRefreshUnavailable
              : l10n.tagNavigationUnavailable;
          expect(find.text(message), findsOneWidget);
          expect(
            app.repository.watchResults.last,
            isA<TagReadError>().having(
              (result) => result.failure,
              'причина',
              isA<TagReadUnavailableFailure>(),
            ),
          );
          expect(app.model(tester).canActOn(_intention(2)), isFalse);
          oldOpen?.call();
          expect(app.router.current.name, TagNavigationRoute.name);
          if (loaded) {
            final stale = app.state(tester) as TagNavigationLoaded;
            expect(stale.items, before!.items);
            expect(stale.nextCursor, isNull);
          } else {
            expect(app.state(tester), isA<TagNavigationInitialFailure>());
          }

          final writes = app.raw
              .select('SELECT total_changes() AS count')
              .single['count'];
          final queryCount = app.repository.queries.length;
          final observed = app.repository.watchResults.length;
          final held = app.repository.holdNextPage();
          app.readProbe.failure = null;
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, l10n.commonRetry),
          );
          await _waitFor(
            tester,
            () =>
                held.ready.isCompleted &&
                app.repository.watchResults.length > observed,
          );
          expect(app.repository.watchResults.last, isA<TagReadSuccess>());
          expect(app.model(tester).canActOn(_intention(2)), isFalse);
          oldOpen?.call();
          expect(app.router.current.name, TagNavigationRoute.name);
          app.repository.releasePage(held);
          final restored = await app.loaded(tester);
          final snapshot =
              (await held.ready.future as TaggedIntentionsPageSuccess).value;
          expect(restored.tagId, _tagId);
          expect(restored.scope, TaggedIntentionsScope.archived);
          expect(restored.items, snapshot.items);
          expect(
            restored.items.map((item) => item.id).toSet(),
            hasLength(restored.items.length),
          );
          expect(restored.refreshFailure, isNull);
          expect(find.text(message), findsNothing);
          expect(app.model(tester).canActOn(_intention(2)), isTrue);
          expect(app.repository.queries, hasLength(queryCount + 1));
          expect(app.repository.queries.last.tagId, _tagId);
          expect(
            app.repository.queries.last.scope,
            TaggedIntentionsScope.archived,
          );
          expect(app.repository.queries.last.cursor, isNull);
          expect(app.repository.watchedIds, [_tagId, _tagId]);
          expect(app.repository.commands, isEmpty);
          expect(
            app.raw.select('SELECT total_changes() AS count').single['count'],
            writes,
          );

          // Удерживаем пакет координатора: экран обновляет именно новое наблюдение.
          final command = app.repository.holdNextCommand(
            delay: _CommandDelay.afterWrite,
          );
          final accepted = app.runtime.commandCoordinator.acceptTagRename(
            RenameTag(tagId: _tagId, name: TagName.fromInput('Быт')),
          ) as TagCommandAccepted;
          await _waitFor(tester, () => command.written.isCompleted);
          await _waitFor(
            tester,
            () => app.repository.watchResults.whereType<TagReadSuccess>().any(
              (result) => result.value.value?.name.value == 'Быт',
            ),
          );
          final renamed = await app.loaded(tester);
          expect(renamed.tag.name.value, 'Быт');
          expect(renamed.scope, TaggedIntentionsScope.archived);
          tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          expect(find.text(l10n.tagNavigationTag('Быт')), findsOneWidget);
          command.release.complete();
          expect(
            (await _completed(tester, accepted.future)).isFailure,
            isFalse,
          );
          expect(app.repository.commands.whereType<RenameTag>(), hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'обработчики наблюдения и повтора закрытой сессии не меняют новый экран',
    (tester) async {
      final app = await _App.pump(tester);
      await app.openNavigation(tester);
      await app.loaded(tester);
      final oldModel = app.model(tester);
      final callbacks = app.repository.watchCallbacks.single;
      app.readProbe.failure = sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'занято',
      );
      app.database.markTablesUpdated({app.database.tags});
      await _waitFor(tester, () => app.repository.completedWatches == 1);
      await tester.pumpAndSettle();
      final failure = app.repository.watchResults.last;
      expect(failure, isA<TagReadError>());
      final retry = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, app.l10n(tester).commonRetry),
          )
          .onPressed!;

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
      final queryCount = app.repository.queries.length;

      callbacks.onData?.call(failure);
      callbacks.onDone?.call();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect(app.state(tester), same(current));
      expect(current.canUseCurrentItems, isTrue);
      expect(current.scope, TaggedIntentionsScope.active);
      expect(app.repository.queries, hasLength(queryCount));
      final writes = app.raw
          .select('SELECT total_changes() AS count')
          .single['count'];
      retry();
      await _waitFor(tester, () => app.repository.activePages == 0);
      await tester.pumpAndSettle();
      expect(app.state(tester), same(current));
      expect(
        app.raw.select('SELECT total_changes() AS count').single['count'],
        writes,
      );
      expect(app.repository.watchedIds, [_tagId, _tagId]);
      expect(app.repository.commands, isEmpty);
      expect(app.router.current.name, TagNavigationRoute.name);
      expect(
        find.text(app.l10n(tester).tagNavigationRefreshUnavailable),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// Отказ настоящего чтения классифицируется Drift-адаптером.
final class _ReadProbe extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    if (failure case final error?) throw error;
  }
}

typedef _WatchCallbacks = ({
  void Function(TagReadResult)? onData,
  void Function()? onDone,
});

/// Сохраняет обработчики уже запланированных событий закрытой подписки.
final class _CapturedWatchStream extends Stream<TagReadResult> {
  _CapturedWatchStream(this.source, this.capture);

  final Stream<TagReadResult> source;
  final void Function(_WatchCallbacks) capture;

  @override
  StreamSubscription<TagReadResult> listen(
    void Function(TagReadResult)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    capture((onData: onData, onDone: onDone));
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
