import '../../intention/domain/intention_id.dart';
import '../domain/long_term_relation.dart';
import '../domain/long_term_relation_id.dart';
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
  const PairOccupant({required this.relationId, required this.scope});

  final LongTermRelationId relationId;

  /// Архивное состояние занимающей связи.
  final RelationScope scope;

  @override
  bool operator ==(Object other) =>
      other is PairOccupant &&
      other.relationId == relationId &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(relationId, scope);
}
