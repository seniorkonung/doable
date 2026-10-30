import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';

/// Поток формы связи, из которой открыт поиск участника.
sealed class RelationParticipantChoiceFlow {
  const RelationParticipantChoiceFlow();
}

/// Создание новой связи: архивного состояния у неё ещё нет.
final class RelationCreationChoiceFlow extends RelationParticipantChoiceFlow {
  const RelationCreationChoiceFlow();
}

/// Изменение существующей связи в её подтверждённом архивном состоянии.
final class RelationChangeChoiceFlow extends RelationParticipantChoiceFlow {
  const RelationChangeChoiceFlow({
    required this.relationId,
    required this.relationScope,
  });

  final LongTermRelationId relationId;
  final RelationScope relationScope;
}

/// Описание выбора участника, которое форма связи передаёт поиску.
///
/// Участники и вид — значения черновика в момент открытия поиска. Проба пары
/// и допустимый охват выводятся из описания, поэтому противоречивое сочетание
/// собрать нельзя.
final class RelationParticipantChoice {
  const RelationParticipantChoice({
    required this.role,
    required this.flow,
    required this.type,
    required this.source,
    required this.related,
  });

  /// Роль, участника которой выбирает поиск.
  final RelationParticipantRole role;
  final RelationParticipantChoiceFlow flow;

  /// Вид связи; `null`, пока он не выбран.
  final LongTermRelationType? type;
  final RelationParticipantSummary? source;
  final RelationParticipantSummary? related;
}
