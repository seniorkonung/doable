import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../relation_graph_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  test('каждая категория отказа даёт своё безопасное состояние', () async {
    for (final expectation in <(LongTermRelationReadFailure, Matcher, bool)>[
      (
        const LongTermRelationReadUnavailableFailure(),
        isA<RelationDetailsUnavailable>(),
        true,
      ),
      (
        const LongTermRelationReadCorruptionFailure(),
        isA<RelationDetailsCorruption>(),
        false,
      ),
      (
        const LongTermRelationReadUnexpectedFailure(),
        isA<RelationDetailsUnexpected>(),
        false,
      ),
    ]) {
      final harness = _RelationDetailsHarness();

      harness.repository.watchAt(0).fail(expectation.$1);
      await pumpEventQueue();

      expect(harness.state, expectation.$2);
      expect(harness.state.canRetry, expectation.$3);
      await harness.dispose();
    }
  });

  test('исключение наблюдения не выдаётся за отсутствие связи', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    harness.repository.watchAt(0).throwError(StateError('сбой наблюдения'));
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsUnexpected>());
  });

  test('повтор доступен только при устранимом отказе', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    harness.repository
        .watchAt(0)
        .fail(const LongTermRelationReadCorruptionFailure());
    await pumpEventQueue();
    harness.viewModel.retry();
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsCorruption>());
  });

  test('позднее чтение прежней ревизии не отменяет подтверждённое', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    final watch = harness.repository.watchAt(0);
    watch.emitDetails(
      testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'актуальное название',
      ),
      revision: const TestGraphRevision(9),
    );
    await pumpEventQueue();

    watch.emitDetails(
      testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'устаревшее название',
      ),
      revision: const TestGraphRevision(3),
    );
    await pumpEventQueue();

    final state = harness.state;
    expect(state, isA<RelationDetailsLoaded>());
    expect(
      (state as RelationDetailsLoaded).details.related.title,
      'актуальное название',
    );
  });

  test('ответ прежнего поколения не возвращается после повтора', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    harness.repository
        .watchAt(0)
        .fail(const LongTermRelationReadUnavailableFailure());
    await pumpEventQueue();
    harness.viewModel.retry();
    await pumpEventQueue();

    harness.repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: harness.relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            relatedTitle: 'актуальное название',
          ),
          revision: const TestGraphRevision(9),
        );
    await pumpEventQueue();

    harness.repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: harness.relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            relatedTitle: 'устаревшее название',
          ),
          revision: const TestGraphRevision(11),
        );
    await pumpEventQueue();

    final state = harness.state;
    expect(state, isA<RelationDetailsLoaded>());
    expect(
      (state as RelationDetailsLoaded).details.related.title,
      'актуальное название',
    );
  });

  test(
    'завершение изменения удерживает прежний снимок до нового полного чтения',
    () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      final initialDetails = testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'прежний участник',
        description: 'Прежнее описание',
      );
      harness.repository
          .watchAt(0)
          .emitDetails(initialDetails, revision: const TestGraphRevision(1));
      await pumpEventQueue();

      final start = harness.startUpdate();
      expect(start, isA<LongTermRelationCommandAccepted>());
      harness.repository.completeRelationUpdate(
        0,
        before: initialDetails.relation,
        after: initialDetails.relation.copyWithForTest(
          priority: RelationPriority.p1,
        ),
        revision: const TestGraphRevision(5),
        description: LongTermRelationDescription.fromInput('Новое описание'),
      );
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationDetailsLoaded>()
            .having(
              (state) => state.details.description?.value,
              'прежнее цельное описание',
              'Прежнее описание',
            )
            .having(
              (state) => state.refreshStatus,
              'состояние обновления',
              isA<RelationDetailsRefreshing>(),
            )
            .having(
              (state) => state.isOperationRunning,
              'завершённая операция',
              isFalse,
            ),
      );

      harness.repository
          .watchAt(1)
          .emitDetails(
            testRelationDetails(
              relationId: harness.relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
              relatedTitle: 'запоздалый участник',
              description: 'Запоздалое описание',
            ),
            revision: const TestGraphRevision(3),
          );
      await pumpEventQueue();

      expect(
        (harness.state as RelationDetailsLoaded).details.description?.value,
        'Прежнее описание',
      );

      harness.repository
          .watchAt(1)
          .fail(const LongTermRelationReadUnavailableFailure());
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationDetailsLoaded>()
            .having(
              (state) => state.details.related.title,
              'прежний цельный участник',
              'прежний участник',
            )
            .having(
              (state) => state.refreshStatus,
              'устранимая ошибка обновления',
              isA<RelationDetailsRefreshUnavailable>(),
            )
            .having((state) => state.canRetry, 'повтор', isTrue),
      );

      harness.viewModel.retry();
      await pumpEventQueue();

      harness.repository
          .watchAt(2)
          .emitDetails(
            testRelationDetails(
              relationId: harness.relationId,
              sourceId: testIntentionId(3),
              relatedId: testIntentionId(4),
              sourceTitle: 'новый исходный участник',
              relatedTitle: 'новый связанный участник',
              priority: RelationPriority.p1,
              description: 'Новое описание',
            ),
            revision: const TestGraphRevision(5),
          );
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationDetailsLoaded>()
            .having(
              (state) => state.details.description?.value,
              'новое описание',
              'Новое описание',
            )
            .having(
              (state) => state.details.source.title,
              'новый исходный участник',
              'новый исходный участник',
            )
            .having(
              (state) => state.refreshStatus,
              'актуальный снимок',
              isA<RelationDetailsFresh>(),
            ),
      );
    },
  );

  test(
    'удаление связи в составном пакете завершает открытый просмотр',
    () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      final initial = testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
      );
      harness.repository
          .watchAt(0)
          .emitDetails(initial, revision: const TestGraphRevision(1));
      await pumpEventQueue();

      final unrelated = testRelationDetails(
        relationId: testRelationId(9),
        sourceId: testIntentionId(3),
        relatedId: testIntentionId(4),
      ).relation;
      final start = harness.coordinator.acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: unrelated.id,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      );
      const revision = TestGraphRevision(5);
      harness.repository.completeRelationUpdate(
        0,
        before: unrelated,
        after: unrelated.copyWithForTest(priority: RelationPriority.p1),
        revision: revision,
        additionalChanges: [
          LongTermRelationDeletedChange(
            revision: revision,
            relation: initial.relation,
          ),
        ],
      );
      await (start as LongTermRelationCommandAccepted).future;
      await pumpEventQueue();

      expect(harness.state, isA<RelationDetailsDeleted>());
      harness.repository
          .watchAt(0)
          .emitDetails(initial, revision: const TestGraphRevision(1));
      await pumpEventQueue();
      expect(harness.state, isA<RelationDetailsDeleted>());
    },
  );

  test(
    'ошибка обновления сохраняет данные и разрешает только уместный повтор',
    () async {
      for (final expectation in <(LongTermRelationReadFailure, Matcher, bool)>[
        (
          const LongTermRelationReadUnavailableFailure(),
          isA<RelationDetailsRefreshUnavailable>(),
          true,
        ),
        (
          const LongTermRelationReadCorruptionFailure(),
          isA<RelationDetailsRefreshCorruption>(),
          false,
        ),
        (
          const LongTermRelationReadUnexpectedFailure(),
          isA<RelationDetailsRefreshUnexpected>(),
          false,
        ),
      ]) {
        final harness = _RelationDetailsHarness();
        harness.repository
            .watchAt(0)
            .emitDetails(
              testRelationDetails(
                relationId: harness.relationId,
                sourceId: testIntentionId(1),
                relatedId: testIntentionId(2),
                description: 'Подтверждённые данные',
              ),
              revision: const TestGraphRevision(1),
            );
        await pumpEventQueue();

        harness.repository.watchAt(0).fail(expectation.$1);
        await pumpEventQueue();

        expect(
          harness.state,
          isA<RelationDetailsLoaded>()
              .having(
                (state) => state.details.description?.value,
                'подтверждённые данные',
                'Подтверждённые данные',
              )
              .having(
                (state) => state.refreshStatus,
                'безопасная категория обновления',
                expectation.$2,
              )
              .having((state) => state.canRetry, 'повтор', expectation.$3),
        );
        await harness.dispose();
      }
    },
  );

  test('устранимый отказ восстановления допускает обычный повтор', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);
    harness.repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: harness.relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            scope: RelationScope.archived,
          ),
          revision: const TestGraphRevision(1),
        );
    await pumpEventQueue();

    harness.viewModel.restore();
    await pumpEventQueue();
    harness.repository.failRelationCommand(
      0,
      const LongTermRelationUnavailableFailure(),
    );
    await pumpEventQueue();
    harness.viewModel.retryLifecycleChange();
    await pumpEventQueue();

    expect(harness.repository.relationCommands, hasLength(2));
    expect(
      harness.repository.relationCommands.last,
      isA<RestoreLongTermRelation>(),
    );
  });

  test('подтверждённое отсутствие завершает прежний контекст', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);
    final initialDetails = testRelationDetails(
      relationId: harness.relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
    );
    harness.repository
        .watchAt(0)
        .emitDetails(initialDetails, revision: const TestGraphRevision(1));
    await pumpEventQueue();

    harness.startUpdate();
    harness.repository.completeRelationUpdate(
      0,
      before: initialDetails.relation,
      after: initialDetails.relation.copyWithForTest(
        priority: RelationPriority.p1,
      ),
      revision: const TestGraphRevision(5),
    );
    await pumpEventQueue();
    harness.repository
        .watchAt(1)
        .emitMissing(revision: const TestGraphRevision(5));
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsNotFound>());
  });

  group('правка связи', () {
    test('смена типа отправляет только тип', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.viewModel.changeType(LongTermRelationType.can);

      final patch = harness.singleUpdatePatch;
      expect(
        patch.type,
        isA<LongTermRelationFieldSet<LongTermRelationType>>().having(
          (field) => field.value,
          'тип',
          LongTermRelationType.can,
        ),
      );
      expect(
        patch.priority,
        isA<LongTermRelationFieldUnchanged<RelationPriority>>(),
      );
      expect(patch.description, isA<LongTermRelationDescriptionUnchanged>());
    });

    test('смена приоритета отправляет только приоритет', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.viewModel.changePriority(RelationPriority.p1);

      final patch = harness.singleUpdatePatch;
      expect(
        patch.priority,
        isA<LongTermRelationFieldSet<RelationPriority>>().having(
          (field) => field.value,
          'приоритет',
          RelationPriority.p1,
        ),
      );
      expect(
        patch.type,
        isA<LongTermRelationFieldUnchanged<LongTermRelationType>>(),
      );
      expect(patch.description, isA<LongTermRelationDescriptionUnchanged>());
    });

    test('значение, равное подтверждённому, команды не порождает', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open(priority: RelationPriority.p2);

      harness.viewModel.changePriority(RelationPriority.p2);
      harness.viewModel.changeType(LongTermRelationType.need);

      expect(harness.repository.relationCommands, isEmpty);
    });

    test(
      'до нового снимка правка сравнивается с подтверждённым приоритетом',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        final details = await harness.open(priority: RelationPriority.p2);

        harness.viewModel.changePriority(RelationPriority.p1);
        harness.repository.completeRelationUpdate(
          0,
          before: details.relation,
          after: details.relation.copyWithForTest(
            priority: RelationPriority.p1,
          ),
          revision: const TestGraphRevision(2),
        );
        await pumpEventQueue();

        expect(harness.loaded.details.relation.priority, RelationPriority.p2);
        harness.viewModel.changePriority(RelationPriority.p1);
        expect(harness.repository.relationCommands, hasLength(1));

        harness.viewModel.changePriority(RelationPriority.p2);
        expect(harness.repository.relationCommands, hasLength(2));
      },
    );

    test(
      'до нового снимка каскадное архивирование запрещает смену типа',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        final details = await harness.open();
        final unrelated = testRelationDetails(
          relationId: testRelationId(9),
          sourceId: testIntentionId(3),
          relatedId: testIntentionId(4),
        ).relation;

        final start = harness.coordinator.acceptRelationUpdate(
          UpdateLongTermRelation(
            relationId: unrelated.id,
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p1),
            ),
          ),
        );
        const revision = TestGraphRevision(2);
        harness.repository.completeRelationUpdate(
          0,
          before: unrelated,
          after: unrelated,
          revision: revision,
          additionalChanges: [
            LongTermRelationUpdatedChange(
              revision: revision,
              before: details.relation,
              after: details.relation.copyWithForTest(
                scope: RelationScope.archived,
              ),
            ),
          ],
        );
        await (start as LongTermRelationCommandAccepted).future;
        await pumpEventQueue();

        harness.viewModel.changeType(LongTermRelationType.can);

        expect(harness.repository.relationCommands, hasLength(1));
      },
    );

    test('пока операция связи выполняется, правка не принимается и не ждёт очереди', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      final details = await harness.open(priority: RelationPriority.p2);

      harness.viewModel.changePriority(RelationPriority.p1);
      expect(harness.state.isOperationRunning, isTrue);

      harness.viewModel.changeType(LongTermRelationType.can);
      harness.viewModel.changePriority(RelationPriority.p3);
      final save = await harness.viewModel.saveDescription('Новое описание');

      expect(save, isA<RelationDescriptionSaveFailed>());
      expect(harness.loaded.editFailure, isNull);
      harness.repository.completeRelationUpdate(
        0,
        before: details.relation,
        after: details.relation.copyWithForTest(priority: RelationPriority.p1),
        revision: const TestGraphRevision(2),
      );
      await pumpEventQueue();

      expect(harness.repository.relationCommands, hasLength(1));
      expect(harness.state.isOperationRunning, isFalse);
    });

    test('архивированная связь принимает правки, кроме типа', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open(scope: RelationScope.archived);

      harness.viewModel.changeType(LongTermRelationType.can);
      expect(harness.repository.relationCommands, isEmpty);

      harness.viewModel.changePriority(RelationPriority.p1);
      expect(
        harness.singleUpdatePatch.priority,
        isA<LongTermRelationFieldSet>(),
      );
    });

    test(
      'отказ каскадно архивированной связи переживает запоздавший снимок',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        await harness.open();

        harness.viewModel.changeType(LongTermRelationType.can);
        harness.repository.failRelationCommand(
          0,
          LongTermRelationArchivedTypeChangeFailure(harness.relationId),
        );
        await pumpEventQueue();

        expect(
          harness.loaded.editFailure?.failure,
          isA<LongTermRelationArchivedTypeChangeFailure>(),
        );
        expect(harness.loaded.editFailure?.failurePresentation, isNotNull);
        expect(harness.state.isOperationRunning, isFalse);

        harness.repository
            .watchAt(0)
            .emitDetails(
              testRelationDetails(
                relationId: harness.relationId,
                sourceId: testIntentionId(1),
                relatedId: testIntentionId(2),
                scope: RelationScope.archived,
              ),
              revision: const TestGraphRevision(2),
            );
        await pumpEventQueue();

        expect(harness.loaded.details.relation.scope, RelationScope.archived);
        expect(
          harness.loaded.editFailure?.failure,
          isA<LongTermRelationArchivedTypeChangeFailure>(),
        );
      },
    );

    test(
      'отказ оставляет подтверждённые поля до следующей принятой правки',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        await harness.open(priority: RelationPriority.p2);

        harness.viewModel.changePriority(RelationPriority.p1);
        harness.repository.failRelationCommand(
          0,
          const LongTermRelationUnavailableFailure(),
        );
        await pumpEventQueue();

        expect(harness.loaded.details.relation.priority, RelationPriority.p2);
        final failure = harness.loaded.editFailure;
        expect(failure?.failure, isA<LongTermRelationUnavailableFailure>());

        harness.viewModel.changePriority(RelationPriority.p2);
        expect(harness.loaded.editFailure, same(failure));

        harness.viewModel.changePriority(RelationPriority.p3);
        expect(harness.loaded.editFailure, isNull);
      },
    );

    test('снятое право отказа переходит общей поверхности', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.viewModel.changePriority(RelationPriority.p1);
      harness.repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await pumpEventQueue();
      final claim = harness.loaded.editFailure!.failurePresentation!;
      expect(
        harness.coordinator.claimInitiatorFailure(claim.token),
        same(claim),
      );

      harness.viewModel.changePriority(RelationPriority.p3);
      await pumpEventQueue();

      expect(harness.coordinator.claimInitiatorFailure(claim.token), isNull);
    });

    test('принятое архивирование снимает отказ правки', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.viewModel.changePriority(RelationPriority.p1);
      harness.repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await pumpEventQueue();

      harness.viewModel.archive();
      await pumpEventQueue();

      expect(harness.loaded.editFailure, isNull);
    });
  });

  group('сохранение описания', () {
    test('успех собственной команды заменяет только описание', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      final details = await harness.open(description: 'Прежнее описание');

      final save = harness.viewModel.saveDescription('Новое описание');

      final patch = harness.singleUpdatePatch;
      expect(
        patch.description,
        isA<LongTermRelationDescriptionReplaced>().having(
          (description) => description.value.value,
          'текст',
          'Новое описание',
        ),
      );
      expect(
        patch.priority,
        isA<LongTermRelationFieldUnchanged<RelationPriority>>(),
      );
      expect(
        patch.type,
        isA<LongTermRelationFieldUnchanged<LongTermRelationType>>(),
      );
      harness.repository.completeRelationUpdate(
        0,
        before: details.relation,
        after: details.relation,
        revision: const TestGraphRevision(2),
        description: LongTermRelationDescription.fromInput('Новое описание'),
      );

      expect(await save, isA<RelationDescriptionSaved>());
    });

    test('текст, равный сохранённому, команды не порождает', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open(description: 'Прежнее описание');

      final save = await harness.viewModel.saveDescription('Прежнее описание');

      expect(save, isA<RelationDescriptionUnchanged>());
      expect(harness.repository.relationCommands, isEmpty);
    });

    test('пробелы у связи без описания команды не порождают', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final save = await harness.viewModel.saveDescription('  \n ');

      expect(save, isA<RelationDescriptionUnchanged>());
      expect(harness.repository.relationCommands, isEmpty);
    });

    test('пробельный текст очищает описание', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open(description: 'Прежнее описание');

      unawaited(harness.viewModel.saveDescription('   '));

      expect(
        harness.singleUpdatePatch.description,
        isA<LongTermRelationDescriptionCleared>(),
      );
    });

    test(
      'до нового снимка текст сравнивается с подтверждённым описанием',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        final details = await harness.open(description: 'Прежнее описание');

        final save = harness.viewModel.saveDescription('Новое описание');
        harness.repository.completeRelationUpdate(
          0,
          before: details.relation,
          after: details.relation,
          revision: const TestGraphRevision(2),
          description: LongTermRelationDescription.fromInput('Новое описание'),
        );
        await save;

        expect(harness.loaded.details.description?.value, 'Прежнее описание');
        expect(
          await harness.viewModel.saveDescription('Новое описание'),
          isA<RelationDescriptionUnchanged>(),
        );
        unawaited(harness.viewModel.saveDescription('Прежнее описание'));
        expect(harness.repository.relationCommands, hasLength(2));
      },
    );

    test('слишком длинный текст называет свою причину', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final save = await harness.viewModel.saveDescription(
        'а' * (LongTermRelationDescription.maxGraphemeClusters + 1),
      );

      expect(
        save,
        isA<RelationDescriptionInvalid>().having(
          (outcome) => outcome.reason,
          'причина',
          LongTermRelationTextValidationReason.tooLong,
        ),
      );
      expect(harness.repository.relationCommands, isEmpty);
    });

    test('NUL называет причину недопустимого Unicode', () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final save = await harness.viewModel.saveDescription('текст\u0000');

      expect(
        save,
        isA<RelationDescriptionInvalid>().having(
          (outcome) => outcome.reason,
          'причина',
          LongTermRelationTextValidationReason.invalidUnicodeRepertoire,
        ),
      );
      expect(harness.repository.relationCommands, isEmpty);
    });

    test(
      'отказ команды возвращается вызывающему и хранится в состоянии',
      () async {
        final harness = _RelationDetailsHarness();
        addTearDown(harness.dispose);
        await harness.open(description: 'Прежнее описание');

        final save = harness.viewModel.saveDescription('Новое описание');
        harness.repository.failRelationCommand(
          0,
          const LongTermRelationCorruptionFailure(),
        );

        expect(await save, isA<RelationDescriptionSaveFailed>());
        expect(
          harness.loaded.editFailure?.failure,
          isA<LongTermRelationCorruptionFailure>(),
        );
        expect(harness.loaded.details.description?.value, 'Прежнее описание');
      },
    );
  });
}

final class _RelationDetailsHarness {
  _RelationDetailsHarness({bool startUpdateBeforeOpening = false})
    : repository = ControlledRelationDetailsRepository(),
      relationId = testRelationId(1) {
    _container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );
    if (startUpdateBeforeOpening) {
      startUpdate();
    }
    _subscription = _container.listen(
      relationDetailsViewModelProvider(relationId),
      (_, _) {},
      fireImmediately: true,
    );
  }

  final ControlledRelationDetailsRepository repository;
  final LongTermRelationId relationId;
  late final ProviderContainer _container;
  late final ProviderSubscription<RelationDetailsState> _subscription;

  RelationDetailsState get state => _subscription.read();

  RelationDetailsLoaded get loaded => state as RelationDetailsLoaded;

  LongTermRelationPatch get singleUpdatePatch =>
      (repository.relationCommands.single as UpdateLongTermRelation).patch;

  RelationDetailsViewModel get viewModel =>
      _container.read(relationDetailsViewModelProvider(relationId).notifier);

  Future<LongTermRelationDetails> open({
    RelationPriority priority = RelationPriority.p2,
    RelationScope scope = RelationScope.active,
    String? description,
  }) async {
    final details = testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      priority: priority,
      scope: scope,
      description: description,
    );
    repository
        .watchAt(0)
        .emitDetails(details, revision: const TestGraphRevision(1));
    await pumpEventQueue();
    return details;
  }

  LongTermRelationCommandStart startUpdate() =>
      coordinator.acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      );

  GraphCommandCoordinator get coordinator =>
      _container.read(graphCommandCoordinatorProvider.notifier);

  Future<void> dispose() async {
    _subscription.close();
    _container.dispose();
    await repository.dispose();
  }
}

extension on LongTermRelation {
  LongTermRelation copyWithForTest({
    RelationPriority? priority,
    RelationScope? scope,
  }) => LongTermRelation(
    id: id,
    sourceIntentionId: sourceIntentionId,
    relatedIntentionId: relatedIntentionId,
    type: type,
    priority: priority ?? this.priority,
    scope: scope ?? this.scope,
    creationSequence: creationSequence,
    createdAt: RelationTimestamp(DateTime.utc(2026)),
    updatedAt: RelationTimestamp(DateTime.utc(2026)),
  );
}
