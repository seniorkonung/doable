import 'dart:async';

import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
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
      expect(harness.state, isA<BlockingRelationsSelectionEditing>());
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
