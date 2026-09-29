import '../../intention/domain/intention_id.dart';
import 'tag_id.dart';

/// Назначение одному намерению определяется парой идентичностей тега и намерения.
/// Архивное состояние и готовность к действию не меняют получателя.
/// Назначение не распространяется на соседние намерения или связи.
final class TagAssignment {
  const TagAssignment({required this.tagId, required this.intentionId});

  final TagId tagId;
  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is TagAssignment &&
      other.tagId == tagId &&
      other.intentionId == intentionId;

  @override
  int get hashCode => Object.hash(tagId, intentionId);
}
