import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';

abstract interface class GraphCommandRepository<
  TCommand extends GraphCommand<TSuccess, TFailure>,
  TSuccess extends GraphCommandOutcome,
  TFailure extends GraphCommandFailure
> {
  Future<GraphCommandResult<TSuccess, TFailure>> execute(TCommand command);
}

abstract interface class PersonalGraphRepository
    implements
        GraphCommandRepository<
          IntentionCommand,
          IntentionCommandSuccess,
          IntentionFailure
        > {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  );

  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  );

  @override
  Future<GraphCommandResult<IntentionCommandSuccess, IntentionFailure>> execute(
    IntentionCommand command,
  );
}
