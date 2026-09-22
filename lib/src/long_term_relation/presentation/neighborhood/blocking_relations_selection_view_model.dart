import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation_id.dart';
import 'blocking_relations_selection_state.dart';

part 'blocking_relations_selection_view_model.g.dart';

/// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.
@riverpod
final class BlockingRelationsSelectionViewModel
    extends _$BlockingRelationsSelectionViewModel {
  late GraphCommandCoordinator _coordinator;
  BlockingRelationsDeleteOperationToken? _activeToken;

  @override
  BlockingRelationsSelectionState build(IntentionId intentionId) {
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final token = _activeToken;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
    });
    return BlockingRelationsSelectionEditing(
      intentionId: intentionId,
      selected: const {},
    );
  }

  /// Добавляет только явно указанную непосредственную связь.
  bool select(LongTermRelationSummary row) {
    final current = state;
    if (current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionSucceeded) {
      return false;
    }
    final relation = row.relation;
    if (relation.sourceIntentionId != current.intentionId &&
        relation.relatedIntentionId != current.intentionId) {
      return false;
    }
    if (current.selected.containsKey(relation.id)) {
      return false;
    }
    _releaseFailureClaim();
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selected: {...current.selected, relation.id: row},
    );
    return true;
  }

  /// Удаляет только конкретный идентификатор из незавершённого выбора.
  bool unselect(LongTermRelationId relationId) {
    final current = state;
    if (current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionSucceeded ||
        !current.selected.containsKey(relationId)) {
      return false;
    }
    _releaseFailureClaim();
    final updated = Map<LongTermRelationId, LongTermRelationSummary>.of(
      current.selected,
    )..remove(relationId);
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selected: updated,
    );
    return true;
  }

  /// Фиксирует непустой набор для просмотра и отдельного подтверждения.
  bool prepare() {
    final current = state;
    if (current is! BlockingRelationsSelectionEditing ||
        current.selected.isEmpty) {
      return false;
    }
    state = BlockingRelationsSelectionPrepared(
      intentionId: current.intentionId,
      selected: current.selected,
      snapshot: BlockingRelationsPreparedSelection.fromSelected(
        intentionId: current.intentionId,
        selected: current.selected,
      ),
    );
    return true;
  }

  /// Отмена до принятия команды оставляет черновик и не пишет в граф.
  void cancel() {
    final current = state;
    if (current is BlockingRelationsSelectionPrepared) {
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: current.selected,
      );
    }
  }

  /// Подтверждённый снимок отправляется общему координатору только однажды.
  void confirm({required String presentationTitle}) {
    final current = state;
    if (current is! BlockingRelationsSelectionPrepared) {
      return;
    }
    final start = _coordinator.acceptBlockingRelationsDelete(
      current.snapshot.command,
      presentationTitle: presentationTitle,
    );
    switch (start) {
      case BlockingRelationsDeleteAccepted(:final token, :final future):
        _activeToken = token;
        state = BlockingRelationsSelectionRunning(
          intentionId: current.intentionId,
          selected: current.selected,
          snapshot: current.snapshot,
          token: token,
        );
        unawaited(_finish(future));
      case BlockingRelationsDeleteAlreadyRunning():
        state = BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selected: current.selected,
          failure: const BlockingRelationsSelectionBusy(),
        );
      case GraphCommandCoordinatorDraining():
        state = BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selected: current.selected,
          failure: const BlockingRelationsSelectionDraining(),
        );
    }
  }

  /// После отказа исправление начинается явно, без повтора старой команды.
  void resumeEditing() {
    final current = state;
    if (current is BlockingRelationsSelectionFailed) {
      _releaseFailureClaim();
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: current.selected,
      );
    }
  }

  Future<void> _finish(Future<BlockingRelationsDeleteCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }
      final current = state;
      if (current is! BlockingRelationsSelectionRunning) {
        return;
      }
      state = switch (completion.result) {
        GraphResultSuccess(value: final confirmed) =>
          BlockingRelationsSelectionSucceeded(
            intentionId: current.intentionId,
            selected: current.selected,
            snapshot: current.snapshot,
            deleted: confirmed.value,
          ),
        GraphResultFailure(:final failure) => BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selected: current.selected,
          failure: BlockingRelationsSelectionCommandFailure(failure),
          presentationClaim: _coordinator.claimInitiatorFailure(
            completion.token,
          ),
        ),
      };
      if (completion.result is GraphResultSuccess) {
        _activeToken = null;
      }
    } on Object {
      if (!ref.mounted) {
        return;
      }
      _releaseFailureClaim();
      final current = state;
      if (current is BlockingRelationsSelectionRunning) {
        state = BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selected: current.selected,
          failure: const BlockingRelationsSelectionCommandFailure(
            DeleteBlockingRelationsUnexpectedFailure(),
          ),
        );
      }
    }
  }

  void _releaseFailureClaim() {
    final token = _activeToken;
    if (token != null) {
      _coordinator.releaseInitiatorPresentation(token);
      _activeToken = null;
    }
  }
}
