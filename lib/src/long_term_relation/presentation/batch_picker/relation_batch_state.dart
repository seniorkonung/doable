import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_command.dart';
import '../../domain/long_term_relation.dart';

/// Отмеченное намерение и его актуальное название.
final class RelationBatchSelection {
  const RelationBatchSelection({required this.id, required this.title});

  final IntentionId id;
  final String title;
}

/// Состояние добавления отмеченных намерений.
sealed class RelationBatchOperation {
  const RelationBatchOperation();
}

final class RelationBatchIdle extends RelationBatchOperation {
  const RelationBatchIdle();
}

final class RelationBatchSubmitting extends RelationBatchOperation {
  const RelationBatchSubmitting();
}

/// Отказ с правом инициатора предъявить его на экране поиска; [claim] нет у
/// команды, которую координатор не принял.
final class RelationBatchFailed extends RelationBatchOperation {
  const RelationBatchFailed({required this.failure, required this.claim});

  final LongTermRelationCommandFailure failure;
  final GraphInitiatorPresentationClaim? claim;
}

/// Связи подтверждены, и поиск закрывается.
/// Связи пачки в порядке отметок.
final class RelationBatchAdded extends RelationBatchOperation {
  RelationBatchAdded(Iterable<LongTermRelation> relations)
    : relations = List.unmodifiable(relations);

  final List<LongTermRelation> relations;
}

/// Состояние отметок одного экземпляра поиска.
final class RelationBatchState {
  RelationBatchState({
    required this.pageTitle,
    required Iterable<RelationBatchSelection> selected,
    required this.operation,
    required this.hasCreatedIntentions,
  }) : selected = List.unmodifiable(selected);

  final String pageTitle;
  final List<RelationBatchSelection> selected;
  final RelationBatchOperation operation;
  final bool hasCreatedIntentions;

  /// Отметки и переходы со строк принимаются, пока добавление не начато.
  bool get canEdit => switch (operation) {
    RelationBatchIdle() || RelationBatchFailed() => true,
    RelationBatchSubmitting() || RelationBatchAdded() => false,
  };

  bool get canSubmit => canEdit && selected.isNotEmpty;
}
