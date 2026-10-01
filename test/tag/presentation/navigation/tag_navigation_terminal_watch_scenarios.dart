part of 'tag_navigation_view_model_test.dart';

void _testTerminalWatchRecovery() {
  for (final loaded in [false, true]) {
    test(
      'подтверждённое изменение во время восстановления ${loaded ? 'списка' : 'первой порции'} не возвращает ожидающую старую страницу',
      () async {
        final h = _Harness(reader: _Reads(terminalWatches: true));
        addTearDown(h.dispose);
        if (loaded) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
        }
        await _finishWatch(h, failure: const TagReadUnavailableFailure());
        if (!loaded) {
          h.reads.fail(0, const TaggedIntentionsUnavailableFailure());
          await pumpEventQueue();
        }
        final retry = loaded
            ? h.model.retryRefresh()
            : h.model.retryFirstPage();
        h.reads.page(1, [_intention(2)]);
        await retry;

        h.change(2);
        h.reads.observe(_tag('Дом'), index: 1);
        await pumpEventQueue();

        expect(h.model.canActOn(_intention(2).id), isFalse);
        expect(h.reads.queries, hasLength(3));
        h.reads.page(2, [_intention(3)], revision: 2);
        await pumpEventQueue();
        expect(
          (h.state as TagNavigationLoaded).items.single.id,
          _intention(3).id,
        );
        expect(h.model.canActOn(_intention(3).id), isTrue);
        expect(h.reads.watchedIds, hasLength(2));
      },
    );

    for (final failure in const [
      TagReadUnavailableFailure(),
      TagReadCorruptionFailure(),
      TagReadUnexpectedFailure(),
    ]) {
      test(
        'конечный отказ ${failure.category} ${loaded ? 'после загрузки' : 'до первой порции'} сохраняет категорию после done',
        () async {
          final h = _Harness(reader: _Reads(terminalWatches: true));
          addTearDown(h.dispose);
          if (loaded) {
            h.reads.page(0, [_intention(1)], cursor: _Cursor());
            await pumpEventQueue();
          }

          await _finishWatch(h, failure: failure);

          _expectWatchFailure(h, failure.category, loaded: loaded);
          unawaited(h.model.loadMore());
          unawaited(h.model.retryLoadMore());
          expect(h.reads.queries, hasLength(1));
          expect(h.reads.watchedIds, [_tagId(1)]);
          expect(h.reads.watches.single.isClosed, isTrue);
        },
      );
    }

    for (final rawError in [false, true]) {
      test(
        '${rawError ? 'исключение и done' : 'необъяснённый done'} ${loaded ? 'после загрузки' : 'до первой порции'} остаётся неизвестным отказом',
        () async {
          final h = _Harness(reader: _Reads(terminalWatches: true));
          addTearDown(h.dispose);
          if (loaded) {
            h.reads.page(0, [_intention(1)], cursor: _Cursor());
            await pumpEventQueue();
          }
          if (rawError) {
            h.reads.watches.single.addError(StateError('SQL и личные данные'));
          }

          await _finishWatch(h);

          _expectWatchFailure(
            h,
            GraphFailureCategory.unexpected,
            loaded: loaded,
          );
          expect(h.reads.queries, hasLength(1));
          expect(h.reads.watchedIds, hasLength(1));
        },
      );
    }

    for (final (pageFirst, pageRevision) in [
      (false, 1),
      (true, 1),
      (false, 2),
      (true, 2),
    ]) {
      test(
        'явный повтор конечного отказа ${loaded ? 'после загрузки' : 'до первой порции'} ждёт ${pageFirst ? 'наблюдение после страницы' : 'страницу после наблюдения'} ревизии $pageRevision',
        () async {
          final h = _Harness(reader: _Reads(terminalWatches: true));
          addTearDown(h.dispose);
          h.model.setScope(TaggedIntentionsScope.archived);
          h.reads.page(0, []);
          await pumpEventQueue();
          if (loaded) {
            h.reads.page(1, [_intention(1, archived: true)], cursor: _Cursor());
            await pumpEventQueue();
          }
          await _finishWatch(h, failure: const TagReadUnavailableFailure());
          _expectWatchFailure(
            h,
            GraphFailureCategory.unavailable,
            loaded: loaded,
          );
          if (!loaded) {
            h.reads.fail(1, const TaggedIntentionsUnavailableFailure());
            await pumpEventQueue();
          }

          final retry = loaded
              ? h.model.retryRefresh()
              : h.model.retryFirstPage();
          expect(
            loaded ? h.model.retryRefresh() : h.model.retryFirstPage(),
            same(retry),
          );
          expect(h.reads.watchedIds, [_tagId(1), _tagId(1)]);
          expect(h.reads.queries, hasLength(3));
          expect(h.reads.queries.last.tagId, _tagId(1));
          expect(h.reads.queries.last.scope, TaggedIntentionsScope.archived);
          expect(h.reads.queries.last.cursor, isNull);

          if (pageFirst) {
            h.reads.page(2, [
              _intention(2, archived: true),
            ], revision: pageRevision);
            await retry;
            expect(h.model.canActOn(_intention(2).id), isFalse);
            h.reads.observe(_tag('Дом'), index: 1);
          } else {
            h.reads.observe(_tag('Дом'), index: 1);
            expect(h.model.canActOn(_intention(1).id), isFalse);
            h.reads.page(2, [
              _intention(2, archived: true),
            ], revision: pageRevision);
            await retry;
          }
          await pumpEventQueue();

          final restored = h.state as TagNavigationLoaded;
          expect(restored.scope, TaggedIntentionsScope.archived);
          expect(restored.refreshFailure, isNull);
          expect(restored.canUseCurrentItems, isTrue);
          expect(restored.items.map((item) => item.id), [_intention(2).id]);
          expect(h.model.canActOn(_intention(2).id), isTrue);
          expect(h.reads.queries, hasLength(3));
          h.reads.observe(_tag('Быт'), index: 1, revision: pageRevision);
          expect((h.state as TagNavigationLoaded).tag.name.value, 'Быт');
          expect(h.reads.watchedIds, hasLength(2));
        },
      );
    }

    for (final failure in const [
      TagReadUnavailableFailure(),
      TagReadCorruptionFailure(),
      TagReadUnexpectedFailure(),
    ]) {
      test(
        'повторный конечный отказ ${failure.category} ${loaded ? 'после загрузки' : 'до первой порции'} принадлежит новой подписке',
        () async {
          final h = _Harness(reader: _Reads(terminalWatches: true));
          addTearDown(h.dispose);
          if (loaded) {
            h.reads.page(0, [_intention(1)], cursor: _Cursor());
            await pumpEventQueue();
          }
          await _finishWatch(h, failure: const TagReadUnavailableFailure());
          if (!loaded) {
            h.reads.fail(0, const TaggedIntentionsUnavailableFailure());
            await pumpEventQueue();
          }
          final retry = loaded
              ? h.model.retryRefresh()
              : h.model.retryFirstPage();

          await _finishWatch(h, index: 1, failure: failure);

          _expectWatchFailure(h, failure.category, loaded: loaded);
          h.reads.fail(1, switch (failure) {
            TagReadUnavailableFailure() =>
              const TaggedIntentionsUnavailableFailure(),
            TagReadCorruptionFailure() =>
              const TaggedIntentionsCorruptionFailure(),
            TagReadUnexpectedFailure() =>
              const TaggedIntentionsUnexpectedFailure(),
          });
          await retry;
          await pumpEventQueue();
          _expectWatchFailure(h, failure.category, loaded: loaded);
          expect(h.reads.queries, hasLength(2));
          expect(h.reads.watchedIds, hasLength(2));
        },
      );
    }
  }

  for (final action in ['переподключение', 'смена тега', 'освобождение']) {
    test(
      'поздний done старой подписки после действия «$action» не публикует состояние',
      () async {
        final h = _Harness();
        if (action != 'освобождение') addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        final oldDone = h.reads.doneCallbacks.single;
        switch (action) {
          case 'переподключение':
            h.reads.watches.single.add(
              const TagReadError(TagReadUnavailableFailure()),
            );
            final retry = h.model.retryRefresh();
            h.reads.observe(_tag('Дом'), index: 1);
            h.reads.page(1, [_intention(2)]);
            await retry;
          case 'смена тега':
            h.model.setTagId(_tagId(2));
            h.reads.page(1, [_intention(2)]);
            await pumpEventQueue();
          case 'освобождение':
            h.dispose();
        }
        final stateCount = h.states.length;

        oldDone();
        await pumpEventQueue();

        expect(h.states, hasLength(stateCount));
        expect(h.reads.queries, hasLength(action == 'освобождение' ? 1 : 2));
      },
    );
  }
}

// Сохраняет уже запланированные обработчики, которые отмена подписки не отзывает.
final class _CapturedWatchStream extends Stream<TagReadResult> {
  _CapturedWatchStream(
    this.source, {
    required this.captureDone,
    required this.captureData,
    required this.captureError,
  });

  final Stream<TagReadResult> source;
  final void Function(void Function()) captureDone;
  final void Function(void Function(TagReadResult)) captureData;
  final void Function(void Function(Object)) captureError;

  @override
  StreamSubscription<TagReadResult> listen(
    void Function(TagReadResult)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onDone != null) captureDone(onDone);
    if (onData != null) captureData(onData);
    if (onError is void Function(Object)) captureError(onError);
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

Future<void> _finishWatch(
  _Harness h, {
  TagReadFailure? failure,
  int index = 0,
}) async {
  if (failure != null) h.reads.watches[index].add(TagReadError(failure));
  await h.reads.watches[index].close();
  await pumpEventQueue();
}

void _expectWatchFailure(
  _Harness h,
  GraphFailureCategory category, {
  required bool loaded,
}) {
  if (loaded) {
    final failed = h.state as TagNavigationLoaded;
    expect(failed.refreshFailure?.category, category);
    expect(failed.freshness, TagNavigationFreshness.stale);
    expect(failed.items.single.id, _intention(1).id);
    expect(failed.nextCursor, isNull);
    expect(failed.pageStatus, isA<TagNavigationPageIdle>());
  } else {
    final failed = h.state as TagNavigationInitialFailure;
    expect(failed.failure.category, category);
    expect(failed.canRetry, category == GraphFailureCategory.unavailable);
  }
  expect(h.model.canActOn(_intention(1).id), isFalse);
}
