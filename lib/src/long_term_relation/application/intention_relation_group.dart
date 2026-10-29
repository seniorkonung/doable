import '../domain/long_term_relation.dart';

/// Одна из четырёх групп связей страницы намерения.
///
/// Группа задаёт тип связи и её направление относительно намерения: у
/// исходящих группы оно исходный участник, у входящих — связанный.
enum IntentionRelationGroup {
  /// «Нужно»: намерению нужны другие.
  needs(type: LongTermRelationType.need, direction: RelationDirection.outgoing),

  /// «Можно использовать»: намерение можно достигать через другие.
  canUse(type: LongTermRelationType.can, direction: RelationDirection.outgoing),

  /// «Нужно для»: намерение нужно другим.
  neededFor(
    type: LongTermRelationType.need,
    direction: RelationDirection.incoming,
  ),

  /// «Можно использовать для»: намерение можно использовать для других.
  canBeUsedFor(
    type: LongTermRelationType.can,
    direction: RelationDirection.incoming,
  );

  const IntentionRelationGroup({required this.type, required this.direction});

  final LongTermRelationType type;
  final RelationDirection direction;
}
