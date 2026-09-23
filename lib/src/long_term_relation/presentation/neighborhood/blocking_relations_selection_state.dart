import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation_id.dart';

/// Неизменяемый набор для отдельного пользовательского подтверждения.
final class BlockingRelationsPreparedSelection {
  BlockingRelationsPreparedSelection._({
    required this.command,
    required this.rows,
    required this.descriptions,
  });

  factory BlockingRelationsPreparedSelection.fromSelected({
    required IntentionId intentionId,
    required Map<LongTermRelationId, LongTermRelationSummary> selected,
    Map<LongTermRelationId, String?> descriptions = const {},
  }) {
    final rows = List<LongTermRelationSummary>.unmodifiable(selected.values);
    return BlockingRelationsPreparedSelection._(
      command: DeleteBlockingRelations.longTerm(
        intentionId: intentionId,
        relationIds: rows.map((row) => row.relation.id),
      ),
      rows: rows,
      descriptions: Map.unmodifiable(descriptions),
    );
  }

  final DeleteBlockingRelations command;
  final List<LongTermRelationSummary> rows;
  final Map<LongTermRelationId, String?> descriptions;
}

/// Выбор принадлежит одному намерению и не зависит от кэша соседства.
sealed class BlockingRelationsSelectionState {
  BlockingRelationsSelectionState({
    required this.intentionId,
    required Map<LongTermRelationId, LongTermRelationSummary> selected,
  }) : selected = Map.unmodifiable(selected);

  final IntentionId intentionId;
  final Map<LongTermRelationId, LongTermRelationSummary> selected;
}

enum BlockingRelationsInvalidReason {
  missing,
  noLongerBlocking,
  referencedByDailyPath,
}

final class BlockingRelationsSelectionEditing
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionEditing({
    required super.intentionId,
    required super.selected,
    Map<LongTermRelationId, BlockingRelationsInvalidReason> invalidReasons =
        const {},
  }) : invalidReasons = Map.unmodifiable(invalidReasons);

  /// Эти идентификаторы остаются видимыми до явного исправления выбора.
  final Map<LongTermRelationId, BlockingRelationsInvalidReason> invalidReasons;
  Set<LongTermRelationId> get invalidIds => invalidReasons.keys.toSet();
}

final class BlockingRelationsSelectionRefreshing
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionRefreshing({
    required super.intentionId,
    required super.selected,
  });
}

enum BlockingRelationsRefreshFailure {
  intentionNotFound,
  unavailable,
  corruption,
  unexpected,
}

final class BlockingRelationsSelectionRefreshFailed
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionRefreshFailed({
    required super.intentionId,
    required super.selected,
    required this.failure,
  });

  final BlockingRelationsRefreshFailure failure;
}

final class BlockingRelationsSelectionPrepared
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionPrepared({
    required super.intentionId,
    required super.selected,
    required this.snapshot,
  });

  final BlockingRelationsPreparedSelection snapshot;
}

final class BlockingRelationsSelectionRunning
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionRunning({
    required super.intentionId,
    required super.selected,
    required this.snapshot,
    required this.token,
  });

  final BlockingRelationsPreparedSelection snapshot;
  final BlockingRelationsDeleteOperationToken token;
}

sealed class BlockingRelationsSelectionFailure {
  const BlockingRelationsSelectionFailure();
}

final class BlockingRelationsSelectionCommandFailure
    extends BlockingRelationsSelectionFailure {
  const BlockingRelationsSelectionCommandFailure(this.failure);

  final DeleteBlockingRelationsFailure failure;
}

final class BlockingRelationsSelectionBusy
    extends BlockingRelationsSelectionFailure {
  const BlockingRelationsSelectionBusy();
}

final class BlockingRelationsSelectionDraining
    extends BlockingRelationsSelectionFailure {
  const BlockingRelationsSelectionDraining();
}

final class BlockingRelationsSelectionFailed
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionFailed({
    required super.intentionId,
    required super.selected,
    required this.failure,
    this.presentationClaim,
  });

  final BlockingRelationsSelectionFailure failure;
  final GraphInitiatorPresentationClaim? presentationClaim;

  bool get requiresRefresh => switch (failure) {
    BlockingRelationsSelectionCommandFailure(
      failure: DeleteBlockingRelationsSelectionConflictFailure(),
    ) =>
      true,
    _ => false,
  };
}
