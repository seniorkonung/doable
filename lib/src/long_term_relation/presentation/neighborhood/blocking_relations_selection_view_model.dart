import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/delete_blocking_relations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
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
  final _rowRevisions = <LongTermRelationId, GraphRevision>{};
  final _descriptions = <LongTermRelationId, String?>{};
  final _invalidReasons =
      <LongTermRelationId, BlockingRelationsInvalidReason>{};
  final _preparedSubscriptions =
      <LongTermRelationId, StreamSubscription<LongTermRelationReadResult>>{};

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
    final updated = Map<LongTermRelationId, LongTermRelationSummary>.of(
      current.selected,
    )..remove(relationId);
    _rowRevisions.remove(relationId);
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
    for (final id in current.selected.keys) {
      _preparedSubscriptions[id] = _repository
          .watchRelation(id)
          .listen(
            (result) => _handlePreparedObservation(id, result),
            onError: (Object _) =>
                _preparedReadFailed(BlockingRelationsRefreshFailure.unexpected),
          );
    }
  }

  void _handlePreparedObservation(
    LongTermRelationId id,
    LongTermRelationReadResult result,
  ) {
    if (!ref.mounted || state is! BlockingRelationsSelectionPrepared) {
      return;
    }
    final current = state as BlockingRelationsSelectionPrepared;
    switch (result) {
      case LongTermRelationReadError(:final failure):
        _preparedReadFailed(switch (failure) {
          LongTermRelationReadUnavailableFailure() =>
            BlockingRelationsRefreshFailure.unavailable,
          LongTermRelationReadCorruptionFailure() =>
            BlockingRelationsRefreshFailure.corruption,
          LongTermRelationReadUnexpectedFailure() =>
            BlockingRelationsRefreshFailure.unexpected,
        });
      case LongTermRelationReadSuccess(value: final snapshot):
        final previousRevision = _rowRevisions[id];
        if (previousRevision != null &&
            (snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.older ||
                snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.same)) {
          return;
        }
        _rowRevisions[id] = snapshot.revision;
        final details = snapshot.value;
        if (details == null ||
            (details.relation.sourceIntentionId != current.intentionId &&
                details.relation.relatedIntentionId != current.intentionId)) {
          _invalidReasons[id] = details == null
              ? BlockingRelationsInvalidReason.missing
              : BlockingRelationsInvalidReason.noLongerBlocking;
          _stopPreparedObservation();
          state = BlockingRelationsSelectionEditing(
            intentionId: current.intentionId,
            selected: current.selected,
            invalidReasons: _invalidReasons,
          );
          return;
        }
        _descriptions[id] = details.description?.value;
        final selected = <LongTermRelationId, LongTermRelationSummary>{
          ...current.selected,
          id: LongTermRelationSummary(
            relation: details.relation,
            source: details.source,
            related: details.related,
            hasDescription: details.hasDescription,
          ),
        };
        state = BlockingRelationsSelectionPrepared(
          intentionId: current.intentionId,
          selected: selected,
          snapshot: BlockingRelationsPreparedSelection.fromSelected(
            intentionId: current.intentionId,
            selected: selected,
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
    for (final subscription in _preparedSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _preparedSubscriptions.clear();
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

      final refreshed = Map<LongTermRelationId, LongTermRelationSummary>.of(
        current.selected,
      );
      final invalidReasons =
          Map<LongTermRelationId, BlockingRelationsInvalidReason>.of(
            _invalidReasons,
          );
      final descriptions = Map<LongTermRelationId, String?>.of(_descriptions);
      final revisions = Map<LongTermRelationId, GraphRevision>.of(
        _rowRevisions,
      );
      final ids = current.selected.keys.toList(growable: false);
      final results = await Future.wait([
        for (final id in ids) _repository.watchRelation(id).first,
      ]);
      if (!ref.mounted || state is! BlockingRelationsSelectionRefreshing) {
        return false;
      }
      for (var index = 0; index < ids.length; index++) {
        final id = ids[index];
        final result = results[index];
        switch (result) {
          case LongTermRelationReadError(:final failure):
            return _refreshFailed(current, switch (failure) {
              LongTermRelationReadUnavailableFailure() =>
                BlockingRelationsRefreshFailure.unavailable,
              LongTermRelationReadCorruptionFailure() =>
                BlockingRelationsRefreshFailure.corruption,
              LongTermRelationReadUnexpectedFailure() =>
                BlockingRelationsRefreshFailure.unexpected,
            });
          case LongTermRelationReadSuccess(value: final snapshot):
            final previousRevision = revisions[id];
            if (previousRevision != null &&
                snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.older) {
              continue;
            }
            revisions[id] = snapshot.revision;
            final details = snapshot.value;
            if (details == null) {
              invalidReasons[id] = BlockingRelationsInvalidReason.missing;
            } else if (details.relation.sourceIntentionId !=
                    current.intentionId &&
                details.relation.relatedIntentionId != current.intentionId) {
              invalidReasons[id] =
                  BlockingRelationsInvalidReason.noLongerBlocking;
            } else {
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
      }
      _rowRevisions
        ..clear()
        ..addAll(revisions);
      _descriptions
        ..clear()
        ..addAll(descriptions);
      _invalidReasons
        ..clear()
        ..addAll(invalidReasons);
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selected: refreshed,
        invalidReasons: invalidReasons,
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
          _rowRevisions.clear();
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
