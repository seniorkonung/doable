import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
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

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../details/relation_details_test_support.dart';

/// Граф для страницы создания связи: команды, каталог выбора участника и
/// подробный просмотр связи конфликтующей пары.
///
/// Соседство и отдельная сводка здесь недоступны: форма получает выбор из
/// каталога и наблюдает выбранные на замену намерения до сохранения связи.
final class ControlledRelationFormRepository
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

  final catalogQueries = <IntentionCatalogQuery>[];
  final relationCommands = <CreateLongTermRelation>[];
  final relationUpdateCommands = <UpdateLongTermRelation>[];
  final relationWatches = <ControlledRelationWatch>[];
  final watchedIntentionIds = <IntentionId>[];
  final _intentionStreams =
      <
        IntentionId,
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>
      >{};
  final _catalogRequests = <Completer<Result<IntentionCatalogPage>>>[];
  final _relationRequests = <Completer<LongTermRelationCommandResult>>[];

  CreateLongTermRelation commandAt(int index) => relationCommands[index];

  UpdateLongTermRelation updateCommandAt(int index) =>
      relationUpdateCommands[index];

  ControlledRelationWatch watchAt(int index) => relationWatches[index];

  void emitIntention(
    Intention intention, {
    required RelationCounts counts,
    required GraphRevision revision,
  }) => _intentionStreams[intention.id]!.add(
    ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(intention: intention, relationCounts: counts),
        revision: revision,
      ),
    ),
  );

  /// Отдаёт очередную порцию каталога выбора участника.
  void completeCatalogPage(
    int index,
    List<IntentionSummary> items, {
    GraphRevision revision = const TestCatalogRevision(1),
  }) => _catalogRequests[index].complete(
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: revision,
      ),
    ),
  );

  void failRelationCommand(int index, LongTermRelationCommandFailure failure) =>
      _relationRequests[index].complete(GraphCommandFailed(failure));

  /// Подтверждает создание связи по отправленной команде того же индекса.
  LongTermRelation completeRelationCreated(int index, {int revision = 1}) {
    final command = relationCommands[index];
    final graphRevision = TestCatalogRevision(revision);
    final relation = LongTermRelation(
      id: testFormRelationId(index + 1),
      sourceIntentionId: command.sourceIntentionId,
      relatedIntentionId: command.relatedIntentionId,
      type: command.type,
      priority: command.priority,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(index + 1),
    );
    _relationRequests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationCreated(
            relation: relation,
            description: command.description,
            changes: <GraphChange>[
              LongTermRelationCreatedChange(
                revision: graphRevision,
                relation: relation,
              ),
            ],
          ),
        ),
      ),
    );
    return relation;
  }

  /// Подтверждает изменение связи по отправленной команде того же индекса.
  void completeRelationUpdated(
    int index, {
    required LongTermRelation before,
    required LongTermRelation after,
    required LongTermRelationDescription? description,
    int revision = 1,
  }) {
    final graphRevision = TestCatalogRevision(revision);
    _relationRequests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationUpdated(
            before: before,
            relation: after,
            description: description,
            changes: <GraphChange>[
              LongTermRelationUpdatedChange(
                revision: graphRevision,
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
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final CreateLongTermRelation creation => await _createRelation(creation),
      final UpdateLongTermRelation update => await _updateRelation(update),
      _ => throw UnsupportedError(
        'Форма связи отправляет только создание или изменение.',
      ),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogQueries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _catalogRequests.add(request);
    return request.future;
  }

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    final watch = ControlledRelationWatch(id);
    relationWatches.add(watch);
    return watch.stream;
  }

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не читается формой создания связи.');

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => Completer<RelationGroupPageResult>().future;

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    watchedIntentionIds.add(id);
    final controller = _intentionStreams.putIfAbsent(
      id,
      () =>
          StreamController<
            Result<GraphSnapshot<IntentionDetails?>>
          >.broadcast(),
    );
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final watch in relationWatches) {
      await watch.close();
    }
    for (final controller in _intentionStreams.values) {
      await controller.close();
    }
  }

  Future<LongTermRelationCommandResult> _createRelation(
    CreateLongTermRelation command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationRequests.add(request);
    return request.future;
  }

  Future<LongTermRelationCommandResult> _updateRelation(
    UpdateLongTermRelation command,
  ) {
    relationUpdateCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationRequests.add(request);
    return request.future;
  }
}

LongTermRelationId testFormRelationId(int index) {
  final encoded =
      '018f1400-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (LongTermRelationId.decode(encoded)) {
    LongTermRelationIdDecodingSuccess(:final id) => id,
    InvalidLongTermRelationIdDecoding() => throw StateError(
      'Некорректный fixture ID связи.',
    ),
  };
}
