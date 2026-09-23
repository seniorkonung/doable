import '../../daily_choice/domain/daily_choice_id.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';

/// Прямая зависимость намерения в подтверждённом наборе.
sealed class BlockingRelationReference {
  const BlockingRelationReference();
}

final class LongTermBlockingRelationReference
    extends BlockingRelationReference {
  const LongTermBlockingRelationReference(this.id);

  final LongTermRelationId id;

  @override
  bool operator ==(Object other) =>
      other is LongTermBlockingRelationReference && other.id == id;

  @override
  int get hashCode => Object.hash(LongTermBlockingRelationReference, id);
}

final class DailyChoiceBlockingRelationReference
    extends BlockingRelationReference {
  const DailyChoiceBlockingRelationReference(this.id);

  final DailyChoiceId id;

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceBlockingRelationReference && other.id == id;

  @override
  int get hashCode => Object.hash(DailyChoiceBlockingRelationReference, id);
}
