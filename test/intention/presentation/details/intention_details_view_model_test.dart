import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart';
import 'package:doable/src/intention/presentation/operation/intention_repository_provider.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
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

  test('передаёт изменение активного и архивного намерения через coordinator без optimistic state', () async {
    for (final archiveState in IntentionArchiveState.values) {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final intention = testDetailsIntention(
        index: archiveState.index + 51,
        title: 'Прежнее название',
        description: 'Прежнее описание',
        archiveState: archiveState,
      );
      final provider = intentionDetailsViewModelProvider(intention.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await pumpEventQueue();

      final details = container.read(provider.notifier)
        ..beginEditing()
        ..changeTitle('  Новое название  ')
        ..changeDescription('  Новое описание\n')
        ..saveChanges()
        ..saveChanges();

      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<UpdateIntention>()
            .having((command) => command.id, 'идентификатор', intention.id)
            .having(
              (command) => command.title,
              'название',
              '  Новое название  ',
            )
            .having(
              (command) => command.description,
              'описание',
              '  Новое описание\n',
            ),
      );
      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention,
              'последнее подтверждённое намерение',
              same(intention),
            )
            .having(
              (state) => state.edit?.operation,
              'наблюдаемая update-операция',
              isA<OperationRunning<Intention>>(),
            )
            .having(
              (state) => state.isOperationRunning,
              'единый gate намерения',
              isTrue,
            ),
      );

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await pumpEventQueue();
      subscription.close();
      container.dispose();
      expect(details, isNotNull);
    }
  });

  test('сохраняет поля и snapshot для всех failures изменения', () async {
    final scenarios = <(IntentionFailure, bool)>[
      (
        const IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
        false,
      ),
      (const IntentionNotFoundFailure(), false),
      (const IntentionConflictFailure(), false),
      (const IntentionUnavailableFailure(), true),
      (const IntentionCorruptionFailure(), false),
      (const IntentionUnexpectedFailure(), false),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final intention = testDetailsIntention(index: index + 70);
      final provider = intentionDetailsViewModelProvider(intention.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await pumpEventQueue();
      container.read(provider.notifier)
        ..beginEditing()
        ..changeTitle('Введённое название $index')
        ..changeDescription('Введённое описание $index')
        ..saveChanges();

      final (failure, canRetry) = scenarios[index];
      repository.completeCommand(0, ResultFailure(failure));
      await pumpEventQueue();

      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention,
              'последний подтверждённый snapshot',
              same(intention),
            )
            .having(
              (state) => state.edit?.title,
              'введённое название',
              'Введённое название $index',
            )
            .having(
              (state) => state.edit?.description,
              'введённое описание',
              'Введённое описание $index',
            )
            .having(
              (state) => state.edit?.canRetry,
              'доступность обычного повтора',
              canRetry,
            )
            .having(
              (state) => state.isOperationRunning,
              'освобождённый gate',
              isFalse,
            ),
      );

      subscription.close();
      container.dispose();
    }
  });

  test('подтверждённое изменение проходит generation barrier и принадлежит открытому details', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final before = testDetailsIntention(index: 80, title: 'Прежнее');
    final saved = testDetailsIntention(
      index: 80,
      title: 'Сохранённое',
      description: 'Сохранённое описание',
    );
    final refreshed = testDetailsIntention(index: 80, title: 'Перечитанное');
    final provider = intentionDetailsViewModelProvider(before.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(before));
    await pumpEventQueue();

    final coordinator = container.read(
      intentionCommandCoordinatorProvider.notifier,
    );
    final fallback =
        Completer<Future<IntentionCatalogFallbackPresentationClaim?>>();
    final completionTokens = <IntentionOperationToken>[];
    final completionSubscription = coordinator.completions.listen((event) {
      completionTokens.add(event.token);
      fallback.complete(coordinator.claimCatalogFallback(event.token));
    });
    addTearDown(completionSubscription.cancel);

    container.read(provider.notifier)
      ..beginEditing()
      ..changeTitle(saved.title)
      ..changeDescription(saved.description!)
      ..saveChanges();
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await waitForDetailRequests(repository, 2);

    expect(
      container.read(provider),
      isA<IntentionDetailsLoaded>()
          .having(
            (state) => state.intention,
            'подтверждённый success',
            same(saved),
          )
          .having((state) => state.edit, 'завершённая форма', isNull)
          .having(
            (state) => state.event,
            'одноразовое подтверждение',
            isA<IntentionDetailsSaved>(),
          ),
    );
    expect(await (await fallback.future), isNull);

    repository.detailRequests[0].add(ResultSuccess(before));
    await pumpEventQueue();
    expect(
      (container.read(provider) as IntentionDetailsLoaded).intention,
      same(saved),
    );

    repository.detailRequests[1].add(ResultSuccess(refreshed));
    await pumpEventQueue();
    expect(
      (container.read(provider) as IntentionDetailsLoaded).intention,
      same(refreshed),
    );
    expect(completionTokens, hasLength(1));
  });

  test('disposal передаёт update outcome каталогу и сохраняет gate при повторном открытии', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 81);
    final provider = intentionDetailsViewModelProvider(intention.id);
    final firstSubscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();
    container.read(provider.notifier)
      ..beginEditing()
      ..changeTitle('Позднее изменение')
      ..saveChanges();

    final coordinator = container.read(
      intentionCommandCoordinatorProvider.notifier,
    );
    final fallback =
        Completer<Future<IntentionCatalogFallbackPresentationClaim?>>();
    final completionSubscription = coordinator.completions.listen((event) {
      fallback.complete(coordinator.claimCatalogFallback(event.token));
    });
    addTearDown(completionSubscription.cancel);
    firstSubscription.close();
    await pumpEventQueue();

    final reopenedSubscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(reopenedSubscription.close);
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(intention));
    await pumpEventQueue();
    final reopened = container.read(provider) as IntentionDetailsLoaded;
    expect(reopened.isOperationRunning, isTrue);
    container.read(provider.notifier).beginEditing();
    expect((container.read(provider) as IntentionDetailsLoaded).edit, isNull);

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    final claim = await (await fallback.future);
    expect(claim, isA<IntentionCatalogFallbackPresentationClaim>());
    coordinator.confirmPresentation(claim!);
    await pumpEventQueue();

    expect(
      (container.read(provider) as IntentionDetailsLoaded).isOperationRunning,
      isFalse,
    );
    container.read(provider.notifier).beginEditing();
    expect(
      (container.read(provider) as IntentionDetailsLoaded).edit,
      isNotNull,
    );
  });

  test('retry изменения получает новый token без прежнего failure', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 82);
    final provider = intentionDetailsViewModelProvider(intention.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();
    final tokens = <IntentionOperationToken>[];
    final fallbackClaims =
        <Future<IntentionCatalogFallbackPresentationClaim?>>[];
    final coordinator = container.read(
      intentionCommandCoordinatorProvider.notifier,
    );
    final coordinatorSubscription = coordinator.completions.listen((
      completion,
    ) {
      tokens.add(completion.token);
      fallbackClaims.add(coordinator.claimCatalogFallback(completion.token));
    });
    addTearDown(coordinatorSubscription.cancel);

    final details = container.read(provider.notifier)
      ..beginEditing()
      ..changeTitle('Исправленное намерение')
      ..saveChanges();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(
      (container.read(provider) as IntentionDetailsLoaded).edit?.canRetry,
      isTrue,
    );

    details.saveChanges();
    repository.completeCommand(
      1,
      testDetailsSavedResult(
        testDetailsIntention(index: 82, title: 'Исправленное намерение'),
        before: intention,
      ),
    );
    await waitForDetailRequests(repository, 2);

    expect(tokens, hasLength(2));
    expect(identical(tokens.first, tokens.last), isFalse);
    expect(await Future.wait(fallbackClaims), everyElement(isNull));
    expect(
      (container.read(provider) as IntentionDetailsLoaded).event,
      isA<IntentionDetailsSaved>(),
    );
  });

  test('проводит readiness, архивирование и восстановление через общий gate и generation barrier', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    var confirmed = testDetailsIntention(index: 83);
    final provider = intentionDetailsViewModelProvider(confirmed.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(confirmed));
    await pumpEventQueue();
    final details = container.read(provider.notifier);

    final scenarios =
        <
          (
            void Function(),
            Matcher,
            IntentionDetailsStateChangeKind,
            Intention,
            Matcher,
          )
        >[
          (
            details.enableReadiness,
            isA<EnableIntentionReadiness>(),
            IntentionDetailsStateChangeKind.enableReadiness,
            testDetailsIntention(
              index: 83,
              readiness: IntentionReadiness.ready,
            ),
            isA<IntentionDetailsReadinessEnabled>(),
          ),
          (
            details.disableReadiness,
            isA<DisableIntentionReadiness>(),
            IntentionDetailsStateChangeKind.disableReadiness,
            testDetailsIntention(index: 83),
            isA<IntentionDetailsReadinessDisabled>(),
          ),
          (
            details.archive,
            isA<ArchiveIntention>(),
            IntentionDetailsStateChangeKind.archive,
            testDetailsIntention(
              index: 83,
              archiveState: IntentionArchiveState.archived,
            ),
            isA<IntentionDetailsArchived>(),
          ),
          (
            details.restore,
            isA<RestoreIntention>(),
            IntentionDetailsStateChangeKind.restore,
            testDetailsIntention(index: 83),
            isA<IntentionDetailsRestored>(),
          ),
        ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final (start, commandMatcher, kind, saved, eventMatcher) =
          scenarios[index];
      final before = confirmed;
      start();
      start();

      expect(repository.commands, hasLength(index + 1));
      expect(repository.commands[index], commandMatcher);
      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention,
              'последний подтверждённый snapshot',
              same(before),
            )
            .having((state) => state.stateChange?.kind, 'вид перехода', kind)
            .having(
              (state) => state.stateChange?.operation,
              'выполняющийся переход',
              isA<OperationRunning<Intention>>(),
            )
            .having((state) => state.isOperationRunning, 'общий gate', isTrue),
      );

      repository.completeCommand(
        index,
        testDetailsSavedResult(saved, before: before),
      );
      await waitForDetailRequests(repository, index + 2);

      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention,
              'подтверждённый переход',
              same(saved),
            )
            .having((state) => state.stateChange, 'завершённый переход', isNull)
            .having(
              (state) => state.event,
              'одноразовое подтверждение',
              eventMatcher,
            ),
      );

      repository.detailRequests[index].add(ResultSuccess(before));
      await pumpEventQueue();
      expect(
        (container.read(provider) as IntentionDetailsLoaded).intention,
        same(saved),
      );

      repository.detailRequests[index + 1].add(ResultSuccess(saved));
      await pumpEventQueue();
      details.consumeEvent();
      confirmed = saved;
    }
  });

  test('failure перехода сохраняет snapshot и допускает retry только для unavailable', () async {
    final scenarios = <(IntentionFailure, bool)>[
      (const IntentionNotFoundFailure(), false),
      (const IntentionUnavailableFailure(), true),
      (const IntentionCorruptionFailure(), false),
      (const IntentionUnexpectedFailure(), false),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final intention = testDetailsIntention(index: 90 + index);
      final provider = intentionDetailsViewModelProvider(intention.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await pumpEventQueue();

      final details = container.read(provider.notifier)..enableReadiness();
      final (failure, canRetry) = scenarios[index];
      repository.completeCommand(0, ResultFailure(failure));
      await pumpEventQueue();

      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention,
              'последний подтверждённый snapshot',
              same(intention),
            )
            .having(
              (state) => state.stateChange?.canRetry,
              'доступность обычного повтора',
              canRetry,
            )
            .having(
              (state) => state.isOperationRunning,
              'освобождённый gate',
              isFalse,
            ),
      );

      details.retryStateChange();
      expect(repository.commands, hasLength(canRetry ? 2 : 1));
      if (!canRetry) {
        details.archive();
        expect(repository.commands, hasLength(2));
      }

      repository.completeCommand(
        1,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await pumpEventQueue();
      subscription.close();
      container.dispose();
    }
  });

  test(
    'gate перехода переживает disposal и не блокирует другое намерение',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final first = testDetailsIntention(index: 94);
      final second = testDetailsIntention(index: 95);
      final firstProvider = intentionDetailsViewModelProvider(first.id);
      final firstSubscription = container.listen(
        firstProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(first));
      await pumpEventQueue();
      container.read(firstProvider.notifier).enableReadiness();
      firstSubscription.close();
      await pumpEventQueue();

      final reopenedSubscription = container.listen(
        firstProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(reopenedSubscription.close);
      final secondProvider = intentionDetailsViewModelProvider(second.id);
      final secondSubscription = container.listen(
        secondProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(secondSubscription.close);
      await waitForDetailRequests(repository, 3);
      repository.detailRequests[1].add(ResultSuccess(first));
      repository.detailRequests[2].add(ResultSuccess(second));
      await pumpEventQueue();

      container.read(firstProvider.notifier).archive();
      container.read(secondProvider.notifier).archive();
      expect(repository.commands, hasLength(2));
      expect(repository.commands[0], isA<EnableIntentionReadiness>());
      expect(repository.commands[1], isA<ArchiveIntention>());
      expect(
        (container.read(
          firstProvider,
        ) as IntentionDetailsLoaded).isOperationRunning,
        isTrue,
      );

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      repository.completeCommand(
        1,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await pumpEventQueue();
    },
  );

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
