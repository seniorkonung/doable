import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';

/// Дескриптор формы создания, открывшей поиск: через него поиск завершает
/// создание восстановлением связи, которая занимает пару.
abstract interface class RelationCreationRestore {
  /// Может ли поток создания продолжаться: верно, только пока форма принимает
  /// правки.
  bool get canContinue;

  /// Передаёт форме восстановление связи как её отправку.
  void accept(LongTermRelationId relationId);
}

/// Описание выбора участника, которое форма создания связи передаёт поиску.
///
/// Участники, вид, приоритет и описание — значения черновика в момент открытия
/// поиска. Проба пары выводится из описания, поэтому противоречивое сочетание
/// собрать нельзя.
final class RelationParticipantChoice {
  const RelationParticipantChoice({
    required this.role,
    required this.restore,
    required this.type,
    required this.priority,
    required this.description,
    required this.source,
    required this.related,
  });

  /// Роль, участника которой выбирает поиск.
  final RelationParticipantRole role;
  final RelationCreationRestore restore;

  /// Вид связи; `null`, пока он не выбран.
  final LongTermRelationType? type;

  /// Приоритет связи; `null`, пока он не выбран.
  final RelationPriority? priority;
  final String description;
  final RelationParticipantSummary? source;
  final RelationParticipantSummary? related;
}
