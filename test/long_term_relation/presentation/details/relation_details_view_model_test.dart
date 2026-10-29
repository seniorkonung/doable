import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../relation_graph_test_support.dart';
import '../daily_path_change_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  test('дневные пути меняют разрешения без изменения строки связи', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);
    final relation = testRelationDetails(
      relationId: harness.relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
    );
    harness.repository
        .watchAt(0)
        .emitDetails(relation, revision: const TestGraphRevision(1));
    await pumpEventQueue();

    final unrelated = testRelationDetails(
      relationId: testRelationId(9),
      sourceId: testIntentionId(3),
      relatedId: testIntentionId(4),
    ).relation;
    for (final (number, created, permission) in [
      (2, true, const LongTermRelationPermissions.referencedByDailyPath()),
      (3, true, const LongTermRelationPermissions.referencedByDailyPath()),
      (4, false, const LongTermRelationPermissions.referencedByDailyPath()),
      (5, false, const LongTermRelationPermissions.unrestricted()),
    ]) {
      final start = harness.coordinator.acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: unrelated.id,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      );
      final revision = TestGraphRevision(number);
      harness.repository.completeRelationUpdate(
        number - 2,
        before: unrelated,
        after: unrelated,
        revision: revision,
        additionalChanges: [
          testDailyPathChange(
            revision: revision,
            relationId: relation.relation.id,
            sourceId: relation.source.id,
            selectedId: relation.related.id,
            choiceNumber: created ? number : number - 2,
            isCreated: created,
            permissions: permission,
          ),
        ],
      );
      await (start as LongTermRelationCommandAccepted).future;
      await pumpEventQueue();

      final loaded = harness.state as RelationDetailsLoaded;
      expect(loaded.permissions.canDelete, number == 5);
      expect(loaded.permissions.canChangeMeaning, number == 5);
      expect(loaded.permissions.canEditDescriptionAndPriority, isTrue);
      expect(loaded.permissions.canChangeArchiveState, isTrue);
      if (number == 2) {
        harness.viewModel.delete();
        expect(harness.repository.relationCommands, hasLength(1));
        harness.repository
            .watchAt(0)
            .emitDetails(relation, revision: const TestGraphRevision(1));
        await pumpEventQueue();
        expect(
          (harness.state as RelationDetailsLoaded).permissions.canDelete,
          isFalse,
        );
      }
    }
  });

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
    harness.repository.failRelationCommand(
      0,
      const LongTermRelationUnavailableFailure(),
    );
    await pumpEventQueue();
    harness.viewModel.retryLifecycleChange();

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

  RelationDetailsViewModel get viewModel =>
      _container.read(relationDetailsViewModelProvider(relationId).notifier);

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
  );
}
