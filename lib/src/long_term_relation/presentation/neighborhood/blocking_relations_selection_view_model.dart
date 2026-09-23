import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/application/selected_relations.dart';
import '../../../intention/application/intention_result.dart';
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
  late PersonalGraphRepository _repository;
  BlockingRelationsDeleteOperationToken? _activeToken;
  GraphRevision? _selectionRevision;
  final _descriptions = <LongTermRelationId, String?>{};
  final _invalidReasons =
      <LongTermRelationId, BlockingRelationsInvalidReason>{};
  StreamSubscription<SelectedRelationsReadResult>? _preparedSubscription;

  @override
  BlockingRelationsSelectionState build(IntentionId intentionId) {
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _repository = ref.watch(personalGraphRepositoryProvider);
    ref.onDispose(() {
      _stopPreparedObservation();
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
        current is BlockingRelationsSelectionRefreshing ||
        current is BlockingRelationsSelectionRefreshFailed ||
        (current is BlockingRelationsSelectionFailed &&
            current.requiresRefresh)) {
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
    _stopPreparedObservation();
    _releaseFailureClaim();
    _selectionRevision = null;
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selected: {...current.selected, relation.id: row},
      invalidReasons: _invalidReasons,
    );
    return true;
  }

  /// Удаляет только конкретный идентификатор из незавершённого выбора.
  bool unselect(LongTermRelationId relationId) {
    final current = state;
    if (current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionRefreshing ||
        current is BlockingRelationsSelectionRefreshFailed ||
        (current is BlockingRelationsSelectionFailed &&
            current.requiresRefresh) ||
        !current.selected.containsKey(relationId)) {
      return false;
    }
    _stopPreparedObservation();
    _releaseFailureClaim();
    _selectionRevision = null;
    final updated = Map<LongTermRelationId, LongTermRelationSummary>.of(
      current.selected,
    )..remove(relationId);
    _descriptions.remove(relationId);
    _invalidReasons.remove(relationId);
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selected: updated,
      invalidReasons: _invalidReasons,
    );
    return true;
  }

  /// Фиксирует непустой набор для просмотра и отдельного подтверждения.
  bool prepare() {
    final current = state;
    if (current is! BlockingRelationsSelectionEditing ||
        current.selected.isEmpty ||
        current.invalidReasons.isNotEmpty) {
      return false;
    }
    state = BlockingRelationsSelectionPrepared(
      intentionId: current.intentionId,
      selected: current.selected,
      snapshot: BlockingRelationsPreparedSelection.fromSelected(
        intentionId: current.intentionId,
        selected: current.selected,
        descriptions: _descriptions,
      ),
    );
    return true;
  }

  /// Пока подтверждение открыто, новые снимки выбранных связей обновляют его.
  void observePrepared() {
    final current = state;
    if (current is! BlockingRelationsSelectionPrepared) {
      return;
    }
    _stopPreparedObservation();
    final query = SelectedRelationsQuery(
      intentionId: current.intentionId,
      relationIds: current.selected.keys,
    );
    _preparedSubscription = _repository
        .watchSelectedRelations(query)
        .listen(
          _handlePreparedObservation,
          onError: (Object _) =>
              _preparedReadFailed(BlockingRelationsRefreshFailure.unexpected),
        );
  }

  void _handlePreparedObservation(SelectedRelationsReadResult result) {
    if (!ref.mounted || state is! BlockingRelationsSelectionPrepared) {
      return;
    }
    final current = state as BlockingRelationsSelectionPrepared;
    switch (result) {
      case SelectedRelationsReadError(:final failure):
        _preparedReadFailed(switch (failure) {
          SelectedRelationsReadUnavailableFailure() =>
            BlockingRelationsRefreshFailure.unavailable,
          SelectedRelationsReadCorruptionFailure() =>
            BlockingRelationsRefreshFailure.corruption,
          SelectedRelationsReadUnexpectedFailure() =>
            BlockingRelationsRefreshFailure.unexpected,
        });
      case SelectedRelationsReadSuccess(value: final snapshot):
        final previousRevision = _selectionRevision;
        if (previousRevision != null &&
            (snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.older ||
                snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.same)) {
          return;
        }
        final updated = _updatedSelection(current.selected, snapshot.value);
        _selectionRevision = snapshot.revision;
        _descriptions
          ..clear()
          ..addAll(updated.descriptions);
        _invalidReasons
          ..clear()
          ..addAll(updated.invalidReasons);
        if (_invalidReasons.isNotEmpty) {
          _stopPreparedObservation();
          state = BlockingRelationsSelectionEditing(
            intentionId: current.intentionId,
            selected: updated.selected,
            invalidReasons: _invalidReasons,
          );
          return;
        }
        state = BlockingRelationsSelectionPrepared(
          intentionId: current.intentionId,
          selected: updated.selected,
          snapshot: BlockingRelationsPreparedSelection.fromSelected(
            intentionId: current.intentionId,
            selected: updated.selected,
            descriptions: _descriptions,
          ),
        );
    }
  }

  void _preparedReadFailed(BlockingRelationsRefreshFailure failure) {
    if (!ref.mounted || state is! BlockingRelationsSelectionPrepared) {
      return;
    }
    final current = state;
    _stopPreparedObservation();
    state = BlockingRelationsSelectionRefreshFailed(
      intentionId: current.intentionId,
      selected: current.selected,
      failure: failure,
    );
  }

  void _stopPreparedObservation() {
    final subscription = _preparedSubscription;
    _preparedSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Перечитывает только явно выбранные связи перед просмотром или после конфликта.
  /// Ошибка сохраняет весь прежний выбор; недоступные строки остаются видимыми.
  Future<bool> refreshSelection() async {
    final current = state;
    if (current is BlockingRelationsSelectionPrepared ||
        current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionRefreshing ||
        current.selected.isEmpty) {
      return false;
    }
    _releaseFailureClaim();
    state = BlockingRelationsSelectionRefreshing(
      intentionId: current.intentionId,
      selected: current.selected,
    );
    try {
      final intention = await _repository.getRelationCounts(
        current.intentionId,
      );
      if (!ref.mounted || state is! BlockingRelationsSelectionRefreshing) {
        return false;
      }
      switch (intention) {
        case ResultFailure(:final failure):
          return _refreshFailed(current, switch (failure) {
            IntentionNotFoundFailure() =>
              BlockingRelationsRefreshFailure.intentionNotFound,
            IntentionUnavailableFailure() =>
              BlockingRelationsRefreshFailure.unavailable,
            IntentionCorruptionFailure() =>
              BlockingRelationsRefreshFailure.corruption,
            _ => BlockingRelationsRefreshFailure.unexpected,
          });
        case ResultSuccess():
          break;
      }

      final result = await _repository.getSelectedRelations(
        SelectedRelationsQuery(
          intentionId: current.intentionId,
          relationIds: current.selected.keys,
        ),
      );
      if (!ref.mounted || state is! BlockingRelationsSelectionRefreshing) {
        return false;
      }
      if (result case SelectedRelationsReadError(:final failure)) {
        return _refreshFailed(current, switch (failure) {
          SelectedRelationsReadUnavailableFailure() =>
            BlockingRelationsRefreshFailure.unavailable,
          SelectedRelationsReadCorruptionFailure() =>
            BlockingRelationsRefreshFailure.corruption,
          SelectedRelationsReadUnexpectedFailure() =>
            BlockingRelationsRefreshFailure.unexpected,
        });
      }
      final snapshot = (result as SelectedRelationsReadSuccess).value;
      final previousRevision = _selectionRevision;
      if (previousRevision != null &&
          snapshot.revision.compareTo(previousRevision) ==
              GraphRevisionOrder.older) {
        state = BlockingRelationsSelectionEditing(
          intentionId: current.intentionId,
          selected: current.selected,
          invalidReasons: _invalidReasons,
        );
        return true;
      }
      final updated = _updatedSelection(current.selected, snapshot.value);
      _selectionRevision = snapshot.revision;
      _descriptions
        ..clear()
        ..addAll(updated.descriptions);
      _invalidReasons
        ..clear()
        ..addAll(updated.invalidReasons);
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: updated.selected,
        invalidReasons: updated.invalidReasons,
      );
      return true;
    } on Object {
      if (!ref.mounted || state is! BlockingRelationsSelectionRefreshing) {
        return false;
      }
      return _refreshFailed(
        current,
        BlockingRelationsRefreshFailure.unexpected,
      );
    }
  }

  ({
    Map<LongTermRelationId, LongTermRelationSummary> selected,
    Map<LongTermRelationId, BlockingRelationsInvalidReason> invalidReasons,
    Map<LongTermRelationId, String?> descriptions,
  })
  _updatedSelection(
    Map<LongTermRelationId, LongTermRelationSummary> selected,
    SelectedRelationsSnapshot snapshot,
  ) {
    final refreshed = Map<LongTermRelationId, LongTermRelationSummary>.of(
      selected,
    );
    final invalidReasons =
        Map<LongTermRelationId, BlockingRelationsInvalidReason>.of(
          _invalidReasons,
        );
    final descriptions = Map<LongTermRelationId, String?>.of(_descriptions);
    for (final entry in snapshot.entries.entries) {
      final id = entry.key;
      switch (entry.value) {
        case SelectedRelationMissing():
          invalidReasons[id] = BlockingRelationsInvalidReason.missing;
        case SelectedRelationNoLongerBlocking():
          invalidReasons[id] = BlockingRelationsInvalidReason.noLongerBlocking;
        case SelectedRelationPresent(:final details):
          invalidReasons.remove(id);
          descriptions[id] = details.description?.value;
          refreshed[id] = LongTermRelationSummary(
            relation: details.relation,
            source: details.source,
            related: details.related,
            hasDescription: details.hasDescription,
          );
      }
    }
    return (
      selected: refreshed,
      invalidReasons: invalidReasons,
      descriptions: descriptions,
    );
  }

  bool _refreshFailed(
    BlockingRelationsSelectionState previous,
    BlockingRelationsRefreshFailure failure,
  ) {
    state = BlockingRelationsSelectionRefreshFailed(
      intentionId: previous.intentionId,
      selected: previous.selected,
      failure: failure,
    );
    return false;
  }

  /// Отмена до принятия команды оставляет черновик и не пишет в граф.
  void cancel() {
    final current = state;
    if (current is BlockingRelationsSelectionPrepared) {
      _stopPreparedObservation();
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: current.selected,
        invalidReasons: _invalidReasons,
      );
    }
  }

  /// Подтверждённый снимок отправляется общему координатору только однажды.
  void confirm({required String presentationTitle}) {
    final current = state;
    if (current is! BlockingRelationsSelectionPrepared) {
      return;
    }
    _stopPreparedObservation();
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
    if (current is BlockingRelationsSelectionFailed &&
        !current.requiresRefresh) {
      _releaseFailureClaim();
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: current.selected,
        invalidReasons: _invalidReasons,
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
      switch (completion.result) {
        case GraphResultSuccess():
          _selectionRevision = null;
          _descriptions.clear();
          _invalidReasons.clear();
          _activeToken = null;
          state = BlockingRelationsSelectionEditing(
            intentionId: current.intentionId,
            selected: const {},
          );
        case GraphResultFailure(:final failure):
          state = BlockingRelationsSelectionFailed(
            intentionId: current.intentionId,
            selected: current.selected,
            failure: BlockingRelationsSelectionCommandFailure(failure),
            presentationClaim: _coordinator.claimInitiatorFailure(
              completion.token,
            ),
          );
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
