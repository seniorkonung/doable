import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final relation in [false, true]) {
    final recipient = relation ? 'долговременной связи' : 'намерения';

    test(
      'полный снимок обновляет имя выбранного тега до ответа наблюдения для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();
        final renamed = _rename(harness.selected, 'Имя из нового снимка');

        await harness.completeRefresh(selected: renamed);

        final selection = harness.state.selection as TagCatalogSelectionReady;
        expect(selection.tag.id, harness.selected.id);
        expect(selection.tag.name.value, renamed.name.value);
        expect(harness.state.freshness, TagCatalogFreshness.current);
        expect(
          harness.state.selectedAssignment,
          TagCatalogSelectedAssignment.available,
        );
        expect(harness.model.canActOn(renamed.id), isTrue);
      },
    );

    test(
      'полный снимок снимает выбор исчезнувшего тега до ответа наблюдения для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();

        await harness.completeRefresh(selected: null);

        expect(harness.state.selection, isA<TagCatalogNoSelection>());
        expect(
          harness.state.selectedAssignment,
          TagCatalogSelectedAssignment.unknown,
        );
        expect(
          harness.state.items.any((tag) => tag.id == harness.selected.id),
          isFalse,
        );
        expect(harness.model.canActOn(harness.selected.id), isFalse);
      },
    );

    test(
      'позднее наблюдение старой ревизии не возвращает прежнее имя после полного снимка для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();
        final renamed = _rename(harness.selected, 'Имя из нового снимка');
        await harness.completeRefresh(selected: renamed);

        harness.repository.observation.deliver(harness.selected, revision: 1);
        await _flush();

        final selection = harness.state.selection as TagCatalogSelectionReady;
        expect(selection.tag.id, renamed.id);
        expect(selection.tag.name.value, renamed.name.value);
        expect(harness.state.items.first.name.value, renamed.name.value);
      },
    );

    test(
      'позднее наблюдение старой ревизии не возвращает удалённый выбор после полного снимка для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();
        await harness.completeRefresh(selected: null);

        harness.repository.observation.deliver(
          harness.selected,
          revision: 1,
          afterCancellation: true,
        );
        await _flush();

        expect(harness.state.selection, isA<TagCatalogNoSelection>());
        expect(
          harness.state.selectedAssignment,
          TagCatalogSelectedAssignment.unknown,
        );
        expect(harness.model.canActOn(harness.selected.id), isFalse);
      },
    );

    test(
      'полный снимок сохраняет более новое имя из наблюдения выбранного тега для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();
        final newest = _rename(
          harness.selected,
          'Более новое имя из наблюдения',
        );
        harness.repository.observation.deliver(newest, revision: 3);
        await _flush();

        final renamed = _rename(harness.selected, 'Имя из нового снимка');
        await harness.completeRefresh(selected: renamed);

        final selection = harness.state.selection as TagCatalogSelectionReady;
        expect(selection.tag.id, newest.id);
        expect(selection.tag.name.value, newest.name.value);
        expect(harness.state.items.first.name.value, renamed.name.value);
        expect(
          harness.state.revision.compareTo(const _Revision(2)),
          GraphRevisionOrder.same,
        );
        expect(harness.model.canActOn(newest.id), isTrue);
      },
    );

    test(
      'снимок новой эпохи разрешает последующие ответы наблюдения этой эпохи для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh(revision: 1, epoch: 2);
        final renamed = _rename(harness.selected, 'Имя в новой эпохе');
        await harness.completeRefresh(selected: renamed, revision: 1, epoch: 2);

        expect(
          harness.state.revision.compareTo(const _Revision(1, 2)),
          GraphRevisionOrder.same,
        );
        expect(
          (harness.state.selection as TagCatalogSelectionReady).tag.name.value,
          renamed.name.value,
        );

        final newest = _rename(harness.selected, 'Следующее имя в новой эпохе');
        harness.repository.observation.deliver(newest, revision: 2, epoch: 2);
        await _flush();

        final selection = harness.state.selection as TagCatalogSelectionReady;
        expect(selection.tag.id, newest.id);
        expect(selection.tag.name.value, newest.name.value);
        expect(harness.model.canActOn(newest.id), isTrue);
      },
    );

    test(
      'успешный снимок сохраняет отказ наблюдения и отклоняет старый успех для $recipient',
      () async {
        final harness = await _prepare(relation);
        await harness.startRefresh();
        harness.repository.observation.fail(const TagReadUnavailableFailure());
        await _flush();
        expect(harness.state.selection, isA<TagCatalogSelectionFailure>());

        final renamed = _rename(harness.selected, 'Имя из нового снимка');
        await harness.completeRefresh(selected: renamed);

        final afterRefresh =
            harness.state.selection as TagCatalogSelectionFailure;
        expect(afterRefresh.id, harness.selected.id);
        expect(afterRefresh.failure, isA<TagReadUnavailableFailure>());
        expect(harness.state.freshness, TagCatalogFreshness.current);
        expect(harness.state.items.first.name.value, renamed.name.value);
        expect(harness.model.canActOn(harness.selected.id), isFalse);

        harness.repository.observation.deliver(harness.selected, revision: 1);
        await _flush();

        final afterOldSuccess =
            harness.state.selection as TagCatalogSelectionFailure;
        expect(afterOldSuccess.id, harness.selected.id);
        expect(afterOldSuccess.failure, isA<TagReadUnavailableFailure>());
        expect(harness.model.canActOn(harness.selected.id), isFalse);
      },
    );
  }
}

Future<_Harness> _prepare(bool relation) async {
  final target = relation
      ? LongTermRelationTagTarget(
          (LongTermRelationId.decode(
            _id(200),
          ) as LongTermRelationIdDecodingSuccess).id,
        )
      : IntentionTagTarget(
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id,
        );
  final repository = _Repository();
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  final subscription = container.listen(
    tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target)),
    (_, _) {},
  );
  addTearDown(() {
    subscription.close();
    container.dispose();
  });
  final harness = _Harness(container, repository, target);
  repository.catalogReads.single.complete(
    TagCatalogSuccess(
      TagCatalogSnapshot.selection(
        target: target,
        rows: [
          TagSelectionRow(tag: harness.selected, isAssigned: false),
          TagSelectionRow(tag: harness.other, isAssigned: false),
        ],
        revision: const _Revision(),
      ),
    ),
  );
  await _flush();
  harness.model.selectTag(harness.selected.id);
  expect(harness.state.selection, isA<TagCatalogSelectionReady>());
  return harness;
}

final class _Harness {
  _Harness(this.container, this.repository, this.target);

  final ProviderContainer container;
  final _Repository repository;
  final TagTarget target;
  final selected = _tag(1, 'Прежнее имя');
  final other = _tag(2, 'Другой тег');

  TagCatalogViewModel get model => container.read(
    tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target)).notifier,
  );

  TagCatalogLoaded get state => container.read(
    tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target)),
  ) as TagCatalogLoaded;

  Future<void> startRefresh({int revision = 2, int epoch = 1}) async {
    // Выбранный тег изменяется только в снимке, а не в событии команды.
    final renamedOther = _rename(other, 'Изменённый другой тег');
    repository.commandResult = TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: _Revision(revision, epoch),
        value: TagRenamed(
          TagRenamedChange(
            before: other,
            after: renamedOther,
            revision: _Revision(revision, epoch),
          ),
        ),
      ),
    );
    final start =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptTagRename(
                  RenameTag(tagId: other.id, name: renamedOther.name),
                )
            as TagCommandAccepted;
    await start.future;
    await _flush();
    expect(repository.catalogReads, hasLength(2));
    expect(state.freshness, TagCatalogFreshness.refreshing);
    expect(
      (state.selection as TagCatalogSelectionReady).tag.name,
      selected.name,
    );
  }

  Future<void> completeRefresh({
    required Tag? selected,
    int revision = 2,
    int epoch = 1,
  }) async {
    repository.catalogReads.last.complete(
      TagCatalogSuccess(
        TagCatalogSnapshot.selection(
          target: target,
          rows: [
            if (selected != null)
              TagSelectionRow(tag: selected, isAssigned: false),
            TagSelectionRow(
              tag: _rename(other, 'Изменённый другой тег'),
              isAssigned: false,
            ),
          ],
          revision: _Revision(revision, epoch),
        ),
      ),
    );
    await _flush();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Tag _rename(Tag tag, String name) =>
    Tag(id: tag.id, name: TagName.fromInput(name));

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

final class _Revision implements GraphRevision {
  const _Revision([this.number = 1, this.epoch = 1]);

  final int number;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(epoch: final otherEpoch) when epoch != otherEpoch =>
      GraphRevisionOrder.differentEpoch,
    _Revision(number: final value) when number < value =>
      GraphRevisionOrder.older,
    _Revision(number: final value) when number > value =>
      GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

final class _Repository extends Fake implements PersonalGraphRepository {
  final catalogReads = <Completer<TagCatalogResult>>[];
  final observation = _Observation();
  TagCommandResult? commandResult;

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    final result = Completer<TagCatalogResult>();
    catalogReads.add(result);
    return result.future;
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) => observation;

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    TagTarget target,
  ) => Completer<TagAssignmentStatusResult>().future;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async =>
      commandResult! as GraphCommandResult<TSuccess, TFailure>;
}

final class _Observation extends Stream<TagReadResult> {
  void Function(TagReadResult)? _onData;
  bool cancelled = false;

  void deliver(
    Tag tag, {
    required int revision,
    int epoch = 1,
    bool afterCancellation = false,
  }) {
    if (!cancelled || afterCancellation) {
      _onData?.call(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: _Revision(revision, epoch)),
        ),
      );
    }
  }

  void fail(TagReadFailure failure) {
    if (!cancelled) _onData?.call(TagReadError(failure));
  }

  @override
  StreamSubscription<TagReadResult> listen(
    void Function(TagReadResult)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    return _Subscription(this);
  }
}

final class _Subscription extends Fake
    implements StreamSubscription<TagReadResult> {
  _Subscription(this.observation);

  final _Observation observation;

  @override
  Future<void> cancel() async => observation.cancelled = true;
}
