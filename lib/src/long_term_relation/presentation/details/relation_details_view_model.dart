import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/long_term_relation_permissions.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_details_state.dart';

part 'relation_details_view_model.g.dart';

/// Поколение наблюдения: повтор делает ответы прежнего чтения непригодными.
final class _RelationObservationGeneration {
  const _RelationObservationGeneration(this.value);

  static const initial = _RelationObservationGeneration(0);

  final int value;

  _RelationObservationGeneration next() =>
      _RelationObservationGeneration(value + 1);

  @override
  bool operator ==(Object other) =>
      other is _RelationObservationGeneration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
Stream<LongTermRelationReadResult> _relationDetailsObservation(
  Ref ref,
  LongTermRelationId relationId,
  _RelationObservationGeneration generation,
) => ref.watch(personalGraphRepositoryProvider).watchRelation(relationId);

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.
@riverpod
final class RelationDetailsViewModel extends _$RelationDetailsViewModel {
  late LongTermRelationId _relationId;
  late GraphCommandCoordinator _coordinator;
  late _RelationObservationGeneration _generation;
  late StreamSubscription<GraphCommandCompletion> _completionSubscription;
  ProviderSubscription<AsyncValue<LongTermRelationReadResult>>?
  _observationSubscription;
  GraphRevision? _acceptedRevision;
  LongTermRelationOperationToken? _activeLifecycleToken;
  var _isTerminated = false;

  @override
  RelationDetailsState build(LongTermRelationId relationId) {
    _relationId = relationId;
    _generation = _RelationObservationGeneration.initial;
    _acceptedRevision = null;
    _isTerminated = false;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.completions.listen(
      _handleCompletion,
    );
    ref.onDispose(() {
      final activeLifecycleToken = _activeLifecycleToken;
      if (activeLifecycleToken != null) {
        _coordinator.releaseInitiatorPresentation(activeLifecycleToken);
      }
      _observationSubscription?.close();
      unawaited(_completionSubscription.cancel());
    });
    return _stateFromObservation(_startObservation());
  }

  /// Повторяет чтение после устранимого отказа.
  void retry() {
    if (!state.canRetry) {
      return;
    }
    _generation = _generation.next();
    final current = state;
    if (current is RelationDetailsLoaded) {
      state = current.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      );
      _startObservation();
      return;
    }
    state = _stateFromObservation(_startObservation());
  }

  /// Архивирует активную связь независимо от состояния её участников.
  void archive() => _startLifecycleChange(RelationDetailsLifecycleKind.archive);

  /// Восстанавливает архивную связь, только если оба участника активны.
  void restore() => _startLifecycleChange(RelationDetailsLifecycleKind.restore);

  /// Физически удаляет конкретную активную или архивную связь.
  void delete() => _startLifecycleChange(RelationDetailsLifecycleKind.delete);

  /// Повторяет доказанно устранимый отказ той же операции.
  void retryLifecycleChange() {
    final current = state;
    final change = current is RelationDetailsLoaded
        ? current.lifecycleChange
        : null;
    if (change is RelationDetailsLifecycleFailed && change.canRetry) {
      _startLifecycleChange(change.kind);
    }
  }

  void _startLifecycleChange(RelationDetailsLifecycleKind kind) {
    final current = state;
    if (current is! RelationDetailsLoaded ||
        _isOperationRunning ||
        !_isLifecycleChangeApplicable(current, kind)) {
      return;
    }

    final start = switch (kind) {
      RelationDetailsLifecycleKind.archive =>
        _coordinator.acceptRelationArchive(
          ArchiveLongTermRelation(_relationId),
        ),
      RelationDetailsLifecycleKind.restore =>
        _coordinator.acceptRelationRestore(
          RestoreLongTermRelation(_relationId),
        ),
      RelationDetailsLifecycleKind.delete => _coordinator.acceptRelationDelete(
        DeleteLongTermRelation(_relationId),
      ),
    };
    switch (start) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _activeLifecycleToken = token;
        state = current.copyWith(
          isOperationRunning: true,
          lifecycleChange: RelationDetailsLifecycleRunning(kind),
        );
        unawaited(_finishLifecycleChange(kind, future));
      case LongTermRelationCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecycleFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        );
    }
  }

  bool _isLifecycleChangeApplicable(
    RelationDetailsLoaded loaded,
    RelationDetailsLifecycleKind kind,
  ) => switch (kind) {
    RelationDetailsLifecycleKind.archive =>
      loaded.permissions.canChangeArchiveState &&
          loaded.details.relation.scope == RelationScope.active,
    RelationDetailsLifecycleKind.restore =>
      loaded.permissions.canChangeArchiveState &&
          loaded.details.relation.scope == RelationScope.archived &&
          loaded.details.source.archiveState == IntentionArchiveState.active &&
          loaded.details.related.archiveState == IntentionArchiveState.active,
    RelationDetailsLifecycleKind.delete => loaded.permissions.canDelete,
  };

  Future<void> _finishLifecycleChange(
    RelationDetailsLifecycleKind kind,
    Future<LongTermRelationCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeLifecycleToken, completion.token)) {
        return;
      }

      _activeLifecycleToken = null;
      final current = state;
      if (current is! RelationDetailsLoaded) {
        if (completion.isFailure) {
          _coordinator.releaseInitiatorPresentation(completion.token);
        }
        return;
      }
      state = switch (completion.result) {
        GraphResultSuccess(value: LongTermRelationUpdated(:final relation))
            when relation.id == _relationId &&
                _scopeMatchesLifecycleKind(relation.scope, kind) =>
          current.copyWith(clearLifecycleChange: true),
        GraphResultSuccess(value: LongTermRelationDeleted(:final relation))
            when relation.id == _relationId &&
                kind == RelationDetailsLifecycleKind.delete =>
          _terminateAsDeleted(),
        GraphResultSuccess() => current.copyWith(
          lifecycleChange: RelationDetailsLifecycleFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        ),
        GraphResultFailure(:final failure) => current.copyWith(
          lifecycleChange: RelationDetailsLifecycleFailed(
            kind,
            failure,
            failurePresentation: _coordinator.claimInitiatorFailure(
              completion.token,
            ),
          ),
        ),
      };
      _scheduleGateRefresh();
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final token = _activeLifecycleToken;
      _activeLifecycleToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      final current = state;
      if (current is RelationDetailsLoaded) {
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecycleFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        );
      }
      _scheduleGateRefresh();
    }
  }

  bool _scopeMatchesLifecycleKind(
    RelationScope scope,
    RelationDetailsLifecycleKind kind,
  ) => switch (kind) {
    RelationDetailsLifecycleKind.archive => scope == RelationScope.archived,
    RelationDetailsLifecycleKind.restore => scope == RelationScope.active,
    RelationDetailsLifecycleKind.delete => false,
  };

  AsyncValue<LongTermRelationReadResult> _startObservation() {
    _observationSubscription?.close();
    final generation = _generation;
    final subscription = ref.listen(
      _relationDetailsObservationProvider(_relationId, generation),
      (previous, next) => _handleObservation(generation, next),
    );
    _observationSubscription = subscription;
    return subscription.read();
  }

  void _handleObservation(
    _RelationObservationGeneration generation,
    AsyncValue<LongTermRelationReadResult> observation,
  ) {
    if (!ref.mounted || _isTerminated || generation != _generation) {
      return;
    }
    if (observation case AsyncData(value: GraphResultSuccess(:final value))) {
      if (!_acceptSnapshotRevision(value.revision)) {
        return;
      }
    }
    final current = state;
    state = _stateFromObservation(
      observation,
      previousLoaded: current is RelationDetailsLoaded ? current : null,
    );
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isTerminated) {
      return;
    }
    if (completion
        case LongTermRelationCommandCompletion(
          target: ExistingLongTermRelationOperationTarget(:final relationId),
        )
        when relationId == _relationId) {
      _scheduleGateRefresh();
    }
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) {
      return;
    }
    final changes = confirmedChange.changes;
    final deleted = changes.whereType<LongTermRelationDeletedChange>().any(
      (change) => change.id == _relationId,
    );
    final relationChanged = changes.whereType<LongTermRelationChange>().any(
      (change) => change.id == _relationId,
    );
    LongTermRelationPermissions? confirmedPermissions;
    for (final change in changes) {
      switch (change) {
        case DailyChoiceChange(:final relationPermissions):
          confirmedPermissions =
              relationPermissions[_relationId] ?? confirmedPermissions;
        case LongTermRelationChange(:final id, :final permissions)
            when id == _relationId && permissions?.isConfirmed == true:
          confirmedPermissions = permissions;
        case GraphChange():
          break;
      }
    }
    final current = state;
    final participantIds = current is RelationDetailsLoaded
        ? <IntentionId>{current.details.source.id, current.details.related.id}
        : <IntentionId>{};
    final participantChanged = changes.any(
      (change) => switch (change) {
        IntentionRelationCountsChanged(:final intentionId) =>
          participantIds.contains(intentionId),
        IntentionCatalogMutation(:final before, :final after) =>
          participantIds.contains(before?.summary.id) ||
              participantIds.contains(after?.summary.id),
        LongTermRelationChange() => false,
        GraphChange() => false,
      },
    );
    if ((!relationChanged &&
            !participantChanged &&
            confirmedPermissions == null) ||
        !_advanceRevisionBarrier(confirmedChange.revision)) {
      return;
    }
    if (deleted) {
      state = _terminateAsDeleted();
      return;
    }
    _generation = _generation.next();
    state = switch (current) {
      RelationDetailsLoaded() => current.copyWith(
        permissions: confirmedPermissions,
        permissionRevision: confirmedPermissions == null
            ? null
            : confirmedChange.revision,
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      ),
      _ => RelationDetailsLoading(isOperationRunning: _isOperationRunning),
    };
    _startObservation();
  }

  bool _advanceRevisionBarrier(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null) {
      final order = revision.compareTo(accepted);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return false;
      }
    }
    // Завершение задаёт только барьер: поля связи и участников по-прежнему
    // публикуются исключительно полным снимком watchRelation.
    _acceptedRevision = revision;
    return true;
  }

  void _scheduleGateRefresh() {
    unawaited(
      Future<void>.microtask(() {}).then((_) {
        if (!ref.mounted || _isTerminated) {
          return;
        }
        final isRunning = _isOperationRunning;
        if (state.isOperationRunning != isRunning) {
          state = _withOperationRunning(state, isRunning);
        }
      }),
    );
  }

  bool _acceptSnapshotRevision(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null &&
        revision.compareTo(accepted) == GraphRevisionOrder.older) {
      return false;
    }
    _acceptedRevision = revision;
    return true;
  }

  RelationDetailsState _stateFromObservation(
    AsyncValue<LongTermRelationReadResult> observation, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (observation) {
    AsyncData(:final value) => _stateFromResult(
      value,
      previousLoaded: previousLoaded,
    ),
    AsyncError() when previousLoaded != null => previousLoaded.copyWith(
      isOperationRunning: _isOperationRunning,
      refreshStatus: const RelationDetailsRefreshUnexpected(),
    ),
    AsyncError() => RelationDetailsUnexpected(
      isOperationRunning: _isOperationRunning,
    ),
    AsyncValue<LongTermRelationReadResult>() when previousLoaded != null =>
      previousLoaded.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      ),
    AsyncValue<LongTermRelationReadResult>() => RelationDetailsLoading(
      isOperationRunning: _isOperationRunning,
    ),
  };

  RelationDetailsState _stateFromResult(
    LongTermRelationReadResult result, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (result) {
    GraphResultSuccess(
      value: GraphSnapshot(value: final details?, :final revision),
    ) =>
      RelationDetailsLoaded(
        details: details,
        revision: revision,
        isOperationRunning: _isOperationRunning,
      ),
    GraphResultSuccess() => _terminateAsNotFound(),
    GraphResultFailure(failure: LongTermRelationReadUnavailableFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnavailable(),
          ) ??
          RelationDetailsUnavailable(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadCorruptionFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshCorruption(),
          ) ??
          RelationDetailsCorruption(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadUnexpectedFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnexpected(),
          ) ??
          RelationDetailsUnexpected(isOperationRunning: _isOperationRunning),
  };

  RelationDetailsNotFound _terminateAsNotFound() {
    _isTerminated = true;
    _observationSubscription?.close();
    _observationSubscription = null;
    unawaited(_completionSubscription.cancel());
    return RelationDetailsNotFound(isOperationRunning: _isOperationRunning);
  }

  RelationDetailsDeleted _terminateAsDeleted() {
    _isTerminated = true;
    _observationSubscription?.close();
    _observationSubscription = null;
    unawaited(_completionSubscription.cancel());
    return const RelationDetailsDeleted();
  }

  bool get _isOperationRunning => _coordinator.isRelationRunning(_relationId);

  RelationDetailsState _withOperationRunning(
    RelationDetailsState current,
    bool isOperationRunning,
  ) => switch (current) {
    RelationDetailsLoading() => RelationDetailsLoading(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsLoaded() => current.copyWith(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsNotFound() => current,
    RelationDetailsDeleted() => current,
    RelationDetailsUnavailable() => RelationDetailsUnavailable(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsCorruption() => RelationDetailsCorruption(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsUnexpected() => RelationDetailsUnexpected(
      isOperationRunning: isOperationRunning,
    ),
  };
}
