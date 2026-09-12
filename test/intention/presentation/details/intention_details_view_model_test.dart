import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart';
import 'package:doable/src/intention/presentation/operation/intention_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'details_test_support.dart';

void main() {
  test('различает загрузку и подтверждённое активное намерение', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    final intention = testDetailsIntention(
      title: 'Сохранить пользовательский текст',
      readiness: IntentionReadiness.ready,
    );
    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoading>(),
    );
    await waitForDetailRequests(repository, 1);
    expect(repository.detailIds.single, intention.id);

    repository.detailRequests.single.add(ResultSuccess(intention));
    await pumpEventQueue();

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoaded>()
          .having((state) => state.intention, 'намерение', same(intention))
          .having(
            (state) => state.isOperationRunning,
            'выполняющаяся операция',
            isFalse,
          ),
    );
  });

  test('отличает подтверждённое отсутствие намерения', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    final id = testDetailsIntentionId(2);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    await waitForDetailRequests(repository, 1);

    repository.detailRequests.single.add(const ResultSuccess(null));
    await pumpEventQueue();

    expect(
      container.read(intentionDetailsViewModelProvider(id)),
      isA<IntentionDetailsNotFound>(),
    );
  });

  test('различает устранимый и терминальные отказы чтения', () async {
    final scenarios = <(IntentionFailure, Matcher)>[
      (const IntentionUnavailableFailure(), isA<IntentionDetailsUnavailable>()),
      (const IntentionCorruptionFailure(), isA<IntentionDetailsCorruption>()),
      (const IntentionUnexpectedFailure(), isA<IntentionDetailsUnexpected>()),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final id = testDetailsIntentionId(index + 10);
      final subscription = container.listen(
        intentionDetailsViewModelProvider(id),
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);

      final (failure, expectedState) = scenarios[index];
      repository.detailRequests.single.add(ResultFailure(failure));
      await pumpEventQueue();

      expect(
        container.read(intentionDetailsViewModelProvider(id)),
        expectedState,
      );
      subscription.close();
      container.dispose();
    }
  });

  test(
    'повтор недоступного чтения сменяет generation только выбранного намерения',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final firstId = testDetailsIntentionId(21);
      final secondId = testDetailsIntentionId(22);
      final firstSubscription = container.listen(
        intentionDetailsViewModelProvider(firstId),
        (_, _) {},
        fireImmediately: true,
      );
      final secondSubscription = container.listen(
        intentionDetailsViewModelProvider(secondId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(firstSubscription.close);
      addTearDown(secondSubscription.close);
      addTearDown(container.dispose);
      await waitForDetailRequests(repository, 2);

      repository.detailRequests[0].add(
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await pumpEventQueue();
      container
          .read(intentionDetailsViewModelProvider(firstId).notifier)
          .retry();
      await waitForDetailRequests(repository, 3);

      expect(repository.detailIds, [firstId, secondId, firstId]);
      expect(
        container.read(intentionDetailsViewModelProvider(firstId)),
        isA<IntentionDetailsLoading>(),
      );

      final stale = testDetailsIntention(index: 21, title: 'Устаревшее');
      repository.detailRequests[0].add(ResultSuccess(stale));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(firstId)),
        isA<IntentionDetailsLoading>(),
      );

      final current = testDetailsIntention(index: 21, title: 'Актуальное');
      repository.detailRequests[2].add(ResultSuccess(current));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(firstId)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention,
          'актуальное намерение',
          same(current),
        ),
      );
      expect(repository.detailIds.where((id) => id == secondId), hasLength(1));
    },
  );

  test('терминальный отказ не допускает обычный повтор', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    final id = testDetailsIntentionId(30);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(
      const ResultFailure(IntentionCorruptionFailure()),
    );
    await pumpEventQueue();

    container.read(intentionDetailsViewModelProvider(id).notifier).retry();
    await pumpEventQueue();

    expect(repository.detailRequests, hasLength(1));
    expect(
      container.read(intentionDetailsViewModelProvider(id)),
      isA<IntentionDetailsCorruption>(),
    );
  });

  test(
    'уход последнего слушателя отменяет чтение, а повтор открывает новое',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final id = testDetailsIntentionId(40);
      final firstSubscription = container.listen(
        intentionDetailsViewModelProvider(id),
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);

      firstSubscription.close();
      await pumpEventQueue();
      expect(repository.detailRequests[0].cancellationCount, 1);

      final secondSubscription = container.listen(
        intentionDetailsViewModelProvider(id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(secondSubscription.close);
      await waitForDetailRequests(repository, 2);

      expect(repository.detailIds, [id, id]);
    },
  );

  test('повторное открытие отражает сохраняющийся gate намерения', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 50);
    final coordinator = container.read(
      intentionCommandCoordinatorProvider.notifier,
    );
    final start = coordinator.accept(DeleteIntention(intention.id));
    expect(start, isA<IntentionCommandAccepted>());

    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoading>().having(
        (state) => state.isOperationRunning,
        'выполняющаяся операция',
        isTrue,
      ),
    );

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await (start as IntentionCommandAccepted).future;
  });

  test(
    'IntentionSaved становится авторитетным до snapshot новой generation',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final before = testDetailsIntention(index: 60, title: 'Прежнее');
      final saved = testDetailsIntention(index: 60, title: 'Сохранённое');
      final refreshed = testDetailsIntention(index: 60, title: 'Перечитанное');
      final subscription = container.listen(
        intentionDetailsViewModelProvider(before.id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(before));
      await pumpEventQueue();

      final start = container
          .read(intentionCommandCoordinatorProvider.notifier)
          .accept(
            UpdateIntention(
              id: before.id,
              title: saved.title,
              description: saved.description,
            ),
          );
      expect(start, isA<IntentionCommandAccepted>());
      repository.completeCommand(
        0,
        testDetailsSavedResult(saved, before: before),
      );
      await (start as IntentionCommandAccepted).future;
      await waitForDetailRequests(repository, 2);

      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention,
          'подтверждённое намерение',
          same(saved),
        ),
      );

      repository.detailRequests[0].add(ResultSuccess(before));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention,
          'намерение после запоздалого snapshot',
          same(saved),
        ),
      );

      repository.detailRequests[1].add(ResultSuccess(refreshed));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention,
          'snapshot новой generation',
          same(refreshed),
        ),
      );
    },
  );

  test('no-op IntentionSaved запускает новую detail generation', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 61);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();

    final start = container
        .read(intentionCommandCoordinatorProvider.notifier)
        .accept(
          UpdateIntention(
            id: intention.id,
            title: intention.title,
            description: intention.description,
          ),
        );
    repository.completeCommand(0, testDetailsSavedResult(intention));
    await (start as IntentionCommandAccepted).future;
    await waitForDetailRequests(repository, 2);

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoaded>().having(
        (state) => state.intention,
        'подтверждённое намерение',
        same(intention),
      ),
    );
  });

  test(
    'повторно открытый details слушает completion до первого чтения',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final before = testDetailsIntention(index: 64, title: 'Прежнее');
      final saved = testDetailsIntention(index: 64, title: 'Сохранённое');
      final start = container
          .read(intentionCommandCoordinatorProvider.notifier)
          .accept(
            UpdateIntention(
              id: before.id,
              title: saved.title,
              description: saved.description,
            ),
          );
      expect(start, isA<IntentionCommandAccepted>());
      repository.onWatchById = (id) {
        repository.onWatchById = null;
        repository.completeCommand(
          0,
          testDetailsSavedResult(saved, before: before),
        );
      };

      final subscription = container.listen(
        intentionDetailsViewModelProvider(before.id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await (start as IntentionCommandAccepted).future;
      await waitForDetailRequests(repository, 2);

      expect(repository.detailIds, [before.id, before.id]);
      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention,
          'подтверждённое намерение',
          same(saved),
        ),
      );
    },
  );

  test('failure completion сохраняет snapshot и текущую generation', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 62);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();

    final start = container
        .read(intentionCommandCoordinatorProvider.notifier)
        .accept(DeleteIntention(intention.id));
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await (start as IntentionCommandAccepted).future;
    await pumpEventQueue();

    expect(repository.detailRequests, hasLength(1));
    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoaded>().having(
        (state) => state.intention,
        'последний подтверждённый snapshot',
        same(intention),
      ),
    );
  });

  test(
    'IntentionDeleted завершает details и отбрасывает прежний snapshot',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final intention = testDetailsIntention(index: 63);
      final subscription = container.listen(
        intentionDetailsViewModelProvider(intention.id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await pumpEventQueue();

      final start = container
          .read(intentionCommandCoordinatorProvider.notifier)
          .accept(DeleteIntention(intention.id));
      repository.completeCommand(0, testDetailsDeletedResult(intention));
      await (start as IntentionCommandAccepted).future;
      await pumpEventQueue();

      expect(
        container.read(intentionDetailsViewModelProvider(intention.id)),
        isA<IntentionDetailsDeleted>(),
      );
      expect(repository.detailRequests[0].cancellationCount, 1);

      repository.detailRequests[0].add(ResultSuccess(intention));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(intention.id)),
        isA<IntentionDetailsDeleted>(),
      );
    },
  );
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) =>
    ProviderContainer(
      overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
      retry: (retryCount, error) => null,
    );
