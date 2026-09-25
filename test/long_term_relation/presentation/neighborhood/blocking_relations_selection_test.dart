import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';
import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  test('смешанный выбор сохраняет виды, порции и совпадающие UUID', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final relation = testGroupRow(ownerId: harness.intentionId, index: 1);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 1);
    final later = _dailyItem(
      ownerId: harness.intentionId,
      index: 2,
      ownerIsSelected: true,
    );
    final relationRef = LongTermBlockingRelationReference(relation.relation.id);
    final dailyRef = DailyChoiceBlockingRelationReference(daily.id);
    final laterRef = DailyChoiceBlockingRelationReference(later.id);

    expect(harness.viewModel.select(relation), isTrue);
    expect(harness.viewModel.selectDailyChoice(daily), isTrue);
    expect(harness.viewModel.selectDailyChoice(later), isTrue);
    expect(harness.state.selectedByReference.keys, {
      relationRef,
      dailyRef,
      laterRef,
    });
    expect(harness.viewModel.prepare(), isTrue);
    final prepared =
        (harness.state as BlockingRelationsSelectionPrepared).snapshot;
    expect(prepared.command.references, {relationRef, dailyRef, laterRef});
    expect(prepared.items.length, 3);
    expect(prepared.command.relationIds, {relation.relation.id});
    expect(prepared.command.dailyChoiceIds, {daily.id, later.id});
    expect(
      harness.viewModel.selectDailyChoice(
        _dailyItem(ownerId: testIntentionId(80), index: 20),
      ),
      isFalse,
    );
  });

  test(
    'исчезнувший дневной выбор сохраняет весь набор до исправления',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final relation = testGroupRow(ownerId: harness.intentionId, index: 3);
      final daily = _dailyItem(ownerId: harness.intentionId, index: 4);
      final dailyRef = DailyChoiceBlockingRelationReference(daily.id);
      harness.viewModel.select(relation);
      harness.viewModel.selectDailyChoice(daily);
      harness.repository.queueRelation(relation);
      harness.repository.queueDailyMissing(daily.id);

      expect(await harness.viewModel.refreshSelection(), isTrue);
      expect(harness.repository.selectedQueries.single.references, {
        LongTermBlockingRelationReference(relation.relation.id),
        dailyRef,
      });
      expect(harness.state.selectedByReference.length, 2);
      expect(
        (harness.state as BlockingRelationsSelectionEditing)
            .invalidReasonsByReference[dailyRef],
        BlockingRelationsInvalidReason.missing,
      );
      expect(harness.viewModel.prepare(), isFalse);
      expect(harness.repository.commands, isEmpty);
      expect(harness.viewModel.unselectReference(dailyRef), isTrue);
      expect(harness.viewModel.prepare(), isTrue);
      final prepared =
          (harness.state as BlockingRelationsSelectionPrepared).snapshot;
      expect(prepared.command.references, {
        LongTermBlockingRelationReference(relation.relation.id),
      });
    },
  );

  test('поздний снимок не возвращает устаревший дневной выбор', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final original = _dailyItem(ownerId: harness.intentionId, index: 5);
    final changed = _dailyItem(
      ownerId: harness.intentionId,
      index: 5,
      isCompleted: true,
    );
    final reference = DailyChoiceBlockingRelationReference(original.id);
    expect(harness.viewModel.selectDailyChoice(original), isTrue);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.observePrepared();
    expect(harness.repository.preparedQueries.single.references, {reference});

    harness.repository.emitPrepared({
      reference: SelectedDailyChoicePresent(changed),
    }, revision: const TestGraphRevision(5));
    final prepared = harness.state as BlockingRelationsSelectionPrepared;
    expect(
      (prepared.snapshot.items.single as BlockingRelationsSelectedDailyChoice)
          .item
          .isCompleted,
      isTrue,
    );
    harness.repository.emitPrepared({
      reference: SelectedDailyChoiceMissing(original.id),
    }, revision: const TestGraphRevision(4));
    expect(harness.state, same(prepared));
    expect(harness.repository.commands, isEmpty);
  });

  test('новая защита связи не удаляет дневную часть выбора молча', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final relation = testGroupRow(ownerId: harness.intentionId, index: 21);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 22);
    final relationRef = LongTermBlockingRelationReference(relation.relation.id);
    final dailyRef = DailyChoiceBlockingRelationReference(daily.id);
    harness.viewModel.select(relation);
    harness.viewModel.selectDailyChoice(daily);
    harness.repository.queueRelation(
      relation,
      permissions: const LongTermRelationPermissions.referencedByDailyPath(),
    );
    harness.repository.queueDaily(daily);

    expect(await harness.viewModel.refreshSelection(), isTrue);
    final editing = harness.state as BlockingRelationsSelectionEditing;
    expect(editing.selectedByReference.keys, {relationRef, dailyRef});
    expect(
      editing.invalidReasonsByReference[relationRef],
      BlockingRelationsInvalidReason.referencedByDailyPath,
    );
    expect(harness.viewModel.prepare(), isFalse);
    expect(harness.repository.commands, isEmpty);
  });

  test('наблюдение утраты принадлежности требует нового подтверждения', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final relation = testGroupRow(ownerId: harness.intentionId, index: 6);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 7);
    final relationRef = LongTermBlockingRelationReference(relation.relation.id);
    final dailyRef = DailyChoiceBlockingRelationReference(daily.id);
    harness.viewModel.select(relation);
    harness.viewModel.selectDailyChoice(daily);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.observePrepared();
    harness.repository.emitPrepared({
      relationRef: SelectedRelationPresent(
        LongTermRelationDetails(
          relation: relation.relation,
          source: relation.source,
          related: relation.related,
          description: null,
        ),
      ),
      dailyRef: SelectedDailyChoiceNoLongerBlocking(daily.id),
    }, revision: const TestGraphRevision(6));

    final editing = harness.state as BlockingRelationsSelectionEditing;
    expect(editing.selectedByReference.keys, {relationRef, dailyRef});
    expect(
      editing.invalidReasonsByReference[dailyRef],
      BlockingRelationsInvalidReason.noLongerBlocking,
    );
    expect(harness.viewModel.prepare(), isFalse);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, isEmpty);
  });

  test('смешанная команда идёт через coordinator, затем выбор пуст', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final relation = testGroupRow(ownerId: harness.intentionId, index: 8);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 9);
    final next = _dailyItem(ownerId: harness.intentionId, index: 10);
    harness.viewModel.select(relation);
    harness.viewModel.selectDailyChoice(daily);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    final command =
        harness.repository.commands.single as DeleteBlockingRelations;
    expect(command.references, {
      LongTermBlockingRelationReference(relation.relation.id),
      DailyChoiceBlockingRelationReference(daily.id),
    });
    expect(harness.viewModel.selectDailyChoice(next), isFalse);

    const revision = TestGraphRevision(5);
    final choice = DailyChoice(
      id: daily.id,
      sourceIntentionId: daily.source.id,
      selectedIntentionId: daily.selected.id,
      date: daily.date,
      description: null,
      isCompleted: daily.isCompleted,
    );
    final pathRelationId = testRelationId(100);
    final change = DailyChoiceChange(
      revision: revision,
      before: choice,
      after: null,
      releasedRelationIds: [pathRelationId],
      occupiedRelationIds: const [],
      intentionCounts: {
        daily.source.id: testRelationCounts(),
        daily.selected.id: testRelationCounts(),
      },
      relationPermissions: {
        pathRelationId: const LongTermRelationPermissions.unrestricted(),
      },
    );
    final deleted = BlockingRelationsDeleted(
      command: command,
      revision: revision,
      deletedRelations: [relation.relation],
      deletedChoiceChanges: [change],
      counts: {
        harness.intentionId: testRelationCounts(),
        relation.relation.relatedIntentionId: testRelationCounts(),
        daily.selected.id: testRelationCounts(),
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

    expect(harness.state.selectedByReference, isEmpty);
    expect(harness.viewModel.prepare(), isFalse);
    expect(harness.viewModel.selectDailyChoice(next), isTrue);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, hasLength(2));
    expect(
      (harness.repository.commands.last as DeleteBlockingRelations).references,
      {DailyChoiceBlockingRelationReference(next.id)},
    );
  });

  test('конфликт дневной связи не сужает смешанное подтверждение', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final relation = testGroupRow(ownerId: harness.intentionId, index: 11);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 12);
    final relationRef = LongTermBlockingRelationReference(relation.relation.id);
    final dailyRef = DailyChoiceBlockingRelationReference(daily.id);
    harness.viewModel.select(relation);
    harness.viewModel.selectDailyChoice(daily);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    harness.repository.fail(
      0,
      DeleteBlockingRelationsSelectionConflictFailure(
        reference: dailyRef,
        reason: BlockingRelationConflictReason.noLongerBlocking,
      ),
    );
    await pumpEventQueue();

    expect(harness.state.selectedByReference.keys, {relationRef, dailyRef});
    expect(
      (harness.state as BlockingRelationsSelectionFailed).requiresRefresh,
      isTrue,
    );
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, hasLength(1));

    harness.repository.queueRelation(relation);
    harness.repository.queueDailyMissing(daily.id);
    expect(await harness.viewModel.refreshSelection(), isTrue);
    final editing = harness.state as BlockingRelationsSelectionEditing;
    expect(editing.selectedByReference.keys, {relationRef, dailyRef});
    expect(
      editing.invalidReasonsByReference[dailyRef],
      BlockingRelationsInvalidReason.missing,
    );
    expect(harness.viewModel.prepare(), isFalse);
  });

  test('принятая смешанная команда завершается после ухода', () async {
    final harness = _Harness();
    final relation = testGroupRow(ownerId: harness.intentionId, index: 13);
    final daily = _dailyItem(ownerId: harness.intentionId, index: 14);
    harness.viewModel.select(relation);
    harness.viewModel.selectDailyChoice(daily);
    expect(harness.viewModel.prepare(), isTrue);
    harness.viewModel.confirm(presentationTitle: 'Намерение');
    expect(harness.repository.commands, hasLength(1));
    harness.dispose();
    harness.repository.fail(
      0,
      const DeleteBlockingRelationsUnavailableFailure(),
    );
    await pumpEventQueue();
    expect(harness.repository.commands, hasLength(1));
  });

  test('актуализация читает весь выбор одним согласованным запросом', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final rows = testGroupRows(ownerId: harness.intentionId, from: 1, count: 3);
    for (final row in rows) {
      harness.viewModel.select(row);
      harness.repository.queueRelation(row);
    }

    expect(await harness.viewModel.refreshSelection(), isTrue);
    expect(harness.repository.selectedQueries, hasLength(1));
    expect(
      harness.repository.selectedQueries.single.relationIds,
      rows.map((row) => row.relation.id).toSet(),
    );
  });

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
        DeleteBlockingRelationsSelectionConflictFailure.longTerm(
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

  test(
    'после успеха новый выбор пуст и требует отдельного подтверждения',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = testGroupRow(ownerId: harness.intentionId, index: 1);
      final second = testGroupRow(ownerId: harness.intentionId, index: 2);
      harness.viewModel.select(first);
      harness.viewModel.prepare();
      harness.viewModel.confirm(presentationTitle: 'Намерение');
      final command =
          harness.repository.commands.single as DeleteBlockingRelations;
      expect(harness.viewModel.select(second), isFalse);
      expect(harness.viewModel.prepare(), isFalse);
      const revision = TestGraphRevision(5);
      final deleted = BlockingRelationsDeleted(
        command: command,
        revision: revision,
        deletedRelations: [first.relation],
        counts: {
          harness.intentionId: testRelationCounts(),
          first.relation.relatedIntentionId: testRelationCounts(),
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

      expect(harness.state, isA<BlockingRelationsSelectionEditing>());
      expect(harness.state.selected, isEmpty);
      expect(harness.viewModel.prepare(), isFalse);
      harness.viewModel.confirm(presentationTitle: 'Намерение');
      expect(harness.repository.commands, hasLength(1));

      expect(harness.viewModel.select(second), isTrue);
      expect(harness.viewModel.prepare(), isTrue);
      final next =
          (harness.state as BlockingRelationsSelectionPrepared).snapshot;
      expect(next.command, isNot(same(command)));
      expect(next.command.relationIds, {second.relation.id});
      harness.viewModel.confirm(presentationTitle: 'Намерение');
      expect(harness.repository.commands, hasLength(2));
      expect(harness.repository.commands.last, same(next.command));
    },
  );

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
      DeleteBlockingRelationsSelectionConflictFailure.longTerm(
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
    'отказ пакетного чтения не публикует обновлённую часть выбора',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final original = testGroupRow(ownerId: harness.intentionId, index: 1);
      final second = testGroupRow(ownerId: harness.intentionId, index: 2);
      final changed = testGroupRow(
        ownerId: harness.intentionId,
        index: 1,
        neighborTitle: 'Неопубликованное название',
      );
      harness.viewModel.select(original);
      harness.viewModel.select(second);
      harness.repository.queueRelation(
        changed,
        revision: const TestGraphRevision(5),
      );
      harness.repository.queueRelationFailure(
        second.relation.id,
        const LongTermRelationReadUnavailableFailure(),
      );

      expect(await harness.viewModel.refreshSelection(), isFalse);
      expect(harness.state, isA<BlockingRelationsSelectionRefreshFailed>());
      expect(harness.state.selected[original.relation.id], same(original));
      expect(harness.state.selected.keys, {
        original.relation.id,
        second.relation.id,
      });
      expect(harness.viewModel.prepare(), isFalse);
      expect(harness.repository.commands, isEmpty);
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

DailyChoiceCatalogItem _dailyItem({
  required IntentionId ownerId,
  required int index,
  bool isCompleted = false,
  bool ownerIsSelected = false,
}) {
  final id = (DailyChoiceId.decode(
    testRelationId(index).toCanonicalString(),
  ) as DailyChoiceIdDecodingSuccess).id;
  return DailyChoiceCatalogItem(
    id: id,
    source: DailyChoiceCatalogParticipant(
      id: ownerIsSelected ? testIntentionId(3000 + index) : ownerId,
      title: 'Основание',
      archiveState: IntentionArchiveState.active,
      readiness: IntentionReadiness.notReady,
    ),
    selected: DailyChoiceCatalogParticipant(
      id: ownerIsSelected ? ownerId : testIntentionId(2000 + index),
      title: 'Действие',
      archiveState: IntentionArchiveState.active,
      readiness: IntentionReadiness.ready,
    ),
    date: CalendarDate.fromParts(2026, 9, 24),
    isCompleted: isCompleted,
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

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  final commands = <GraphCommand>[];
  final selectedQueries = <SelectedRelationsQuery>[];
  final _results = <Completer<Object>>[];
  final _relationReads =
      <LongTermRelationId, List<LongTermRelationReadResult>>{};
  final _dailyReads = <DailyChoiceId, List<SelectedRelationEntry>>{};
  final preparedQueries = <SelectedRelationsQuery>[];
  final _preparedController =
      StreamController<SelectedRelationsReadResult>.broadcast(sync: true);
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
    LongTermRelationPermissions permissions =
        const LongTermRelationPermissions.unrestricted(),
  }) => _queue(
    row.relation.id,
    LongTermRelationReadSuccess(
      GraphSnapshot(
        value: LongTermRelationDetails(
          relation: row.relation,
          source: row.source,
          related: row.related,
          description: null,
          permissions: permissions,
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

  void queueDailyMissing(DailyChoiceId id) =>
      _dailyReads.putIfAbsent(id, () => []).add(SelectedDailyChoiceMissing(id));

  void queueDaily(DailyChoiceCatalogItem item) => _dailyReads
      .putIfAbsent(item.id, () => [])
      .add(SelectedDailyChoicePresent(item));

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
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) async {
    selectedQueries.add(query);
    final entries = <BlockingRelationReference, SelectedRelationEntry>{};
    GraphRevision revision = const TestGraphRevision(1);
    for (final id in query.relationIds) {
      final result = _relationReads[id]!.removeAt(0);
      switch (result) {
        case LongTermRelationReadError(:final failure):
          return SelectedRelationsReadError(switch (failure) {
            LongTermRelationReadUnavailableFailure() =>
              const SelectedRelationsReadUnavailableFailure(),
            LongTermRelationReadCorruptionFailure() =>
              const SelectedRelationsReadCorruptionFailure(),
            LongTermRelationReadUnexpectedFailure() =>
              const SelectedRelationsReadUnexpectedFailure(),
          });
        case LongTermRelationReadSuccess(value: final snapshot):
          if (snapshot.revision.compareTo(revision) ==
              GraphRevisionOrder.newer) {
            revision = snapshot.revision;
          }
          final details = snapshot.value;
          entries[LongTermBlockingRelationReference(id)] = details == null
              ? SelectedRelationMissing(id)
              : details.relation.sourceIntentionId != query.intentionId &&
                    details.relation.relatedIntentionId != query.intentionId
              ? SelectedRelationNoLongerBlocking(id)
              : SelectedRelationPresent(details);
      }
    }
    for (final id in query.dailyChoiceIds) {
      entries[DailyChoiceBlockingRelationReference(id)] = _dailyReads[id]!
          .removeAt(0);
    }
    return SelectedRelationsReadSuccess(
      GraphSnapshot(
        value: SelectedRelationsSnapshot.mixed(
          query: query,
          entriesByReference: entries,
        ),
        revision: revision,
      ),
    );
  }

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) {
    preparedQueries.add(query);
    return _preparedController.stream;
  }

  void emitPrepared(
    Map<BlockingRelationReference, SelectedRelationEntry> entries, {
    required GraphRevision revision,
  }) {
    _preparedController.add(
      SelectedRelationsReadSuccess(
        GraphSnapshot(
          value: SelectedRelationsSnapshot.mixed(
            query: preparedQueries.last,
            entriesByReference: entries,
          ),
          revision: revision,
        ),
      ),
    );
  }

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
