import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_repository.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import 'graph_revision.dart';

abstract interface class GraphCommandRepository {
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  );
}

abstract interface class PersonalGraphRepository
    implements GraphCommandRepository {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Stream<Result<GraphSnapshot<Intention?>>> watchIntention(IntentionId id);

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  );
}
