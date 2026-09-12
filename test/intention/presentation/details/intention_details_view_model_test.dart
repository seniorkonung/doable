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
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) =>
    ProviderContainer(
      overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
      retry: (retryCount, error) => null,
    );
