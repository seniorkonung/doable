import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
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

import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  group('GraphCommandCoordinator — изменение долговременной связи', () {
    test('удаление разделяет ключ со всеми операциями той же связи', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);

      final deletion = coordinator.acceptRelationDelete(
        DeleteLongTermRelation(_relationId),
      );
      final repeatedDeletion = coordinator.acceptRelationDelete(
        DeleteLongTermRelation(_relationId),
      );
      final competingUpdate = coordinator.acceptRelationUpdate(
        _updateRelation(_relationId),
      );
      final competingArchive = coordinator.acceptRelationArchive(
        ArchiveLongTermRelation(_relationId),
      );
      final competingRestore = coordinator.acceptRelationRestore(
        RestoreLongTermRelation(_relationId),
      );
      final independentDeletion = coordinator.acceptRelationDelete(
        DeleteLongTermRelation(_otherRelationId),
      );

      expect(deletion, isA<LongTermRelationCommandAccepted>());
      expect(repeatedDeletion, isA<LongTermRelationCommandAlreadyRunning>());
      expect(competingUpdate, isA<LongTermRelationCommandAlreadyRunning>());
      expect(competingArchive, isA<LongTermRelationCommandAlreadyRunning>());
      expect(competingRestore, isA<LongTermRelationCommandAlreadyRunning>());
      expect(independentDeletion, isA<LongTermRelationCommandAccepted>());
      expect(repository.commands, [
        isA<DeleteLongTermRelation>(),
        isA<DeleteLongTermRelation>(),
      ]);

      repository
        ..completeRelationDeleted(0, _relationId, revision: 1)
        ..completeRelationFailure(1);
      final deletionCompletion =
          await (deletion as LongTermRelationCommandAccepted).future;
      await (independentDeletion as LongTermRelationCommandAccepted).future;

      expect(deletionCompletion.kind, LongTermRelationCommandKind.delete);
      expect(
        deletionCompletion.result,
        isA<
              GraphResultSuccess<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >
            >()
            .having(
              (result) => result.value,
              'результат',
              isA<LongTermRelationDeleted>(),
            ),
      );
      expect(coordinator.isRelationRunning(_relationId), isFalse);
      await coordinator.shutdown();
    });

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

LongTermRelation _relation(
  LongTermRelationId id,
  RelationPriority priority, {
  RelationScope scope = RelationScope.active,
}) => LongTermRelation(
  id: id,
  sourceIntentionId: _intentionId(_sourceUuid),
  relatedIntentionId: _intentionId(_relatedUuid),
  type: LongTermRelationType.need,
  priority: priority,
  scope: scope,
  creationSequence: RelationCreationSequence(1),
);

final class _ControlledPersonalGraphRepository
    with TagReadContractTestFallback, CatalogReconciliationTestFallback
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

  void completeRelationDeleted(
    int index,
    LongTermRelationId id, {
    required int revision,
  }) {
    final graphRevision = _TestRevision(revision);
    final relation = _relation(id, RelationPriority.p2);
    _results[index].complete(
      GraphCommandSucceeded<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationDeleted(
            relation: relation,
            changes: [
              LongTermRelationDeletedChange(
                revision: graphRevision,
                relation: relation,
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
