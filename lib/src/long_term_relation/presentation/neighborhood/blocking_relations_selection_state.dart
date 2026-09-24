import '../../../daily_choice/application/daily_choice_catalog.dart';
import '../../../graph/application/blocking_relation_reference.dart';
import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation_id.dart';

sealed class BlockingRelationsSelectedItem {
  const BlockingRelationsSelectedItem();

  BlockingRelationReference get reference;
}

final class BlockingRelationsSelectedLongTerm
    extends BlockingRelationsSelectedItem {
  const BlockingRelationsSelectedLongTerm(this.row);

  final LongTermRelationSummary row;

  @override
  BlockingRelationReference get reference =>
      LongTermBlockingRelationReference(row.relation.id);
}

final class BlockingRelationsSelectedDailyChoice
    extends BlockingRelationsSelectedItem {
  const BlockingRelationsSelectedDailyChoice(this.item);

  final DailyChoiceCatalogItem item;

  @override
  BlockingRelationReference get reference =>
      DailyChoiceBlockingRelationReference(item.id);
}

/// Неизменяемый набор для отдельного пользовательского подтверждения.
final class BlockingRelationsPreparedSelection {
  BlockingRelationsPreparedSelection._({
    required this.command,
    required this.items,
    required this.descriptions,
  });

  factory BlockingRelationsPreparedSelection.fromSelected({
    required IntentionId intentionId,
    required Map<BlockingRelationReference, BlockingRelationsSelectedItem>
    selected,
    Map<LongTermRelationId, String?> descriptions = const {},
  }) {
    final items = List<BlockingRelationsSelectedItem>.unmodifiable(
      selected.values,
    );
    return BlockingRelationsPreparedSelection._(
      command: DeleteBlockingRelations(
        intentionId: intentionId,
        references: items.map((item) => item.reference),
      ),
      items: items,
      descriptions: Map.unmodifiable(descriptions),
    );
  }

  final DeleteBlockingRelations command;
  final List<BlockingRelationsSelectedItem> items;
  final Map<LongTermRelationId, String?> descriptions;

  List<LongTermRelationSummary> get rows => List.unmodifiable(
    items.whereType<BlockingRelationsSelectedLongTerm>().map(
      (item) => item.row,
    ),
  );
}

/// Выбор принадлежит одному намерению и не зависит от кэша соседства.
sealed class BlockingRelationsSelectionState {
  BlockingRelationsSelectionState({
    required this.intentionId,
    required Map<BlockingRelationReference, BlockingRelationsSelectedItem>
    selectedByReference,
  }) : selectedByReference = Map.unmodifiable(selectedByReference);

  final IntentionId intentionId;
  final Map<BlockingRelationReference, BlockingRelationsSelectedItem>
  selectedByReference;

  Map<LongTermRelationId, LongTermRelationSummary> get selected =>
      Map.unmodifiable({
        for (final item in selectedByReference.values)
          if (item case BlockingRelationsSelectedLongTerm(:final row))
            row.relation.id: row,
      });
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
    required super.selectedByReference,
    Map<BlockingRelationReference, BlockingRelationsInvalidReason>
        invalidReasonsByReference =
        const {},
  }) : invalidReasonsByReference = Map.unmodifiable(invalidReasonsByReference);

  /// Эти идентификаторы остаются видимыми до явного исправления выбора.
  final Map<BlockingRelationReference, BlockingRelationsInvalidReason>
  invalidReasonsByReference;
  Map<LongTermRelationId, BlockingRelationsInvalidReason> get invalidReasons =>
      Map.unmodifiable({
        for (final entry in invalidReasonsByReference.entries)
          if (entry.key case LongTermBlockingRelationReference(:final id))
            id: entry.value,
      });
  Set<LongTermRelationId> get invalidIds => invalidReasons.keys.toSet();
}

final class BlockingRelationsSelectionRefreshing
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionRefreshing({
    required super.intentionId,
    required super.selectedByReference,
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
    required super.selectedByReference,
    required this.failure,
  });

  final BlockingRelationsRefreshFailure failure;
}

final class BlockingRelationsSelectionPrepared
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionPrepared({
    required super.intentionId,
    required super.selectedByReference,
    required this.snapshot,
  });

  final BlockingRelationsPreparedSelection snapshot;
}

final class BlockingRelationsSelectionRunning
    extends BlockingRelationsSelectionState {
  BlockingRelationsSelectionRunning({
    required super.intentionId,
    required super.selectedByReference,
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
    required super.selectedByReference,
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
