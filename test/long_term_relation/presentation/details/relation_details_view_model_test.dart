import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../neighborhood/neighborhood_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  test('открытие начинает наблюдение именно запрошенной связи', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    expect(harness.state, isA<RelationDetailsLoading>());
    expect(harness.repository.relationWatches, hasLength(1));
    expect(harness.repository.watchAt(0).relationId, harness.relationId);
  });

  test(
    'подтверждённые данные раскрывают описание и обоих участников',
    () async {
      final harness = _RelationDetailsHarness();
      addTearDown(harness.dispose);

      harness.repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: harness.relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
              sourceTitle: 'быть здоровым',
              relatedTitle: 'много ходить',
              sourceActiveRelationCount: 4,
              relatedActiveRelationCount: 7,
              relatedArchiveState: IntentionArchiveState.archived,
              priority: RelationPriority.p3,
              scope: RelationScope.archived,
              description: 'Полное описание связи.',
            ),
            revision: const TestGraphRevision(1),
          );
      await pumpEventQueue();

      final state = harness.state;
      expect(state, isA<RelationDetailsLoaded>());
      final details = (state as RelationDetailsLoaded).details;
      expect(details.relation.id, harness.relationId);
      expect(details.relation.priority, RelationPriority.p3);
      expect(details.relation.scope, RelationScope.archived);
      expect(details.description?.value, 'Полное описание связи.');
      expect(details.source.title, 'быть здоровым');
      expect(details.source.activeRelationCount, 4);
      expect(details.related.title, 'много ходить');
      expect(details.related.archiveState, IntentionArchiveState.archived);
      expect(details.related.activeRelationCount, 7);
    },
  );

  test('подтверждённое отсутствие связи отличается от ошибки', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    harness.repository
        .watchAt(0)
        .emitMissing(revision: const TestGraphRevision(2));
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsNotFound>());
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

    expect(harness.repository.relationWatches, hasLength(1));
    expect(harness.state, isA<RelationDetailsCorruption>());
  });

  test('повтор после недоступности начинает новое наблюдение', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    harness.repository
        .watchAt(0)
        .fail(const LongTermRelationReadUnavailableFailure());
    await pumpEventQueue();
    harness.viewModel.retry();
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsLoading>());
    expect(harness.repository.relationWatches, hasLength(2));
    expect(harness.repository.watchAt(1).relationId, harness.relationId);

    harness.repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: harness.relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
          ),
          revision: const TestGraphRevision(5),
        );
    await pumpEventQueue();

    expect(harness.state, isA<RelationDetailsLoaded>());
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

  test('переименование участника обновляет подтверждённые данные', () async {
    final harness = _RelationDetailsHarness();
    addTearDown(harness.dispose);

    final watch = harness.repository.watchAt(0);
    watch.emitDetails(
      testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'прежнее название',
      ),
      revision: const TestGraphRevision(1),
    );
    await pumpEventQueue();
    watch.emitDetails(
      testRelationDetails(
        relationId: harness.relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'новое название',
        relatedActiveRelationCount: 12,
      ),
      revision: const TestGraphRevision(2),
    );
    await pumpEventQueue();

    final state = harness.state as RelationDetailsLoaded;
    expect(state.details.related.title, 'новое название');
    expect(state.details.related.activeRelationCount, 12);
  });

  test(
    'повторное открытие показывает выполняющееся изменение по ключу связи',
    () async {
      final harness = _RelationDetailsHarness(startUpdateBeforeOpening: true);
      addTearDown(harness.dispose);

      expect(
        harness.state,
        isA<RelationDetailsLoading>().having(
          (state) => state.isOperationRunning,
          'выполняющаяся операция',
          isTrue,
        ),
      );

      harness.repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: harness.relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
            ),
            revision: const TestGraphRevision(1),
          );
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationDetailsLoaded>().having(
          (state) => state.isOperationRunning,
          'выполняющаяся операция',
          isTrue,
        ),
      );
    },
  );

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

      expect(harness.repository.relationWatches, hasLength(2));
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
      expect(harness.repository.relationWatches, hasLength(3));

      harness.repository
          .watchAt(2)
          .emitDetails(
            testRelationDetails(
              relationId: harness.relationId,
              sourceId: testIntentionId(3),
              relatedId: testIntentionId(4),
              sourceTitle: 'новый исходный участник',
              relatedTitle: 'новый связанный участник',
              sourceActiveRelationCount: 7,
              relatedActiveRelationCount: 8,
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
              (state) => state.details.related.activeRelationCount,
              'новое количество связанного участника',
              8,
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
  LongTermRelation copyWithForTest({required RelationPriority priority}) =>
      LongTermRelation(
        id: id,
        sourceIntentionId: sourceIntentionId,
        relatedIntentionId: relatedIntentionId,
        type: type,
        priority: priority,
        scope: scope,
        creationSequence: creationSequence,
      );
}
