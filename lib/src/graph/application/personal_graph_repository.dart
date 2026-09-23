import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';
import 'selected_relations.dart';

abstract interface class GraphCommandRepository {
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}

abstract interface class PersonalGraphRepository
    implements GraphCommandRepository {
  /// Возвращает null в снимке, если выбор отсутствует на момент чтения.
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id);

  /// Наблюдает выбор вместе с текущими данными участников и связей его пути.
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id);

  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  );

  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  );

  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id);

  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  );

  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  );

  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}
