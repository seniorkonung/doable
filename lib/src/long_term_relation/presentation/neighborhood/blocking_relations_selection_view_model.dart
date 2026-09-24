import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../daily_choice/application/daily_choice_catalog.dart';
import '../../../graph/application/blocking_relation_reference.dart';
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
import '../../application/long_term_relation_permissions.dart';
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
      <BlockingRelationReference, BlockingRelationsInvalidReason>{};
  StreamSubscription<SelectedRelationsReadResult>? _preparedSubscription;
  var _preparedGeneration = 0;

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
      selectedByReference: const {},
    );
  }

  /// Добавляет только явно указанную непосредственную связь.
  bool select(LongTermRelationSummary row) =>
      _select(BlockingRelationsSelectedLongTerm(row));

  /// Дневной выбор добавляется только по его прямому участнику.
  bool selectDailyChoice(DailyChoiceCatalogItem item) =>
      _select(BlockingRelationsSelectedDailyChoice(item));

  bool _select(BlockingRelationsSelectedItem item) {
    final current = state;
    if (current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionRefreshing ||
        current is BlockingRelationsSelectionRefreshFailed ||
        (current is BlockingRelationsSelectionFailed &&
            current.requiresRefresh)) {
      return false;
    }
    final belongs = switch (item) {
      BlockingRelationsSelectedLongTerm(:final row) =>
        row.relation.sourceIntentionId == current.intentionId ||
            row.relation.relatedIntentionId == current.intentionId,
      BlockingRelationsSelectedDailyChoice(:final item) =>
        item.source.id == current.intentionId ||
            item.selected.id == current.intentionId,
    };
    if (!belongs) {
      return false;
    }
    if (current.selectedByReference.containsKey(item.reference)) {
      return false;
    }
    _stopPreparedObservation();
    _releaseFailureClaim();
    _selectionRevision = null;
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selectedByReference: {
        ...current.selectedByReference,
        item.reference: item,
      },
      invalidReasonsByReference: _invalidReasons,
    );
    return true;
  }

  /// Удаляет только конкретный идентификатор из незавершённого выбора.
  bool unselect(LongTermRelationId relationId) =>
      unselectReference(LongTermBlockingRelationReference(relationId));

  bool unselectReference(BlockingRelationReference reference) {
    final current = state;
    if (current is BlockingRelationsSelectionRunning ||
        current is BlockingRelationsSelectionRefreshing ||
        current is BlockingRelationsSelectionRefreshFailed ||
        (current is BlockingRelationsSelectionFailed &&
            current.requiresRefresh) ||
        !current.selectedByReference.containsKey(reference)) {
      return false;
    }
    _stopPreparedObservation();
    _releaseFailureClaim();
    _selectionRevision = null;
    final updated =
        Map<BlockingRelationReference, BlockingRelationsSelectedItem>.of(
          current.selectedByReference,
        )..remove(reference);
    if (reference case LongTermBlockingRelationReference(:final id)) {
      _descriptions.remove(id);
    }
    _invalidReasons.remove(reference);
    state = BlockingRelationsSelectionEditing(
      intentionId: current.intentionId,
      selectedByReference: updated,
      invalidReasonsByReference: _invalidReasons,
    );
    return true;
  }

  /// Фиксирует непустой набор для просмотра и отдельного подтверждения.
  bool prepare() {
    final current = state;
    if (current is! BlockingRelationsSelectionEditing ||
        current.selectedByReference.isEmpty ||
        current.invalidReasonsByReference.isNotEmpty) {
      return false;
    }
    state = BlockingRelationsSelectionPrepared(
      intentionId: current.intentionId,
      selectedByReference: current.selectedByReference,
      snapshot: BlockingRelationsPreparedSelection.fromSelected(
        intentionId: current.intentionId,
        selected: current.selectedByReference,
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
    final generation = _preparedGeneration;
    final query = SelectedRelationsQuery.mixed(
      intentionId: current.intentionId,
      references: current.selectedByReference.keys,
    );
    _preparedSubscription = _repository
        .watchSelectedRelations(query)
        .listen(
          (result) => _handlePreparedObservation(result, generation),
          onError: (Object _) => _preparedReadFailed(
            BlockingRelationsRefreshFailure.unexpected,
            generation,
          ),
        );
  }

  void _handlePreparedObservation(
    SelectedRelationsReadResult result,
    int generation,
  ) {
    if (!ref.mounted ||
        generation != _preparedGeneration ||
        state is! BlockingRelationsSelectionPrepared) {
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
        }, generation);
      case SelectedRelationsReadSuccess(value: final snapshot):
        final previousRevision = _selectionRevision;
        if (previousRevision != null &&
            (snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.older ||
                snapshot.revision.compareTo(previousRevision) ==
                    GraphRevisionOrder.same)) {
          return;
        }
        final updated = _updatedSelection(
          current.selectedByReference,
          snapshot.value,
        );
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
            selectedByReference: updated.selected,
            invalidReasonsByReference: _invalidReasons,
          );
          return;
        }
        state = BlockingRelationsSelectionPrepared(
          intentionId: current.intentionId,
          selectedByReference: updated.selected,
          snapshot: BlockingRelationsPreparedSelection.fromSelected(
            intentionId: current.intentionId,
            selected: updated.selected,
            descriptions: _descriptions,
          ),
        );
    }
  }

  void _preparedReadFailed(
    BlockingRelationsRefreshFailure failure,
    int generation,
  ) {
    if (!ref.mounted ||
        generation != _preparedGeneration ||
        state is! BlockingRelationsSelectionPrepared) {
      return;
    }
    final current = state;
    _stopPreparedObservation();
    state = BlockingRelationsSelectionRefreshFailed(
      intentionId: current.intentionId,
      selectedByReference: current.selectedByReference,
      failure: failure,
    );
  }

  void _stopPreparedObservation() {
    _preparedGeneration += 1;
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
        current.selectedByReference.isEmpty) {
      return false;
    }
    _releaseFailureClaim();
    state = BlockingRelationsSelectionRefreshing(
      intentionId: current.intentionId,
      selectedByReference: current.selectedByReference,
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
        SelectedRelationsQuery.mixed(
          intentionId: current.intentionId,
          references: current.selectedByReference.keys,
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
          selectedByReference: current.selectedByReference,
          invalidReasonsByReference: _invalidReasons,
        );
        return true;
      }
      final updated = _updatedSelection(
        current.selectedByReference,
        snapshot.value,
      );
      _selectionRevision = snapshot.revision;
      _descriptions
        ..clear()
        ..addAll(updated.descriptions);
      _invalidReasons
        ..clear()
        ..addAll(updated.invalidReasons);
      state = BlockingRelationsSelectionEditing(
        intentionId: current.intentionId,
        selectedByReference: updated.selected,
        invalidReasonsByReference: updated.invalidReasons,
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
    Map<BlockingRelationReference, BlockingRelationsSelectedItem> selected,
    Map<BlockingRelationReference, BlockingRelationsInvalidReason>
    invalidReasons,
    Map<LongTermRelationId, String?> descriptions,
  })
  _updatedSelection(
    Map<BlockingRelationReference, BlockingRelationsSelectedItem> selected,
    SelectedRelationsSnapshot snapshot,
  ) {
    final refreshed =
        Map<BlockingRelationReference, BlockingRelationsSelectedItem>.of(
          selected,
        );
    final invalidReasons =
        Map<BlockingRelationReference, BlockingRelationsInvalidReason>.of(
          _invalidReasons,
        );
    final descriptions = Map<LongTermRelationId, String?>.of(_descriptions);
    for (final entry in snapshot.entriesByReference.entries) {
      final reference = entry.key;
      switch (entry.value) {
        case SelectedRelationMissing() || SelectedDailyChoiceMissing():
          invalidReasons[reference] = BlockingRelationsInvalidReason.missing;
        case SelectedRelationNoLongerBlocking() ||
            SelectedDailyChoiceNoLongerBlocking():
          invalidReasons[reference] =
              BlockingRelationsInvalidReason.noLongerBlocking;
        case SelectedRelationPresent(:final details):
          if (details.permissions.restriction ==
              LongTermRelationPermissionRestriction.referencedByDailyPath) {
            invalidReasons[reference] =
                BlockingRelationsInvalidReason.referencedByDailyPath;
          } else {
            invalidReasons.remove(reference);
          }
          descriptions[details.relation.id] = details.description?.value;
          refreshed[reference] = BlockingRelationsSelectedLongTerm(
            LongTermRelationSummary(
              relation: details.relation,
              source: details.source,
              related: details.related,
              hasDescription: details.hasDescription,
            ),
          );
        case SelectedDailyChoicePresent(:final item):
          invalidReasons.remove(reference);
          refreshed[reference] = BlockingRelationsSelectedDailyChoice(item);
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
      selectedByReference: previous.selectedByReference,
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
        selectedByReference: current.selectedByReference,
        invalidReasonsByReference: _invalidReasons,
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
          selectedByReference: current.selectedByReference,
          snapshot: current.snapshot,
          token: token,
        );
        unawaited(_finish(future));
      case BlockingRelationsDeleteAlreadyRunning():
        state = BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selectedByReference: current.selectedByReference,
          failure: const BlockingRelationsSelectionBusy(),
        );
      case GraphCommandCoordinatorDraining():
        state = BlockingRelationsSelectionFailed(
          intentionId: current.intentionId,
          selectedByReference: current.selectedByReference,
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
        selectedByReference: current.selectedByReference,
        invalidReasonsByReference: _invalidReasons,
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
            selectedByReference: const {},
          );
        case GraphResultFailure(:final failure):
          state = BlockingRelationsSelectionFailed(
            intentionId: current.intentionId,
            selectedByReference: current.selectedByReference,
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
          selectedByReference: current.selectedByReference,
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
