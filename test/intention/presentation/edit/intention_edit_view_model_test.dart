import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_state.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../details/details_test_support.dart';

void main() {
  test('отсутствующее описание считается пустым текстом', () async {
    final session = await _openSession(
      testDetailsIntention(title: 'Бегать', description: null),
    );
    final model = session.model;

    model.changeDescription('Утром');
    expect(session.state.isChanged, isTrue);
    model.changeDescription('');

    expect(session.state.isChanged, isFalse);
    expect(session.state.canSave, isFalse);
    expect(model.requestClose(), IntentionEditCloseDecision.close);
  });

  test(
    'название из пробелов закрывает «Сохранить» при изменённом описании',
    () async {
      final session = await _openSession(testDetailsIntention(title: 'Бегать'));

      session.model.changeDescription('Новое описание');
      expect(session.state.canSave, isTrue);
      session.model.changeTitle('   ');

      expect(session.state.isChanged, isTrue);
      expect(session.state.canSave, isFalse);
    },
  );

  test(
    '«Сохранить» недоступна, пока выполняется другая команда намерения',
    () async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(title: 'Бегать');
      final container = await _loadedContainer(repository, intention);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      coordinator.acceptExisting(
        EnableIntentionReadiness(intention.id),
        presentationTitle: intention.title,
      );
      final session = _listenSession(container, intention);

      session.model.changeTitle('Бегать по утрам');
      expect(session.state.canSave, isFalse);
      session.model.save();
      expect(repository.commands, hasLength(1));

      repository.completeCommand(0, testDetailsSavedResult(intention));
      await pumpEventQueue();

      expect(session.state.canSave, isTrue);
    },
  );

  test('ответ «уже выполняется» делает сессию занятой без команды', () async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    final container = await _loadedContainer(repository, intention);
    final session = _listenSession(container, intention);
    session.model.changeTitle('Бегать по утрам');
    container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptExisting(
          ArchiveIntention(intention.id),
          presentationTitle: intention.title,
        );

    session.model.save();

    expect(repository.commands.single, isA<ArchiveIntention>());
    expect(session.state.isIntentionBusy, isTrue);
    expect(session.state.canSave, isFalse);
    expect(session.state.operation, isA<OperationIdle<Intention>>());
  });

  test('сохранение отправляет пустое описание как отсутствующее', () async {
    final session = await _openSession(testDetailsIntention(title: 'Бегать'));

    session.model
      ..changeTitle('Бегать по утрам')
      ..changeDescription('')
      ..save();

    expect(
      session.repository.commands.single,
      isA<UpdateIntention>()
          .having((command) => command.title, 'название', 'Бегать по утрам')
          .having((command) => command.description, 'описание', isNull),
    );
    expect(session.state.operation, isA<OperationRunning<Intention>>());
  });

  test(
    'правка названия снимает отказ его проверки и передаёт право оболочке',
    () async {
      final session = await _openSession(testDetailsIntention(title: 'Бегать'));
      final presenter = session.coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      session.model
        ..changeTitle('Слишком длинное название')
        ..save();
      session.repository.completeCommand(
        0,
        const ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(
              field: IntentionTextField.title,
              reason: IntentionTextValidationReason.tooLong,
            ),
          ),
        ),
      );
      await pumpEventQueue();
      expect(session.state.failurePresentation, isNotNull);
      expect(session.state.title, 'Слишком длинное название');

      session.model.changeDescription('Другое описание');
      expect(session.state.operation, isA<OperationFailed<Intention>>());
      expect(session.state.failurePresentation, isNotNull);
      session.model.changeTitle('Короткое');

      expect(session.state.operation, isA<OperationIdle<Intention>>());
      expect(session.state.failurePresentation, isNull);
      final claim = await presenter.nextClaim();
      expect(claim!.completions.single, isA<IntentionCommandCompletion>());
    },
  );

  test('правка любого поля снимает общий отказ проверки', () async {
    final session = await _openSession(testDetailsIntention(title: 'Бегать'));
    session.model
      ..changeTitle('Бегать по утрам')
      ..save();
    session.repository.completeCommand(
      0,
      const ResultFailure(IntentionGenericValidationFailure()),
    );
    await pumpEventQueue();
    expect(session.state.failurePresentation, isNotNull);

    session.model.changeDescription('Утром');

    expect(session.state.operation, isA<OperationIdle<Intention>>());
    expect(session.state.failurePresentation, isNull);
  });

  test('освобождение сессии передаёт оболочке непредъявленный отказ', () async {
    final session = await _openSession(testDetailsIntention(title: 'Бегать'));
    final presenter = session.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    session.model
      ..changeTitle('Бегать по утрам')
      ..save();
    session.repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(session.state.failurePresentation, isNotNull);

    session.subscription.close();
    await pumpEventQueue();

    final claim = await presenter.nextClaim();
    expect(
      claim!.completions.single,
      isA<IntentionCommandCompletion>().having(
        (completion) => completion.result,
        'отказ сохранения',
        isA<ResultFailure<IntentionCommandSuccess>>(),
      ),
    );
  });

  test('повторное сохранение после предъявленного отказа идёт новой командой без сообщения прежнего отказа', () async {
    final session = await _openSession(testDetailsIntention(title: 'Бегать'));
    final presenter = session.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    session.model
      ..changeTitle('Бегать по утрам')
      ..save();
    session.repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    final shownFailure = session.state.failurePresentation!;
    session.coordinator.confirmPresentation(shownFailure);

    expect(session.state.canSave, isTrue);
    session.model.save();

    expect(session.repository.commands, hasLength(2));
    expect(session.state.operation, isA<OperationRunning<Intention>>());
    expect(session.state.failurePresentation, isNull);
    GraphAppPresentationClaim? unexpectedMessage;
    unawaited(presenter.nextClaim().then((claim) => unexpectedMessage = claim));
    await pumpEventQueue();
    expect(unexpectedMessage, isNull);
  });

  test('решение о закрытии зависит от изменённости и сохранения', () async {
    final intention = testDetailsIntention(title: 'Бегать');
    final session = await _openSession(intention);
    expect(session.model.requestClose(), IntentionEditCloseDecision.close);

    session.model.changeTitle('Бегать по утрам');
    expect(session.model.requestClose(), IntentionEditCloseDecision.askDiscard);

    session.model.save();
    expect(session.model.requestClose(), IntentionEditCloseDecision.close);

    session.repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(session.model.requestClose(), IntentionEditCloseDecision.askDiscard);

    session.model.save();
    final saved = testDetailsIntention(title: 'Бегать по утрам');
    session.repository.completeCommand(
      1,
      testDetailsSavedResult(saved, before: intention),
    );
    await pumpEventQueue();
    expect(
      session.state.operation,
      isA<OperationSucceeded<Intention>>().having(
        (operation) => operation.value.title,
        'сохранённое название',
        'Бегать по утрам',
      ),
    );
    expect(session.model.requestClose(), IntentionEditCloseDecision.close);
  });

  test('отказ после ухода во время сохранения получает оболочка', () async {
    final session = await _openSession(testDetailsIntention(title: 'Бегать'));
    final presenter = session.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    session.model
      ..changeTitle('Бегать по утрам')
      ..save();
    expect(session.model.requestClose(), IntentionEditCloseDecision.close);
    session.subscription.close();
    await pumpEventQueue();

    session.repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );

    final claim = await presenter.nextClaim();
    expect(
      claim!.completions.single,
      isA<IntentionCommandCompletion>().having(
        (completion) => completion.result,
        'отказ сохранения',
        isA<ResultFailure<IntentionCommandSuccess>>(),
      ),
    );
  });

  test('успех после ухода во время сохранения не образует сообщения', () async {
    final intention = testDetailsIntention(title: 'Бегать');
    final session = await _openSession(intention);
    final presenter = session.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    session.model
      ..changeTitle('Бегать по утрам')
      ..save();
    session.subscription.close();
    await pumpEventQueue();

    session.repository.completeCommand(
      0,
      testDetailsSavedResult(
        testDetailsIntention(title: 'Бегать по утрам'),
        before: intention,
      ),
    );
    await pumpEventQueue();

    expect(session.repository.commands, hasLength(1));
    GraphAppPresentationClaim? unexpectedMessage;
    unawaited(presenter.nextClaim().then((claim) => unexpectedMessage = claim));
    await pumpEventQueue();
    expect(unexpectedMessage, isNull);
  });
}

final class _Session {
  _Session({
    required this.container,
    required this.repository,
    required this.provider,
    required this.subscription,
  });

  final ProviderContainer container;
  final ControlledDetailsRepository repository;
  final IntentionEditViewModelProvider provider;
  final ProviderSubscription<IntentionEditState> subscription;

  IntentionEditViewModel get model => container.read(provider.notifier);
  IntentionEditState get state => container.read(provider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);
}

Future<_Session> _openSession(Intention intention) async {
  final repository = ControlledDetailsRepository();
  final container = await _loadedContainer(repository, intention);
  return _listenSession(container, intention);
}

/// Контейнер с полученными подробными данными, над которыми открывается экран.
Future<ProviderContainer> _loadedContainer(
  ControlledDetailsRepository repository,
  Intention intention,
) async {
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  final details = container.listen(
    intentionDetailsViewModelProvider(intention.id),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(details.close);
  await waitForDetailRequests(repository, 1);
  repository.detailRequests.single.add(ResultSuccess(intention));
  await pumpEventQueue();
  return container;
}

_Session _listenSession(ProviderContainer container, Intention intention) {
  final provider = intentionEditViewModelProvider(
    IntentionEditFormKey(),
    intention.id,
  );
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  return _Session(
    container: container,
    repository: container.read(
      personalGraphRepositoryProvider,
    ) as ControlledDetailsRepository,
    provider: provider,
    subscription: subscription,
  );
}
