import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_test_support.dart';

void main() {
  test(
    'синхронно принимает одну отправку и не ставит повторную в очередь',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('  Быть здоровым  ')
        ..changeDescription('  Сохранить буквально\n');

      editor.submit();
      editor.submit();

      final state = container.read(provider);
      expect(state.operation, isA<OperationRunning<Intention>>());
      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<CreateIntention>()
            .having((command) => command.title, 'title', '  Быть здоровым  ')
            .having(
              (command) => command.description,
              'description',
              '  Сохранить буквально\n',
            ),
      );
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await _settle(container);

      expect(repository.commands, hasLength(1));
    },
  );

  test(
    'не принимает повтор той же формы после пересоздания ViewModel',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final firstSubscription = container.listen(provider, (_, _) {});

      container.read(provider.notifier)
        ..changeTitle('Первое намерение')
        ..submit();
      expect(repository.commands, hasLength(1));

      firstSubscription.close();
      await _settle(container);
      final reopenedSubscription = container.listen(provider, (_, _) {});
      addTearDown(reopenedSubscription.close);
      container.read(provider.notifier)
        ..changeTitle('Повтор той же формы')
        ..submit();

      expect(repository.commands, hasLength(1));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await _settle(container);
    },
  );

  test(
    'независимые формы позволяют создать намерения с одинаковым названием',
    () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final firstProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final secondProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      final secondSubscription = container.listen(secondProvider, (_, _) {});
      addTearDown(firstSubscription.close);
      addTearDown(secondSubscription.close);

      container.read(firstProvider.notifier)
        ..changeTitle('Одинаковое намерение')
        ..submit();
      container.read(secondProvider.notifier)
        ..changeTitle('Одинаковое намерение')
        ..submit();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands,
        everyElement(
          isA<CreateIntention>().having(
            (command) => command.title,
            'название',
            'Одинаковое намерение',
          ),
        ),
      );
    },
  );

  test('сохраняет поля и field-specific validation для исправления', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final editor = container.read(provider.notifier)
      ..changeTitle('')
      ..changeDescription('Описание')
      ..submit();

    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
      ),
    );
    await _settle(container);

    final failed = container.read(provider);
    expect(failed.title, isEmpty);
    expect(failed.description, 'Описание');
    expect(
      failed.operation,
      isA<OperationFailed<Intention>>().having(
        (operation) => operation.failure,
        'failure',
        isA<IntentionTextInputValidationFailure>(),
      ),
    );
    expect(failed.canSubmit, isFalse);

    editor.changeTitle('Исправленное намерение');

    final corrected = container.read(provider);
    expect(corrected.operation, isA<OperationIdle<Intention>>());
    expect(corrected.canSubmit, isTrue);
    expect(corrected.description, 'Описание');
  });

  test(
    'разрешает новый token после unavailable и не оставляет прежний failure',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final tokens = <IntentionOperationToken>[];
      final coordinatorSubscription = container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen((completion) => tokens.add(completion.token));
      addTearDown(coordinatorSubscription.cancel);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..submit();

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(container);

      expect(container.read(provider).canRetry, isTrue);
      editor.submit();
      expect(repository.commands, hasLength(2));
      expect(
        container.read(provider).operation,
        isA<OperationRunning<Intention>>(),
      );

      repository.completeCommand(1, _savedResult());
      await _settle(container);

      final succeeded = container.read(provider);
      expect(succeeded.operation, isA<OperationSucceeded<Intention>>());
      expect(succeeded.event, isA<IntentionEditorCreated>());
      expect(tokens, hasLength(2));
      expect(identical(tokens.first, tokens.last), isFalse);
    },
  );

  test('публикует claim failure, а renderer передаёт его оболочке', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});

    container.read(provider.notifier)
      ..changeTitle('Намерение')
      ..submit();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnexpectedFailure()),
    );
    await _settle(container);

    final failed = container.read(provider);
    expect(failed.operation, isA<OperationFailed<Intention>>());
    expect(
      failed.failurePresentation,
      isA<IntentionInitiatorPresentationClaim>(),
    );
    IntentionAppPresentationClaim? fallback;
    final fallbackRequest = presenter.nextClaim()
      ..then((claim) => fallback = claim);
    await _settle(container);
    expect(fallback, isNull);

    coordinator.releaseInitiatorClaim(failed.failurePresentation!);
    await _settle(container);
    await fallbackRequest;

    expect(fallback!.token, same(failed.failurePresentation!.token));
    coordinator.confirmPresentation(failed.failurePresentation!);
    coordinator.confirmPresentation(fallback!);
    subscription.close();
  });

  test(
    'success закрывает форму без initiator claim и сразу доступен оболочке',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..submit();
      repository.completeCommand(0, _savedResult());
      await _settle(container);

      final succeeded = container.read(provider);
      expect(succeeded.event, isA<IntentionEditorCreated>());
      expect(succeeded.failurePresentation, isNull);
      final claim = await presenter.nextClaim();
      expect(
        claim!.completion.result,
        isA<ResultSuccess<IntentionCommandSuccess>>(),
      );
      coordinator.confirmPresentation(claim);
    },
  );

  test('предъявленный failure не переходит оболочке после успешной повторной попытки', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final tokens = <IntentionOperationToken>[];
    final completionSubscription = coordinator.completions.listen(
      (completion) => tokens.add(completion.token),
    );
    addTearDown(completionSubscription.cancel);
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});
    final editor = container.read(provider.notifier)
      ..changeTitle('Намерение')
      ..submit();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await _settle(container);
    coordinator.confirmPresentation(
      container.read(provider).failurePresentation!,
    );

    editor.submit();
    repository.completeCommand(1, _savedResult());
    await _settle(container);
    subscription.close();
    await _settle(container);

    final success = await presenter.nextClaim();
    expect(tokens, hasLength(2));
    expect(success!.token, same(tokens.last));
    coordinator.confirmPresentation(success);
    IntentionAppPresentationClaim? stale;
    unawaited(presenter.nextClaim().then((claim) => stale = claim));
    await _settle(container);
    expect(stale, isNull);
  });
}

ProviderContainer _container(ControlledCatalogRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(ProviderContainer container) async {
  await container.pump();
  await container.pump();
}

Result<IntentionCommandSuccess> _savedResult() {
  final intention = testIntention(title: 'Намерение');
  return ResultSuccess(
    IntentionSaved(
      intention,
      catalogMutation: IntentionCatalogCreated(
        revision: const TestCatalogRevision(1),
        entry: TestCatalogEntrySnapshot(
          IntentionSummary(
            id: intention.id,
            title: intention.title,
            hasDescription: intention.description != null,
            readiness: intention.readiness,
            archiveState: intention.archiveState,
            createdAt: intention.createdAt,
            updatedAt: intention.updatedAt,
          ),
        ),
      ),
    ),
  );
}
