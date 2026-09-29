import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('пустой снимок отличается от отсутствия намерения', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    expect(h.state, isA<TagAssignmentsInitialLoading>());
    expect(h.reads.queries.single, h.intentionId);
    h.reads.page(0, []);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).isEmpty, isTrue);

    h.model.setIntentionId(_intentionId(2));
    expect(h.state, isA<TagAssignmentsInitialLoading>());
    expect(h.reads.queries.last, _intentionId(2));
    h.reads.fail(1, const TagAssignmentsIntentionNotFound());
    await pumpEventQueue();
    expect(h.state, isA<TagAssignmentsIntentionMissing>());
  });

  test('одно чтение показывает все 150 назначений без усечения', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final tags = [
      for (var index = 1; index <= 150; index++) _tag(index, 'Тег $index'),
    ];
    h.reads.page(0, tags);
    await pumpEventQueue();
    final loaded = h.state as TagAssignmentsLoaded;
    expect(loaded.items, tags);
    expect(h.reads.queries, [h.intentionId]);
    expect(h.model.canActOn(_id(150)), isTrue);
    expect(() => loaded.items.clear(), throwsUnsupportedError);
  });

  test(
    'отказ актуализации сохраняет строки и блокирует действия до повтора',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(2), [
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Дом'),
            after: _tag(1, 'Семья'),
          ),
        ]),
      );
      expect(
        (h.state as TagAssignmentsLoaded).items.single.name.value,
        'Семья',
      );
      expect(h.model.canActOn(_id(1)), isFalse);
      h.reads.fail(1, const TagAssignmentsUnavailableFailure());
      await pumpEventQueue();
      final stale = h.state as TagAssignmentsLoaded;
      expect(stale.items.single.name.value, 'Семья');
      expect(stale.freshness, TagAssignmentsFreshness.stale);
      expect(stale.refreshFailure, isA<TagAssignmentsUnavailableFailure>());
      expect(h.model.canActOn(_id(1)), isFalse);

      final retry = h.model.retryRefresh();
      expect(h.reads.queries, [h.intentionId, h.intentionId, h.intentionId]);
      h.reads.page(2, [_tag(1, 'Семья'), _tag(2, 'Работа')], revision: 2);
      await retry;
      expect((h.state as TagAssignmentsLoaded).items.map((tag) => tag.id), [
        _id(1),
        _id(2),
      ]);
      expect(h.model.canActOn(_id(1)), isTrue);
    },
  );

  test(
    'новый пакет сразу меняет строки и отвергает позднее обновление',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(2), [
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Дом'),
            after: _tag(1, 'Быт'),
          ),
        ]),
      );
      h.changes.add(
        _Package(const _Revision(3), [
          TagRenamedChange(
            revision: const _Revision(3),
            before: _tag(1, 'Быт'),
            after: _tag(1, 'Семья'),
          ),
          TagDeletedChange(revision: const _Revision(3), tagId: _id(2)),
        ]),
      );
      final refreshing = h.state as TagAssignmentsLoaded;
      expect(refreshing.items.map((tag) => tag.name.value), ['Семья']);
      expect(refreshing.freshness, TagAssignmentsFreshness.refreshing);
      expect(h.model.canActOn(_id(1)), isFalse);
      expect(h.reads.queries, hasLength(2));

      h.reads.page(1, [_tag(1, 'Быт'), _tag(2, 'Работа')], revision: 2);
      await pumpEventQueue();
      expect(
        (h.state as TagAssignmentsLoaded).items.map((tag) => tag.name.value),
        ['Семья'],
      );
      expect(h.reads.queries, hasLength(3));
      h.reads.page(2, [_tag(1, 'Семья')], revision: 3);
      await pumpEventQueue();
      expect(h.model.canActOn(_id(1)), isTrue);
    },
  );

  test(
    'более свежий снимок уже включает пакет без повторного чтения',
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
      h.reads.fail(0, const TagAssignmentsIntentionNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsInitialLoading>());
      expect(h.reads.queries, hasLength(2));
      h.reads.page(1, [_tag(1, 'Дом')], revision: 2);
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsLoaded>());
    },
  );

  test(
    'смена намерения не допускает поздний ответ старого поколения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setIntentionId(_intentionId(2));
      expect(h.reads.queries, hasLength(1));
      h.reads.page(0, [_tag(1, 'Старый')]);
      await pumpEventQueue();
      expect(h.reads.queries, [h.intentionId, _intentionId(2)]);
      h.reads.page(1, [_tag(2, 'Новый')], intentionId: _intentionId(2));
      await pumpEventQueue();
      expect((h.state as TagAssignmentsLoaded).items.single.id, _id(2));
    },
  );

  test('устаревший полный ответ повторяется без очистки строк', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.changes.add(
      _Package(const _Revision(2), [
        TagDeletedChange(revision: const _Revision(2), tagId: _id(2)),
      ]),
    );
    h.reads.page(1, [_tag(1, 'Старое имя'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).items.single.name.value, 'Дом');
    expect(h.reads.queries, hasLength(3));
    h.reads.page(2, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    expect(
      (h.state as TagAssignmentsLoaded).freshness,
      TagAssignmentsFreshness.current,
    );
  });

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

  test(
    'явный повтор начального отказа восстанавливает полный список',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.fail(0, const TagAssignmentsUnavailableFailure());
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsInitialFailure>());
      final retry = h.model.retryInitialLoad();
      expect(h.state, isA<TagAssignmentsInitialLoading>());
      h.reads.page(1, [_tag(1, 'Дом')]);
      await retry;
      expect(h.model.canActOn(_id(1)), isTrue);
    },
  );

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

  test('чужой снимок сообщает отказ без бесконечной актуализации', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.changes.add(
      _Package(const _Revision(2), [
        TagDeletedChange(revision: const _Revision(2), tagId: _id(3)),
      ]),
    );
    h.reads.page(
      1,
      [_tag(2, 'Работа')],
      intentionId: _intentionId(2),
      revision: 2,
    );
    await pumpEventQueue();
    final stale = h.state as TagAssignmentsLoaded;
    expect(h.reads.queries, hasLength(2));
    expect(stale.items.single.id, _id(1));
    expect(stale.freshness, TagAssignmentsFreshness.stale);
    expect(stale.refreshFailure, isA<TagAssignmentsUnexpectedFailure>());
    expect(h.model.canActOn(_id(1)), isFalse);
  });

  test('после смены намерения изменения продолжают согласовываться', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setIntentionId(_intentionId(2));
    h.reads.page(0, [_tag(1, 'Прежнее')]);
    await pumpEventQueue();
    h.reads.page(1, [_tag(2, 'Дом')]);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).intentionId, _intentionId(2));

    h.changes.add(
      _Package(const _Revision(2), [
        TagRenamedChange(
          revision: const _Revision(2),
          before: _tag(2, 'Дом'),
          after: _tag(2, 'Быт'),
        ),
      ]),
    );
    expect((h.state as TagAssignmentsLoaded).items.single.name.value, 'Быт');
    expect(h.model.canActOn(_id(2)), isFalse);
    expect(h.reads.queries.last, _intentionId(2));
    h.reads.page(2, [_tag(2, 'Быт')], revision: 2);
    await pumpEventQueue();
    expect(h.model.canActOn(_id(2)), isTrue);
  });

  test('изменения пар различают намерения с общим тегом', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.changes.add(
      _Package(const _Revision(2), [
        TagAssignmentChangedChange(
          revision: const _Revision(2),
          assignment: TagAssignment(
            tagId: _id(1),
            intentionId: _intentionId(2),
          ),
          state: TagAssignmentState.absent,
        ),
      ]),
    );
    expect((h.state as TagAssignmentsLoaded).items.single.id, _id(1));
    h.reads.page(1, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();

    h.changes.add(
      _Package(const _Revision(3), [
        TagAssignmentChangedChange(
          revision: const _Revision(3),
          assignment: TagAssignment(tagId: _id(1), intentionId: h.intentionId),
          state: TagAssignmentState.absent,
        ),
      ]),
    );
    expect((h.state as TagAssignmentsLoaded).items, isEmpty);
    h.reads.page(2, [], revision: 3);
    await pumpEventQueue();
    expect(
      (h.state as TagAssignmentsLoaded).revision.compareTo(const _Revision(3)),
      GraphRevisionOrder.same,
    );

    h.changes.add(
      _Package(const _Revision(4), [
        TagAssignmentChangedChange(
          revision: const _Revision(4),
          assignment: TagAssignment(tagId: _id(2), intentionId: h.intentionId),
          state: TagAssignmentState.assigned,
        ),
      ]),
    );
    h.reads.page(3, [_tag(2, 'Работа')], revision: 4);
    await pumpEventQueue();
    expect((h.state as TagAssignmentsLoaded).items.single.id, _id(2));
    expect(h.model.canActOn(_id(2)), isTrue);
  });

  test(
    'удаление намерения немедленно исключает старые и поздние назначения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(2), [
          TagDeletedChange(revision: const _Revision(2), tagId: _id(3)),
        ]),
      );
      h.changes.add(
        _Package(const _Revision(3), [
          IntentionCatalogDeleted(
            revision: const _Revision(3),
            entry: _Entry(h.intentionId),
          ),
        ]),
      );
      expect(h.state, isA<TagAssignmentsIntentionMissing>());
      expect(h.model.canActOn(_id(1)), isFalse);
      h.reads.page(1, [_tag(1, 'Дом')], revision: 2);
      await pumpEventQueue();
      h.changes.add(
        _Package(const _Revision(4), [
          TagDeletedChange(revision: const _Revision(4), tagId: _id(4)),
        ]),
      );
      await pumpEventQueue();
      expect(h.state, isA<TagAssignmentsIntentionMissing>());
      expect(h.reads.queries, hasLength(2));
    },
  );
}

final class _Entry extends Fake implements IntentionCatalogEntrySnapshot {
  _Entry(IntentionId id)
    : summary = IntentionSummary(
        id: id,
        title: 'Одинаковое намерение',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 0,
        createdAt: IntentionTimestamp(DateTime.utc(2026)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026)),
      );

  @override
  final IntentionSummary summary;
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
      tagAssignmentsViewModelProvider(intentionId),
      (_, _) {},
    );
  }

  final intentionId = _intentionId(1);
  final reads = _Reads();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  late final ProviderContainer container;
  late final ProviderSubscription<TagAssignmentsState> subscription;

  TagAssignmentsViewModel get model =>
      container.read(tagAssignmentsViewModelProvider(intentionId).notifier);
  TagAssignmentsState get state =>
      container.read(tagAssignmentsViewModelProvider(intentionId));

  void dispose() {
    subscription.close();
    container.dispose();
    changes.close();
  }
}

final class _Reads extends Fake implements TagReadContract {
  final queries = <IntentionId>[];
  final pages = <Completer<TagAssignmentsResult>>[];

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) {
    queries.add(intentionId);
    final page = Completer<TagAssignmentsResult>();
    pages.add(page);
    return page.future;
  }

  void page(
    int index,
    List<Tag> tags, {

    int revision = 1,
    int epoch = 0,
    IntentionId? intentionId,
  }) {
    pages[index].complete(
      TagAssignmentsSuccess(
        TagAssignmentsSnapshot(
          intentionId: intentionId ?? queries[index],
          items: tags,

          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TagAssignmentsReadFailure failure) =>
      pages[index].complete(TagAssignmentsError(failure));
}

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

IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
