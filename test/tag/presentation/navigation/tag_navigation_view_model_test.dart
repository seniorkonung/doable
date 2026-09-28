import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'вход выбирает активный охват и отличает пустоту от отсутствия тега',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.state.tagId, _tagId(1));
      expect(h.state.scope, TaggedEntitiesScope.active);
      expect(h.reads.queries.single.cursor, isNull);
      expect(h.reads.queries.single.pageSize, 50);

      h.reads.page(0, []);
      await pumpEventQueue();
      final empty = h.state as TagNavigationLoaded;
      expect(empty.tag.name.value, 'Дом');
      expect(empty.isEmpty, isTrue);
      expect(empty.hasReachedEnd, isTrue);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(1));

      h.model.setScope(TaggedEntitiesScope.archived);
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.state.scope, TaggedEntitiesScope.archived);
      h.reads.fail(1, const TaggedEntitiesTagNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationTagMissing>());
      expect(h.state.tagId, _tagId(1));
      expect(h.state.scope, TaggedEntitiesScope.archived);
    },
  );

  test(
    'подгрузка сохраняет смешанный порядок и выполняется один раз',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.reads.page(0, [_intention(1), _relation(1)], cursor: cursor);
      await pumpEventQueue();
      final base = h.state as TagNavigationLoaded;
      expect(base.isEmpty, isFalse);
      expect(base.hasReachedEnd, isFalse);

      final pending = h.model.loadMore();
      expect(h.model.loadMore(), same(pending));
      expect(h.reads.queries, hasLength(2));
      expect(h.reads.queries[1].cursor, same(cursor));
      expect(
        (h.state as TagNavigationLoaded).pageStatus,
        isA<TagNavigationPageLoading>(),
      );
      h.reads.page(1, [_relation(2), _intention(2)]);
      await pending;

      final loaded = h.state as TagNavigationLoaded;
      expect(loaded.items.map((item) => item.target), [
        _intention(1).target,
        _relation(1).target,
        _relation(2).target,
        _intention(2).target,
      ]);
      expect(loaded.hasReachedEnd, isTrue);
      expect(loaded.pageStatus, isA<TagNavigationPageIdle>());
      expect(() => loaded.items.clear(), throwsUnsupportedError);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(2));
    },
  );

  test(
    'повтор временного отказа продолжает тот же снимок без повторов строк',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.reads.page(0, [_intention(1)], cursor: cursor);
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.fail(1, const TaggedEntitiesUnavailableFailure());
      await pending;
      final failed = h.state as TagNavigationLoaded;
      expect(failed.items.single.target, _intention(1).target);
      expect(failed.nextCursor, same(cursor));
      expect((failed.pageStatus as TagNavigationPageFailure).canRetry, isTrue);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(2));

      final retry = h.model.retryLoadMore();
      expect(h.reads.queries[2].cursor, same(cursor));
      expect(h.model.retryLoadMore(), same(retry));
      expect(h.reads.queries, hasLength(3));
      h.reads.page(2, [_relation(1)]);
      await retry;
      expect((h.state as TagNavigationLoaded).items, hasLength(2));
    },
  );

  test('смена охвата очищает список и отвергает позднее продолжение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.model.setScope(TaggedEntitiesScope.archived);
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_intention(2)]);
    await pending;
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries[2].scope, TaggedEntitiesScope.archived);
    expect(h.reads.queries[2].cursor, isNull);
    h.reads.page(2, [_relation(2, archived: true)]);
    await pumpEventQueue();
    expect(
      (h.state as TagNavigationLoaded).items.single.target,
      _relation(2).target,
    );
  });

  test(
    'быстрые смены тега и охвата ждут запрос и читают только последний выбор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setTagId(_tagId(2));
      h.model.setScope(TaggedEntitiesScope.archived);
      h.model.setTagId(_tagId(3));
      expect(h.reads.queries, hasLength(1));
      h.reads.fail(0, const TaggedEntitiesTagNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.reads.queries, hasLength(2));
      expect(h.reads.queries[1].tagId, _tagId(3));
      expect(h.reads.queries[1].scope, TaggedEntitiesScope.archived);
      h.reads.page(1, [_intention(3, archived: true)]);
      await pumpEventQueue();
      expect(h.state.tagId, _tagId(3));
      expect(
        (h.state as TagNavigationLoaded).items.single.target,
        _intention(3).target,
      );
    },
  );

  test('ошибка нового тега не показывает список прежнего выбора', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    h.model.setTagId(_tagId(2));
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.state.tagId, _tagId(2));
    h.reads.fail(1, const TaggedEntitiesUnavailableFailure());
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationInitialFailure>());
    expect(h.state.tagId, _tagId(2));
    final retry = h.model.retryFirstPage();
    expect(h.model.retryFirstPage(), same(retry));
    expect(h.reads.queries, hasLength(3));
    expect(h.reads.queries[2].tagId, _tagId(2));
    expect(h.reads.queries[2].cursor, isNull);
    h.reads.page(2, [_intention(2)]);
    await retry;
    expect(
      (h.state as TagNavigationLoaded).items.single.target,
      _intention(2).target,
    );
  });

  test('возврат к прежнему охвату всё равно создаёт новое поколение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setScope(TaggedEntitiesScope.archived);
    h.model.setScope(TaggedEntitiesScope.active);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_intention(2)]);
    await pumpEventQueue();
    expect(
      (h.state as TagNavigationLoaded).items.single.target,
      _intention(2).target,
    );
  });

  test('повтор неизменного выбора не начинает новое чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setTagId(_tagId(1));
    h.model.setScope(TaggedEntitiesScope.active);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    final loaded = h.state;
    h.model.setTagId(_tagId(1));
    h.model.setScope(TaggedEntitiesScope.active);
    expect(h.state, same(loaded));
    expect(h.reads.queries, hasLength(1));
  });

  test('смена тега из обработчика нового охвата не повторяет уже запущенное чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    final listener = h.container.listen(
      tagNavigationViewModelProvider(_tagId(1)),
      (_, next) {
        if (next is TagNavigationInitialLoading &&
            next.scope == TaggedEntitiesScope.archived &&
            next.tagId == _tagId(1)) {
          h.model.setTagId(_tagId(2));
        }
      },
    );
    addTearDown(listener.close);
    h.model.setScope(TaggedEntitiesScope.archived);
    expect(h.reads.queries, hasLength(2));
    expect(h.reads.queries.last.tagId, _tagId(2));
    h.reads.page(1, [_intention(2, archived: true)]);
    await pumpEventQueue();
    expect(h.state.tagId, _tagId(2));
    expect(h.state, isA<TagNavigationLoaded>());
    expect(h.reads.queries, hasLength(2));
  });

  const failures = [
    (
      failure: TaggedEntitiesInvalidCursor(),
      category: GraphFailureCategory.validation,
    ),
    (
      failure: TaggedEntitiesSnapshotExpired(),
      category: GraphFailureCategory.conflict,
    ),
    (
      failure: TaggedEntitiesUnavailableFailure(),
      category: GraphFailureCategory.unavailable,
    ),
    (
      failure: TaggedEntitiesCorruptionFailure(),
      category: GraphFailureCategory.corruption,
    ),
    (
      failure: TaggedEntitiesUnexpectedFailure(),
      category: GraphFailureCategory.unexpected,
    ),
  ];
  for (final (:failure, :category) in failures) {
    test(
      'первый отказ категории $category различим и повторяется только при недоступности',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.fail(0, failure);
        await pumpEventQueue();
        final failed = h.state as TagNavigationInitialFailure;
        expect(failed.failure, same(failure));
        expect(failed.failure.category, category);
        expect(failed.canRetry, category == GraphFailureCategory.unavailable);
        await h.model.loadMore();
        await h.model.retryLoadMore();
        expect(h.reads.queries, hasLength(1));
        final retry = h.model.retryFirstPage();
        if (failed.canRetry) {
          expect(h.state, isA<TagNavigationInitialLoading>());
          expect(h.reads.queries, hasLength(2));
          expect(h.reads.queries.last.cursor, isNull);
          h.reads.page(1, []);
          await retry;
          expect(h.state, isA<TagNavigationLoaded>());
        } else {
          await retry;
          expect(h.state, same(failed));
          expect(h.reads.queries, hasLength(1));
        }
      },
    );

    test(
      'отказ продолжения категории $category сохраняет строки и безопасный статус',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        final cursor = _Cursor();
        h.reads.page(0, [_intention(1)], cursor: cursor);
        await pumpEventQueue();
        final pending = h.model.loadMore();
        h.reads.fail(1, failure);
        await pending;
        final failed = h.state as TagNavigationLoaded;
        final status = failed.pageStatus as TagNavigationPageFailure;
        expect(failed.items.single.target, _intention(1).target);
        expect(failed.hasReachedEnd, isFalse);
        expect(status.failure, same(failure));
        expect(status.failure.category, category);
        expect(status.canRetry, category == GraphFailureCategory.unavailable);
        expect(failed.nextCursor, status.canRetry ? same(cursor) : isNull);
        await h.model.loadMore();
        await h.model.retryFirstPage();
        expect(h.reads.queries, hasLength(2));
        if (!status.canRetry) {
          await h.model.retryLoadMore();
          expect(h.state, same(failed));
          expect(h.reads.queries, hasLength(2));
        }
      },
    );
  }

  test('отсутствие тега в продолжении убирает все прежние строки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.reads.fail(1, const TaggedEntitiesTagNotFound());
    await pending;
    expect(h.state, isA<TagNavigationTagMissing>());
    await h.model.loadMore();
    await h.model.retryFirstPage();
    await h.model.retryLoadMore();
    expect(h.reads.queries, hasLength(2));
  });

  for (final continuation in [false, true]) {
    test(
      'исключение чтения ${continuation ? 'продолжения' : 'первой порции'} скрывает исходную причину',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (continuation) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
          unawaited(h.model.loadMore());
        }
        h.reads.pending.last.completeError(StateError('SQL и личные данные'));
        await pumpEventQueue();
        final failure = switch (h.state) {
          TagNavigationInitialFailure(:final failure) => failure,
          TagNavigationLoaded(
            pageStatus: TagNavigationPageFailure(:final failure),
          ) =>
            failure,
          _ => fail('Ожидался типизированный отказ'),
        };
        expect(failure, isA<TaggedEntitiesUnexpectedFailure>());
        await h.model.retryFirstPage();
        await h.model.retryLoadMore();
        expect(h.reads.queries, hasLength(continuation ? 2 : 1));
      },
    );

    test(
      'после освобождения ${continuation ? 'подгрузка' : 'первое чтение'} и обработчики не публикуют состояние',
      () async {
        final h = _Harness();
        if (continuation) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
          unawaited(h.model.loadMore());
        }
        h.model.setScope(TaggedEntitiesScope.archived);
        final queryCount = h.reads.queries.length;
        final stateCount = h.states.length;
        h.dispose();
        h.model.setTagId(_tagId(2));
        h.model.setScope(TaggedEntitiesScope.active);
        await h.model.loadMore();
        await h.model.retryFirstPage();
        await h.model.retryLoadMore();
        h.reads.page(queryCount - 1, [_intention(2)]);
        await pumpEventQueue();
        expect(h.states, hasLength(stateCount));
        expect(h.reads.queries, hasLength(queryCount));
      },
    );
  }

  final invalidPages = <String, void Function(_Reads)>{
    'чужой тег': (reads) => reads.page(
      0,
      [],
      tag: Tag(id: _tagId(2), name: TagName.fromInput('Дом')),
    ),
    'чужой охват': (reads) =>
        reads.page(0, [], scope: TaggedEntitiesScope.archived),
    'другой размер': (reads) => reads.page(0, [], pageSize: 49),
    'повторение получателя': (reads) =>
        reads.page(0, [_intention(1), _intention(1)]),
  };
  for (final entry in invalidPages.entries) {
    test('несогласованная первая порция: ${entry.key}', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      entry.value(h.reads);
      await pumpEventQueue();
      final failed = h.state as TagNavigationInitialFailure;
      expect(failed.failure, isA<TaggedEntitiesUnexpectedFailure>());
      expect(failed.canRetry, isFalse);
    });
  }

  for (final revision in [
    const _Revision(0),
    const _Revision(2),
    const _Revision(1, 1),
  ]) {
    test(
      'продолжение другого снимка ${revision.value}/${revision.epoch} не смешивает строки',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        final pending = h.model.loadMore();
        h.reads.page(
          1,
          [_relation(1)],
          revision: revision.value,
          epoch: revision.epoch,
        );
        await pending;
        final failed = h.state as TagNavigationLoaded;
        expect(failed.items.single.target, _intention(1).target);
        expect(failed.nextCursor, isNull);
        expect(
          (failed.pageStatus as TagNavigationPageFailure).failure,
          isA<TaggedEntitiesSnapshotExpired>(),
        );
      },
    );
  }

  test('повтор получателя в продолжении не создаёт повторных строк', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.reads.page(1, [_relation(1), _intention(1)]);
    await pending;
    final failed = h.state as TagNavigationLoaded;
    expect(failed.items, hasLength(1));
    final status = failed.pageStatus as TagNavigationPageFailure;
    expect(status.failure, isA<TaggedEntitiesUnexpectedFailure>());
    expect(status.canRetry, isFalse);
  });
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [tagNavigationReaderProvider.overrideWithValue(reads)],
    );
    subscription = container.listen(
      tagNavigationViewModelProvider(_tagId(1)),
      (_, value) => states.add(value),
      fireImmediately: true,
    );
    model = container.read(tagNavigationViewModelProvider(_tagId(1)).notifier);
  }

  final reads = _Reads();
  final states = <TagNavigationState>[];
  late final ProviderContainer container;
  late final ProviderSubscription<TagNavigationState> subscription;
  late final TagNavigationViewModel model;
  TagNavigationState get state => subscription.read();
  void dispose() => container.dispose();
}

final class _Reads with TagReadContractTestFallback implements TagReadContract {
  final queries = <TaggedEntitiesQuery>[];
  final pending = <Completer<TaggedEntitiesPageResult>>[];

  @override
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) {
    queries.add(query);
    final result = Completer<TaggedEntitiesPageResult>();
    pending.add(result);
    return result.future;
  }

  void page(
    int index,
    List<TaggedEntity> items, {
    TaggedEntitiesCursor? cursor,
    Tag? tag,
    TaggedEntitiesScope? scope,
    int? pageSize,
    int revision = 1,
    int epoch = 0,
  }) {
    final query = queries[index];
    pending[index].complete(
      TaggedEntitiesPageSuccess(
        TaggedEntitiesPage(
          tag: tag ?? Tag(id: query.tagId, name: TagName.fromInput('Дом')),
          scope: scope ?? query.scope,
          items: items,
          pageSize: pageSize ?? query.pageSize,
          nextCursor: cursor,
          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TaggedEntitiesReadFailure failure) =>
      pending[index].complete(TaggedEntitiesPageError(failure));
}

final class _Cursor implements TaggedEntitiesCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value, [this.epoch = 0]);
  final int value;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision || epoch != other.epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    return value < other.value
        ? GraphRevisionOrder.older
        : value > other.value
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

TagId _tagId(int n) => (TagId.decode(
  '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

TaggedIntention _intention(int n, {bool archived = false}) => TaggedIntention(
  id: (IntentionId.decode(
    '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  ) as IntentionIdDecodingSuccess).id,
  title: 'Намерение $n',
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
);

TaggedLongTermRelation _relation(int n, {bool archived = false}) =>
    TaggedLongTermRelation(
      id: (LongTermRelationId.decode(
        '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
      ) as LongTermRelationIdDecodingSuccess).id,
      type: LongTermRelationType.need,
      sourceTitle: 'Исходное намерение $n',
      relatedTitle: 'Связанное намерение $n',
      scope: archived ? RelationScope.archived : RelationScope.active,
    );
