import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('пустой снимок отличается от отсутствия получателя', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    expect(h.state, isA<TagAssignmentsInitialLoading>());
    expect(h.reads.queries.single.target, h.target);
    h.reads.page(0, []);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).isEmpty, isTrue);

    h.model.setTarget(_target(2));
    expect(h.state, isA<TagAssignmentsInitialLoading>());
    expect(h.reads.queries.last.target, _target(2));
    h.reads.fail(1, const TagAssignmentsTargetNotFound());
    await pumpEventQueue();
    expect(h.state, isA<TagAssignmentsTargetMissing>());
  });

  test('ошибка продолжения сохраняет строки и курсор для повтора', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final cursor = _Cursor();
    h.reads.page(0, [_tag(1, 'Дом')], cursor: cursor);
    await pumpEventQueue();

    final pending = h.model.loadMore();
    expect(h.reads.queries[1].cursor, same(cursor));
    expect(h.model.loadMore(), same(pending));
    expect(h.reads.queries, hasLength(2));
    h.reads.fail(1, const TagAssignmentsUnavailableFailure());
    await pending;
    final loaded = h.state as TagAssignmentsLoaded;
    expect(loaded.items.map((tag) => tag.id), [_id(1)]);
    expect(loaded.nextCursor, same(cursor));
    expect(loaded.pageStatus, isA<TagAssignmentsPageFailure>());
    expect(h.model.canActOn(_id(1)), isTrue);

    final retry = h.model.retryLoadMore();
    expect(h.reads.queries[2].cursor, same(cursor));
    h.reads.page(2, [_tag(2, 'Работа')]);
    await retry;
    expect((h.state as TagAssignmentsLoaded).items.map((tag) => tag.id), [
      _id(1),
      _id(2),
    ]);
  });

  test(
    'пакет сразу меняет известные строки и отвергает позднее продолжение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')], cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.changes.add(
        _Package(_Revision(2), [
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Дом'),
            after: _tag(1, 'Семья'),
          ),
          TagDeletedChange(revision: const _Revision(2), tagId: _id(2)),
        ]),
      );
      await pumpEventQueue();
      final refreshing = h.state as TagAssignmentsLoaded;
      expect(refreshing.items.map((tag) => tag.name.value), ['Семья']);
      expect(refreshing.freshness, TagAssignmentsFreshness.refreshing);
      expect(refreshing.nextCursor, isNull);
      expect(h.model.canActOn(_id(1)), isFalse);
      h.reads.page(1, [_tag(3, 'Поздний')]);
      await pending;
      expect(h.reads.queries[2].cursor, isNull);
      h.reads.page(2, [_tag(1, 'Семья')], revision: 2);
      await pumpEventQueue();
      expect(
        (h.state as TagAssignmentsLoaded).items.single.name.value,
        'Семья',
      );
      expect(h.model.canActOn(_id(1)), isTrue);
    },
  );

  test(
    'более свежая страница уже включает пакет без повторного чтения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Новое')], revision: 2);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(2), [
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Старое'),
            after: _tag(1, 'Новое'),
          ),
        ]),
      );
      await pumpEventQueue();
      expect(
        (h.state as TagAssignmentsLoaded).items.single.name.value,
        'Новое',
      );
      expect(h.reads.queries, hasLength(1));
    },
  );

  test(
    'отказ начального чтения после пакета не скрывает актуализацию',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.changes.add(
        _Package(const _Revision(2), [
          TagDeletedChange(revision: const _Revision(2), tagId: _id(3)),
        ]),
      );
      h.reads.fail(0, const TagAssignmentsTargetNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsInitialLoading>());
      expect(h.reads.queries, hasLength(2));
      h.reads.page(1, [_tag(1, 'Дом')], revision: 2);
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsLoaded>());
    },
  );

  test(
    'смена получателя не допускает поздний ответ старого поколения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setTarget(_target(2));
      expect(h.reads.queries, hasLength(1));
      h.reads.page(0, [_tag(1, 'Старый')]);
      await pumpEventQueue();
      expect(h.reads.queries, hasLength(2));
      expect(h.reads.queries.last.target, _target(2));
      h.reads.page(1, [_tag(2, 'Новый')], target: _target(2));
      await pumpEventQueue();
      expect((h.state as TagAssignmentsLoaded).items.single.id, _id(2));
    },
  );

  test(
    'отказ актуализации оставляет прежние строки явно устаревшими',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(2), [
          TagDeletedChange(revision: const _Revision(2), tagId: _id(2)),
        ]),
      );
      await pumpEventQueue();
      h.reads.fail(1, const TagAssignmentsUnavailableFailure());
      await pumpEventQueue();
      final stale = h.state as TagAssignmentsLoaded;
      expect(stale.items.single.id, _id(1));
      expect(stale.freshness, TagAssignmentsFreshness.stale);
      expect(stale.refreshFailure, isA<TagAssignmentsUnavailableFailure>());
      expect(h.model.canActOn(_id(1)), isFalse);
      final retry = h.model.retryRefresh();
      h.reads.page(2, [_tag(1, 'Дом')], revision: 2);
      await retry;
      expect(
        (h.state as TagAssignmentsLoaded).freshness,
        TagAssignmentsFreshness.current,
      );
    },
  );

  test(
    'устаревшее продолжение начинает новый снимок без старого курсора',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.fail(1, const TagAssignmentsSnapshotExpired());
      await pending;
      expect((h.state as TagAssignmentsLoaded).nextCursor, isNull);
      expect(h.reads.queries[2].cursor, isNull);
      h.reads.page(2, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();
      expect((h.state as TagAssignmentsLoaded).items.map((tag) => tag.id), [
        _id(1),
        _id(2),
      ]);
    },
  );

  test('смена эпохи отбрасывает ответ прежней эпохи', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.changes.add(
      _Package(const _Revision(1, 1), [
        TagDeletedChange(revision: const _Revision(1, 1), tagId: _id(2)),
      ]),
    );
    h.reads.page(0, [_tag(2, 'Старый')]);
    await pumpEventQueue();
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_tag(1, 'Новый')], epoch: 1);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).items.single.id, _id(1));
  });

  test('новая ревизия переводит отказ первого чтения в загрузку', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.fail(0, const TagAssignmentsUnavailableFailure());
    await pumpEventQueue();
    expect(h.state, isA<TagAssignmentsInitialFailure>());
    h.changes.add(
      _Package(const _Revision(2), [
        TagDeletedChange(revision: const _Revision(2), tagId: _id(3)),
      ]),
    );
    expect(h.state, isA<TagAssignmentsInitialLoading>());
    h.reads.page(1, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    expect(h.state, isA<TagAssignmentsLoaded>());
  });

  test('чужая порция сообщает отказ без бесконечной актуализации', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.reads.page(1, [_tag(2, 'Работа')], target: _target(2));
    await pending;
    expect(h.reads.queries, hasLength(2));
    expect(
      (h.state as TagAssignmentsLoaded).pageStatus,
      isA<TagAssignmentsPageFailure>().having(
        (value) => value.failure,
        'причина',
        isA<TagAssignmentsUnexpectedFailure>(),
      ),
    );
  });
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        tagAssignmentsReaderProvider.overrideWithValue(reads),
        tagAssignmentsChangesProvider.overrideWithValue(changes.stream),
      ],
    );
    subscription = container.listen(
      tagAssignmentsViewModelProvider(target),
      (_, _) {},
    );
  }

  final target = _target(1);
  final reads = _Reads();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  late final ProviderContainer container;
  late final ProviderSubscription<TagAssignmentsState> subscription;

  TagAssignmentsViewModel get model =>
      container.read(tagAssignmentsViewModelProvider(target).notifier);
  TagAssignmentsState get state =>
      container.read(tagAssignmentsViewModelProvider(target));

  void dispose() {
    subscription.close();
    container.dispose();
    changes.close();
  }
}

final class _Reads extends Fake implements TagReadContract {
  final queries = <TagAssignmentsQuery>[];
  final pages = <Completer<TagAssignmentsPageResult>>[];

  @override
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) {
    queries.add(query);
    final page = Completer<TagAssignmentsPageResult>();
    pages.add(page);
    return page.future;
  }

  void page(
    int index,
    List<Tag> tags, {
    TagAssignmentsCursor? cursor,
    int revision = 1,
    int epoch = 0,
    TagTarget? target,
  }) {
    pages[index].complete(
      TagAssignmentsPageSuccess(
        TagAssignmentsPage(
          target: target ?? queries[index].target,
          items: tags,
          pageSize: queries[index].pageSize,
          nextCursor: cursor,
          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TagAssignmentsReadFailure failure) =>
      pages[index].complete(TagAssignmentsPageError(failure));
}

final class _Cursor implements TagAssignmentsCursor {}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);
  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

final class _Revision implements GraphRevision {
  const _Revision(this.number, [this.epoch = 0]);
  final int number;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(epoch: final e) when e != epoch =>
      GraphRevisionOrder.differentEpoch,
    _Revision(number: final n) when number < n => GraphRevisionOrder.older,
    _Revision(number: final n) when number > n => GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

TagTarget _target(int number) => IntentionTagTarget(
  (IntentionId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as IntentionIdDecodingSuccess).id,
);
TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
