import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraphCommandCoordinator — изменение долговременной связи', () {
    test(
      'ключ связи блокирует повтор и не смешивается с другими ключами',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _coordinator(repository);

        final accepted = coordinator.acceptRelationUpdate(
          _updateRelation(_relationId),
        );
        final repeated = coordinator.acceptRelationUpdate(
          _updateRelation(_relationId),
        );
        final independentRelation = coordinator.acceptRelationUpdate(
          _updateRelation(_otherRelationId),
        );
        final creation = coordinator.acceptRelationCreation(
          LongTermRelationCreationFormKey(),
          _createRelation(),
        );
        final intention = coordinator.acceptCreation(
          IntentionCreationFormKey(),
          const CreateIntention(title: 'Намерение', description: null),
        );

        expect(accepted, isA<LongTermRelationCommandAccepted>());
        expect(repeated, isA<LongTermRelationCommandAlreadyRunning>());
        expect(independentRelation, isA<LongTermRelationCommandAccepted>());
        expect(creation, isA<LongTermRelationCommandAccepted>());
        expect(intention, isA<IntentionCommandAccepted>());
        expect(coordinator.isRelationRunning(_relationId), isTrue);
        expect(repository.commands, [
          isA<UpdateLongTermRelation>(),
          isA<UpdateLongTermRelation>(),
          isA<CreateLongTermRelation>(),
          isA<CreateIntention>(),
        ]);

        repository
          ..completeRelationFailure(0)
          ..completeRelationFailure(1)
          ..completeRelationFailure(2)
          ..completeIntentionFailure(3);
        await (accepted as LongTermRelationCommandAccepted).future;
        await (independentRelation as LongTermRelationCommandAccepted).future;
        await (creation as LongTermRelationCommandAccepted).future;
        await (intention as IntentionCommandAccepted).future;

        expect(coordinator.isRelationRunning(_relationId), isFalse);
        await coordinator.shutdown();
      },
    );

    test(
      'публикует изменение в общем порядке с видом и контекстом связи',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _coordinator(repository);
        final completions = <GraphCommandCompletion>[];
        final subscription = coordinator.completions.listen(completions.add);

        final intention = coordinator.acceptCreation(
          IntentionCreationFormKey(),
          const CreateIntention(title: 'Намерение', description: null),
        ) as IntentionCommandAccepted;
        final update = coordinator.acceptRelationUpdate(
          _updateRelation(_relationId),
        ) as LongTermRelationCommandAccepted;

        repository.completeRelationUpdated(1, _relationId);
        await Future<void>.delayed(Duration.zero);
        expect(completions, isEmpty);

        repository.completeIntentionFailure(0);
        final intentionCompletion = await intention.future;
        final updateCompletion = await update.future;

        expect(completions, [
          same(intentionCompletion),
          same(updateCompletion),
        ]);
        expect(updateCompletion.kind, LongTermRelationCommandKind.update);
        expect(updateCompletion.revision, const _TestRevision(1));
        expect(
          updateCompletion.target,
          isA<ExistingLongTermRelationOperationTarget>().having(
            (target) => target.relationId,
            'идентификатор связи',
            _relationId,
          ),
        );

        await subscription.cancel();
        await coordinator.shutdown();
      },
    );

    test(
      'удерживает ошибку после ухода и допускает явную повторную попытку',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _coordinator(repository);
        final registration = coordinator.registerAppPresentation();

        final accepted = coordinator.acceptRelationUpdate(
          _updateRelation(_relationId),
        ) as LongTermRelationCommandAccepted;
        final appClaimFuture = registration.nextClaim();
        expect(coordinator.isRelationRunning(_relationId), isTrue);

        repository.completeRelationFailure(0);
        final completion = await accepted.future;
        final initiatorClaim = coordinator.claimInitiatorFailure(
          completion.token,
        );
        expect(initiatorClaim, isNotNull);

        coordinator.releaseInitiatorClaim(initiatorClaim!);
        final appClaim = await appClaimFuture;
        expect(appClaim, isNotNull);
        expect(appClaim!.completion, same(completion));

        final retry = coordinator.acceptRelationUpdate(
          _updateRelation(_relationId),
        );
        expect(retry, isA<LongTermRelationCommandAccepted>());
        expect(repository.commands, hasLength(2));

        coordinator.confirmPresentation(appClaim);
        repository.completeRelationFailure(1);
        await (retry as LongTermRelationCommandAccepted).future;
        registration.release();
        await coordinator.shutdown();
      },
    );

    test('shutdown ждёт изменение связи и запрещает новую работу', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptRelationUpdate(
        _updateRelation(_relationId),
      ) as LongTermRelationCommandAccepted;

      final shutdown = coordinator.shutdown();
      var shutdownCompleted = false;
      unawaited(shutdown.then((_) => shutdownCompleted = true));

      expect(
        coordinator.acceptRelationUpdate(_updateRelation(_otherRelationId)),
        isA<GraphCommandCoordinatorDraining>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(shutdownCompleted, isFalse);

      repository.completeRelationFailure(0);
      await accepted.future;
      await shutdown;
      expect(shutdownCompleted, isTrue);
    });
  });
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

UpdateLongTermRelation _updateRelation(LongTermRelationId relationId) =>
    UpdateLongTermRelation(
      relationId: relationId,
      patch: const LongTermRelationPatch(
        priority: LongTermRelationFieldSet(RelationPriority.p1),
      ),
    );

CreateLongTermRelation _createRelation() => CreateLongTermRelation(
  sourceIntentionId: _intentionId(_sourceUuid),
  relatedIntentionId: _intentionId(_relatedUuid),
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: null,
);

LongTermRelation _relation(LongTermRelationId id, RelationPriority priority) =>
    LongTermRelation(
      id: id,
      sourceIntentionId: _intentionId(_sourceUuid),
      relatedIntentionId: _intentionId(_relatedUuid),
      type: LongTermRelationType.need,
      priority: priority,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );

final class _ControlledPersonalGraphRepository
    implements PersonalGraphRepository {
  final commands = <Object>[];
  final _results = <Completer<Object>>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final result = Completer<Object>();
    _results.add(result);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeRelationFailure(int index) => _results[index].complete(
    const GraphCommandFailed<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(LongTermRelationUnavailableFailure()),
  );

  void completeIntentionFailure(int index) => _results[index].complete(
    const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
      IntentionUnavailableFailure(),
    ),
  );

  void completeRelationUpdated(int index, LongTermRelationId id) {
    const revision = _TestRevision(1);
    final before = _relation(id, RelationPriority.p2);
    final after = _relation(id, RelationPriority.p1);
    _results[index].complete(
      GraphCommandSucceeded<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationUpdated(
            before: before,
            relation: after,
            description: null,
            changes: [
              LongTermRelationUpdatedChange(
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

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => throw UnsupportedError('Группы связей не используются в этих тестах.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в этих тестах.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => throw UnsupportedError('Намерения не наблюдаются в этих тестах.');
}

final class _TestRevision implements GraphRevision {
  const _TestRevision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _TestRevision(value: final otherValue) when otherValue < value =>
      GraphRevisionOrder.newer,
    _TestRevision(value: final otherValue) when otherValue > value =>
      GraphRevisionOrder.older,
    _TestRevision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is _TestRevision && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID намерения.',
  ),
};

LongTermRelationId _relationIdFrom(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Некорректный UUID связи.',
      ),
    };

final _relationId = _relationIdFrom('018f47c2-6b7d-7abc-8def-0123456789ab');
final _otherRelationId = _relationIdFrom(
  '018f47c2-6b7d-7abc-8def-0123456789ac',
);

const _sourceUuid = '018f47c2-6b7d-7abc-8def-0123456789ad';
const _relatedUuid = '018f47c2-6b7d-7abc-8def-0123456789ae';
