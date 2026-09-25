import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';

/// Подтверждённый пользователем смысл перехода. Он сверяется с графом
/// заново в транзакции сохранения и не записывается как снимок в шаг пути.
final class ConfirmedChoicePathStep {
  const ConfirmedChoicePathStep({
    required this.relationId,
    required this.sourceIntentionId,
    required this.type,
    required this.relatedIntentionId,
  });

  final LongTermRelationId relationId;
  final IntentionId sourceIntentionId;
  final LongTermRelationType type;
  final IntentionId relatedIntentionId;
}

final class ConfirmedChoicePath {
  factory ConfirmedChoicePath(Iterable<ConfirmedChoicePathStep> steps) {
    final ordered = List<ConfirmedChoicePathStep>.unmodifiable(steps);
    if (ordered.isEmpty) {
      throw ArgumentError.value(steps, 'steps');
    }
    return ConfirmedChoicePath._(ordered);
  }

  const ConfirmedChoicePath._(this.steps);

  final List<ConfirmedChoicePathStep> steps;
}
