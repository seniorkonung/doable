import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart' as domain;
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'повтор формы не принимается, а другая форма с теми же полями принимается',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final form = ActionCreationFormKey();
      final command = CreateAction(
        title: ActionTitle('Пробежка'),
        description: null,
        path: ActionPath([_intention]),
        date: CalendarDate.fromParts(2026, 10, 8),
        schedule: const ActionAllDay(),
        priority: ActionPriority.p4,
      );
      final first = coordinator.acceptActionCreation(
        form,
        command,
      ) as ActionCommandAccepted;
      expect(
        coordinator.acceptActionCreation(form, command),
        isA<ActionCommandAlreadyRunning>(),
      );
      final second = coordinator.acceptActionCreation(
        ActionCreationFormKey(),
        command,
      ) as ActionCommandAccepted;
      expect(repository.commands, hasLength(2));
      repository.completeFailure(0);
      repository.completeFailure(1);
      await first.future;
      await second.future;
      await coordinator.shutdown();
    },
  );

  test('изменение и удаление одного действия, как и повтор той же команды, '
      'не принимаются, пока принятая выполняется', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final update = _updateCompleted(_actionA);

    final accepted =
        coordinator.acceptActionUpdate(update) as ActionCommandAccepted;

    expect(coordinator.isActionRunning(_actionA), isTrue);
    expect(
      coordinator.acceptActionUpdate(update),
      isA<ActionCommandAlreadyRunning>(),
    );
    expect(
      coordinator.acceptActionDelete(DeleteAction(_actionA)),
      isA<ActionCommandAlreadyRunning>(),
    );
    final independent = coordinator.acceptActionDelete(
      DeleteAction(_actionB),
    ) as ActionCommandAccepted;
    expect(repository.commands, hasLength(2));

    repository.completeFailure(0);
    repository.completeFailure(1);
    await accepted.future;
    await independent.future;

    expect(coordinator.isActionRunning(_actionA), isFalse);
    final next = coordinator.acceptActionDelete(DeleteAction(_actionA));
    expect(next, isA<ActionCommandAccepted>());
    repository.completeFailure(2);
    await (next as ActionCommandAccepted).future;
    await coordinator.shutdown();
  });

  test('успех изменения публикуется только для согласования данных, а успех '
      'удаления получает право предъявления', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);

    final update = coordinator.acceptActionUpdate(
      _updateCompleted(_actionA),
    ) as ActionCommandAccepted;
    repository.completeUpdated(0);
    final updateCompletion = await update.future;
    final delete = coordinator.acceptActionDelete(
      DeleteAction(_actionB),
    ) as ActionCommandAccepted;
    repository.completeDeleted(1);
    final deleteCompletion = await delete.future;

    expect(updateCompletion.kind, ActionCommandKind.update);
    expect(updateCompletion.isFailure, isFalse);
    expect(updateCompletion, isNot(isA<GraphPresentableCompletion>()));
    expect(updateCompletion.confirmedChange?.revision, const _Revision());
    expect(deleteCompletion.kind, ActionCommandKind.delete);
    expect(deleteCompletion.isFailure, isFalse);
    expect(deleteCompletion, isA<GraphPresentableCompletion>());
    await coordinator.shutdown();
  });

  test(
    'исключение репозитория становится безопасным неизвестным отказом',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptActionDelete(
        DeleteAction(_actionA),
      ) as ActionCommandAccepted;

      repository.fail(0);
      final completion = await accepted.future;

      expect(
        completion.result,
        isA<GraphResultFailure<ActionCommandSuccess, ActionCommandFailure>>()
            .having(
              (result) => result.failure,
              'отказ',
              isA<ActionUnexpectedFailure>(),
            ),
      );
      expect(coordinator.isActionRunning(_actionA), isFalse);
      await coordinator.shutdown();
    },
  );
}

UpdateActionFields _updateCompleted(ActionId id) => UpdateActionFields(
  actionId: id,
  patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
);

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

String _uuid(int number) =>
    '018f47c2-6b7d-7abc-8def-${number.toRadixString(16).padLeft(12, '0')}';
final _intention =
    (IntentionId.decode(_uuid(1)) as IntentionIdDecodingSuccess).id;
final _actionA = (ActionId.decode(_uuid(4)) as ActionIdDecodingSuccess).id;
final _actionB = (ActionId.decode(_uuid(5)) as ActionIdDecodingSuccess).id;

domain.Action _action(ActionId id, {required bool isCompleted}) =>
    domain.Action(
      id: id,
      title: ActionTitle('Пробежка'),
      description: null,
      path: ActionPath([_intention]),
      date: CalendarDate.fromParts(2026, 10, 8),
      schedule: const ActionAllDay(),
      priority: ActionPriority.p4,
      isCompleted: isCompleted,
      creationSequence: domain.ActionCreationSequence(1),
      createdAt: domain.ActionTimestamp(DateTime.utc(2026, 10, 7)),
      updatedAt: domain.ActionTimestamp(DateTime.utc(2026, 10, 7)),
    );

final class _ControlledRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final commands = <Object>[];
  final _results = <Completer<Object>>[];

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    commands.add(command);
    final result = Completer<Object>();
    _results.add(result);
    return await result.future as GraphCommandResult<T, F>;
  }

  void completeFailure(int index) => _results[index].complete(
    const GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>(
      ActionUnavailableFailure(),
    ),
  );

  void completeUpdated(int index) {
    const revision = _Revision();
    final before = _action(_actionA, isCompleted: false);
    final after = _action(_actionA, isCompleted: true);
    _results[index].complete(
      GraphCommandSucceeded<ActionCommandSuccess, ActionCommandFailure>(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionFieldsUpdated(
            action: after,
            changes: [
              ActionUpdatedChange(
                revision: revision,
                before: before,
                after: after,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void completeDeleted(int index) {
    const revision = _Revision();
    final action = _action(_actionB, isCompleted: false);
    _results[index].complete(
      GraphCommandSucceeded<ActionCommandSuccess, ActionCommandFailure>(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionDeleted(
            action: action,
            changes: [ActionDeletedChange(revision: revision, action: action)],
          ),
        ),
      ),
    );
  }

  void fail(int index) =>
      _results[index].completeError(StateError('Текст записи.'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
