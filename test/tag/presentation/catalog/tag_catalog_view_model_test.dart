import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'подгрузка запрашивается один раз и повторяет сохранённый курсор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.repository.page(0, [_tag(1, 'Дом')], cursor: cursor);
      await pumpEventQueue();
      final first = h.model.loadMore();
      final duplicate = h.model.loadMore();
      expect(h.repository.queries, hasLength(2));
      expect(h.repository.queries[1].cursor, same(cursor));
      h.repository.fail(1, const TagCatalogUnavailableFailure());
      await Future.wait([first, duplicate]);
      final failed = h.state as TagCatalogLoaded;
      expect(failed.items.map((tag) => tag.id), [_id(1)]);
      expect(failed.nextCursor, same(cursor));
      expect(failed.pageStatus, isA<TagCatalogPageFailure>());
      final retry = h.model.retryLoadMore();
      expect(h.repository.queries[2].cursor, same(cursor));
      h.repository.page(2, [_tag(2, 'Работа')]);
      await retry;
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
        _id(1),
        _id(2),
      ]);
    },
  );

  test('завершение до первой порции отклоняет старый снимок', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.created(_tag(2, 'Работа'), revision: 2);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(2));
    expect(h.state, isA<TagCatalogInitialLoading>());
    h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
      _id(1),
      _id(2),
    ]);
  });

  test('переименование во время подгрузки не возвращает старое имя', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final cursor = _Cursor();
    h.repository.page(0, [_tag(1, 'Дом')], cursor: cursor);
    await pumpEventQueue();
    final pending = h.model.loadMore();
    await h.renamed(_tag(1, 'Дом'), _tag(1, 'Семья'), revision: 2);
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.items.single.name.value, 'Семья');
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    expect(refreshing.canUseCurrentItems, isFalse);
    h.repository.page(1, [_tag(2, 'Работа')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(1, 'Семья'), _tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.name.value), [
      'Семья',
      'Работа',
    ]);
  });

  test(
    'удаление убирает строку и отказ актуализации не повторяет команду',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();
      await h.deleted(_id(1), revision: 2);
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
        _id(2),
      ]);
      h.repository.fail(1, const TagCatalogUnavailableFailure());
      await pumpEventQueue();
      final stale = h.state as TagCatalogLoaded;
      expect(stale.freshness, TagCatalogFreshness.stale);
      expect(stale.canUseCurrentItems, isFalse);
      expect(stale.refreshFailure, isA<TagCatalogUnavailableFailure>());
      final retry = h.model.retryRefresh();
      expect(h.repository.commands, hasLength(1));
      h.repository.page(2, [_tag(2, 'Работа')], revision: 2);
      await retry;
      expect(
        (h.state as TagCatalogLoaded).freshness,
        TagCatalogFreshness.current,
      );
    },
  );

  test('учтённое завершение не запускает повторное чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    await h.created(_tag(1, 'Дом'), revision: 2);
    expect(h.repository.queries, hasLength(1));
    expect(
      (h.state as TagCatalogLoaded).freshness,
      TagCatalogFreshness.current,
    );
  });

  test('новая эпоха отбрасывает позднюю порцию прежней эпохи', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    await h.deleted(_id(1), revision: 1, epoch: 1);
    h.repository.page(1, [_tag(2, 'Работа')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(3, 'Другое')], revision: 1, epoch: 1);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.map((tag) => tag.id), [_id(3)]);
    expect(
      loaded.revision.compareTo(const _Revision(1, 1)),
      GraphRevisionOrder.same,
    );
  });

  test('недопустимое продолжение начинает чтение с первой порции', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.repository.fail(1, const TagCatalogInvalidCursor());
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
      _id(1),
      _id(2),
    ]);
  });

  test(
    'повторяющийся старый снимок заканчивается явным отказом чтения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.created(_tag(2, 'Работа'), revision: 2);
      for (var index = 0; index < 8; index++) {
        h.repository.page(index, [_tag(1, 'Дом')]);
        await pumpEventQueue();
      }
      expect(h.repository.queries, hasLength(8));
      expect(h.state, isA<TagCatalogInitialFailure>());
      expect(
        (h.state as TagCatalogInitialFailure).failure,
        isA<TagCatalogUnavailableFailure>(),
      );
    },
  );
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(tagCatalogViewModelProvider, (_, _) {});
  }

  final repository = _Repository();
  late final ProviderContainer container;
  late final ProviderSubscription<TagCatalogState> subscription;
  TagCatalogViewModel get model =>
      container.read(tagCatalogViewModelProvider.notifier);
  TagCatalogState get state => container.read(tagCatalogViewModelProvider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<void> created(Tag tag, {required int revision}) async {
    final accepted = coordinator.acceptTagCreation(
      TagCreationFormKey(),
      CreateTag(tag.name),
    ) as TagCommandAccepted;
    final r = _Revision(revision);
    repository.completeCommand(
      TagCreated(TagCreatedChange(revision: r, after: tag)),
      r,
    );
    await accepted.future;
  }

  Future<void> renamed(Tag before, Tag after, {required int revision}) async {
    final accepted = coordinator.acceptTagRename(
      RenameTag(tagId: before.id, name: after.name),
    ) as TagCommandAccepted;
    final r = _Revision(revision);
    repository.completeCommand(
      TagRenamed(TagRenamedChange(revision: r, before: before, after: after)),
      r,
    );
    await accepted.future;
  }

  Future<void> deleted(TagId id, {required int revision, int epoch = 0}) async {
    final accepted =
        coordinator.acceptTagDelete(DeleteTag(id)) as TagCommandAccepted;
    final r = _Revision(revision, epoch);
    repository.completeCommand(
      TagDeleted(TagDeletedChange(revision: r, tagId: id)),
      r,
    );
    await accepted.future;
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository extends Fake implements PersonalGraphRepository {
  final queries = <TagCatalogQuery>[];
  final pages = <Completer<TagCatalogPageResult>>[];
  final commands = <Completer<TagCommandResult>>[];

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    queries.add(query);
    final completer = Completer<TagCatalogPageResult>();
    pages.add(completer);
    return completer.future;
  }

  void page(
    int index,
    List<Tag> tags, {
    TagCatalogCursor? cursor,
    int revision = 1,
    int epoch = 0,
  }) {
    pages[index].complete(
      TagCatalogPageSuccess(
        TagCatalogPage(
          items: tags,
          pageSize: TagCatalogQuery.defaultPageSize,
          nextCursor: cursor,
          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TagCatalogReadFailure failure) =>
      pages[index].complete(TagCatalogPageError(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final completer = Completer<TagCommandResult>();
    commands.add(completer);
    return await completer.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeCommand(TagCommandSuccess success, _Revision revision) {
    commands.last.complete(
      TagCommandSucceeded(
        ConfirmedGraphResult(revision: revision, value: success),
      ),
    );
  }
}

final class _Cursor implements TagCatalogCursor {}

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

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
