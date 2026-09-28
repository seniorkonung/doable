import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'смешанное удаление резервирует дневной выбор и долговременную связь',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final command = DeleteBlockingRelations(
        intentionId: _intentionA,
        references: {
          LongTermBlockingRelationReference(_relationA),
          DailyChoiceBlockingRelationReference(_choiceA),
        },
      );
      final accepted = coordinator.acceptBlockingRelationsDelete(
        command,
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;

      expect(coordinator.isRunning(_intentionA), isTrue);
      expect(coordinator.isRelationRunning(_relationA), isTrue);
      expect(coordinator.isDailyChoiceRunning(_choiceA), isTrue);
      expect(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choiceA)),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptDailyChoiceUpdate(
          UpdateDailyChoiceFields(
            choiceId: _choiceA,
            patch: const DailyChoiceFieldsPatch(),
          ),
        ),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptRelationDelete(DeleteLongTermRelation(_relationA)),
        isA<LongTermRelationCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptBlockingRelationsDelete(
          DeleteBlockingRelations(
            intentionId: _intentionB,
            references: {
              DailyChoiceBlockingRelationReference(_choiceA),
              LongTermBlockingRelationReference(_relationB),
            },
          ),
          presentationTitle: 'Второе',
        ),
        isA<BlockingRelationsDeleteAlreadyRunning>(),
      );
      expect(coordinator.isRunning(_intentionB), isFalse);
      expect(coordinator.isRelationRunning(_relationB), isFalse);
      expect(repository.commands, [same(command)]);

      repository.completeFailure(0);
      await accepted.future;
      expect(coordinator.isDailyChoiceRunning(_choiceA), isFalse);
      await coordinator.shutdown();
    },
  );

  test('дневная команда не отдаёт ключ смешанному удалению', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted = coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_choiceA),
    ) as DailyChoiceCommandAccepted;
    expect(
      coordinator.acceptBlockingRelationsDelete(
        DeleteBlockingRelations(
          intentionId: _intentionA,
          references: {
            DailyChoiceBlockingRelationReference(_choiceA),
            LongTermBlockingRelationReference(_relationA),
          },
        ),
        presentationTitle: 'Первое',
      ),
      isA<BlockingRelationsDeleteAlreadyRunning>(),
    );
    expect(coordinator.isRunning(_intentionA), isFalse);
    expect(coordinator.isRelationRunning(_relationA), isFalse);
    repository.completeDailyFailure(0);
    await accepted.future;
    await coordinator.shutdown();
  });

  test('ключи остаются занятыми до публикации конечного результата', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final earlier = coordinator.acceptCreation(
      IntentionCreationFormKey(),
      const CreateIntention(title: 'Раннее намерение', description: null),
    ) as IntentionCommandAccepted;
    final accepted = coordinator.acceptBlockingRelationsDelete(
      DeleteBlockingRelations(
        intentionId: _intentionA,
        references: {DailyChoiceBlockingRelationReference(_choiceA)},
      ),
      presentationTitle: 'Первое',
    ) as BlockingRelationsDeleteAccepted;
    repository.completeFailure(1);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isDailyChoiceRunning(_choiceA), isTrue);
    expect(coordinator.isRunning(_intentionA), isTrue);
    expect(
      coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choiceA)),
      isA<DailyChoiceCommandAlreadyRunning>(),
    );
    repository.completeIntentionFailure(0);
    await earlier.future;
    await accepted.future;
    expect(coordinator.isDailyChoiceRunning(_choiceA), isFalse);
    await coordinator.shutdown();
  });

  test(
    'массовая команда резервирует все ключи и отклоняет пересечение целиком',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final command = _delete(_intentionA, {_relationA, _relationB});

      final accepted = coordinator.acceptBlockingRelationsDelete(
        command,
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;
      expect(coordinator.isRunning(_intentionA), isTrue);
      expect(coordinator.isRelationRunning(_relationA), isTrue);
      expect(coordinator.isRelationRunning(_relationB), isTrue);
      expect(
        coordinator.acceptExisting(
          DeleteIntention(_intentionA),
          presentationTitle: 'Первое',
        ),
        isA<IntentionCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptRelationDelete(DeleteLongTermRelation(_relationA)),
        isA<LongTermRelationCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptBlockingRelationsDelete(
          _delete(_intentionB, {_relationB, _relationC}),
          presentationTitle: 'Второе',
        ),
        isA<BlockingRelationsDeleteAlreadyRunning>(),
      );
      expect(coordinator.isRunning(_intentionB), isFalse);
      expect(coordinator.isRelationRunning(_relationC), isFalse);

      final independent = coordinator.acceptBlockingRelationsDelete(
        _delete(_intentionB, {_relationC}),
        presentationTitle: 'Второе',
      ) as BlockingRelationsDeleteAccepted;
      expect(repository.commands, [
        same(command),
        isA<DeleteBlockingRelations>(),
      ]);

      repository.completeFailure(0);
      repository.completeFailure(1);
      await accepted.future;
      await independent.future;
      expect(coordinator.isRunning(_intentionA), isFalse);
      expect(coordinator.isRelationRunning(_relationA), isFalse);
      expect(coordinator.isRelationRunning(_relationB), isFalse);
      expect(coordinator.isRelationRunning(_relationC), isFalse);
      await coordinator.shutdown();
    },
  );

  test(
    'занятый ключ намерения или связи не захватывает остальные ключи',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final intention = coordinator.acceptExisting(
        DeleteIntention(_intentionA),
        presentationTitle: 'Первое',
      ) as IntentionCommandAccepted;
      expect(
        coordinator.acceptBlockingRelationsDelete(
          _delete(_intentionA, {_relationA, _relationB}),
          presentationTitle: 'Первое',
        ),
        isA<BlockingRelationsDeleteAlreadyRunning>(),
      );
      expect(coordinator.isRelationRunning(_relationA), isFalse);
      expect(coordinator.isRelationRunning(_relationB), isFalse);

      final relation = coordinator.acceptRelationDelete(
        DeleteLongTermRelation(_relationA),
      ) as LongTermRelationCommandAccepted;
      expect(
        coordinator.acceptBlockingRelationsDelete(
          _delete(_intentionB, {_relationA, _relationB}),
          presentationTitle: 'Второе',
        ),
        isA<BlockingRelationsDeleteAlreadyRunning>(),
      );
      expect(coordinator.isRunning(_intentionB), isFalse);
      expect(coordinator.isRelationRunning(_relationB), isFalse);
      expect(repository.commands, hasLength(2));

      repository.completeIntentionFailure(0);
      repository.completeRelationFailure(1);
      await intention.future;
      await relation.future;
      await coordinator.shutdown();
    },
  );

  test('уход и возврат не снимают блокировки принятого набора и не повторяют запись', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final command = _delete(_intentionA, {_relationA, _relationB});
    final accepted = coordinator.acceptBlockingRelationsDelete(
      command,
      presentationTitle: 'Первое',
    ) as BlockingRelationsDeleteAccepted;

    coordinator.releaseInitiatorPresentation(accepted.token);
    final registration = coordinator.registerAppPresentation();
    final appClaimFuture = registration.nextClaim();
    expect(coordinator.isRunning(_intentionA), isTrue);
    expect(coordinator.isRelationRunning(_relationA), isTrue);
    expect(coordinator.isRelationRunning(_relationB), isTrue);
    expect(
      coordinator.acceptBlockingRelationsDelete(
        command,
        presentationTitle: 'Первое',
      ),
      isA<BlockingRelationsDeleteAlreadyRunning>(),
    );
    expect(repository.commands, [same(command)]);

    repository.completeFailure(0);
    final completion = await accepted.future;
    final claim = await appClaimFuture;
    expect(claim?.token, same(accepted.token));
    expect(claim?.completion, same(completion));
    expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
    expect(coordinator.isRunning(_intentionA), isFalse);
    expect(coordinator.isRelationRunning(_relationA), isFalse);
    expect(coordinator.isRelationRunning(_relationB), isFalse);
    coordinator.confirmPresentation(claim!);
    registration.release();
    await coordinator.shutdown();
  });

  test(
    'успех отдаёт один token и пакет, освобождает ключи и принадлежит оболочке',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);
      final registration = coordinator.registerAppPresentation();
      final command = _delete(_intentionA, {_relationA});
      final accepted = coordinator.acceptBlockingRelationsDelete(
        command,
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;
      final claimFuture = registration.nextClaim();

      const revision = _Revision();
      final outcome = BlockingRelationsDeleted(
        command: command,
        revision: revision,
        deletedRelations: [_relation(_relationA)],
        counts: {_intentionA: _zeroCounts, _intentionB: _zeroCounts},
      );
      repository.completeSuccess(
        0,
        GraphCommandSucceeded<
          BlockingRelationsDeleted,
          DeleteBlockingRelationsFailure
        >(ConfirmedGraphResult(revision: revision, value: outcome)),
      );
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(completion.token, same(accepted.token));
      expect(completion.confirmedChange?.changes, hasLength(3));
      expect(completions, [same(completion)]);
      expect(claim?.completion, same(completion));
      expect(coordinator.claimInitiatorFailure(completion.token), isNull);
      expect(coordinator.isRunning(_intentionA), isFalse);
      expect(coordinator.isRelationRunning(_relationA), isFalse);
      coordinator.confirmPresentation(claim!);
      registration.release();
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'отказ остаётся у инициатора, а shutdown ждёт принятую команду',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptBlockingRelationsDelete(
        _delete(_intentionA, {_relationA}),
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;
      final shutdown = coordinator.shutdown();
      var drained = false;
      unawaited(shutdown.then((_) => drained = true));
      expect(
        coordinator.acceptBlockingRelationsDelete(
          _delete(_intentionB, {_relationB}),
          presentationTitle: 'Второе',
        ),
        isA<GraphCommandCoordinatorDraining>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);

      repository.completeFailure(0);
      final completion = await accepted.future;
      expect(completion.isFailure, isTrue);
      expect(completion.confirmedChange, isNull);
      expect(coordinator.isRunning(_intentionA), isFalse);
      expect(coordinator.isRelationRunning(_relationA), isFalse);
      await shutdown;
      expect(drained, isTrue);
    },
  );

  test(
    'ошибка открытого инициатора переходит оболочке после освобождения',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final registration = coordinator.registerAppPresentation();
      final accepted = coordinator.acceptBlockingRelationsDelete(
        _delete(_intentionA, {_relationA}),
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;
      final appClaimFuture = registration.nextClaim();

      repository.completeFailure(0);
      final completion = await accepted.future;
      final initiatorClaim = coordinator.claimInitiatorFailure(
        completion.token,
      );
      expect(initiatorClaim?.completion, same(completion));
      coordinator.releaseInitiatorClaim(initiatorClaim!);
      final appClaim = await appClaimFuture;
      expect(appClaim?.completion, same(completion));
      coordinator.confirmPresentation(appClaim!);
      registration.release();
      await coordinator.shutdown();
    },
  );

  test(
    'исключение репозитория становится отказом и освобождает все ключи',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptBlockingRelationsDelete(
        _delete(_intentionA, {_relationA, _relationB}),
        presentationTitle: 'Первое',
      ) as BlockingRelationsDeleteAccepted;

      repository.completeError(0);
      final completion = await accepted.future;
      expect(
        completion.result,
        isA<
              GraphResultFailure<
                ConfirmedGraphResult<BlockingRelationsDeleted>,
                DeleteBlockingRelationsFailure
              >
            >()
            .having(
              (result) => result.failure,
              'причина',
              isA<DeleteBlockingRelationsUnexpectedFailure>(),
            ),
      );
      expect(coordinator.isRunning(_intentionA), isFalse);
      expect(coordinator.isRelationRunning(_relationA), isFalse);
      expect(coordinator.isRelationRunning(_relationB), isFalse);
      await coordinator.shutdown();
    },
  );
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

DeleteBlockingRelations _delete(
  IntentionId intentionId,
  Set<LongTermRelationId> relationIds,
) => DeleteBlockingRelations.longTerm(
  intentionId: intentionId,
  relationIds: relationIds,
);

final class _ControlledRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
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
    const GraphCommandFailed<
      BlockingRelationsDeleted,
      DeleteBlockingRelationsFailure
    >(DeleteBlockingRelationsUnavailableFailure()),
  );

  void completeIntentionFailure(int index) => _results[index].complete(
    const GraphCommandFailed<IntentionCommandSuccess, IntentionFailure>(
      IntentionUnavailableFailure(),
    ),
  );

  void completeRelationFailure(int index) => _results[index].complete(
    const GraphCommandFailed<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(LongTermRelationUnavailableFailure()),
  );

  void completeDailyFailure(int index) => _results[index].complete(
    const GraphCommandFailed<
      DailyChoiceCommandSuccess,
      DailyChoiceCommandFailure
    >(DailyChoiceUnavailableFailure()),
  );

  void completeSuccess(int index, DeleteBlockingRelationsResult result) =>
      _results[index].complete(result);

  void completeError(int index) =>
      _results[index].completeError(StateError('Внутренняя ошибка.'));

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

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный идентификатор намерения.',
  ),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Некорректный идентификатор связи.',
      ),
    };

final _intentionA = _intentionId('018f47c2-6b7d-7abc-8def-0123456789a1');
final _intentionB = _intentionId('018f47c2-6b7d-7abc-8def-0123456789a2');
final _relationA = _relationId('018f47c2-6b7d-7abc-8def-0123456789b1');
final _relationB = _relationId('018f47c2-6b7d-7abc-8def-0123456789b2');
final _relationC = _relationId('018f47c2-6b7d-7abc-8def-0123456789b3');
final _choiceA = (DailyChoiceId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789b1',
) as DailyChoiceIdDecodingSuccess).id;

LongTermRelation _relation(LongTermRelationId id) => LongTermRelation(
  id: id,
  sourceIntentionId: _intentionA,
  relatedIntentionId: _intentionB,
  type: LongTermRelationType.need,
  priority: RelationPriority.p1,
  scope: RelationScope.active,
  creationSequence: RelationCreationSequence(1),
);

final _zeroCounts = RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: 0,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);
