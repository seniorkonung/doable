import '../domain/long_term_relation.dart';

/// Закрытый выбор одной из десяти прямых групп зависимостей намерения.
sealed class RelationGroup {
  const RelationGroup();
}

final class LongTermRelationGroup extends RelationGroup {
  const LongTermRelationGroup({
    required this.type,
    required this.direction,
    required this.scope,
  });

  final LongTermRelationType type;
  final RelationDirection direction;
  final RelationScope scope;

  @override
  bool operator ==(Object other) =>
      other is LongTermRelationGroup &&
      other.type == type &&
      other.direction == direction &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(type, direction, scope);
}

enum DailyChoiceRelationRole { source, selected }

/// У дневного выбора нет архивного состояния или направления связи.
final class DailyChoiceRelationGroup extends RelationGroup {
  const DailyChoiceRelationGroup({required this.role});

  final DailyChoiceRelationRole role;

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceRelationGroup && other.role == role;

  @override
  int get hashCode => Object.hash(DailyChoiceRelationGroup, role);
}
