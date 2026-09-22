import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

import '../neighborhood/neighborhood_test_support.dart';

/// Одно наблюдение подробных данных связи, которым управляет тест.
final class ControlledRelationWatch {
  ControlledRelationWatch(this.relationId)
    : _controller = StreamController<LongTermRelationReadResult>(sync: true);

  final LongTermRelationId relationId;
  final StreamController<LongTermRelationReadResult> _controller;

  Stream<LongTermRelationReadResult> get stream => _controller.stream;

  bool get isObserved => _controller.hasListener;

  void emitDetails(
    LongTermRelationDetails details, {
    required GraphRevision revision,
  }) => _controller.add(
    GraphResultSuccess(GraphSnapshot(value: details, revision: revision)),
  );

  void emitMissing({required GraphRevision revision}) => _controller.add(
    GraphResultSuccess(
      GraphSnapshot<LongTermRelationDetails?>(value: null, revision: revision),
    ),
  );

  void fail(LongTermRelationReadFailure failure) =>
      _controller.add(GraphResultFailure(failure));

  void throwError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();
}

/// Управляемый граф для подробного просмотра связи и переходов к участникам.
final class ControlledRelationDetailsRepository
    implements PersonalGraphRepository {
  final relationWatches = <ControlledRelationWatch>[];
  final watchedIntentionIds = <IntentionId>[];
  final groupQueries = <RelationGroupQuery>[];
  final _intentionControllers =
      <
        IntentionId,
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>
      >{};
  final _groupRequests = <Completer<RelationGroupPageResult>>[];
  final relationCommands = <LongTermRelationCommand>[];
  final _relationCommandRequests = <Completer<LongTermRelationCommandResult>>[];

  ControlledRelationWatch watchAt(int index) => relationWatches[index];

  /// Последнее наблюдение указанной связи.
  ControlledRelationWatch latestWatchOf(LongTermRelationId relationId) =>
      relationWatches.lastWhere((watch) => watch.relationId == relationId);

  void emitIntention(
    Intention intention, {
    required RelationCounts counts,
    required GraphRevision revision,
  }) => _intentionControllerFor(intention.id).add(
    ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(intention: intention, relationCounts: counts),
        revision: revision,
      ),
    ),
  );

  void completeGroupPage(int index, RelationGroupPage page) =>
      _groupRequests[index].complete(GraphResultSuccess(page));

  void completeRelationUpdate(
    int index, {
    required LongTermRelation before,
    required LongTermRelation after,
    required GraphRevision revision,
    LongTermRelationDescription? description,
  }) => _relationCommandRequests[index].complete(
    GraphCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: LongTermRelationUpdated(
          before: before,
          relation: after,
          description: description,
          changes: <GraphChange>[
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

  void completeRelationDelete(
    int index, {
    required LongTermRelation relation,
    required GraphRevision revision,
  }) => _relationCommandRequests[index].complete(
    GraphCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: LongTermRelationDeleted(
          relation: relation,
          changes: <GraphChange>[
            LongTermRelationDeletedChange(
              revision: revision,
              relation: relation,
            ),
          ],
        ),
      ),
    ),
  );

  void failRelationCommand(int index, LongTermRelationCommandFailure failure) =>
      _relationCommandRequests[index].complete(GraphCommandFailed(failure));

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    final watch = ControlledRelationWatch(id);
    relationWatches.add(watch);
    return watch.stream;
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    watchedIntentionIds.add(id);
    return _intentionControllerFor(id).stream;
  }

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) {
    groupQueries.add(query);
    final request = Completer<RelationGroupPageResult>();
    _groupRequests.add(request);
    return request.future;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этом тесте.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Отдельная сводка не читается этим тестом.');

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final LongTermRelationCommand relationCommand =>
        await _executeRelationCommand(relationCommand),
      _ => throw UnsupportedError('Команда вне границы этого теста.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<void> dispose() async {
    for (final watch in relationWatches) {
      await watch.close();
    }
    for (final controller in _intentionControllers.values) {
      await controller.close();
    }
  }

  StreamController<Result<GraphSnapshot<IntentionDetails?>>>
  _intentionControllerFor(IntentionId id) => _intentionControllers.putIfAbsent(
    id,
    () => StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
      sync: true,
    ),
  );

  Future<LongTermRelationCommandResult> _executeRelationCommand(
    LongTermRelationCommand command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationCommandRequests.add(request);
    return request.future;
  }
}

/// Подробные данные связи между двумя намерениями.
LongTermRelationDetails testRelationDetails({
  required LongTermRelationId relationId,
  required IntentionId sourceId,
  required IntentionId relatedId,
  String sourceTitle = 'Исходное намерение',
  String relatedTitle = 'Связанное намерение',
  IntentionArchiveState sourceArchiveState = IntentionArchiveState.active,
  IntentionArchiveState relatedArchiveState = IntentionArchiveState.active,
  int sourceActiveRelationCount = 1,
  int relatedActiveRelationCount = 1,
  LongTermRelationType type = LongTermRelationType.need,
  RelationPriority priority = RelationPriority.p2,
  RelationScope scope = RelationScope.active,
  int creationSequence = 1,
  String? description,
}) => LongTermRelationDetails(
  relation: LongTermRelation(
    id: relationId,
    sourceIntentionId: sourceId,
    relatedIntentionId: relatedId,
    type: type,
    priority: priority,
    scope: scope,
    creationSequence: RelationCreationSequence(creationSequence),
  ),
  source: testParticipant(
    sourceId,
    title: sourceTitle,
    archiveState: sourceArchiveState,
    activeRelationCount: sourceActiveRelationCount,
  ),
  related: testParticipant(
    relatedId,
    title: relatedTitle,
    archiveState: relatedArchiveState,
    activeRelationCount: relatedActiveRelationCount,
  ),
  description: description == null
      ? null
      : LongTermRelationDescription.fromInput(description),
);
