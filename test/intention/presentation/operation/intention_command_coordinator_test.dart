import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  group('GraphCommandCoordinator', () {
    test(
      'типизированный ключ не принимает повтор одной формы создания',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final firstForm = IntentionCreationFormKey();
        final secondForm = IntentionCreationFormKey();

        final first = coordinator.acceptCreation(
          firstForm,
          const CreateIntention(title: 'Первое', description: null),
        );
        final repeated = coordinator.acceptCreation(
          firstForm,
          const CreateIntention(title: 'Повтор', description: null),
        );
        final independent = coordinator.acceptCreation(
          secondForm,
          const CreateIntention(title: 'Второе', description: null),
        );

        expect(first, isA<IntentionCommandAccepted>());
        expect(repeated, isA<IntentionCommandAlreadyRunning>());
        expect(independent, isA<IntentionCommandAccepted>());
        expect(repository.commands, hasLength(2));

        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        repository.complete(
          1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await (first as IntentionCommandAccepted).future;
        await (independent as IntentionCommandAccepted).future;
        await coordinator.shutdown();
      },
    );

    test('доставляет подтверждённые результаты в порядке ревизий', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final epoch = Object();
      final completions = <IntentionCommandCompletion>[];
      final subscription = coordinator.intentionCompletions.listen(
        completions.add,
      );
      final firstId = _id(_firstUuid);
      final secondId = _id(_secondUuid);

      final first = coordinator.acceptExisting(
        DeleteIntention(firstId),
        presentationTitle: 'Первое намерение',
      ) as IntentionCommandAccepted;
      final second = coordinator.acceptExisting(
        DeleteIntention(secondId),
        presentationTitle: 'Второе намерение',
      ) as IntentionCommandAccepted;

      repository.complete(
        1,
        _confirmedDeletedResult(secondId, _OrderedTestGraphRevision(epoch, 2)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completions, isEmpty);

      repository.complete(
        0,
        _confirmedDeletedResult(firstId, _OrderedTestGraphRevision(epoch, 1)),
      );
      final firstCompletion = await first.future;
      final secondCompletion = await second.future;

      expect(completions, [same(firstCompletion), same(secondCompletion)]);
      expect(completions.map((completion) => completion.revision), [
        isA<_OrderedTestGraphRevision>().having(
          (revision) => revision.value,
          'номер',
          1,
        ),
        isA<_OrderedTestGraphRevision>().having(
          (revision) => revision.value,
          'номер',
          2,
        ),
      ]);

      coordinator.releaseInitiatorPresentation(firstCompletion.token);
      coordinator.releaseInitiatorPresentation(secondCompletion.token);
      await subscription.cancel();
      await coordinator.shutdown();
    });
  });

  group('GraphCommandCoordinator', () {
    test('generated provider сохраняет один keep-alive coordinator', () {
      final repository = _ControlledGraphRepository();
      final container = ProviderContainer.test(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final provider = graphCommandCoordinatorProvider;

      final first = container.read(provider.notifier);
      final second = container.read(provider.notifier);

      expect(second, same(first));
    });

    test(
      'синхронно принимает command и сохраняет gate одного намерения',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final firstId = _id(_firstUuid);
        final secondId = _id(_secondUuid);

        final first = _acceptExisting(
          coordinator,
          EnableIntentionReadiness(firstId),
        );
        final repeated = _acceptExisting(
          coordinator,
          ArchiveIntention(firstId),
        );
        final independent = _acceptExisting(
          coordinator,
          EnableIntentionReadiness(secondId),
        );

        expect(first, isA<IntentionCommandAccepted>());
        expect(repeated, isA<IntentionCommandAlreadyRunning>());
        expect(independent, isA<IntentionCommandAccepted>());
        expect(repository.commands, [
          isA<EnableIntentionReadiness>(),
          isA<EnableIntentionReadiness>(),
        ]);

        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final firstCompletion =
            await (first as IntentionCommandAccepted).future;
        expect(firstCompletion.kind, IntentionCommandKind.enableReadiness);
        expect(
          firstCompletion.result,
          isA<ResultFailure<IntentionCommandSuccess>>(),
        );

        final next = _acceptExisting(coordinator, ArchiveIntention(firstId));
        expect(next, isA<IntentionCommandAccepted>());
        expect(repository.commands.last, isA<ArchiveIntention>());

        repository.complete(
          1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        repository.complete(
          2,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await (independent as IntentionCommandAccepted).future;
        await (next as IntentionCommandAccepted).future;
        coordinator.releaseInitiatorPresentation(firstCompletion.token);
        await coordinator.shutdown();
      },
    );

    test('не сериализует независимые формы создания общим gate', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);

      final first = _acceptCreation(
        coordinator,
        const CreateIntention(title: 'Первое', description: null),
      );
      final second = _acceptCreation(
        coordinator,
        const CreateIntention(title: 'Второе', description: null),
      );

      expect(first, isA<IntentionCommandAccepted>());
      expect(second, isA<IntentionCommandAccepted>());
      expect(repository.commands, hasLength(2));

      repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await (first as IntentionCommandAccepted).future;
      await (second as IntentionCommandAccepted).future;
      await coordinator.shutdown();
    });

    test(
      'публикует один completion всем текущим data consumers без replay',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final firstConsumer = <IntentionCommandCompletion>[];
        final secondConsumer = <IntentionCommandCompletion>[];
        final firstSubscription = coordinator.intentionCompletions.listen(
          firstConsumer.add,
        );
        final secondSubscription = coordinator.intentionCompletions.listen(
          secondConsumer.add,
        );

        final accepted = _acceptExisting(
          coordinator,
          EnableIntentionReadiness(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final completion = await accepted.future;

        expect(firstConsumer, [same(completion)]);
        expect(secondConsumer, [same(completion)]);

        final lateConsumer = <IntentionCommandCompletion>[];
        final lateSubscription = coordinator.intentionCompletions.listen(
          lateConsumer.add,
        );
        await Future<void>.delayed(Duration.zero);
        expect(lateConsumer, isEmpty);

        coordinator.releaseInitiatorPresentation(completion.token);
        await firstSubscription.cancel();
        await secondSubscription.cancel();
        await lateSubscription.cancel();
        await coordinator.shutdown();
      },
    );

    test('details consumers фильтруют success по идентификатору и игнорируют failure', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final firstId = _id(_firstUuid);
      final secondId = _id(_secondUuid);
      final firstDetails = <IntentionCommandSuccess>[];
      final secondDetails = <IntentionCommandSuccess>[];
      final firstSubscription = coordinator.intentionCompletions.listen(
        (completion) => _collectSuccessFor(
          completion,
          intentionId: firstId,
          target: firstDetails,
        ),
      );
      final secondSubscription = coordinator.intentionCompletions.listen(
        (completion) => _collectSuccessFor(
          completion,
          intentionId: secondId,
          target: secondDetails,
        ),
      );

      final successful = _acceptExisting(
        coordinator,
        DeleteIntention(firstId),
      ) as IntentionCommandAccepted;
      repository.complete(0, _deletedResult(firstId));
      final successfulCompletion = await successful.future;

      final failed = _acceptExisting(
        coordinator,
        ArchiveIntention(secondId),
      ) as IntentionCommandAccepted;
      repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      final failedCompletion = await failed.future;

      expect(firstDetails, [isA<IntentionDeleted>()]);
      expect(secondDetails, isEmpty);

      coordinator.releaseInitiatorPresentation(successfulCompletion.token);
      coordinator.releaseInitiatorPresentation(failedCompletion.token);
      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await coordinator.shutdown();
    });

    test(
      'преобразует неожиданную ошибку repository в typed completion',
      () async {
        final repository = _ControlledGraphRepository()
          ..nextError = StateError('неожиданный отказ');
        final coordinator = _graphCoordinator(repository);

        final accepted = _acceptExisting(
          coordinator,
          ArchiveIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        final completion = await accepted.future;

        expect(
          completion.result,
          isA<ResultFailure<IntentionCommandSuccess>>().having(
            (result) => result.failure,
            'failure',
            isA<IntentionUnexpectedFailure>(),
          ),
        );
        expect(
          _acceptExisting(coordinator, RestoreIntention(_id(_firstUuid))),
          isA<IntentionCommandAccepted>(),
        );
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await coordinator.shutdown();
      },
    );

    test(
      'success сразу доступен оболочке и не выдаёт initiator claim',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final registration = coordinator.registerAppPresentation();
        final id = _id(_firstUuid);

        final accepted = _acceptExisting(
          coordinator,
          DeleteIntention(id),
        ) as IntentionCommandAccepted;
        repository.complete(0, _deletedResult(id));
        final completion = await accepted.future;

        expect(coordinator.claimInitiatorFailure(completion.token), isNull);
        final claim = await registration.nextClaim();
        expect(claim, isA<GraphAppPresentationClaim>());
        expect(claim!.completion, same(completion));

        coordinator.confirmPresentation(claim);
        await coordinator.shutdown();
      },
    );

    test('failure открытой сессии принадлежит инициатору и не блокирует очередь оболочки', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final registration = coordinator.registerAppPresentation();

      final failed = _acceptExisting(
        coordinator,
        ArchiveIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      final succeeded = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_secondUuid)),
      ) as IntentionCommandAccepted;
      repository.complete(0, const ResultFailure(IntentionConflictFailure()));
      repository.complete(1, _deletedResult(_id(_secondUuid)));
      final failedCompletion = await failed.future;
      final succeededCompletion = await succeeded.future;

      final appClaim = await registration.nextClaim();
      expect(appClaim!.completion, same(succeededCompletion));
      coordinator.confirmPresentation(appClaim);

      final initiatorClaim = coordinator.claimInitiatorFailure(
        failedCompletion.token,
      );
      expect(initiatorClaim, isA<GraphInitiatorPresentationClaim>());
      expect(
        coordinator.claimInitiatorFailure(failedCompletion.token),
        same(initiatorClaim),
      );

      var fallbackIssued = false;
      unawaited(registration.nextClaim().then((_) => fallbackIssued = true));
      await Future<void>.delayed(Duration.zero);
      expect(fallbackIssued, isFalse);

      coordinator.confirmPresentation(initiatorClaim!);
      coordinator.releaseInitiatorPresentation(failedCompletion.token);
      await Future<void>.delayed(Duration.zero);
      expect(fallbackIssued, isFalse);

      await coordinator.shutdown();
      expect(fallbackIssued, isTrue);
    });

    test('освобождённая до предъявления ошибка переходит оболочке в прежнем порядке', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final registration = coordinator.registerAppPresentation();

      final failed = _acceptExisting(
        coordinator,
        ArchiveIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      final firstSuccess = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_secondUuid)),
      ) as IntentionCommandAccepted;
      final secondSuccess = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_thirdUuid)),
      ) as IntentionCommandAccepted;
      repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      repository.complete(1, _deletedResult(_id(_secondUuid)));
      repository.complete(2, _deletedResult(_id(_thirdUuid)));
      final failedCompletion = await failed.future;
      await firstSuccess.future;
      await secondSuccess.future;

      final staleInitiatorClaim = coordinator.claimInitiatorFailure(
        failedCompletion.token,
      );
      final first = await registration.nextClaim();
      expect(first!.token, same(firstSuccess.token));

      coordinator.releaseInitiatorPresentation(failedCompletion.token);
      coordinator.releaseInitiatorPresentation(failedCompletion.token);
      coordinator.confirmPresentation(first);

      final fallback = await registration.nextClaim();
      expect(fallback!.token, same(failed.token));
      expect(coordinator.claimInitiatorFailure(failed.token), isNull);
      coordinator.confirmPresentation(staleInitiatorClaim!);
      coordinator.confirmPresentation(fallback);
      coordinator.confirmPresentation(fallback);

      final last = await registration.nextClaim();
      expect(last!.token, same(secondSuccess.token));
      coordinator.confirmPresentation(last);
      await coordinator.shutdown();
    });

    test(
      'выдаёт следующий app claim только после подтверждения текущего',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final registration = coordinator.registerAppPresentation();

        final first = _acceptExisting(
          coordinator,
          DeleteIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        final second = _acceptExisting(
          coordinator,
          DeleteIntention(_id(_secondUuid)),
        ) as IntentionCommandAccepted;
        repository.complete(1, _deletedResult(_id(_secondUuid)));
        repository.complete(0, _deletedResult(_id(_firstUuid)));
        await second.future;

        final firstClaim = await registration.nextClaim();
        expect(firstClaim!.token, same(first.token));

        GraphAppPresentationClaim? secondClaim;
        final pending = registration.nextClaim()
          ..then((claim) => secondClaim = claim);
        expect(registration.nextClaim(), same(pending));
        await Future<void>.delayed(Duration.zero);
        expect(secondClaim, isNull);

        coordinator.confirmPresentation(firstClaim);
        await pending;
        expect(secondClaim!.token, same(second.token));
        coordinator.confirmPresentation(secondClaim!);
        await coordinator.shutdown();
      },
    );

    test('освобождение presenter возвращает неподтверждённый claim без повторной публикации', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final completions = <IntentionCommandCompletion>[];
      final subscription = coordinator.intentionCompletions.listen(
        completions.add,
      );
      final firstPresenter = coordinator.registerAppPresentation();

      final accepted = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      repository.complete(0, _deletedResult(_id(_firstUuid)));
      await accepted.future;

      final staleClaim = await firstPresenter.nextClaim();
      firstPresenter
        ..release()
        ..release();
      expect(await firstPresenter.nextClaim(), isNull);

      final secondPresenter = coordinator.registerAppPresentation();
      final reissued = await secondPresenter.nextClaim();
      expect(reissued!.token, same(staleClaim!.token));
      expect(identical(reissued, staleClaim), isFalse);

      coordinator.confirmPresentation(staleClaim);
      secondPresenter.release();
      final thirdPresenter = coordinator.registerAppPresentation();
      final afterStaleConfirmation = await thirdPresenter.nextClaim();
      expect(afterStaleConfirmation!.token, same(accepted.token));

      coordinator.confirmPresentation(reissued);
      coordinator.confirmPresentation(afterStaleConfirmation);
      expect(completions, hasLength(1));
      expect(repository.commands, hasLength(1));

      await subscription.cancel();
      await coordinator.shutdown();
    });

    test('новый presenter получает завершения, опубликованные без подписчика и во время регистрации', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final firstPresenter = coordinator.registerAppPresentation();
      final idleRequest = firstPresenter.nextClaim();

      final withoutSubscriber = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      final duringRegistration = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_secondUuid)),
      ) as IntentionCommandAccepted;
      firstPresenter.release();
      expect(await idleRequest, isNull);

      repository.complete(0, _deletedResult(_id(_firstUuid)));
      await withoutSubscriber.future;
      final secondPresenter = coordinator.registerAppPresentation();
      final firstRequest = secondPresenter.nextClaim();
      repository.complete(1, _deletedResult(_id(_secondUuid)));
      await duringRegistration.future;

      final first = await firstRequest;
      expect(first!.token, same(withoutSubscriber.token));
      coordinator.confirmPresentation(first);
      final second = await secondPresenter.nextClaim();
      expect(second!.token, same(duringRegistration.token));
      coordinator.confirmPresentation(second);
      await coordinator.shutdown();
    });

    test('следующая регистрация получает выдачу только после освобождения предыдущей', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final previous = coordinator.registerAppPresentation();
      final next = coordinator.registerAppPresentation();
      GraphAppPresentationClaim? issued;
      final request = next.nextClaim()..then((claim) => issued = claim);

      final accepted = _acceptExisting(
        coordinator,
        DeleteIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      repository.complete(0, _deletedResult(_id(_firstUuid)));
      await accepted.future;
      await Future<void>.delayed(Duration.zero);
      expect(issued, isNull);

      previous.release();
      await request;
      expect(issued!.token, same(accepted.token));
      coordinator.confirmPresentation(issued!);
      await coordinator.shutdown();
    });

    test('уход инициатора до terminal outcome передаёт failure оболочке и сохраняет gate', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final registration = coordinator.registerAppPresentation();
      final intentionId = _id(_firstUuid);

      final accepted = _acceptExisting(
        coordinator,
        DeleteIntention(intentionId),
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      expect(coordinator.isRunning(intentionId), isTrue);
      expect(
        _acceptExisting(coordinator, ArchiveIntention(intentionId)),
        isA<IntentionCommandAlreadyRunning>(),
      );
      repository.complete(0, const ResultFailure(IntentionConflictFailure()));
      final completion = await accepted.future;
      final claim = await registration.nextClaim();

      expect(coordinator.isRunning(intentionId), isFalse);
      expect(claim!.completion, same(completion));
      expect(coordinator.claimInitiatorFailure(completion.token), isNull);
      coordinator.confirmPresentation(claim);
      await coordinator.shutdown();
    });

    test('shutdown завершает ожидающий запрос presenter без claim', () async {
      final repository = _ControlledGraphRepository();
      final coordinator = _graphCoordinator(repository);
      final registration = coordinator.registerAppPresentation();
      final request = registration.nextClaim();

      await coordinator.shutdown();

      expect(await request, isNull);
      expect(await coordinator.registerAppPresentation().nextClaim(), isNull);
    });

    test(
      'не удаляет gate новой команды, принятой из completion-listener',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final intentionId = _id(_firstUuid);
        IntentionCommandAccepted? acceptedFromCompletion;
        final subscription = coordinator.intentionCompletions.listen((
          completion,
        ) {
          acceptedFromCompletion = _acceptExisting(
            coordinator,
            ArchiveIntention(intentionId),
          ) as IntentionCommandAccepted;
        });

        final first = _acceptExisting(
          coordinator,
          EnableIntentionReadiness(intentionId),
        ) as IntentionCommandAccepted;
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final firstCompletion = await first.future;

        expect(acceptedFromCompletion, isNotNull);
        expect(
          _acceptExisting(coordinator, RestoreIntention(intentionId)),
          isA<IntentionCommandAlreadyRunning>(),
        );

        await subscription.cancel();
        repository.complete(
          1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final secondCompletion = await acceptedFromCompletion!.future;
        coordinator.releaseInitiatorPresentation(firstCompletion.token);
        coordinator.releaseInitiatorPresentation(secondCompletion.token);
        await coordinator.shutdown();
      },
    );

    test(
      'shutdown синхронно запрещает новую работу и ждёт принятые operations',
      () async {
        final repository = _ControlledGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final first = _acceptExisting(
          coordinator,
          ArchiveIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        final second = _acceptExisting(
          coordinator,
          ArchiveIntention(_id(_secondUuid)),
        ) as IntentionCommandAccepted;

        final shutdown = coordinator.shutdown();
        var shutdownCompleted = false;
        shutdown.then((_) => shutdownCompleted = true);

        expect(coordinator.shutdown(), same(shutdown));
        expect(
          _acceptExisting(coordinator, RestoreIntention(_id(_thirdUuid))),
          isA<GraphCommandCoordinatorDraining>(),
        );
        expect(repository.commands, hasLength(2));

        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await first.future;
        await Future<void>.delayed(Duration.zero);
        expect(shutdownCompleted, isFalse);

        repository.complete(
          1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await second.future;
        await shutdown;
        expect(shutdownCompleted, isTrue);
      },
    );
  });
}

void _collectSuccessFor(
  IntentionCommandCompletion completion, {
  required IntentionId intentionId,
  required List<IntentionCommandSuccess> target,
}) {
  switch (completion.result) {
    case ResultSuccess(:final value) when _successId(value) == intentionId:
      target.add(value);
    case ResultSuccess() || ResultFailure():
  }
}

IntentionId _successId(IntentionCommandSuccess success) => switch (success) {
  IntentionSaved(:final intention) => intention.id,
  IntentionDeleted(:final id) => id,
};

Result<IntentionCommandSuccess> _deletedResult(IntentionId id) => ResultSuccess(
  IntentionDeleted(
    id,
    catalogMutation: IntentionCatalogDeleted(
      revision: const _TestCatalogRevision(),
      entry: _TestCatalogEntrySnapshot(id),
    ),
  ),
);

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _confirmedDeletedResult(
  IntentionId id,
  GraphRevision revision,
) => ResultSuccess(
  ConfirmedGraphResult(
    revision: revision,
    value: IntentionDeleted(
      id,
      catalogMutation: IntentionCatalogDeleted(
        revision: revision,
        entry: _TestCatalogEntrySnapshot(id),
      ),
    ),
  ),
);

GraphCommandCoordinator _graphCoordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

IntentionCommandStart _acceptCreation(
  GraphCommandCoordinator coordinator,
  CreateIntention command,
) => coordinator.acceptCreation(IntentionCreationFormKey(), command);

IntentionCommandStart _acceptExisting(
  GraphCommandCoordinator coordinator,
  ExistingIntentionCommand command,
) => coordinator.acceptExisting(command, presentationTitle: 'Намерение');

final class _ControlledGraphRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

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

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  final commands = <IntentionCommand>[];
  final _results =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  Object? nextError;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return await _executeIntention(command as IntentionCommand)
        as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    commands.add(command);
    final error = nextError;
    if (error != null) {
      nextError = null;
      return Future.error(error);
    }
    final result =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _results.add(result);
    return result.future;
  }

  void complete(int index, Result<IntentionCommandSuccess> result) {
    _results[index].complete(switch (result) {
      ResultSuccess(:final value) => ResultSuccess(
        ConfirmedGraphResult(
          revision: value.catalogMutation.revision,
          value: value,
        ),
      ),
      ResultFailure(:final failure) => ResultFailure(failure),
    });
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => throw UnsupportedError('Группы связей не используются в этих тестах.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в этих тестах.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) =>
      throw UnsupportedError('Подробное чтение не используется в этих тестах.');
}

final class _ControlledPersonalGraphRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

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

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  final commands = <IntentionCommand>[];
  final _results =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return await _executeIntention(command as IntentionCommand)
        as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    commands.add(command);
    final result =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _results.add(result);
    return result.future;
  }

  void complete(
    int index,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) {
    _results[index].complete(result);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => throw UnsupportedError('Группы связей не используются в этих тестах.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в этих тестах.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) =>
      throw UnsupportedError('Подробное чтение не используется в этих тестах.');
}

final class _OrderedTestGraphRevision implements GraphRevision {
  const _OrderedTestGraphRevision(this.epoch, this.value);

  final Object epoch;
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _OrderedTestGraphRevision || !identical(epoch, other.epoch)) {
      return GraphRevisionOrder.differentEpoch;
    }
    return switch (value.compareTo(other.value)) {
      < 0 => GraphRevisionOrder.older,
      0 => GraphRevisionOrder.same,
      _ => GraphRevisionOrder.newer,
    };
  }
}

final class _TestCatalogRevision implements GraphRevision {
  const _TestCatalogRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _TestCatalogEntrySnapshot implements IntentionCatalogEntrySnapshot {
  _TestCatalogEntrySnapshot(IntentionId id)
    : summary = IntentionSummary(
        id: id,
        title: 'Намерение',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 0,
        createdAt: IntentionTimestamp(DateTime.utc(2026)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026)),
      );

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID fixture.',
  ),
};

const _firstUuid = '018f47c2-6b7d-7abc-8def-0123456789ab';
const _secondUuid = '018f47c2-6b7d-7abc-8def-0123456789ac';
const _thirdUuid = '018f47c2-6b7d-7abc-8def-0123456789ad';
