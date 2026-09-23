import 'dart:async';

import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';

void main() {
  test('выбор сохраняется между всеми группами и заменой порций', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final selected = <LongTermRelationSummary>[];
    var index = 1;
    for (final scope in RelationScope.values) {
      for (final type in LongTermRelationType.values) {
        for (final direction in RelationDirection.values) {
          final page = testGroupRows(
            ownerId: harness.intentionId,
            from: index,
            count: 2,
            scope: scope,
            type: type,
            direction: direction,
            neighborTitles: {index: 'Одинаковое', index + 1: 'Одинаковое'},
          );
          expect(harness.viewModel.select(page.first), isTrue);
          selected.add(page.first);
          index += 2;
        }
      }
    }

    expect(harness.state.intentionId, harness.intentionId);
    expect(harness.state.selected.length, 8);
    expect(
      harness.state.selected.keys,
      containsAll(selected.map((row) => row.relation.id)),
    );
    expect(harness.viewModel.select(selected.first), isFalse);
    expect(harness.state.selected.length, 8);
    expect(
      harness.state.selected[selected.first.relation.id],
      same(selected.first),
    );
    expect(harness.viewModel.unselect(selected[1].relation.id), isTrue);
    expect(harness.state.selected.length, 7);
    expect(
      harness.state.selected.containsKey(selected.first.relation.id),
      isTrue,
    );
    expect(harness.viewModel.unselect(selected[1].relation.id), isFalse);

    final otherOwner = testIntentionId(80);
    final unrelated = testGroupRow(ownerId: otherOwner, index: 90);
    expect(harness.viewModel.select(unrelated), isFalse);
    expect(harness.state.selected.length, 7);
  });

  test('подтверждение фиксирует отдельный набор, а отмена не пишет', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final page = testGroupRows(ownerId: harness.intentionId, from: 1, count: 2);
    expect(harness.viewModel.prepare(), isFalse);
    harness.viewModel.select(page.first);
    expect(harness.viewModel.prepare(), isTrue);
    final prepared =
        (harness.state as BlockingRelationsSelectionPrepared).snapshot;
    expect(prepared.command.relationIds, {page.first.relation.id});
    expect(() => prepared.command.relationIds.clear(), throwsUnsupportedError);
    final firstId = page.first.relation.id;
    page.clear();
    expect(prepared.rows.single.relation.id, firstId);
    harness.viewModel.cancel();
    expect(harness.state, isA<BlockingRelationsSelectionEditing>());
    expect(harness.repository.commands, isEmpty);

    final laterPage = testGroupRows(
      ownerId: harness.intentionId,
      from: 2,
      count: 1,
    );
    harness.viewModel.select(laterPage.single);
    expect(prepared.command.relationIds, {firstId});
    expect(harness.viewModel.prepare(), isTrue);
    final next = (harness.state as BlockingRelationsSelectionPrepared).snapshot;
    expect(next.command.relationIds, {firstId, laterPage.single.relation.id});
    expect(prepared.rows.single.relation.id, firstId);
  });

  test('принятая команда выполняется один раз после закрытия сессии', () async {
    final harness = _Harness();
    final row = testGroupRow(ownerId: harness.intentionId, index: 1);
    harness.viewModel.select(row);
    harness.viewModel.prepare();
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.state, isA<BlockingRelationsSelectionRunning>());
    expect(harness.repository.commands, hasLength(1));
    expect(
      (harness.repository.commands.single as DeleteBlockingRelations)
          .relationIds,
      {row.relation.id},
    );

    harness.dispose();
    harness.repository.fail(
      0,
      const DeleteBlockingRelationsUnavailableFailure(),
    );
    await pumpEventQueue();
    expect(harness.repository.commands, hasLength(1));
  });

  test(
    'отказ сохраняет выбор, а конфликт запрещает повтор старого подтверждения',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final row = testGroupRow(ownerId: harness.intentionId, index: 1);
      harness.viewModel.select(row);
      harness.viewModel.prepare();
      harness.viewModel.confirm(presentationTitle: 'Намерение');
      harness.repository.fail(
        0,
        DeleteBlockingRelationsSelectionConflictFailure(
          relationId: row.relation.id,
          reason: BlockingRelationConflictReason.relationMissing,
        ),
      );
      await pumpEventQueue();

      final failed = harness.state as BlockingRelationsSelectionFailed;
      expect(failed.selected.keys, {row.relation.id});
      expect(failed.requiresRefresh, isTrue);
      harness.viewModel.confirm(presentationTitle: 'Намерение');
      expect(harness.repository.commands, hasLength(1));
      harness.viewModel.resumeEditing();
      expect(harness.state, isA<BlockingRelationsSelectionFailed>());
      expect(harness.state.selected.keys, {row.relation.id});
    },
  );

  test('подтверждённый успех завершает выбор без второй отправки', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final row = testGroupRow(ownerId: harness.intentionId, index: 1);
    harness.viewModel.select(row);
    harness.viewModel.prepare();
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    final command =
        harness.repository.commands.single as DeleteBlockingRelations;
    const revision = TestGraphRevision(5);
    final deleted = BlockingRelationsDeleted(
      command: command,
      revision: revision,
      deletedRelations: [row.relation],
      counts: {
        harness.intentionId: testRelationCounts(),
        row.relation.relatedIntentionId: testRelationCounts(),
      },
    );
    harness.repository.succeed(
      0,
      GraphCommandSucceeded<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(ConfirmedGraphResult(revision: revision, value: deleted)),
    );
    await pumpEventQueue();

    expect(harness.state, isA<BlockingRelationsSelectionSucceeded>());
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, hasLength(1));
  });

  test('конфликт требует чтения и явного удаления недоступной связи', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final first = testGroupRow(ownerId: harness.intentionId, index: 1);
    final second = testGroupRow(ownerId: harness.intentionId, index: 2);
    harness.viewModel.select(first);
    harness.viewModel.select(second);
    harness.viewModel.prepare();
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    harness.repository.fail(
      0,
      DeleteBlockingRelationsSelectionConflictFailure(
        relationId: second.relation.id,
        reason: BlockingRelationConflictReason.relationMissing,
      ),
    );
    await pumpEventQueue();

    harness.repository.queueRelation(
      first,
      revision: const TestGraphRevision(3),
    );
    harness.repository.queueMissing(second.relation.id);
    expect(await harness.viewModel.refreshSelection(), isTrue);
    final editing = harness.state as BlockingRelationsSelectionEditing;
    expect(editing.selected.keys, {first.relation.id, second.relation.id});
    expect(editing.invalidIds, {second.relation.id});
    expect(harness.viewModel.prepare(), isFalse);
    expect(harness.repository.commands, hasLength(1));

    expect(harness.viewModel.unselect(second.relation.id), isTrue);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, hasLength(2));
    expect(
      (harness.repository.commands.last as DeleteBlockingRelations).relationIds,
      {first.relation.id},
    );
  });

  test(
    'актуализация сохраняет идентификаторы при изменении полей и ревизий',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final original = testGroupRow(ownerId: harness.intentionId, index: 1);
      final changed = testGroupRow(
        ownerId: harness.intentionId,
        index: 1,
        type: LongTermRelationType.can,
        scope: RelationScope.archived,
        priority: RelationPriority.p1,
        neighborTitle: 'Новое название',
      );
      harness.viewModel.select(original);
      harness.repository.queueRelation(
        changed,
        revision: const TestGraphRevision(5),
      );
      expect(await harness.viewModel.refreshSelection(), isTrue);
      expect(
        harness.state.selected[original.relation.id],
        isNot(same(original)),
      );
      expect(
        harness.state.selected[original.relation.id]!.related.title,
        'Новое название',
      );
      expect(harness.viewModel.prepare(), isTrue);
      final prepared =
          (harness.state as BlockingRelationsSelectionPrepared).snapshot;
      expect(prepared.command.relationIds, {original.relation.id});
      expect(prepared.rows.single.relation.type, LongTermRelationType.can);
      harness.viewModel.cancel();

      harness.repository.queueRelation(
        original,
        revision: const TestGraphRevision(4),
      );
      expect(await harness.viewModel.refreshSelection(), isTrue);
      expect(
        harness.state.selected[original.relation.id]!.related.title,
        'Новое название',
      );
    },
  );

  test(
    'ошибка чтения и отсутствие намерения не становятся пустым выбором',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final row = testGroupRow(ownerId: harness.intentionId, index: 1);
      harness.viewModel.select(row);
      harness.repository.queueRelationFailure(
        row.relation.id,
        const LongTermRelationReadUnavailableFailure(),
      );
      expect(await harness.viewModel.refreshSelection(), isFalse);
      expect(harness.state, isA<BlockingRelationsSelectionRefreshFailed>());
      expect(harness.state.selected.keys, {row.relation.id});
      expect(harness.viewModel.prepare(), isFalse);

      harness.repository.intentionExists = false;
      expect(await harness.viewModel.refreshSelection(), isFalse);
      final missing = harness.state as BlockingRelationsSelectionRefreshFailed;
      expect(
        missing.failure,
        BlockingRelationsRefreshFailure.intentionNotFound,
      );
      expect(missing.selected.keys, {row.relation.id});
    },
  );

  test(
    'перенос связи вне текущей группы сохраняет её в исправляемом выборе',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final row = testGroupRow(ownerId: harness.intentionId, index: 9);
      final moved = testGroupRow(ownerId: testIntentionId(500), index: 9);
      harness.viewModel.select(row);
      harness.repository.queueRelation(
        moved,
        revision: const TestGraphRevision(5),
      );

      expect(await harness.viewModel.refreshSelection(), isTrue);
      final editing = harness.state as BlockingRelationsSelectionEditing;
      expect(editing.selected[row.relation.id], same(row));
      expect(
        editing.invalidReasons[row.relation.id],
        BlockingRelationsInvalidReason.noLongerBlocking,
      );
      expect(harness.viewModel.prepare(), isFalse);
      expect(harness.repository.commands, isEmpty);

      harness.repository.queueRelation(
        row,
        revision: const TestGraphRevision(4),
      );
      expect(await harness.viewModel.refreshSelection(), isTrue);
      expect(
        (harness.state as BlockingRelationsSelectionEditing).invalidReasons[row
            .relation
            .id],
        BlockingRelationsInvalidReason.noLongerBlocking,
      );
    },
  );

  test(
    'повреждение и неожиданный отказ чтения остаются отдельными состояниями',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final row = testGroupRow(ownerId: harness.intentionId, index: 1);
      harness.viewModel.select(row);
      harness.repository.queueRelationFailure(
        row.relation.id,
        const LongTermRelationReadCorruptionFailure(),
      );
      expect(await harness.viewModel.refreshSelection(), isFalse);
      expect(
        (harness.state as BlockingRelationsSelectionRefreshFailed).failure,
        BlockingRelationsRefreshFailure.corruption,
      );
      harness.repository.queueRelationFailure(
        row.relation.id,
        const LongTermRelationReadUnexpectedFailure(),
      );
      expect(await harness.viewModel.refreshSelection(), isFalse);
      expect(
        (harness.state as BlockingRelationsSelectionRefreshFailed).failure,
        BlockingRelationsRefreshFailure.unexpected,
      );
      expect(harness.state.selected.keys, {row.relation.id});
      expect(harness.repository.commands, isEmpty);
    },
  );
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );
    subscription = container.listen(
      blockingRelationsSelectionViewModelProvider(intentionId),
      (_, _) {},
      fireImmediately: true,
    );
  }

  final intentionId = testIntentionId(100);
  final repository = _Repository();
  late final ProviderContainer container;
  late final ProviderSubscription<BlockingRelationsSelectionState> subscription;

  BlockingRelationsSelectionViewModel get viewModel => container.read(
    blockingRelationsSelectionViewModelProvider(intentionId).notifier,
  );
  BlockingRelationsSelectionState get state =>
      container.read(blockingRelationsSelectionViewModelProvider(intentionId));

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository implements PersonalGraphRepository {
  final commands = <GraphCommand>[];
  final _results = <Completer<Object>>[];
  final _relationReads =
      <LongTermRelationId, List<LongTermRelationReadResult>>{};
  bool intentionExists = true;

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async => intentionExists
      ? ResultSuccess(
          GraphSnapshot(
            value: testRelationCounts(),
            revision: const TestGraphRevision(1),
          ),
        )
      : const ResultFailure(IntentionNotFoundFailure());

  void queueRelation(
    LongTermRelationSummary row, {
    GraphRevision revision = const TestGraphRevision(1),
  }) => _queue(
    row.relation.id,
    LongTermRelationReadSuccess(
      GraphSnapshot(
        value: LongTermRelationDetails(
          relation: row.relation,
          source: row.source,
          related: row.related,
          description: null,
        ),
        revision: revision,
      ),
    ),
  );

  void queueMissing(LongTermRelationId id) => _queue(
    id,
    const LongTermRelationReadSuccess(
      GraphSnapshot(value: null, revision: TestGraphRevision(2)),
    ),
  );

  void queueRelationFailure(
    LongTermRelationId id,
    LongTermRelationReadFailure failure,
  ) => _queue(id, LongTermRelationReadError(failure));

  void _queue(LongTermRelationId id, LongTermRelationReadResult result) =>
      _relationReads.putIfAbsent(id, () => []).add(result);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      Stream.value(_relationReads[id]!.removeAt(0));

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => Stream.value(
    ResultSuccess(
      GraphSnapshot(
        value: intentionExists
            ? IntentionDetails(
                intention: testNeighborhoodIntention(id: id),
                relationCounts: testRelationCounts(),
              )
            : null,
        revision: const TestGraphRevision(1),
      ),
    ),
  );

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    commands.add(command);
    final result = Completer<Object>();
    _results.add(result);
    return await result.future as GraphCommandResult<T, F>;
  }

  void fail(int index, DeleteBlockingRelationsFailure failure) =>
      _results[index].complete(
        GraphCommandFailed<
          BlockingRelationsDeleted,
          DeleteBlockingRelationsFailure
        >(failure),
      );

  void succeed(int index, DeleteBlockingRelationsResult result) =>
      _results[index].complete(result);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
