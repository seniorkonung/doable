part of 'tag_navigation_view_model_test.dart';

void _testLatePageAfterWatchFailure() {
  const pageResults = [
    (label: 'успех', failure: null),
    (label: 'недоступность', failure: TaggedIntentionsUnavailableFailure()),
    (label: 'повреждение', failure: TaggedIntentionsCorruptionFailure()),
    (
      label: 'неизвестная причина',
      failure: TaggedIntentionsUnexpectedFailure(),
    ),
    (label: 'отсутствие тега', failure: TaggedIntentionsTagNotFound()),
    (label: 'устаревший снимок', failure: TaggedIntentionsSnapshotExpired()),
    (label: 'чужой курсор', failure: TaggedIntentionsInvalidCursor()),
  ];
  for (final continuation in [false, true]) {
    for (final terminal in [false, true]) {
      for (final (watchLabel, watchFailure) in const [
        ('недоступность', TagReadUnavailableFailure()),
        ('повреждение', TagReadCorruptionFailure()),
        ('неизвестная причина', TagReadUnexpectedFailure()),
      ]) {
        for (final result in pageResults) {
          test(
            'поздний результат «${result.label}» ${continuation ? 'подгрузки' : 'первой порции'} сохраняет отказ «$watchLabel» ${terminal ? 'после окончания' : 'открытого'} наблюдения',
            () async {
              final h = _Harness(reader: _Reads(terminalWatches: terminal));
              addTearDown(h.dispose);
              Future<void>? pending;
              if (continuation) {
                h.reads.page(0, [_intention(1)], cursor: _Cursor());
                await pumpEventQueue();
                pending = h.model.loadMore();
              }
              h.reads.watches.single.add(TagReadError(watchFailure));
              if (terminal) await h.reads.watches.single.close();
              await pumpEventQueue();
              _expectWatchFailure(
                h,
                watchFailure.category,
                loaded: continuation,
              );
              final failed = h.state;
              final stateCount = h.states.length;
              final index = continuation ? 1 : 0;
              if (result.failure case final failure?) {
                h.reads.fail(index, failure);
              } else {
                h.reads.page(index, [_intention(102)], cursor: _Cursor());
              }
              if (pending != null) await pending;
              await pumpEventQueue();

              _expectWatchFailure(
                h,
                watchFailure.category,
                loaded: continuation,
              );
              expect(h.state, same(failed));
              expect(h.states, hasLength(stateCount));
              expect(h.reads.queries, hasLength(index + 1));
              expect(h.model.canActOn(_intention(102).id), isFalse);
              await h.model.loadMore();
              await h.model.retryLoadMore();
              if (watchFailure is! TagReadUnavailableFailure) {
                await h.model.retryFirstPage();
                await h.model.retryRefresh();
              }
              expect(h.reads.queries, hasLength(index + 1));
              expect(h.reads.watchedIds, hasLength(1));
            },
          );
        }
      }
    }
  }
  _testWatchFailureDuringSelectionUpdates();
  _testRecoveryAfterLatePage();
  _testLateCallbacksAfterSelectionEnds();
}

void _testLateCallbacksAfterSelectionEnds() {
  for (final continuation in [false, true]) {
    for (final disposed in [false, true]) {
      test(
        'поздняя ${continuation ? 'подгрузка' : 'первая порция'} и обработчики отказавшего наблюдения после ${disposed ? 'освобождения' : 'смены тега'} не меняют новый выбор',
        () async {
          final h = _Harness();
          if (!disposed) addTearDown(h.dispose);
          if (continuation) {
            h.reads.page(0, [_intention(1)], cursor: _Cursor());
            await pumpEventQueue();
            unawaited(h.model.loadMore());
          }
          h.reads.watches.single.add(
            const TagReadError(TagReadUnavailableFailure()),
          );
          await pumpEventQueue();
          if (disposed) {
            h.dispose();
          } else {
            h.model.setTagId(_tagId(2));
            h.model.setScope(TaggedIntentionsScope.archived);
          }
          final stateCount = h.states.length;
          _deliverOldWatchCallbacks(h);
          await pumpEventQueue();
          expect(h.states, hasLength(stateCount));
          final oldIndex = continuation ? 1 : 0;
          h.reads.page(oldIndex, [_intention(2)], cursor: _Cursor());
          await pumpEventQueue();
          expect(h.states, hasLength(stateCount));
          expect(h.model.canActOn(_intention(2).id), isFalse);
          expect(h.reads.queries, hasLength(oldIndex + (disposed ? 1 : 2)));
          if (!disposed) {
            expect(h.state, isA<TagNavigationInitialLoading>());
            expect(h.state.tagId, _tagId(2));
            expect(h.state.scope, TaggedIntentionsScope.archived);
            h.reads.observe(_tag('Работа', id: 2), index: 1, revision: 2);
            h.reads.page(
              oldIndex + 1,
              [_intention(103, archived: true)],
              tag: _tag('Работа', id: 2),
              revision: 2,
            );
            await pumpEventQueue();
            expect(h.model.canActOn(_intention(103).id), isTrue);
          }
        },
      );
    }
  }
}

void _testRecoveryAfterLatePage() {
  for (final continuation in [false, true]) {
    for (final terminal in [false, true]) {
      for (final lateSuccess in [false, true]) {
        for (final pageFirst in [false, true]) {
          test(
            'повтор после позднего ${lateSuccess ? 'успеха' : 'отказа'} ${continuation ? 'подгрузки' : 'первой порции'} при ${terminal ? 'конечном' : 'открытом'} отказе ждёт ${pageFirst ? 'новое наблюдение' : 'новую страницу'}',
            () async {
              final h = _Harness(reader: _Reads(terminalWatches: terminal));
              addTearDown(h.dispose);
              h.model.setScope(TaggedIntentionsScope.archived);
              h.reads.page(0, []);
              await pumpEventQueue();
              if (continuation) {
                h.reads.page(1, [
                  _intention(1, archived: true),
                ], cursor: _Cursor());
                await pumpEventQueue();
                unawaited(h.model.loadMore());
              }
              h.reads.watches.single.add(
                const TagReadError(TagReadUnavailableFailure()),
              );
              if (terminal) await h.reads.watches.single.close();
              await pumpEventQueue();
              final oldIndex = continuation ? 2 : 1;
              if (lateSuccess) {
                h.reads.page(oldIndex, [
                  _intention(102, archived: true),
                ], cursor: _Cursor());
              } else {
                h.reads.fail(
                  oldIndex,
                  const TaggedIntentionsUnavailableFailure(),
                );
              }
              await pumpEventQueue();
              _expectWatchFailure(
                h,
                GraphFailureCategory.unavailable,
                loaded: continuation,
              );
              final retry = continuation
                  ? h.model.retryRefresh()
                  : h.model.retryFirstPage();
              final newIndex = oldIndex + 1;
              expect(h.reads.queries, hasLength(newIndex + 1));
              expect(h.reads.watchedIds, [_tagId(1), _tagId(1)]);
              expect(
                h.reads.queries.last.scope,
                TaggedIntentionsScope.archived,
              );
              expect(h.reads.queries.last.cursor, isNull);
              if (pageFirst) {
                h.reads.page(newIndex, [_intention(103, archived: true)]);
                await retry;
                expect(h.model.canActOn(_intention(103).id), isFalse);
                h.reads.observe(_tag('Дом'), index: 1);
              } else {
                h.reads.observe(_tag('Дом'), index: 1);
                expect(h.model.canActOn(_intention(1).id), isFalse);
                expect(h.model.canActOn(_intention(103).id), isFalse);
                h.reads.page(newIndex, [_intention(103, archived: true)]);
                await retry;
              }
              await pumpEventQueue();
              final restored = h.state as TagNavigationLoaded;
              expect(restored.refreshFailure, isNull);
              expect(restored.canUseCurrentItems, isTrue);
              expect(restored.scope, TaggedIntentionsScope.archived);
              expect(restored.items.single.id, _intention(103).id);
              expect(h.model.canActOn(_intention(103).id), isTrue);
              final stateCount = h.states.length;
              _deliverOldWatchCallbacks(h);
              await pumpEventQueue();
              expect(h.state, same(restored));
              expect(h.states, hasLength(stateCount));
              expect(h.reads.queries, hasLength(newIndex + 1));
              h.reads.observe(_tag('Быт'), index: 1, revision: 2);
              h.reads.page(
                newIndex + 1,
                [_intention(4, archived: true)],
                tag: _tag('Быт'),
                revision: 2,
              );
              await pumpEventQueue();
              expect((h.state as TagNavigationLoaded).tag.name.value, 'Быт');
              expect(h.model.canActOn(_intention(4).id), isTrue);
              expect(h.reads.watchedIds, hasLength(2));
            },
          );
        }
      }
    }
  }
}

void _deliverOldWatchCallbacks(_Harness h) {
  h.reads.dataCallbacks.first(const TagReadError(TagReadCorruptionFailure()));
  h.reads.dataCallbacks.first(
    const TagReadSuccess(GraphSnapshot(value: null, revision: _Revision(3))),
  );
  h.reads.errorCallbacks.first(StateError('SQL и личные данные'));
  h.reads.doneCallbacks.first();
}

void _testWatchFailureDuringSelectionUpdates() {
  for (final continuation in [false, true]) {
    for (final terminal in [false, true]) {
      for (final (label, failure) in const [
        ('недоступность', TagReadUnavailableFailure()),
        ('повреждение', TagReadCorruptionFailure()),
        ('неизвестная причина', TagReadUnexpectedFailure()),
      ]) {
        for (final source in ['наблюдение', 'пакет', 'охват']) {
          if (terminal && source == 'наблюдение') continue;
          test(
            '$source после отказа «$label» ${terminal ? 'конечного' : 'открытого'} наблюдения во время ${continuation ? 'подгрузки' : 'первой порции'} не подтверждает восстановление',
            () async {
              final h = _Harness(reader: _Reads(terminalWatches: terminal));
              addTearDown(h.dispose);
              if (continuation) {
                h.reads.page(0, [_intention(1)], cursor: _Cursor());
                await pumpEventQueue();
                unawaited(h.model.loadMore());
              }
              h.reads.watches.single.add(TagReadError(failure));
              if (terminal) await h.reads.watches.single.close();
              await pumpEventQueue();
              switch (source) {
                case 'наблюдение':
                  h.reads.observe(_tag('Быт'), revision: 2);
                case 'пакет':
                  h.change(
                    2,
                    changes: [
                      TagRenamedChange(
                        revision: const _Revision(2),
                        before: _tag('Дом'),
                        after: _tag('Быт'),
                      ),
                    ],
                  );
                case 'охват':
                  h.model.setScope(TaggedIntentionsScope.archived);
              }
              _expectWatchFailure(
                h,
                failure.category,
                loaded: continuation && source != 'охват',
              );
              final failed = h.state;
              final index = continuation ? 1 : 0;
              h.reads.page(
                index,
                [_intention(102)],
                revision: 2,
                tag: _tag('Быт'),
              );
              await pumpEventQueue();
              expect(h.state, same(failed));
              expect(h.reads.queries, hasLength(index + 1));
              expect(h.model.canActOn(_intention(102).id), isFalse);
              await h.model.loadMore();
              await h.model.retryLoadMore();
              expect(h.reads.queries, hasLength(index + 1));
            },
          );
        }
      }
    }
  }
}
