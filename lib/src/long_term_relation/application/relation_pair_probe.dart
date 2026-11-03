import '../../intention/domain/intention_id.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_id.dart';
import 'intention_relation_group.dart';
import 'long_term_relation_command.dart';

/// Направленная пара, которую проверяет поиск участника связи.
///
/// Единственное значение, из которого выводится исключение участника другой
/// роли, поэтому исключение и проверка пары не могут назвать разных участников.
final class RelationPairProbe {
  const RelationPairProbe({
    required this.counterpartId,
    required this.candidateRole,
  });

  factory RelationPairProbe.forGroup({
    required IntentionId intentionId,
    required IntentionRelationGroup group,
  }) => RelationPairProbe(
    counterpartId: intentionId,
    candidateRole: switch (group.direction) {
      RelationDirection.outgoing => RelationParticipantRole.related,
      RelationDirection.incoming => RelationParticipantRole.source,
    },
  );

  /// Участник другой роли; в выдачу не входит.
  final IntentionId counterpartId;

  /// Роль, участника которой выбирает поиск.
  final RelationParticipantRole candidateRole;

  @override
  bool operator ==(Object other) =>
      other is RelationPairProbe &&
      other.counterpartId == counterpartId &&
      other.candidateRole == candidateRole;

  @override
  int get hashCode => Object.hash(counterpartId, candidateRole);
}

/// Связь, которая занимает направленную пару строки поиска участника.
final class PairOccupant {
  const PairOccupant({
    required this.relationId,
    required this.type,
    required this.scope,
  });

  final LongTermRelationId relationId;
  final LongTermRelationType type;

  /// Архивное состояние занимающей связи.
  final RelationScope scope;

  @override
  bool operator ==(Object other) =>
      other is PairOccupant &&
      other.relationId == relationId &&
      other.type == type &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(relationId, type, scope);
}

/// Причина занятости пары относительно группы поиска.
sealed class RelationPairReason {
  const RelationPairReason();

  factory RelationPairReason.from({
    required IntentionRelationGroup group,
    required PairOccupant occupant,
  }) {
    if (group.type == occupant.type) {
      return RelationPairSameGroup(occupant.scope);
    }
    final otherGroup = switch (group) {
      IntentionRelationGroup.needs => IntentionRelationGroup.canUse,
      IntentionRelationGroup.canUse => IntentionRelationGroup.needs,
      IntentionRelationGroup.neededFor => IntentionRelationGroup.canBeUsedFor,
      IntentionRelationGroup.canBeUsedFor => IntentionRelationGroup.neededFor,
    };
    return RelationPairOtherGroup(otherGroup, occupant.scope);
  }
}

final class RelationPairSameGroup extends RelationPairReason {
  const RelationPairSameGroup(this.scope);
  final RelationScope scope;
}

final class RelationPairOtherGroup extends RelationPairReason {
  const RelationPairOtherGroup(this.group, this.scope);
  final IntentionRelationGroup group;
  final RelationScope scope;
}
