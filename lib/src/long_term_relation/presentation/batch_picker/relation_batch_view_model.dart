import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/catalog/pair_occupant_reconciliation.dart';
import '../../application/intention_relation_group.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/relation_pair_probe.dart';
import 'relation_batch_state.dart';

part 'relation_batch_view_model.g.dart';

final relationBatchChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

/// Отметки принадлежат экземпляру поиска и не зависят от его выдачи.
///
/// Принятая команда выполняется до результата и без поиска: его уход передаёт
/// право предъявления оболочке.
@riverpod
final class RelationBatchViewModel extends _$RelationBatchViewModel {
  late GraphCommandCoordinator _coordinator;
  late IntentionId _pageId;
  late IntentionRelationGroup _group;
  final _searchKey = RelationsAdditionSearchKey();
  final _selected = <IntentionId, String>{};
  bool _hasCreatedIntentions = false;
  late String _pageTitle;
  RelationBatchOperation _operation = const RelationBatchIdle();
  LongTermRelationOperationToken? _activeToken;

  @override
  RelationBatchState build(
    IntentionSearchSession session,
    IntentionId pageId,
    IntentionRelationGroup group,
    String pageTitle,
  ) {
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _pageId = pageId;
    _group = group;
    _pageTitle = pageTitle;
    final subscription = ref
        .watch(relationBatchChangesProvider)
        .listen(_onPackage);
    ref.onDispose(() {
      leave();
      unawaited(subscription.cancel());
    });
    return _snapshot();
  }

  void toggle(IntentionId id, String title) {
    if (!state.canEdit) return;
    if (_selected.containsKey(id)) {
      _selected.remove(id);
    } else {
      _selected[id] = title;
    }
    _publish(const RelationBatchIdle());
  }

  /// Принимает результат живой панели создания для этого поиска.
  void acceptCreated(IntentionId id, String title) {
    if (!ref.mounted || !state.canEdit) return;
    _selected.remove(id);
    _selected[id] = title;
    _hasCreatedIntentions = true;
    _publish(const RelationBatchIdle());
  }

  void remove(IntentionId id) {
    if (state.canEdit && _selected.remove(id) != null) {
      _publish(const RelationBatchIdle());
    }
  }

  /// Отправляет одну команду со всеми отметками в порядке их установки.
  void submit() {
    if (!state.canSubmit) return;
    final start = _coordinator.acceptRelationsAddition(
      _searchKey,
      AddLongTermRelations(
        pageIntentionId: _pageId,
        group: _group,
        candidateIds: _selected.keys,
      ),
    );
    switch (start) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _activeToken = token;
        _publish(const RelationBatchSubmitting());
        unawaited(_finish(future));
      case LongTermRelationCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        _publish(
          const RelationBatchFailed(
            failure: LongTermRelationUnexpectedFailure(),
            claim: null,
          ),
        );
    }
  }

  /// Передаёт оболочке право предъявить результат: экран уходит и показать его
  /// уже не сможет.
  void leave() {
    _releaseFailure();
    final token = _activeToken;
    _activeToken = null;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  Future<void> _finish(Future<LongTermRelationCommandCompletion> future) async {
    final completion = await future;
    if (!ref.mounted || !identical(_activeToken, completion.token)) return;
    _activeToken = null;
    _publish(switch (completion.result) {
      GraphResultSuccess() => const RelationBatchAdded(),
      GraphResultFailure(:final failure) => RelationBatchFailed(
        failure: failure,
        claim: _coordinator.claimInitiatorFailure(completion.token),
      ),
    });
  }

  void _publish(RelationBatchOperation operation) {
    _releaseFailure();
    _operation = operation;
    state = _snapshot();
  }

  /// Подтверждённое предъявление запись уже сняло, поэтому освобождение его не
  /// повторит.
  void _releaseFailure() {
    if (_operation case RelationBatchFailed(:final claim?)) {
      _coordinator.releaseInitiatorClaim(claim);
    }
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    final count = _selected.length;
    var changed = false;
    for (final change in package.changes) {
      switch (change) {
        case IntentionCatalogUpdated(:final before, :final after):
          final previous = before.summary;
          final current = after.summary;
          if (current.id == _pageId && previous.title != current.title) {
            _pageTitle = current.title;
            changed = true;
          }
          if (_selected.containsKey(current.id)) {
            if (current.archiveState == IntentionArchiveState.archived) {
              _selected.remove(current.id);
              changed = true;
            } else if (previous.title != current.title &&
                _selected[current.id] != current.title) {
              _selected[current.id] = current.title;
              changed = true;
            }
          }
        case IntentionCatalogDeleted(:final entry):
          changed = _selected.remove(entry.summary.id) != null || changed;
        case GraphChange():
          break;
      }
    }
    final occupied = reconcilePairOccupants(
      probe: RelationPairProbe.forGroup(intentionId: _pageId, group: _group),
      occupants: const {},
      rowIds: _selected.keys.toSet(),
      changes: package.changes.whereType<LongTermRelationChange>(),
    );
    for (final id in occupied.keys) {
      _selected.remove(id);
      changed = true;
    }
    if (_selected.length != count && _operation is RelationBatchFailed) {
      _publish(const RelationBatchIdle());
    } else if (changed) {
      state = _snapshot();
    }
  }

  RelationBatchState _snapshot() => RelationBatchState(
    operation: _operation,
    pageTitle: _pageTitle,
    hasCreatedIntentions: _hasCreatedIntentions,
    selected: [
      for (final entry in _selected.entries)
        RelationBatchSelection(id: entry.key, title: entry.value),
    ],
  );
}
