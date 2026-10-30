import '../../intention/domain/intention_id.dart';
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
    this.ignoredRelationId,
  });

  /// Участник другой роли; в выдачу не входит.
  final IntentionId counterpartId;

  /// Роль, участника которой выбирает поиск.
  final RelationParticipantRole candidateRole;

  /// Изменяемая связь: собственную пару она не занимает.
  final LongTermRelationId? ignoredRelationId;

  @override
  bool operator ==(Object other) =>
      other is RelationPairProbe &&
      other.counterpartId == counterpartId &&
      other.candidateRole == candidateRole &&
      other.ignoredRelationId == ignoredRelationId;

  @override
  int get hashCode =>
      Object.hash(counterpartId, candidateRole, ignoredRelationId);
}
