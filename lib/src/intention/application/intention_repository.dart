import '../domain/intention.dart';
import '../domain/intention_id.dart';
import 'intention_command.dart';
import 'intention_result.dart';

enum IntentionScope { active, archive }

enum IntentionCatalogOrder { byCreationTime, byUpdateTime }

abstract interface class IntentionRepository {
  Stream<List<Intention>> watchCatalog(
    IntentionScope scope,
    IntentionCatalogOrder order,
  );

  Stream<Intention?> watchById(IntentionId id);

  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command);
}
