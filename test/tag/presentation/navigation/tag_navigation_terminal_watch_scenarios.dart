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
      },
    );
  }

  // Точка входа повтора, порядок прихода подписки и страницы и ревизия
  // страницы независимы: каждое значение встречается дважды.
  for (final (loaded, pageFirst, pageRevision) in const [
    (false, false, 1),
    (false, true, 2),
    (true, false, 2),
    (true, true, 1),
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
        unawaited(loaded ? h.model.retryRefresh() : h.model.retryFirstPage());
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
      },
    );
  }

  // Новый конечный отказ принадлежит новой подписке при любом виде отказа:
  // повторный отказ достаточно показать для доступного к повтору и для
  // недоступного к повтору вида.
  for (final (loaded, failure) in const [
    (false, TagReadUnavailableFailure()),
    (true, TagReadCorruptionFailure()),
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
