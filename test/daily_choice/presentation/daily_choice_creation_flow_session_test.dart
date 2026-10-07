import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';

void main() {
  test(
    'сессия связывает конкретный корень с неизменяемой исходной историей',
    () {
      final history = <LocalKey>[const ValueKey('оболочка'), UniqueKey()];
      final root = UniqueKey();
      final session = DailyChoiceCreationFlowSession(
        rootMatchId: root,
        originalHistory: history,
      );
      final snapshot = List<LocalKey>.of(history);
      history.clear();

      expect(session.rootMatchId, root);
      expect(session.originalHistory, snapshot);
      expect(() => session.originalHistory.clear(), throwsUnsupportedError);
      expect(session.state, isA<DailyChoiceCreationFlowEditing>());
      expect(session.canContinue, isTrue);
    },
  );

  test(
    'отмена первой не допускает принятия команды даже до следующего кадра',
    () {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final session = _session();

      expect(session.leave(), isTrue);
      expect(harness.submit(session), isNull);
      expect(harness.repository.requests, isEmpty);
      expect(session.state, isA<DailyChoiceCreationFlowLeft>());
      expect(session.canContinue, isFalse);
      expect(session.leave(), isFalse);
    },
  );

  test(
    'принятие первым сохраняет операцию при выходе без повторной отправки',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final session = _session();
      final accepted = harness.submit(session)!;

      expect(
        session.state,
        isA<DailyChoiceCreationFlowSubmitting>().having(
          (state) => state.operation.token,
          'принятая операция',
          same(accepted.token),
        ),
      );
      expect(session.canContinue, isFalse);
      expect(harness.submit(session), isNull);
      expect(session.leave(), isTrue);
      harness.repository.succeed(0);
      final completion = await accepted.future;
      expect(session.recordCompletion(completion), isTrue);

      expect(
        session.state,
        isA<DailyChoiceCreationFlowLeft>().having(
          (state) => state.lastActiveState,
          'сохранённый результат покинутого потока',
          isA<DailyChoiceCreationFlowSaved>(),
        ),
      );
      expect(session.canContinue, isFalse);
      expect(harness.submit(session), isNull);
      expect(harness.repository.requests, hasLength(1));
    },
  );

  test(
    'успех фиксируется до навигации и не сбрасывается поздним возвратом',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final session = _session();
      final observed = <DailyChoiceCreationFlowState>[];
      void observe() => observed.add(session.state);
      session.changes.addListener(observe);
      addTearDown(() => session.changes.removeListener(observe));
      final accepted = harness.submit(session)!;
      harness.repository.succeed(0);
      final completion = await accepted.future;

      expect(session.recordCompletion(completion), isTrue);
      final saved = session.state;
      expect(
        saved,
        isA<DailyChoiceCreationFlowSaved>().having(
          (state) => state.choiceId,
          'идентификатор созданного выбора',
          durabilityChoice(201),
        ),
      );
      expect(observed, [isA<DailyChoiceCreationFlowSubmitting>(), same(saved)]);
      expect(session.recordCompletion(completion), isFalse);
      expect(harness.submit(session), isNull);
      expect(session.state, same(saved));
      expect(session.canContinue, isFalse);
    },
  );

  for (final leave in [false, true]) {
    test(
      'поздний отказ ${leave ? 'не возобновляет покинутый поток' : 'допускает только явное продолжение'}',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final session = _session();
        final accepted = harness.submit(session)!;
        if (leave) session.leave();
        harness.repository.fail(0);

        expect(session.recordCompletion(await accepted.future), isTrue);
        expect(session.canContinue, !leave);
        expect(harness.repository.requests, hasLength(1));
        if (leave) {
          expect(harness.submit(session), isNull);
        } else {
          expect(harness.submit(session), isNotNull);
          expect(harness.repository.requests, hasLength(2));
        }
      },
    );
  }

  test('операция и оставшаяся страница удерживают одну сессию после удаления подтверждения', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    DailyChoiceCreationFlowSession? confirmation = _session();
    final pathPage = confirmation;
    final accepted = harness.submit(confirmation)!;
    final finishing = accepted.future.then(confirmation.recordCompletion);
    confirmation = null;
    harness.repository.succeed(0);

    expect(await finishing, isTrue);
    expect(pathPage.state, isA<DailyChoiceCreationFlowSaved>());
    expect(pathPage.canContinue, isFalse);
  });

  test(
    'две сессии не принимают результаты друг друга даже при одинаковой границе',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = _session();
      final second = DailyChoiceCreationFlowSession(
        rootMatchId: first.rootMatchId,
        originalHistory: first.originalHistory,
      );
      expect(second.flowId, isNot(first.flowId));
      final a = harness.submit(first)!;
      final b = harness.submit(second)!;
      expect(a.token, isNot(b.token));
      first.leave();
      harness.repository.succeed(0);
      final completion = await a.future;

      expect(second.recordCompletion(completion), isFalse);
      expect(second.state, isA<DailyChoiceCreationFlowSubmitting>());
      expect(first.recordCompletion(completion), isTrue);
      harness.repository.fail(1);
      expect(second.recordCompletion(await b.future), isTrue);
      expect(second.canContinue, isTrue);
      expect(first.canContinue, isFalse);
    },
  );

  test('отклонение координатора не превращается в принятую отправку', () {
    final session = _session();
    final editing = session.state;

    expect(
      session.acceptSubmission((_) => const DailyChoiceCommandAlreadyRunning()),
      isA<DailyChoiceCommandAlreadyRunning>(),
    );
    expect(session.state, same(editing));
    expect(
      session.acceptSubmission((_) => const GraphCommandCoordinatorDraining()),
      isA<GraphCommandCoordinatorDraining>(),
    );
    expect(session.state, same(editing));
    expect(session.canContinue, isTrue);
  });

  test('исключение до принятия не удерживает блокировку редактирования', () {
    final session = _session();

    expect(
      () => session.acceptSubmission((_) => throw StateError('Отказ принятия')),
      throwsStateError,
    );
    expect(session.state, isA<DailyChoiceCreationFlowEditing>());
    expect(session.canContinue, isTrue);
  });

  test(
    'повторный обработчик во время принятия не отправляет вторую команду',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final session = _session();
      final accepted = session.acceptSubmission((key) {
        expect(harness.submit(session), isNull);
        session.leave();
        return harness.coordinator.acceptDailyChoiceCreation(
          key,
          durabilityCreate(),
        );
      }) as DailyChoiceCommandAccepted;

      expect(harness.repository.requests, hasLength(1));
      expect(
        session.state,
        isA<DailyChoiceCreationFlowLeft>().having(
          (state) => state.lastActiveState,
          'операция продолжается после выхода',
          isA<DailyChoiceCreationFlowSubmitting>(),
        ),
      );
      harness.repository.fail(0);
      expect(session.recordCompletion(await accepted.future), isTrue);
      expect(session.canContinue, isFalse);
    },
  );

  test(
    'поздний повтор результата прежней попытки не сбрасывает новую отправку',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final session = _session();
      final first = harness.submit(session)!;
      harness.repository.fail(0);
      final failure = await first.future;
      session.recordCompletion(failure);
      final second = harness.submit(session)!;
      final submitting = session.state;

      expect(session.recordCompletion(failure), isFalse);
      expect(session.state, same(submitting));
      harness.repository.succeed(1);
      expect(session.recordCompletion(await second.future), isTrue);
      expect(session.state, isA<DailyChoiceCreationFlowSaved>());
      session.leave();
      expect(
        session.state,
        isA<DailyChoiceCreationFlowLeft>().having(
          (state) => state.lastActiveState,
          'сохранённый результат после выхода',
          isA<DailyChoiceCreationFlowSaved>().having(
            (state) => state.choiceId,
            'идентификатор',
            durabilityChoice(202),
          ),
        ),
      );
      expect(session.recordCompletion(failure), isFalse);
      expect(session.canContinue, isFalse);
    },
  );

  test('завершение удерживает успех после удаления всех страниц', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    DailyChoiceCreationFlowSession? page = _session();
    final changes = page.changes;
    final accepted = harness.submit(page)!;
    final finishing = accepted.future.then(page.recordCompletion);
    page = null;
    harness.repository.succeed(0);

    expect(await finishing, isTrue);
    expect(changes.value, isA<DailyChoiceCreationFlowSaved>());
  });
}

DailyChoiceCreationFlowSession _session() => DailyChoiceCreationFlowSession(
  rootMatchId: UniqueKey(),
  originalHistory: [const ValueKey('оболочка'), UniqueKey()],
);

final class _Harness {
  final repository = _Repository();
  late final container = ProviderContainer(
    overrides: [
      personalGraphRepositoryProvider.overrideWith((ref) => repository),
    ],
  );
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  DailyChoiceCommandAccepted? submit(DailyChoiceCreationFlowSession session) =>
      session.acceptSubmission(
        (key) => coordinator.acceptDailyChoiceCreation(key, durabilityCreate()),
      ) as DailyChoiceCommandAccepted?;

  void dispose() => container.dispose();
}

final class _Repository implements PersonalGraphRepository {
  final requests = <Completer<DailyChoiceCommandResult>>[];

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    if (command is! CreateDailyChoice) throw UnimplementedError();
    final request = Completer<DailyChoiceCommandResult>();
    requests.add(request);
    return await request.future as GraphCommandResult<T, F>;
  }

  void fail(int index) => requests[index].complete(
    const GraphCommandFailed(DailyChoiceUnavailableFailure()),
  );

  void succeed(int index) {
    final command = durabilityCreate();
    final id = durabilityChoice(201 + index);
    requests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoiceCreated(
            choice: DailyChoice(
              id: id,
              sourceIntentionId: command.sourceIntentionId,
              selectedIntentionId: command.selectedIntentionId,
              date: command.date,
              description: command.description,
              isCompleted: command.isCompleted,
            ),
            path: StoredChoicePath([
              ChoicePathStep(
                id: durabilityStep(301 + index),
                dailyChoiceId: id,
                relationId: command.path.steps.first.relationId,
                previousStepId: null,
              ),
            ]),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _Change implements GraphChange {
  const _Change();

  @override
  GraphRevision get revision => const _Revision();
}
