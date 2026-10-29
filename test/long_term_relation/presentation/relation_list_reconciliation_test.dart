import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/relation_list_reconciliation.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../support/tag_positions.dart';

void main() {
  test(
    'поздний ответ прежнего запроса не заменяет перезапущенный список',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);

      harness.list.restart(harness.query('новый'));
      expect(harness.state, isA<RelationListInitialLoad<_Part, int>>());
      expect(harness.reads.listAt(1), 'новый');
      harness.reads.first(1, [1], total: 1, revision: 2);
      await pumpEventQueue();
      harness.reads.first(0, [2], total: 1, revision: 1);
      await pumpEventQueue();

      expect(harness.active.data.items, [1]);
    },
  );

  test(
    'освобождённый список не публикует поздний ответ и не читает заново',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);

      harness.list.dispose();
      harness.emitIntention(revision: 2);
      harness.reads.first(0, [1], total: 1, revision: 1);
      await pumpEventQueue();

      expect(harness.published, isEmpty);
      expect(harness.reads.count, 1);
    },
  );

  test('прерванная подгрузка ведёт к новой основе в пределах загруженной части '
      'и запрошенной порции', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);
    harness.reads.first(0, [1, 2], total: 5, revision: 1, next: 2);
    await pumpEventQueue();
    harness.scrollTo(1);
    expect(harness.active.progress, isA<RelationListLoadingMore>());

    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    expect(harness.active.data.items, [1, 2]);
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );
    expect(harness.active.progress, isA<RelationListIdle>());
    expect(harness.reads.cursorAt(2), isNull);

    harness.reads.continuation(1, [3, 4], revision: 1, next: 4);
    await pumpEventQueue();
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );
    harness.reads.first(2, [1, 2], total: 5, revision: 2, next: 2);
    await pumpEventQueue();
    expect(harness.reads.cursorAt(3), const _Cursor(2));
    harness.reads.continuation(3, [3, 4], revision: 2, next: 4);
    await pumpEventQueue();

    final current = harness.confirmed;
    expect(harness.active.data.items, [1, 2, 3, 4]);
    expect(harness.active.data.nextCursor, const _Cursor(4));
    expect(current.summaryStatus, isA<RelationListSummaryCurrent>());
    expect(harness.reads.count, 4);
  });

  test(
    'устаревшее продолжение ведёт к новой основе в пределах загруженной части '
    'и запрошенной порции',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1, 2], total: 6, revision: 1, next: 2);
      await pumpEventQueue();
      harness.scrollTo(1);

      harness.reads.fail(1, const RelationGroupSnapshotExpired());
      await pumpEventQueue();
      expect(harness.active.data.items, [1, 2]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );
      expect(harness.reads.cursorAt(2), isNull);
      harness.reads.first(2, [1, 2], total: 6, revision: 2, next: 2);
      await pumpEventQueue();
      harness.reads.continuation(3, [3, 4], revision: 2, next: 4);
      await pumpEventQueue();

      final current = harness.confirmed;
      expect(harness.active.data.items, [1, 2, 3, 4]);
      expect(harness.active.data.nextCursor, const _Cursor(4));
      expect(current.summaryStatus, isA<RelationListSummaryCurrent>());
      expect(harness.reads.count, 4);
    },
  );

  test('чужая ревизия требует новой основы, а запоздалое чтение не возвращает '
      'прежние строки и сводку', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);
    harness.reads.first(0, [1, 2], total: 4, revision: 1, next: 2);
    await pumpEventQueue();

    await harness.completeUnrelatedTagChange(revision: 2);
    expect(harness.confirmed.summaryStatus, isA<RelationListSummaryCurrent>());
    expect(harness.reads.count, 1);

    harness.scrollTo(1);
    expect(harness.reads.cursorAt(1), isNull);
    harness.reads.first(1, [1, 2], total: 4, revision: 1, next: 2);
    await pumpEventQueue();
    expect(harness.confirmed.counts.activeNeedOutgoing, 4);
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );
    expect(harness.reads.cursorAt(2), isNull);
    harness.reads.first(2, [5, 6], total: 2, revision: 2);
    await pumpEventQueue();

    final current = harness.confirmed;
    expect(harness.active.data.items, [5, 6]);
    expect(current.counts.activeNeedOutgoing, 2);
    expect(current.summaryStatus, isA<RelationListSummaryCurrent>());
  });

  test('значимое завершение координатора требует новой основы и видит '
      'опубликованную часть', () async {
    final observed = <List<int>?>[];
    final harness = _ListHarness(
      isSignificant: (change, confirmed) {
        observed.add(confirmed?.items.toList());
        return change is IntentionCatalogMutation;
      },
    );
    addTearDown(harness.dispose);
    harness.reads.first(0, [1], total: 1, revision: 1);
    await pumpEventQueue();

    await harness.completeOwnerRename(revision: 2);

    expect(observed, isNotEmpty);
    expect(observed, everyElement([1]));
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );
    expect(harness.reads.cursorAt(1), isNull);
  });

  test(
    'удаление намерения по наблюдению завершает список без новых чтений',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1, 2], total: 4, revision: 1, next: 2);
      await pumpEventQueue();
      harness.scrollTo(1);

      harness.emitIntentionNotFound(revision: 2);
      await pumpEventQueue();
      expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
      expect(harness.list.isTerminated, isTrue);

      harness.reads.continuation(1, [3, 4], revision: 1);
      harness.emitIntention(revision: 3);
      await pumpEventQueue();
      harness.scrollTo(1);
      expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
      expect(harness.reads.count, 2);
    },
  );

  test('удаление намерения по завершению координатора завершает список без '
      'новых чтений', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);
    harness.reads.first(0, [1], total: 1, revision: 1);
    await pumpEventQueue();

    await harness.completeOwnerDeletion(revision: 2);
    expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());

    harness.emitIntention(revision: 3);
    await pumpEventQueue();
    expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
    expect(harness.reads.count, 1);
  });

  test(
    'незначимое завершение координатора не мешает продолжению по курсору',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1, 2], total: 4, revision: 1, next: 2);
      await pumpEventQueue();

      await harness.completeOwnerRename(revision: 2);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryCurrent>(),
      );
      harness.scrollTo(1);

      expect(harness.reads.count, 2);
      expect(harness.reads.cursorAt(1), const _Cursor(2));
    },
  );

  test('отсутствие намерения при первом чтении завершает список без новых '
      'чтений', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);

    harness.reads.fail(
      0,
      RelationGroupIntentionNotFoundFailure(harness.owner.id),
    );
    await pumpEventQueue();
    expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
    expect(harness.list.isTerminated, isTrue);

    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    unawaited(harness.list.retryFirstPage());
    expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
    expect(harness.reads.count, 1);
  });

  test(
    'поздняя первая порция после отсутствия намерения не публикуется',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);

      harness.emitIntentionNotFound(revision: 1);
      await pumpEventQueue();
      harness.reads.first(0, [1], total: 1, revision: 1);
      await pumpEventQueue();

      expect(harness.state, isA<RelationListIntentionNotFound<_Part, int>>());
      expect(
        harness.published.whereType<RelationListConfirmed<_Part, int>>(),
        isEmpty,
      );
    },
  );

  test(
    'отсутствие намерения на ревизии старше опубликованной не завершает список',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1], total: 1, revision: 2);
      await pumpEventQueue();

      harness.emitIntentionNotFound(revision: 1);
      await pumpEventQueue();

      expect(harness.active.data.items, [1]);
      expect(harness.list.isTerminated, isFalse);
    },
  );

  test('первая порция старше ревизии, наблюдённой во время чтения, читается '
      'заново', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);

    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    harness.reads.first(0, [1], total: 1, revision: 1);
    await pumpEventQueue();
    expect(harness.state, isA<RelationListInitialLoad<_Part, int>>());
    expect(harness.reads.count, 2);
    expect(harness.reads.cursorAt(1), isNull);

    harness.reads.first(1, [], total: 0, revision: 2);
    await pumpEventQueue();
    expect(
      harness.published.whereType<RelationListConfirmed<_Part, int>>(),
      hasLength(1),
    );
    expect(harness.active.data.items, isEmpty);
    expect(harness.confirmed.summaryStatus, isA<RelationListSummaryCurrent>());
  });

  test('наблюдение не новее известной ревизии не требует новой основы и не '
      'снимает отказ обновления', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);
    harness.reads.first(0, [1], total: 1, revision: 2);
    await pumpEventQueue();

    harness.emitIntention(revision: 2);
    harness.emitIntention(revision: 1);
    await pumpEventQueue();
    expect(harness.reads.count, 1);
    expect(harness.confirmed.summaryStatus, isA<RelationListSummaryCurrent>());

    harness.emitIntention(revision: 4);
    await pumpEventQueue();
    expect(harness.reads.count, 2);
    harness.emitIntention(revision: 3);
    await pumpEventQueue();
    expect(harness.reads.count, 2);

    harness.reads.fail(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();
    harness.emitIntention(revision: 4);
    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    expect(harness.reads.count, 2);
    expect(harness.active.data.items, [1]);
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshFailure>(),
    );
  });

  for (final lateSuccess in [true, false]) {
    test('запоздалый ${lateSuccess ? 'успех' : 'отказ'} подгрузки не снимает '
        'отказ обновления, а повтор доступен только у обновления', () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1, 2], total: 4, revision: 1, next: 2);
      await pumpEventQueue();
      harness.scrollTo(1);
      harness.failIntention(const IntentionUnavailableFailure());
      await pumpEventQueue();

      if (lateSuccess) {
        harness.reads.continuation(1, [3, 4], revision: 1);
      } else {
        harness.reads.fail(1, const RelationGroupUnavailableFailure());
      }
      await pumpEventQueue();
      expect(harness.active.data.items, lateSuccess ? [1, 2, 3, 4] : [1, 2]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryRefreshFailure>(),
      );

      unawaited(harness.list.retryLoadMore(part: _Part.active));
      expect(harness.reads.count, 2);
      unawaited(harness.list.retryRefresh());
      expect(harness.reads.count, 3);
      expect(harness.reads.cursorAt(2), isNull);
      harness.reads.first(2, [1, 2], total: 2, revision: 2);
      await pumpEventQueue();
      expect(harness.active.data.items, [1, 2]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryCurrent>(),
      );
    });
  }

  test('до готовности замены видна прежняя часть, а отказ обновления её '
      'сохраняет', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);
    harness.reads.first(0, [1], total: 1, revision: 1);
    await pumpEventQueue();

    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    expect(harness.active.data.items, [1]);
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );

    harness.reads.fail(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();
    final stale = harness.confirmed;
    expect(stale.parts[_Part.active]!.data.items, [1]);
    expect(stale.counts.activeNeedOutgoing, 1);
    expect(
      stale.summaryStatus,
      isA<RelationListSummaryRefreshFailure>().having(
        (status) => status.canRetry,
        'canRetry',
        isTrue,
      ),
    );

    unawaited(harness.list.retryRefresh());
    unawaited(harness.list.retryRefresh());
    expect(harness.reads.count, 3);
    harness.reads.first(2, [1, 2], total: 2, revision: 2);
    await pumpEventQueue();
    expect(harness.active.data.items, [1, 2]);
    expect(harness.confirmed.summaryStatus, isA<RelationListSummaryCurrent>());
  });

  test(
    'отказ наблюдения до первой порции становится отказом первого чтения',
    () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);

      harness.failIntention(const IntentionUnavailableFailure());
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationListInitialFailure<_Part, int>>()
            .having(
              (state) => state.failure,
              'failure',
              isA<RelationGroupUnavailableFailure>(),
            )
            .having((state) => state.canRetry, 'canRetry', isTrue),
      );
    },
  );

  for (final (name, observation, expected)
      in <(String, IntentionFailure, Matcher)>[
        (
          'недоступность',
          const IntentionUnavailableFailure(),
          isA<RelationGroupUnavailableFailure>(),
        ),
        (
          'повреждение',
          const IntentionCorruptionFailure(),
          isA<RelationGroupCorruptionFailure>(),
        ),
        (
          'непредвиденный сбой',
          const IntentionUnexpectedFailure(),
          isA<RelationGroupUnexpectedFailure>(),
        ),
      ]) {
    test('$name наблюдения намерения сохраняет прежнюю часть с той же '
        'категорией отказа', () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1], total: 1, revision: 1);
      await pumpEventQueue();

      harness.failIntention(observation);
      await pumpEventQueue();

      expect(harness.active.data.items, [1]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryRefreshFailure>().having(
          (status) => status.failure,
          'failure',
          expected,
        ),
      );
    });
  }

  test('повтор первого чтения после перезапуска читает новый запрос', () async {
    final harness = _ListHarness();
    addTearDown(harness.dispose);

    harness.list.restart(harness.query('новый'));
    harness.reads.fail(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();
    unawaited(harness.list.retryFirstPage());

    expect(harness.reads.count, 3);
    expect(harness.reads.listAt(2), 'новый');
    expect(harness.reads.cursorAt(2), isNull);
  });

  for (final (name, fail, failure, canRetry)
      in <(String, void Function(_Reads, int), Matcher, bool)>[
        (
          'недоступность',
          (reads, index) =>
              reads.fail(index, const RelationGroupUnavailableFailure()),
          isA<RelationGroupUnavailableFailure>(),
          true,
        ),
        (
          'повреждение',
          (reads, index) =>
              reads.fail(index, const RelationGroupCorruptionFailure()),
          isA<RelationGroupCorruptionFailure>(),
          false,
        ),
        (
          'исключение источника',
          (reads, index) => reads.throwError(index),
          isA<RelationGroupUnexpectedFailure>(),
          false,
        ),
      ]) {
    test('отказ первого чтения «$name»: повтор '
        '${canRetry ? 'доступен' : 'недоступен'}', () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);

      fail(harness.reads, 0);
      await pumpEventQueue();
      expect(
        harness.state,
        isA<RelationListInitialFailure<_Part, int>>()
            .having((state) => state.failure, 'failure', failure)
            .having((state) => state.canRetry, 'canRetry', canRetry),
      );

      unawaited(harness.list.retryFirstPage());
      unawaited(harness.list.retryFirstPage());
      expect(harness.reads.count, canRetry ? 2 : 1);
      if (!canRetry) return;
      expect(harness.state, isA<RelationListInitialLoad<_Part, int>>());
      harness.reads.first(1, [1], total: 1, revision: 1);
      await pumpEventQueue();
      expect(harness.active.data.items, [1]);
    });

    test('отказ подгрузки «$name» сохраняет строки, а повтор '
        '${canRetry ? 'продолжает список один раз' : 'недоступен'}', () async {
      final harness = _ListHarness();
      addTearDown(harness.dispose);
      harness.reads.first(0, [1, 2], total: 3, revision: 1, next: 2);
      await pumpEventQueue();
      harness.scrollTo(1);

      fail(harness.reads, 1);
      await pumpEventQueue();
      expect(harness.active.data.items, [1, 2]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryCurrent>(),
      );
      expect(
        harness.active.progress,
        isA<RelationListLoadMoreFailure>()
            .having((progress) => progress.failure, 'failure', failure)
            .having((progress) => progress.canRetry, 'canRetry', canRetry),
      );

      unawaited(harness.list.retryLoadMore(part: _Part.active));
      unawaited(harness.list.retryLoadMore(part: _Part.active));
      expect(harness.reads.count, canRetry ? 3 : 2);
      if (!canRetry) return;
      expect(harness.reads.cursorAt(2), const _Cursor(2));
      harness.reads.continuation(2, [3], revision: 1);
      await pumpEventQueue();
      expect(harness.active.data.items, [1, 2, 3]);
      expect(harness.active.data.nextCursor, isNull);
    });
  }

  test(
    'первое чтение публикует части только вместе на одной ревизии',
    () async {
      final harness = _ListHarness(parts: {_Part.active, _Part.archived});
      addTearDown(harness.dispose);
      expect(harness.reads.listAt(0), 'исходный');
      expect(harness.reads.listAt(1), 'исходный архив');

      harness.reads.first(0, [1], total: 1, revision: 1);
      await pumpEventQueue();
      expect(harness.state, isA<RelationListInitialLoad<_Part, int>>());
      harness.reads.first(1, [100], total: 1, revision: 2);
      await pumpEventQueue();
      expect(harness.state, isA<RelationListInitialLoad<_Part, int>>());
      expect(harness.reads.listAt(2), 'исходный');
      expect(harness.reads.listAt(3), 'исходный архив');
      harness.reads.first(2, [1, 2], total: 2, revision: 2);
      harness.reads.first(3, [100], total: 1, revision: 2);
      await pumpEventQueue();

      expect(harness.active.data.items, [1, 2]);
      expect(harness.archived?.data.items, [100]);
      expect(
        harness.published.whereType<RelationListConfirmed<_Part, int>>(),
        hasLength(1),
      );
    },
  );

  test('подгрузка продолжает часть у конца прокрутки, а пересборка повторяет '
      'загруженное каждой частью', () async {
    final harness = _ListHarness(parts: {_Part.active, _Part.archived});
    addTearDown(harness.dispose);
    harness.reads.first(0, [1, 2], total: 3, revision: 1, next: 2);
    harness.reads.first(1, [100, 101], total: 4, revision: 1, next: 2);
    await pumpEventQueue();

    harness.scrollTo(1, part: _Part.archived);
    expect(harness.reads.listAt(2), 'исходный архив');
    expect(harness.reads.cursorAt(2), const _Cursor(2));
    expect(harness.archived?.progress, isA<RelationListLoadingMore>());
    expect(harness.active.progress, isA<RelationListIdle>());
    harness.reads.continuation(2, [102, 103], revision: 1);
    await pumpEventQueue();
    expect(harness.archived?.data.items, [100, 101, 102, 103]);

    harness.emitIntention(revision: 2);
    await pumpEventQueue();
    expect(harness.reads.listAt(3), 'исходный');
    expect(harness.reads.cursorAt(3), isNull);
    expect(harness.reads.listAt(4), 'исходный архив');
    expect(harness.reads.cursorAt(4), isNull);
    harness.reads.first(3, [1, 2], total: 3, revision: 2, next: 2);
    harness.reads.first(4, [100, 101], total: 4, revision: 2, next: 2);
    await pumpEventQueue();
    expect(harness.reads.count, 6);
    expect(harness.reads.listAt(5), 'исходный архив');
    expect(harness.reads.cursorAt(5), const _Cursor(2));
    expect(
      harness.confirmed.summaryStatus,
      isA<RelationListSummaryRefreshing>(),
    );
    harness.reads.continuation(5, [102, 103], revision: 2);
    await pumpEventQueue();

    expect(harness.active.data.items, [1, 2]);
    expect(harness.active.data.nextCursor, const _Cursor(2));
    expect(harness.archived?.data.items, [100, 101, 102, 103]);
    expect(harness.confirmed.summaryStatus, isA<RelationListSummaryCurrent>());
    expect(harness.reads.count, 6);
  });

  test(
    'отказ одной части сохраняет прежнюю пару с отказом обновления',
    () async {
      final harness = _ListHarness(parts: {_Part.active, _Part.archived});
      addTearDown(harness.dispose);
      harness.reads.first(0, [1], total: 1, revision: 1);
      harness.reads.first(1, [100], total: 1, revision: 1);
      await pumpEventQueue();

      harness.emitIntention(revision: 2);
      await pumpEventQueue();
      harness.reads.first(2, [1, 2], total: 2, revision: 2);
      await pumpEventQueue();
      expect(harness.active.data.items, [1]);
      harness.reads.fail(3, const RelationGroupUnavailableFailure());
      await pumpEventQueue();

      expect(harness.active.data.items, [1]);
      expect(harness.archived?.data.items, [100]);
      expect(
        harness.confirmed.summaryStatus,
        isA<RelationListSummaryRefreshFailure>(),
      );
      expect(
        harness.published.whereType<RelationListConfirmed<_Part, int>>().map(
          (state) => state.parts[_Part.active]!.data.items,
        ),
        everyElement([1]),
      );
    },
  );
}

/// Части проверочного списка.
enum _Part { active, archived }

/// Слой над подставными чтением порций и наблюдением намерения. Завершения
/// публикует настоящий координатор над управляемым репозиторием.
final class _ListHarness {
  _ListHarness({
    bool Function(GraphChange, RelationListConfirmed<_Part, int>?)?
    isSignificant,
    Set<_Part> parts = const {_Part.active},
  }) : _isSignificant = isSignificant ?? ((_, _) => false) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    list = RelationListReconciliation<_Part, int, int>(
      intentionId: owner.id,
      watchIntention: (_) => _observations.stream,
      completions: _coordinator.completions,
      policy: RelationGroupPagingPolicy(pageSize: 2, prefetchRemaining: 1),
      query: query('исходный', parts: parts),
      publish: (value) {
        published.add(value);
        state = value;
      },
    );
  }

  final owner = testDetailsIntention();
  final repository = ControlledDetailsRepository();
  final reads = _Reads();
  final published = <RelationListState<_Part, int>>[];
  final bool Function(GraphChange, RelationListConfirmed<_Part, int>?)
  _isSignificant;
  final _observations =
      StreamController<RelationListIntentionObservation>.broadcast();
  late final ProviderContainer container;
  late final RelationListReconciliation<_Part, int, int> list;
  RelationListState<_Part, int> state = const RelationListInitialLoad();

  RelationListConfirmed<_Part, int> get confirmed =>
      state as RelationListConfirmed<_Part, int>;

  RelationListPart<int> get active => confirmed.parts[_Part.active]!;

  RelationListPart<int>? get archived => confirmed.parts[_Part.archived];

  GraphCommandCoordinator get _coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Строки активной части — числа от 1 до 99, архивной — от 100, чужие
  /// строки — отрицательные. Чтения архивной части помечены « архив».
  RelationListQuery<_Part, int, int> query(
    String name, {
    Set<_Part> parts = const {_Part.active},
  }) => RelationListQuery(
    parts: {
      for (final part in parts)
        part: RelationListPartQuery(
          readPage: (cursor, _) => reads.read(switch (part) {
            _Part.active => name,
            _Part.archived => '$name архив',
          }, cursor),
          identify: (row) => switch (part) {
            _Part.active => row > 0 && row < 100 ? row : null,
            _Part.archived => row >= 100 ? row : null,
          },
        ),
    },
    isSignificant: _isSignificant,
  );

  /// Прокрутка не ожидает ответа: порция приходит по команде теста.
  void scrollTo(int visibleIndex, {_Part part = _Part.active}) =>
      unawaited(list.loadMoreIfNeeded(part: part, visibleIndex: visibleIndex));

  void emitIntention({required int revision}) => _observations.add(
    ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(
          intention: owner,
          relationCounts: testRelationCounts(),
        ),
        revision: TestDetailsRevision(revision),
      ),
    ),
  );

  void emitIntentionNotFound({required int revision}) => _observations.add(
    ResultSuccess(
      GraphSnapshot(value: null, revision: TestDetailsRevision(revision)),
    ),
  );

  void failIntention(IntentionFailure failure) =>
      _observations.add(ResultFailure(failure));

  Future<void> completeOwnerDeletion({required int revision}) async {
    final start = _coordinator.acceptExisting(
      DeleteIntention(owner.id),
      presentationTitle: owner.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      repository.commands.length - 1,
      testDetailsDeletedResult(owner, revision: TestDetailsRevision(revision)),
    );
    await start.future;
    await pumpEventQueue();
  }

  Future<void> completeOwnerRename({required int revision}) async {
    final renamed = Intention(
      id: owner.id,
      title: 'Новое название',
      description: owner.description,
      readiness: owner.readiness,
      archiveState: owner.archiveState,
      createdAt: owner.createdAt,
      updatedAt: owner.updatedAt,
    );
    final start = _coordinator.acceptExisting(
      UpdateIntention(
        id: owner.id,
        title: renamed.title,
        description: renamed.description,
      ),
      presentationTitle: owner.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      repository.commands.length - 1,
      testDetailsSavedResult(
        renamed,
        before: owner,
        revision: TestDetailsRevision(revision),
      ),
    );
    await start.future;
    await pumpEventQueue();
  }

  /// Создание тега меняет ревизию графа, но не строки списка.
  Future<void> completeUnrelatedTagChange({required int revision}) async {
    final graphRevision = TestDetailsRevision(revision);
    final tag = Tag(
      id: _tagId(1),
      name: TagName.fromInput('Здоровье'),
      color: null,
      position: tagPositionAt(1000),
    );
    final start = _coordinator.acceptTagCreation(
      TagCreationFormKey(),
      CreateTag(name: tag.name, color: null, placement: TagPlacement.first),
    ) as TagCommandAccepted;
    repository.completeTagCommand(
      repository.tagCommands.length - 1,
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: TagCreated(
            TagCreatedChange(revision: graphRevision, after: tag),
          ),
        ),
      ),
    );
    await start.future;
    await pumpEventQueue();
  }

  void dispose() {
    list.dispose();
    container.dispose();
    unawaited(_observations.close());
  }
}

/// Каждое чтение порции завершается тестом вручную.
final class _Reads {
  final _lists = <String>[];
  final _cursors = <RelationGroupCursor?>[];
  final _requests = <Completer<RelationPagingPageResult<int>>>[];

  int get count => _requests.length;

  String listAt(int index) => _lists[index];

  RelationGroupCursor? cursorAt(int index) => _cursors[index];

  Future<RelationPagingPageResult<int>> read(
    String list,
    RelationGroupCursor? cursor,
  ) {
    _lists.add(list);
    _cursors.add(cursor);
    final request = Completer<RelationPagingPageResult<int>>();
    _requests.add(request);
    return request.future;
  }

  void first(
    int index,
    List<int> items, {
    required int total,
    required int revision,
    int? next,
  }) => _requests[index].complete(
    GraphResultSuccess(
      RelationPagingFirstPage(
        items: items,
        counts: testRelationCounts(activeNeedOutgoing: total),
        totalCount: total,
        revision: TestDetailsRevision(revision),
        nextCursor: next == null ? null : _Cursor(next),
      ),
    ),
  );

  void continuation(
    int index,
    List<int> items, {
    required int revision,
    int? next,
  }) => _requests[index].complete(
    GraphResultSuccess(
      RelationPagingContinuationPage(
        items: items,
        revision: TestDetailsRevision(revision),
        nextCursor: next == null ? null : _Cursor(next),
      ),
    ),
  );

  void fail(int index, RelationGroupReadFailure failure) =>
      _requests[index].complete(GraphResultFailure(failure));

  void throwError(int index) =>
      _requests[index].completeError(StateError('Сбой чтения в тесте.'));
}

final class _Cursor implements RelationGroupCursor {
  const _Cursor(this.offset);

  final int offset;

  @override
  bool operator ==(Object other) => other is _Cursor && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

TagId _tagId(int index) => switch (TagId.decode(
  '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError(
    'Некорректный идентификатор тега в тесте.',
  ),
};
