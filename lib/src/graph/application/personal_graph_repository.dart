import '../../action/application/action_read_contract.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../statistics/application/statistics_read_contract.dart';
import '../../tag/application/tag_read_result.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';

abstract interface class GraphCommandRepository {
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}

abstract interface class PersonalGraphRepository
    implements
        GraphCommandRepository,
        ActionReadContract,
        TagReadContract,
        StatisticsReadContract {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  /// Читает одну прямую группу долговременных связей намерения.
  /// Первая порция и полная сводка получены на одной ревизии; продолжение
  /// относится к снимку графа первой порции.
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  );

  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id);

  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}
