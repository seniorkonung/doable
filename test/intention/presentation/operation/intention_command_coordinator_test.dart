import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart'
    show IntentionCommandCoordinator, intentionCommandCoordinatorProvider;
import 'package:doable/src/intention/presentation/operation/intention_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final subscription = coordinator.completions.listen(completions.add);
      final firstId = _id(_firstUuid);
      final secondId = _id(_secondUuid);

      final first = coordinator.acceptExisting(
        DeleteIntention(firstId),
      ) as IntentionCommandAccepted;
      final second = coordinator.acceptExisting(
        DeleteIntention(secondId),
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

    test(
      'сохраняет завершение для позднего fallback до предъявления',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _graphCoordinator(repository);
        final accepted = coordinator.acceptExisting(
          ArchiveIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;

        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final completion = await accepted.future;
        coordinator.releaseInitiatorPresentation(completion.token);

        final fallback = await coordinator.claimCatalogFallback(
          completion.token,
        );
        expect(fallback, isA<IntentionCatalogFallbackPresentationClaim>());
        expect(fallback!.completion, same(completion));

        coordinator.confirmPresentation(fallback);
        expect(
          await coordinator.claimCatalogFallback(completion.token),
          isNull,
        );
        await coordinator.shutdown();
      },
    );
  });

  group('IntentionCommandCoordinator', () {
    test('generated provider сохраняет один keep-alive coordinator', () {
      final repository = _ControlledIntentionRepository();
      final container = ProviderContainer.test(
        overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
      );
      final provider = intentionCommandCoordinatorProvider;

      final first = container.read(provider.notifier);
      final second = container.read(provider.notifier);

      expect(second, same(first));
    });

    test(
      'синхронно принимает command и сохраняет gate одного намерения',
      () async {
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        final firstId = _id(_firstUuid);
        final secondId = _id(_secondUuid);

        final first = coordinator.accept(EnableIntentionReadiness(firstId));
        final repeated = coordinator.accept(ArchiveIntention(firstId));
        final independent = coordinator.accept(
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

        final next = coordinator.accept(ArchiveIntention(firstId));
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
      final repository = _ControlledIntentionRepository();
      final coordinator = _coordinator(repository);

      final first = coordinator.accept(
        const CreateIntention(title: 'Первое', description: null),
      );
      final second = coordinator.accept(
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
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        final firstConsumer = <IntentionCommandCompletion>[];
        final secondConsumer = <IntentionCommandCompletion>[];
        final firstSubscription = coordinator.completions.listen(
          firstConsumer.add,
        );
        final secondSubscription = coordinator.completions.listen(
          secondConsumer.add,
        );

        final accepted = coordinator.accept(
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
        final lateSubscription = coordinator.completions.listen(
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
      final repository = _ControlledIntentionRepository();
      final coordinator = _coordinator(repository);
      final firstId = _id(_firstUuid);
      final secondId = _id(_secondUuid);
      final firstDetails = <IntentionCommandSuccess>[];
      final secondDetails = <IntentionCommandSuccess>[];
      final firstSubscription = coordinator.completions.listen(
        (completion) => _collectSuccessFor(
          completion,
          intentionId: firstId,
          target: firstDetails,
        ),
      );
      final secondSubscription = coordinator.completions.listen(
        (completion) => _collectSuccessFor(
          completion,
          intentionId: secondId,
          target: secondDetails,
        ),
      );

      final successful = coordinator.accept(
        DeleteIntention(firstId),
      ) as IntentionCommandAccepted;
      repository.complete(0, _deletedResult(firstId));
      final successfulCompletion = await successful.future;

      final failed = coordinator.accept(
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
        final repository = _ControlledIntentionRepository()
          ..nextError = StateError('неожиданный отказ');
        final coordinator = _coordinator(repository);

        final accepted = coordinator.accept(
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
          coordinator.accept(RestoreIntention(_id(_firstUuid))),
          isA<IntentionCommandAccepted>(),
        );
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await coordinator.shutdown();
      },
    );

    test('инициатор имеет приоритетный взаимоисключающий claim', () async {
      final repository = _ControlledIntentionRepository();
      final coordinator = _coordinator(repository);
      late Future<IntentionCatalogFallbackPresentationClaim?> fallback;
      final subscription = coordinator.completions.listen((completion) {
        fallback = coordinator.claimCatalogFallback(completion.token);
      });

      final accepted = coordinator.accept(
        ArchiveIntention(_id(_firstUuid)),
      ) as IntentionCommandAccepted;
      repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      final completion = await accepted.future;
      final claim = coordinator.claimInitiator(completion.token);

      expect(claim, isA<IntentionInitiatorPresentationClaim>());
      coordinator.confirmPresentation(claim!);
      expect(await fallback, isNull);
      expect(coordinator.claimInitiator(completion.token), isNull);

      await subscription.cancel();
      await coordinator.shutdown();
    });

    test('disposal до terminal outcome передаёт claim каталогу', () async {
      final repository = _ControlledIntentionRepository();
      final coordinator = _coordinator(repository);
      final intentionId = _id(_firstUuid);
      late Future<IntentionCatalogFallbackPresentationClaim?> fallback;
      final subscription = coordinator.completions.listen((completion) {
        fallback = coordinator.claimCatalogFallback(completion.token);
      });

      final accepted = coordinator.accept(
        DeleteIntention(intentionId),
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      expect(coordinator.isRunning(intentionId), isTrue);
      expect(
        coordinator.accept(ArchiveIntention(intentionId)),
        isA<IntentionCommandAlreadyRunning>(),
      );
      repository.complete(0, const ResultFailure(IntentionConflictFailure()));
      final completion = await accepted.future;
      final claim = await fallback;

      expect(coordinator.isRunning(intentionId), isFalse);
      expect(claim, isA<IntentionCatalogFallbackPresentationClaim>());
      expect(claim!.completion, same(completion));
      expect(coordinator.claimInitiator(completion.token), isNull);
      coordinator.confirmPresentation(claim);

      await subscription.cancel();
      await coordinator.shutdown();
    });

    test(
      'гонка terminal outcome и disposal сохраняет fallback claim',
      () async {
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        late Future<IntentionCatalogFallbackPresentationClaim?> fallback;
        final subscription = coordinator.completions.listen((completion) {
          fallback = coordinator.claimCatalogFallback(completion.token);
        });

        final accepted = coordinator.accept(
          RestoreIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final completion = await accepted.future;
        coordinator.releaseInitiatorPresentation(completion.token);

        final claim = await fallback;
        expect(claim, isA<IntentionCatalogFallbackPresentationClaim>());
        coordinator.confirmPresentation(claim!);

        await subscription.cancel();
        await coordinator.shutdown();
      },
    );

    test(
      'табличная матрица failures сохраняет единственного presentation owner',
      () async {
        final failures = <IntentionFailure>[
          const IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(
              field: IntentionTextField.title,
              reason: IntentionTextValidationReason.empty,
            ),
          ),
          const IntentionNotFoundFailure(),
          const IntentionConflictFailure(),
          const IntentionUnavailableFailure(),
          const IntentionCorruptionFailure(),
          const IntentionUnexpectedFailure(),
        ];

        for (var index = 0; index < failures.length; index += 1) {
          final repository = _ControlledIntentionRepository();
          final coordinator = _coordinator(repository);
          final completions = <IntentionCommandCompletion>[];
          final fallbackClaims =
              <Future<IntentionCatalogFallbackPresentationClaim?>>[];
          final subscription = coordinator.completions.listen((completion) {
            completions.add(completion);
            fallbackClaims.add(
              coordinator.claimCatalogFallback(completion.token),
            );
          });
          final id = _id(_firstUuid);
          final failure = failures[index];

          final owned = coordinator.accept(
            ArchiveIntention(id),
          ) as IntentionCommandAccepted;
          repository.complete(
            0,
            ResultFailure<IntentionCommandSuccess>(failure),
          );
          final ownedCompletion = await owned.future;
          final initiator = coordinator.claimInitiator(owned.token);

          expect(
            ownedCompletion.result,
            isA<ResultFailure<IntentionCommandSuccess>>().having(
              (result) => result.failure,
              'failure',
              same(failure),
            ),
          );
          expect(initiator, isA<IntentionInitiatorPresentationClaim>());
          coordinator.confirmPresentation(initiator!);
          expect(await fallbackClaims[0], isNull);
          expect(coordinator.isRunning(id), isFalse);

          final released = coordinator.accept(
            RestoreIntention(id),
          ) as IntentionCommandAccepted;
          if (index.isEven) {
            coordinator.releaseInitiatorPresentation(released.token);
            repository.complete(
              1,
              ResultFailure<IntentionCommandSuccess>(failure),
            );
            await released.future;
          } else {
            repository.complete(
              1,
              ResultFailure<IntentionCommandSuccess>(failure),
            );
            await released.future;
            coordinator.releaseInitiatorPresentation(released.token);
          }

          final fallback = await fallbackClaims[1];
          expect(completions, hasLength(2));
          expect(identical(owned.token, released.token), isFalse);
          expect(fallback, isA<IntentionCatalogFallbackPresentationClaim>());
          expect(
            fallback!.completion.result,
            isA<ResultFailure<IntentionCommandSuccess>>().having(
              (result) => result.failure,
              'failure',
              same(failure),
            ),
          );
          expect(coordinator.claimInitiator(released.token), isNull);
          expect(coordinator.isRunning(id), isFalse);
          coordinator.confirmPresentation(fallback);
          coordinator.confirmPresentation(fallback);
          expect(
            await coordinator.claimCatalogFallback(released.token),
            isNull,
          );

          await subscription.cancel();
          await coordinator.shutdown();
        }
      },
    );

    test(
      'не удаляет gate новой команды, принятой из completion-listener',
      () async {
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        final intentionId = _id(_firstUuid);
        IntentionCommandAccepted? acceptedFromCompletion;
        final subscription = coordinator.completions.listen((completion) {
          acceptedFromCompletion = coordinator.accept(
            ArchiveIntention(intentionId),
          ) as IntentionCommandAccepted;
        });

        final first = coordinator.accept(
          EnableIntentionReadiness(intentionId),
        ) as IntentionCommandAccepted;
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        final firstCompletion = await first.future;

        expect(acceptedFromCompletion, isNotNull);
        expect(
          coordinator.accept(RestoreIntention(intentionId)),
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
      'освобождение инициатора во время публикации не опережает каталог',
      () async {
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        final releaseSubscription = coordinator.completions.listen(
          (completion) =>
              coordinator.releaseInitiatorPresentation(completion.token),
        );
        late Future<IntentionCatalogFallbackPresentationClaim?> fallback;
        final catalogSubscription = coordinator.completions.listen((
          completion,
        ) {
          fallback = coordinator.claimCatalogFallback(completion.token);
        });

        final accepted = coordinator.accept(
          ArchiveIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        repository.complete(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await accepted.future;

        final claim = await fallback;
        expect(claim, isA<IntentionCatalogFallbackPresentationClaim>());
        coordinator.confirmPresentation(claim!);

        await releaseSubscription.cancel();
        await catalogSubscription.cancel();
        await coordinator.shutdown();
      },
    );

    test(
      'shutdown синхронно запрещает новую работу и ждёт принятые operations',
      () async {
        final repository = _ControlledIntentionRepository();
        final coordinator = _coordinator(repository);
        final first = coordinator.accept(
          ArchiveIntention(_id(_firstUuid)),
        ) as IntentionCommandAccepted;
        final second = coordinator.accept(
          ArchiveIntention(_id(_secondUuid)),
        ) as IntentionCommandAccepted;

        final shutdown = coordinator.shutdown();
        var shutdownCompleted = false;
        shutdown.then((_) => shutdownCompleted = true);

        expect(coordinator.shutdown(), same(shutdown));
        expect(
          coordinator.accept(RestoreIntention(_id(_thirdUuid))),
          isA<IntentionCommandCoordinatorDraining>(),
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

GraphCommandCoordinator _graphCoordinator(
  _ControlledPersonalGraphRepository repository,
) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

IntentionCommandCoordinator _coordinator(
  _ControlledIntentionRepository repository,
) {
  final container = ProviderContainer.test(
    overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(intentionCommandCoordinatorProvider.notifier);
}

final class _ControlledIntentionRepository implements IntentionRepository {
  final commands = <IntentionCommand>[];
  final _results = <Completer<Result<IntentionCommandSuccess>>>[];
  Object? nextError;

  @override
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) {
    commands.add(command);
    final error = nextError;
    if (error != null) {
      nextError = null;
      return Future.error(error);
    }
    final result = Completer<Result<IntentionCommandSuccess>>();
    _results.add(result);
    return result.future;
  }

  void complete(int index, Result<IntentionCommandSuccess> result) {
    _results[index].complete(result);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Stream<Result<Intention?>> watchById(IntentionId id) =>
      throw UnsupportedError('Подробное чтение не используется в этих тестах.');
}

final class _ControlledPersonalGraphRepository
    implements PersonalGraphRepository {
  final commands = <IntentionCommand>[];
  final _results =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) {
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
  Stream<Result<GraphSnapshot<Intention?>>> watchIntention(IntentionId id) =>
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

final class _TestCatalogRevision implements IntentionCatalogRevision {
  const _TestCatalogRevision();

  @override
  IntentionCatalogRevisionOrder compareTo(IntentionCatalogRevision other) =>
      identical(this, other)
      ? IntentionCatalogRevisionOrder.same
      : IntentionCatalogRevisionOrder.differentEpoch;
}

final class _TestCatalogEntrySnapshot implements IntentionCatalogEntrySnapshot {
  _TestCatalogEntrySnapshot(IntentionId id)
    : summary = IntentionSummary(
        id: id,
        title: 'Намерение',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
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
