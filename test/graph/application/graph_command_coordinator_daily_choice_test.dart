import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'замена удерживает ключ выбора после ухода формы до конечного отказа',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptDailyChoiceReplace(
        _replace(_choiceA),
      ) as DailyChoiceCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      final registration = coordinator.registerAppPresentation();
      final claimFuture = registration.nextClaim();

      expect(coordinator.isDailyChoiceRunning(_choiceA), isTrue);
      expect(
        coordinator.acceptDailyChoiceReplace(_replace(_choiceA)),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptDailyChoiceUpdate(
          UpdateDailyChoiceFields(
            choiceId: _choiceA,
            patch: const DailyChoiceFieldsPatch(
              isCompleted: DailyChoiceFieldSet(true),
            ),
          ),
        ),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      expect(repository.commands, hasLength(1));
      repository.completeDailyFailure(0);
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(completion.kind, DailyChoiceCommandKind.replace);
      expect(claim?.completion, same(completion));
      expect(coordinator.isDailyChoiceRunning(_choiceA), isFalse);
      coordinator.confirmPresentation(claim!);
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      registration.release();
      await coordinator.shutdown();
    },
  );

  test(
    'форма удерживает подтверждение, а новая форма допускает дубликат',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final form = DailyChoiceCreationFormKey();
      final first = coordinator.acceptDailyChoiceCreation(
        form,
        _create(),
      ) as DailyChoiceCommandAccepted;
      final repeated = coordinator.acceptDailyChoiceCreation(form, _create());
      final second = coordinator.acceptDailyChoiceCreation(
        DailyChoiceCreationFormKey(),
        _create(),
      ) as DailyChoiceCommandAccepted;

      expect(repeated, isA<DailyChoiceCommandAlreadyRunning>());
      expect(repository.commands, hasLength(2));
      expect(coordinator.isKeyRunning(form), isTrue);

      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);
      repository.completeDailyFailure(1);
      await Future<void>.delayed(Duration.zero);
      expect(completions, isEmpty);
      expect(coordinator.isKeyRunning(form), isTrue);
      repository.completeDailyFailure(0);
      final firstResult = await first.future;
      final secondResult = await second.future;
      expect(completions, [same(firstResult), same(secondResult)]);
      expect(firstResult.kind, DailyChoiceCommandKind.create);
      expect(firstResult.isFailure, isTrue);
      expect(coordinator.isKeyRunning(form), isFalse);
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'изменение и удаление одного выбора конфликтуют до результата',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choiceA,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ) as DailyChoiceCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      final registration = coordinator.registerAppPresentation();
      final claimFuture = registration.nextClaim();

      expect(coordinator.isDailyChoiceRunning(_choiceA), isTrue);
      expect(
        coordinator.acceptDailyChoiceReplace(_replace(_choiceA)),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choiceA)),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      final independent = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(_choiceB),
      ) as DailyChoiceCommandAccepted;
      expect(repository.commands, hasLength(2));

      repository.completeDailyFailure(0);
      repository.completeDailyFailure(1);
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(claim?.completion, same(completion));
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      expect(coordinator.isDailyChoiceRunning(_choiceA), isFalse);
      await independent.future;
      coordinator.confirmPresentation(claim!);
      registration.release();
      await coordinator.shutdown();
    },
  );

  test(
    'shutdown ждёт дневную команду и отклоняет новые подтверждения',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(_choiceA),
      ) as DailyChoiceCommandAccepted;
      final draining = coordinator.shutdown();
      var finished = false;
      unawaited(draining.then((_) => finished = true));

      expect(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choiceB)),
        isA<GraphCommandCoordinatorDraining>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      repository.completeDailyFailure(0);
      await accepted.future;
      await draining;
      expect(finished, isTrue);
    },
  );

  test('исключение записи становится безопасным конечным отказом', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted = coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_choiceA),
    ) as DailyChoiceCommandAccepted;
    repository.fail(0);
    final completion = await accepted.future;
    expect(
      completion.result,
      isA<
            GraphResultFailure<
              DailyChoiceCommandSuccess,
              DailyChoiceCommandFailure
            >
          >()
          .having(
            (result) => result.failure,
            'отказ',
            isA<DailyChoiceUnexpectedFailure>(),
          ),
    );
    expect(coordinator.isDailyChoiceRunning(_choiceA), isFalse);
    await coordinator.shutdown();
  });

  test('успех передаёт подтверждённый пакет общему каналу', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final completions = <GraphCommandCompletion>[];
    final subscription = coordinator.completions.listen(completions.add);
    final accepted = coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_choiceA),
    ) as DailyChoiceCommandAccepted;
    const revision = _Revision();
    repository.complete(
      0,
      GraphCommandSucceeded<
        DailyChoiceCommandSuccess,
        DailyChoiceCommandFailure
      >(
        ConfirmedGraphResult(
          revision: revision,
          value: DailyChoiceDeleted(
            choice: DailyChoice(
              id: _choiceA,
              sourceIntentionId: _source,
              selectedIntentionId: _selected,
              date: CalendarDate.fromParts(2026, 9, 23),
              description: null,
              isCompleted: false,
            ),
            changes: [const _Change(revision)],
          ),
        ),
      ),
    );

    final completion = await accepted.future;
    expect(completion.kind, DailyChoiceCommandKind.delete);
    expect(completion.confirmedChange?.revision, same(revision));
    expect(completion.isFailure, isFalse);
    expect(completions, [same(completion)]);
    await subscription.cancel();
    await coordinator.shutdown();
  });
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

CreateDailyChoice _create() => CreateDailyChoice(
  sourceIntentionId: _source,
  selectedIntentionId: _selected,
  path: _path,
  date: CalendarDate.fromParts(2026, 9, 23),
  description: null,
  isCompleted: false,
);

ReplaceDailyChoicePath _replace(DailyChoiceId id) => ReplaceDailyChoicePath(
  choiceId: id,
  sourceIntentionId: _source,
  selectedIntentionId: _selected,
  path: _path,
);

final _path = ConfirmedChoicePath([
  ConfirmedChoicePathStep(
    relationId: _relation,
    sourceIntentionId: _source,
    type: LongTermRelationType.need,
    relatedIntentionId: _selected,
  ),
]);

String _uuid(int number) =>
    '018f47c2-6b7d-7abc-8def-${number.toRadixString(16).padLeft(12, '0')}';
final _source = (IntentionId.decode(_uuid(1)) as IntentionIdDecodingSuccess).id;
final _selected =
    (IntentionId.decode(_uuid(2)) as IntentionIdDecodingSuccess).id;
final _relation = (LongTermRelationId.decode(
  _uuid(3),
) as LongTermRelationIdDecodingSuccess).id;
final _choiceA =
    (DailyChoiceId.decode(_uuid(4)) as DailyChoiceIdDecodingSuccess).id;
final _choiceB =
    (DailyChoiceId.decode(_uuid(5)) as DailyChoiceIdDecodingSuccess).id;

final class _ControlledRepository implements PersonalGraphRepository {
  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

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

  void completeDailyFailure(int index) => _results[index].complete(
    const GraphCommandFailed<
      DailyChoiceCommandSuccess,
      DailyChoiceCommandFailure
    >(DailyChoiceUnavailableFailure()),
  );

  void fail(int index) =>
      _results[index].completeError(StateError('Текст записи.'));

  void complete(int index, Object result) => _results[index].complete(result);

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

final class _Change implements GraphChange {
  const _Change(this.revision);

  @override
  final GraphRevision revision;
}
