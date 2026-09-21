import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../details/relation_details_test_support.dart';

/// Граф для страницы создания связи: команды, каталог выбора участника и
/// подробный просмотр связи конфликтующей пары.
///
/// Соседство и сводка здесь недоступны намеренно: открытая форма не заводит
/// собственного чтения графа и опирается только на общий каталог намерений.
final class ControlledRelationFormRepository
    implements PersonalGraphRepository {
  final catalogQueries = <IntentionCatalogQuery>[];
  final relationCommands = <CreateLongTermRelation>[];
  final relationWatches = <ControlledRelationWatch>[];
  final _intentionStreams =
      <StreamController<Result<GraphSnapshot<IntentionDetails?>>>>[];
  final _catalogRequests = <Completer<Result<IntentionCatalogPage>>>[];
  final _relationRequests = <Completer<LongTermRelationCommandResult>>[];

  CreateLongTermRelation commandAt(int index) => relationCommands[index];

  /// Отдаёт очередную порцию каталога выбора участника.
  void completeCatalogPage(int index, List<IntentionSummary> items) =>
      _catalogRequests[index].complete(
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: items,
            totalCount: items.length,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
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

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final CreateLongTermRelation creation => await _createRelation(creation),
      _ => throw UnsupportedError('Форма связи отправляет только создание.'),
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
    final controller =
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast();
    _intentionStreams.add(controller);
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final watch in relationWatches) {
      await watch.close();
    }
    for (final controller in _intentionStreams) {
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
